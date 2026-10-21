--[[
    RP Equipment - client : déviation du trafic PNJ autour des plots posés (menu Équipement)
    ----------------------------------------------------------------------------------------
    Seulement les plots posés avec ce script (GlobalState.rpCones, publié par le serveur), jamais ceux du jeu.
    - Plots à moins de Traffic.GroupDistance m les uns des autres = un même dispositif (ligne, biseau en diagonale…).
    - Autour d'un dispositif : zone de vitesse du jeu (les véhicules ralentissent en approchant).
    - Un véhicule PNJ qui a un plot du dispositif dans sa trajectoire, à moins de Traffic.Detect m (10) devant lui :
        * il cherche le passage le plus proche de sa trajectoire, à gauche ou à droite, assez large pour lui, sur la
          route (voie voisine ou voie d'en face) : il s'y engage (contournement anticipé) puis reprend sa route ;
        * aucun passage (route à une seule voie, dispositif qui ferme toute la route) : il s'arrête devant, le
          dispositif est infranchissable.
    Chaque client ne dirige que les PNJ dont il a le contrôle (réseau).

    Performance : aucune boucle sans plot posé à moins de Traffic.Range m (200) du joueur ; sinon une vérification
    toutes les Traffic.Interval ms (250) des véhicules proches des plots.
]]

local Config = EquipConfig
local T = (Config.Stock and Config.Stock.Cones and Config.Stock.Cones.Traffic) or {}
if T.Enabled == false then return end

local DETECT = T.Detect or 10.0
local GROUP_DISTANCE = T.GroupDistance or 6.0
local MARGIN = T.Margin or 0.8           -- m entre la carrosserie et un plot
local RANGE = T.Range or 200.0
local INTERVAL = T.Interval or 250
local STYLE = T.DrivingStyle or 820      -- éviter véhicules / piétons / objets, voie d'en face permise, clignotants
local WANDER_STYLE = T.WanderStyle or 786603

local groups = {}       -- { { cones = { vec3 }, center = vec3, radius, zone } }
local tracked = {}      -- [véhicule] = { group, mode = 'deviate' | 'blocked', driver, target }
local running = false

-- =========================================================================
-- DISPOSITIFS (plots proches regroupés)
-- =========================================================================
local function removeZones()
    for _, g in ipairs(groups) do
        if g.zone then RemoveRoadNodeSpeedZone(g.zone) g.zone = nil end
    end
end

local function buildGroups(list)
    removeZones()
    groups = {}
    local cones = {}
    for _, c in ipairs(type(list) == 'table' and list or {}) do
        if type(c) == 'table' and tonumber(c.x) and tonumber(c.y) and tonumber(c.z) then
            cones[#cones + 1] = { pos = vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0) }
        end
    end
    -- Regroupement de proche en proche (un plot à moins de GROUP_DISTANCE d'un plot du dispositif en fait partie)
    for _, start in ipairs(cones) do
        if not start.group then
            local g = { cones = {} }
            start.group = g
            local queue = { start }
            while #queue > 0 do
                local c = table.remove(queue)
                g.cones[#g.cones + 1] = c.pos
                for _, other in ipairs(cones) do
                    if not other.group and #(other.pos - c.pos) <= GROUP_DISTANCE then
                        other.group = g
                        queue[#queue + 1] = other
                    end
                end
            end
            local sum = vector3(0.0, 0.0, 0.0)
            for _, p in ipairs(g.cones) do sum = sum + p end
            g.center = sum / #g.cones
            g.radius = 0.0
            for _, p in ipairs(g.cones) do g.radius = math.max(g.radius, #(p - g.center)) end
            groups[#groups + 1] = g
        end
    end
end

-- =========================================================================
-- VÉHICULES
-- =========================================================================
local function resume(vehicle, info)
    tracked[vehicle] = nil
    local driver = info.driver
    if DoesEntityExist(driver) and DoesEntityExist(vehicle) and NetworkHasControlOfEntity(driver)
        and GetPedInVehicleSeat(vehicle, -1) == driver and not IsPedDeadOrDying(driver, true) then
        TaskVehicleDriveWander(driver, vehicle, T.ResumeSpeed or 17.0, WANDER_STYLE)
    end
end

--- Passage le plus proche de la trajectoire (décalage latéral en m, repère du véhicule), nil : aucun
--- `cones` : plots du dispositif dans le repère du véhicule ({ x = côté droit, y = devant })
local function findPassage(cones, halfWidth, farY, toWorld, vehicle)
    local needed = halfWidth + MARGIN
    local best = nil
    for i = 0, math.floor((T.MaxShift or 9.0) / 0.5) do
        for _, sign in ipairs(i == 0 and { 1 } or { -1, 1 }) do
            local x = sign * i * 0.5
            local clear = true
            for _, c in ipairs(cones) do
                if c.y > -2.0 and c.y < farY + 2.0 and math.abs(c.x - x) < needed then clear = false break end
            end
            if clear then
                -- Le passage doit être sur la route (voie voisine, voie d'en face), au niveau du dispositif
                local a, b = toWorld(x, math.max(1.0, farY * 0.5)), toWorld(x, farY + 2.0)
                if IsPointOnRoad(a.x, a.y, a.z, vehicle) and IsPointOnRoad(b.x, b.y, b.z, vehicle) then
                    best = x
                    break
                end
            end
        end
        if best then break end
    end
    return best
end

local function handleVehicle(vehicle, group)
    local driver = GetPedInVehicleSeat(vehicle, -1)
    if driver == 0 or IsPedAPlayer(driver) or IsPedDeadOrDying(driver, true) then return end
    if not NetworkHasControlOfEntity(driver) or not NetworkHasControlOfEntity(vehicle) then return end
    local pos = GetEntityCoords(vehicle)
    local fwd = GetEntityForwardVector(vehicle)
    local right = vector3(fwd.y, -fwd.x, 0.0)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local halfWidth, front = math.max(-min.x, max.x), max.y

    -- Plots dans le repère du véhicule ; le plus proche dans la trajectoire, à moins de DETECT m devant
    local local_, inPath, farY = {}, nil, -100.0
    for i, p in ipairs(group.cones) do
        local d = p - pos
        local c = { x = d.x * right.x + d.y * right.y, y = d.x * fwd.x + d.y * fwd.y - front }
        local_[i] = c
        if c.y > farY then farY = c.y end
        if c.y > -1.0 and c.y <= DETECT and math.abs(c.x) < halfWidth + MARGIN then
            if not inPath or c.y < inPath.y then inPath = c end
        end
    end

    local info = tracked[vehicle]
    if not inPath then
        -- Dispositif dépassé (tous les plots derrière) : reprend sa route
        if info and farY < -2.0 then resume(vehicle, info) end
        return
    end
    if info and info.mode == 'deviate' then return end -- déjà en train de contourner

    local function toWorld(x, y)
        return pos + fwd * (y + front) + right * x
    end
    local shift = findPassage(local_, halfWidth, farY, toWorld, vehicle)
    if shift then
        -- Contournement : vers le passage, au-delà du dernier plot, puis reprise de la route
        local target = toWorld(shift, farY + (T.PassBeyond or 8.0))
        TaskVehicleDriveToCoord(driver, vehicle, target.x, target.y, target.z, T.PassSpeed or 7.0, 0,
            GetEntityModel(vehicle), STYLE, 2.0, true)
        tracked[vehicle] = { group = group, mode = 'deviate', driver = driver, target = target, since = GetGameTimer() }
    else
        -- Aucune autre voie : le dispositif est infranchissable, le véhicule s'arrête devant
        TaskVehicleTempAction(driver, vehicle, 6, INTERVAL + 500)
        tracked[vehicle] = { group = group, mode = 'blocked', driver = driver }
    end
end

local function nearGroups(pos, distance)
    local list = {}
    for _, g in ipairs(groups) do
        if #(g.center - pos) <= g.radius + distance then list[#list + 1] = g end
    end
    return list
end

local function tick()
    local here = GetEntityCoords(PlayerPedId())
    local active = nearGroups(here, RANGE)
    -- Zones de vitesse : seulement les dispositifs à portée du joueur
    for _, g in ipairs(groups) do
        local wanted = false
        for _, a in ipairs(active) do if a == g then wanted = true break end end
        if wanted and not g.zone and (T.SlowSpeed or 0) > 0 then
            g.zone = AddRoadNodeSpeedZone(g.center.x, g.center.y, g.center.z, g.radius + (T.SlowRadius or 25.0), T.SlowSpeed, false)
        elseif not wanted and g.zone then
            RemoveRoadNodeSpeedZone(g.zone)
            g.zone = nil
        end
    end
    if #active > 0 then
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            local near = nearGroups(GetEntityCoords(vehicle), DETECT + 12.0)
            if near[1] then handleVehicle(vehicle, near[1]) end
        end
    end
    -- Contournements terminés (arrivés, véhicule disparu, dispositif retiré, trop long) : reprise de la route
    local now = GetGameTimer()
    for vehicle, info in pairs(tracked) do
        local alive = false
        for _, g in ipairs(groups) do if g == info.group then alive = true break end end
        if not DoesEntityExist(vehicle) then
            tracked[vehicle] = nil
        elseif not alive or (info.target and #(GetEntityCoords(vehicle) - info.target) < 4.0)
            or (info.since and now - info.since > (T.MaxDeviateTime or 15000)) then
            resume(vehicle, info)
        end
    end
    return #active > 0 or next(tracked) ~= nil
end

local dirty = false -- plots changés : vérification tout de suite (sans attendre la vérification lente)

local function start()
    if running or #groups == 0 then return end
    running = true
    CreateThread(function()
        while running do
            if #groups == 0 and next(tracked) == nil then break end
            dirty = false
            local busy = tick()
            if busy then
                Wait(INTERVAL)
            else
                -- aucun dispositif à portée : vérification lente (distance seulement), sauf si les plots changent
                local wake = GetGameTimer() + 2000
                repeat Wait(INTERVAL) until dirty or GetGameTimer() >= wake
            end
        end
        running = false
    end)
end

local function refresh(list)
    buildGroups(list)
    dirty = true
    start()
end

AddStateBagChangeHandler('rpCones', 'global', function(_, _, value) refresh(value) end)
CreateThread(function() refresh(GlobalState.rpCones) end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    removeZones()
    for vehicle, info in pairs(tracked) do resume(vehicle, info) end
end)
