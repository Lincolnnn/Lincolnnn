--[[
    RP TrafficControl - client : mesures appliquées au réseau routier du jeu et aux PNJ
    ----------------------------------------------------------------------------------
    Le serveur publie les mesures (GlobalState.rpTraffic) ; chaque joueur les applique à SON jeu (les nœuds et les
    zones de vitesse sont propres à chaque client ; un PNJ est dirigé par le joueur qui le contrôle).

    Une mesure = un TRONÇON (début -> fin, dans le sens de la circulation concernée) et une PORTÉE :
      'lane' (une voie), 'direction' (un sens), 'road' (route entière).
    Dans GTA V, une route n'a qu'UNE ligne de nœuds (au centre ; chaque liaison porte un nombre de voies par sens) ;
    sur les autoroutes, chaque sens est une chaussée séparée, avec ses propres nœuds. D'où :
      - FERMETURE : les nœuds retenus à la pose (ceux qui ne servent qu'à la portée choisie) sont FERMÉS (les PNJ
        n'y passent plus, aucun véhicule n'y apparaît). Et pour ce que les nœuds ne permettent pas :
          * une voie : les PNJ de cette voie se rabattent AVANT le tronçon sur la voie la plus proche DU MÊME SENS,
            la dépassent, puis reprennent leur route ; aucune voie du même sens : demi-tour ;
          * un sens / la route : route recalculée à l'approche, puis demi-tour s'ils continuent vers le tronçon.
      - RALENTISSEMENT / ARRÊT : zone de vitesse du jeu sur les nœuds retenus, et les PNJ de la bande choisie
        (voie / sens / route) ralentissent ou s'arrêtent avant le tronçon ; les autres voies circulent normalement.
    Mesure levée : réseau routier rendu à l'original, PNJ relâchés (route et vitesse normales).

    Performance : aucune boucle sans mesure à moins de Config.Range m (400) ; sinon une vérification toutes les
    Config.Interval ms (300) des PNJ que ce joueur contrôle près des tronçons.
]]

TC = TC or {}
local Config = TrafficConfig
local SEG = Config.Segment or {}
local CL = Config.Closure or {}
local SP = Config.Speed or {}
local MPH = 0.44704

TC.measures = {}
local applied = { nodesOff = {}, zones = {}, blips = {} }
local active = {}     -- mesures préparées pour les PNJ (repère du tronçon)
local tracked = {}    -- [véhicule] = { id, phase, driver, at, target }
local running = false

-- =========================================================================
-- OUTILS PARTAGÉS (editor.lua, menu.lua)
-- =========================================================================
--- Herse de Riven (riven_spikes) en main ou son cordon tenu : ses touches (E, G, X, Q, molette) ont la priorité
local SPIKE_MODES = { holding = true, cord = true, throwing = true, busy = true }
function TC.spikesBusy()
    if LocalPlayer.state.rivenSpikeHand ~= nil then return true end
    if GetResourceState('riven_spikes') ~= 'started' then return false end
    local ok, mode = pcall(function() return exports.riven_spikes:getMode() end)
    return ok and SPIKE_MODES[mode] == true
end

function TC.notify(text)
    if GetResourceState('rp_chat') == 'started'
        and pcall(function() exports.rp_chat:addPrivate({ title = 'Trafic', text = text }) end) then
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end

--- Lieu lisible (noms du MDC si présent : rues d'Atlanta ; sinon ceux du jeu)
function TC.locationText(p)
    local mdc = GlobalState.mdcResource
    if mdc and GetResourceState(mdc) == 'started' then
        local ok, text = pcall(function() return exports[mdc]:GetLocationText(vector3(p.x, p.y, p.z)) end)
        if ok and type(text) == 'string' and text ~= '' then return text end
    end
    return GetStreetNameFromHashKey((GetStreetNameAtCoord(p.x, p.y, p.z)))
end

function TC.isPolice()
    local unit = LocalPlayer.state.mdcUnit
    return unit ~= nil and unit ~= false and unit ~= ''
end

local COMPASS = { 'nord', 'nord-est', 'est', 'sud-est', 'sud', 'sud-ouest', 'ouest', 'nord-ouest' }
--- Direction lisible d'un vecteur (x, y) : "nord-est"…
function TC.compass(x, y)
    local deg = (math.deg(math.atan(x, y)) + 360.0) % 360.0
    return COMPASS[math.floor((deg + 22.5) / 45.0) % 8 + 1]
end

--- Nom d'une voie : 1 = la plus à gauche dans le sens de circulation
function TC.laneName(index, count)
    if not index or not count or count <= 1 then return 'voie unique' end
    if index == 1 then return 'voie de gauche' end
    if index == count then return 'voie de droite' end
    return count == 3 and 'voie centrale' or ('voie %d'):format(index)
end

--- Repère d'un tronçon : origine (début), axe unitaire (sens), côté droit, longueur
function TC.frame(m)
    local dx, dy = m.b.x - m.a.x, m.b.y - m.a.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then return nil end
    local ax, ay = dx / length, dy / length
    return { ox = m.a.x, oy = m.a.y, ax = ax, ay = ay, rx = ay, ry = -ax, length = length }
end

--- Point -> (u le long du tronçon depuis le début, v sur le côté : + à droite du sens)
function TC.localUV(f, x, y)
    local px, py = x - f.ox, y - f.oy
    return px * f.ax + py * f.ay, px * f.rx + py * f.ry
end

--- (u, v) -> point du monde
function TC.worldAt(f, u, v, z)
    return vector3(f.ox + f.ax * u + f.rx * v, f.oy + f.ay * u + f.ry * v, z)
end

-- =========================================================================
-- RÉSEAU ROUTIER DE CE JEU : nœuds fermés, zones de vitesse, cartes
-- =========================================================================
local function nodeBox(n)
    local r, h = CL.NodeBox or 1.2, SEG.Height or 4.0
    return n.x - r, n.y - r, n.z - h, n.x + r, n.y + r, n.z + h
end

local function blipsAllowed()
    if Config.Blips == 'none' then return false end
    if Config.Blips == 'police' then return TC.isPolice() end
    return true
end

local KIND_NAME = { close = 'Fermeture', slow = 'Ralentissement', stop = 'Trafic arrêté' }
local SCOPE_NAME = { lane = 'voie', direction = 'sens', road = 'route' }

function TC.describe(m)
    local what = m.kind == 'slow' and ('Ralentissement %d MPH'):format(m.speed or 0) or KIND_NAME[m.kind] or 'Mesure'
    if m.scope == 'lane' then return ('%s : %s'):format(what, TC.laneName(m.laneIndex, m.laneCount)) end
    if m.scope == 'direction' then return ('%s : sens %s'):format(what, m.compass or '') end
    return ('%s : route entière'):format(what)
end

local function addBlips(m, f)
    local color = (Config.BlipColors or {})[m.kind] or 1
    local mid = TC.worldAt(f, f.length / 2, (m.vmin + m.vmax) / 2, (m.a.z + m.b.z) / 2)
    local area = AddBlipForArea(mid.x, mid.y, mid.z, math.max(m.vmax - m.vmin, 2.0) + 0.0, f.length + 0.0)
    SetBlipRotation(area, math.floor(GetHeadingFromVector_2d(f.ax, f.ay) + 0.5))
    SetBlipColour(area, color)
    SetBlipAlpha(area, 130)
    SetBlipDisplay(area, 3)
    local icon = AddBlipForCoord(mid.x, mid.y, mid.z)
    SetBlipSprite(icon, 1)
    SetBlipColour(icon, color)
    SetBlipScale(icon, 0.75)
    SetBlipAsShortRange(icon, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(TC.describe(m))
    EndTextCommandSetBlipName(icon)
    applied.blips[#applied.blips + 1] = area
    applied.blips[#applied.blips + 1] = icon
end

local function clearApplied()
    for _, n in ipairs(applied.nodesOff) do
        local x1, y1, z1, x2, y2, z2 = nodeBox(n)
        SetRoadsBackToOriginal(x1, y1, z1, x2, y2, z2, false)
    end
    for _, id in ipairs(applied.zones) do RemoveRoadNodeSpeedZone(id) end
    for _, blip in ipairs(applied.blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    applied = { nodesOff = {}, zones = {}, blips = {} }
end

local releaseAll, startLoop -- (plus bas)

--- Mesures publiées -> réseau routier de ce jeu. Tout est retiré puis redonné (deux mesures qui se chevauchent
--- restent appliquées quand on lève l'une des deux) ; changements rares : aucun coût en continu.
function TC.applyAll(list)
    clearApplied()
    TC.measures = type(list) == 'table' and list or {}
    active = {}
    local showBlips = blipsAllowed()
    for _, m in ipairs(TC.measures) do
        local f = m.a and m.b and TC.frame(m)
        if f then
            for _, n in ipairs(m.nodes or {}) do
                if m.kind == 'close' then
                    local x1, y1, z1, x2, y2, z2 = nodeBox(n)
                    SetRoadsInArea(x1, y1, z1, x2, y2, z2, false, false) -- nœud fermé : plus aucun PNJ ne passe
                    applied.nodesOff[#applied.nodesOff + 1] = n
                else
                    local mph = m.kind == 'stop' and 0 or (m.speed or 25)
                    applied.zones[#applied.zones + 1] = AddRoadNodeSpeedZone(n.x + 0.0, n.y + 0.0, n.z + 0.0,
                        (SP.NodeZoneRadius or 4.0) + 0.0, mph * MPH, false)
                end
            end
            active[#active + 1] = { m = m, f = f }
            if showBlips then addBlips(m, f) end
        end
    end
    releaseAll(true)
    if TC.onChange then TC.onChange() end
    startLoop()
end

AddStateBagChangeHandler('rpTraffic', 'global', function(_, _, value)
    SetTimeout(0, function() TC.applyAll(value) end)
end)

AddStateBagChangeHandler('mdcUnit', ('player:%d'):format(GetPlayerServerId(PlayerId())), function()
    if Config.Blips == 'police' then SetTimeout(0, function() TC.applyAll(GlobalState.rpTraffic) end) end
end)

CreateThread(function() TC.applyAll(GlobalState.rpTraffic) end)

-- =========================================================================
-- PNJ : changement de voie, demi-tour, ralentissement, arrêt
-- =========================================================================
local function measureById(id)
    for _, e in ipairs(active) do if e.m.id == id then return e end end
    return nil
end

local function resume(vehicle, info)
    tracked[vehicle] = nil
    local driver = info.driver
    if not DoesEntityExist(vehicle) or not DoesEntityExist(driver) or not NetworkHasControlOfEntity(driver)
        or GetPedInVehicleSeat(vehicle, -1) ~= driver then return end
    if info.phase == 'slow' then
        SetDriveTaskCruiseSpeed(driver, CL.ResumeSpeed or 17.0)       -- vitesse normale
    elseif info.phase == 'merge' or info.phase == 'pass' or info.phase == 'uturn' then
        TaskVehicleDriveWander(driver, vehicle, CL.ResumeSpeed or 17.0, CL.WanderStyle or 786603) -- reprend sa route
    end -- 'stop' : le freinage s'arrête tout seul ; 'replan' : il roule déjà librement
end

--- Mesures retirées / changées : PNJ relâchés (keep = garder ceux dont la mesure existe encore)
releaseAll = function(keep)
    for vehicle, info in pairs(tracked) do
        if not keep or not measureById(info.id) then resume(vehicle, info) end
    end
end

--- Vers où envoyer un PNJ (u, v dans le repère du tronçon, sens du tronçon)
local function driveTo(driver, vehicle, p, speed)
    TaskVehicleDriveToCoord(driver, vehicle, p.x, p.y, p.z, speed, 0, GetEntityModel(vehicle), CL.DrivingStyle or 786603, 3.0, true)
end

--- Demi-tour : vers l'arrière, sur une voie de l'autre sens (route à double sens), sinon un point loin derrière
local function uturn(e, vehicle, driver, info, sign, pos)
    local m, f = e.m, e.f
    local back
    local u = TC.localUV(f, pos.x, pos.y)
    if (m.oppositeLanes or 0) > 0 then
        -- voies d'en face (à gauche du sens concerné) : premier voie de l'autre sens
        local v = -((m.median or 0) / 2 + (m.laneWidth or 5.4) / 2)
        back = TC.worldAt(f, u - 120 * sign, v * sign, pos.z)
    else
        back = TC.worldAt(f, u - 150 * sign, 0, pos.z)
    end
    TaskVehicleDriveToCoordLongrange(driver, vehicle, back.x, back.y, back.z, CL.RedirectSpeed or 14.0, CL.DrivingStyle or 786603, 15.0)
    info.phase, info.at, info.target = 'uturn', GetGameTimer(), back
end

--- Voie ouverte la plus proche, du même sens que la voie fermée ; nil s'il n'y en a pas
local function openLane(m)
    local best, bestDist
    for _, off in ipairs(m.lanes or {}) do
        if math.abs(off - (m.closedLane or 0)) > 0.5 then
            local d = math.abs(off - m.closedLane)
            if not best or d < bestDist then best, bestDist = off, d end
        end
    end
    return best
end

local function handle(e, vehicle, driver, pos, fwd, speed, now)
    local m, f = e.m, e.f
    local along = fwd.x * f.ax + fwd.y * f.ay
    local sign = along > 0.3 and 1 or (along < -0.3 and -1 or 0)
    if sign == 0 or (m.scope ~= 'road' and sign ~= 1) then return false end
    local u, v = TC.localUV(f, pos.x, pos.y)
    local vmin, vmax = m.vmin, m.vmax
    if sign == -1 then u, v, vmin, vmax = f.length - u, -v, -m.vmax, -m.vmin end -- route entière, autre sens
    local info = tracked[vehicle]
    if info and info.id ~= m.id then return false end
    -- Hors de la bande : pas concerné, sauf un PNJ déjà rabattu sur une autre voie (suivi jusqu'à la fin du tronçon)
    local merging = info and (info.phase == 'merge' or info.phase == 'pass')
    if (v < vmin - 0.8 or v > vmax + 0.8) and not merging then return false end

    if m.kind == 'slow' then
        if u >= -(SP.SlowFrom or 25.0) and u <= f.length then
            if not info then
                SetDriveTaskCruiseSpeed(driver, (m.speed or 25) * MPH)
                tracked[vehicle] = { id = m.id, phase = 'slow', driver = driver, at = now }
            end
            return true
        end
        return false
    end

    if m.kind == 'stop' then
        if u >= -(SP.StopBefore or 20.0) and u <= f.length then
            TaskVehicleTempAction(driver, vehicle, 6, (Config.Interval or 300) + 900) -- freine et reste arrêté
            tracked[vehicle] = { id = m.id, phase = 'stop', driver = driver, at = now }
            return true
        end
        return false
    end

    -- FERMETURE
    local approach = CL.ApproachDistance or 60.0
    if m.scope == 'lane' then
        if u < -approach or u > f.length + 5 then return false end
        local target = openLane(m)
        if not target then
            -- aucune voie ouverte dans ce sens : demi-tour
            if not info or info.phase ~= 'uturn' then
                local new = { id = m.id, driver = driver }
                tracked[vehicle] = new
                uturn(e, vehicle, driver, new, 1, pos)
            end
            return true
        end
        local z = pos.z
        if u < -2 then
            -- se rabat AVANT le tronçon sur la voie ouverte du même sens
            if not info or info.phase ~= 'merge' then
                driveTo(driver, vehicle, TC.worldAt(f, 2, target, z), math.max(8.0, math.min(speed, CL.RedirectSpeed or 14.0)))
                tracked[vehicle] = { id = m.id, phase = 'merge', driver = driver, at = now }
            end
        elseif not info or info.phase ~= 'pass' then
            -- longe le tronçon sur cette voie, puis reprend sa route
            driveTo(driver, vehicle, TC.worldAt(f, f.length + 15, target, z), math.max(8.0, math.min(speed, CL.RedirectSpeed or 14.0)))
            tracked[vehicle] = { id = m.id, phase = 'pass', driver = driver, at = now }
        end
        return true
    end

    -- Sens / route fermés : route recalculée à l'approche, demi-tour s'il continue vers le tronçon
    if u > -1 or u < -approach then return false end
    if not info then
        if u < -(CL.ReplanDistance or 45.0) * 0.5 then
            TaskVehicleDriveWander(driver, vehicle, math.max(speed, 10.0), CL.WanderStyle or 786603)
            tracked[vehicle] = { id = m.id, phase = 'replan', driver = driver, at = now }
        else
            tracked[vehicle] = { id = m.id, driver = driver }
            uturn(e, vehicle, driver, tracked[vehicle], sign, pos)
        end
    elseif info.phase == 'replan' and now - info.at > 1500 and u > -(CL.ReplanDistance or 45.0) * 0.5 then
        uturn(e, vehicle, driver, info, sign, pos)
    end
    return true
end

local function tick()
    local here = GetEntityCoords(PlayerPedId())
    local near = {}
    for _, e in ipairs(active) do
        local mid = TC.worldAt(e.f, e.f.length / 2, 0, 0)
        local dx, dy = mid.x - here.x, mid.y - here.y
        if math.sqrt(dx * dx + dy * dy) < (Config.Range or 400.0) + e.f.length / 2 then near[#near + 1] = e end
    end
    local now = GetGameTimer()
    if #near > 0 then
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            local driver = GetPedInVehicleSeat(vehicle, -1)
            if driver ~= 0 and not IsPedAPlayer(driver) and NetworkHasControlOfEntity(driver) and not IsPedDeadOrDying(driver, true) then
                local pos, fwd, speed = GetEntityCoords(vehicle), GetEntityForwardVector(vehicle), GetEntitySpeed(vehicle)
                local handled = false
                for _, e in ipairs(near) do
                    if handle(e, vehicle, driver, pos, fwd, speed, now) then handled = true break end
                end
                local info = tracked[vehicle]
                -- Sorti de la mesure (dépassé le tronçon, changé de route, demi-tour fait) : relâché
                if info and not handled and info.phase ~= 'uturn' then resume(vehicle, info) end
            end
        end
    end
    for vehicle, info in pairs(tracked) do
        if not DoesEntityExist(vehicle) then
            tracked[vehicle] = nil
        elseif info.phase == 'uturn' and (now - (info.at or now) > 25000
            or (info.target and #(GetEntityCoords(vehicle) - info.target) < 20.0)) then
            resume(vehicle, info)
        end
    end
    return #near > 0 or next(tracked) ~= nil
end

startLoop = function()
    if running or #active == 0 then return end
    running = true
    CreateThread(function()
        while #active > 0 or next(tracked) ~= nil do
            local busy = tick()
            Wait(busy and (Config.Interval or 300) or 2000)
        end
        running = false
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    active = {}
    releaseAll(false)
    clearApplied() -- réseau routier rendu tel qu'il était
end)
