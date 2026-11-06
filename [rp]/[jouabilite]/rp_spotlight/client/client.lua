--[[
    RP Spotlight - client
    ---------------------
    Projecteur(s) de portière des véhicules de config.lua (Vehicles) : côté conducteur (d) et, s'il est configuré, côté
    passager avant (p). La lumière est dessinée chez TOUS les joueurs proches à partir de l'état du véhicule « rpSpot »
    (publié par le serveur) ; le joueur qui tient le projecteur le voit bouger sans délai (valeurs locales).
    Modes : 0 manuel (direction par rapport au véhicule), 1 verrouillé (point du monde), 2 suivi (véhicule / personne).
    Performance : 0.00 ms hors d'un véhicule équipé et sans projecteur allumé à proximité ; une vérification de la
    place toutes les 500 ms à bord d'un véhicule ; boucle par image seulement pour dessiner un projecteur allumé
    (à moins de RenderDistance) ou pendant la visée.
]]

local C = SpotlightConfig or {}
local L = C.Light or {}
local RESOURCE = GetCurrentResourceName()

local function u32(h) return (math.tointeger(tonumber(h) or 0) or 0) & 0xFFFFFFFF end
local function vec(t, fallback)
    t = type(t) == 'table' and t or fallback
    return vector3((t[1] or t.x or 0.0) + 0.0, (t[2] or t.y or 0.0) + 0.0, (t[3] or t.z or 0.0) + 0.0)
end

-- [modèle] = { name, d = offset, p = offset }
local MODELS = {}
for name, def in pairs(C.Vehicles or {}) do
    if type(def) == 'table' then
        MODELS[u32(GetHashKey(name:lower()))] = {
            name = name:lower(),
            d = def.driver and vec(def.driver.offset, C.DefaultDriver or { -0.95, 0.8, 0.55 }) or nil,
            p = def.passenger and vec(def.passenger.offset, C.DefaultPassenger or { 0.95, 0.8, 0.55 }) or nil,
        }
    end
end
local override = {} -- [modèle][côté] = offset (réglage en jeu, /editspotlight : ce joueur seulement)

local function modelOf(vehicle) return MODELS[u32(GetEntityModel(vehicle))] end
local function offsetOf(vehicle, side)
    local m = modelOf(vehicle)
    if not m then return nil end
    local o = override[u32(GetEntityModel(vehicle))]
    return (o and o[side]) or m[side]
end

-- =========================================================================
-- GÉOMÉTRIE : direction relative au véhicule (yaw, pitch en degrés) <-> direction dans le monde
-- =========================================================================
local function axes(vehicle)
    local pos = GetEntityCoords(vehicle)
    return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 1.0, 0.0) - pos,
        GetOffsetFromEntityInWorldCoords(vehicle, 1.0, 0.0, 0.0) - pos,
        GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, 1.0) - pos
end

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function norm(v)
    local l = math.sqrt(dot(v, v))
    if l < 1e-6 then return vector3(0.0, 1.0, 0.0) end
    return v / l
end

--- Débattement du projecteur : celui du conducteur, inversé (gauche / droite) pour le passager
local function limits(side)
    local y, p = C.Yaw or { Min = -110.0, Max = 50.0 }, C.Pitch or { Min = -35.0, Max = 25.0 }
    if side == 'p' then return -y.Max, -y.Min, p.Min, p.Max end
    return y.Min, y.Max, p.Min, p.Max
end

local function clampAngles(side, yaw, pitch)
    local y1, y2, p1, p2 = limits(side)
    return math.max(y1, math.min(y2, yaw)), math.max(p1, math.min(p2, pitch))
end

local function toWorld(vehicle, yaw, pitch)
    local f, r, u = axes(vehicle)
    local cy, sy = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
    local cp, sp = math.cos(math.rad(pitch)), math.sin(math.rad(pitch))
    return norm((f * cy + r * sy) * cp + u * sp)
end

local function toRelative(vehicle, dir)
    local f, r, u = axes(vehicle)
    local yaw = math.deg(math.atan(dot(dir, r), dot(dir, f)))
    local pitch = math.deg(math.asin(math.max(-1.0, math.min(1.0, dot(dir, u)))))
    return yaw, pitch
end

-- =========================================================================
-- PROJECTEUR TENU PAR CE JOUEUR
-- =========================================================================
local my = nil          -- { veh, side, on, yaw, pitch, mode, tx, ty, tz, net, strobe }
local aiming = false
local lastSend = 0
local lit = {}          -- [véhicule] = true : projecteurs allumés publiés (état rpSpot)
local smooth = {}       -- [véhicule .. côté] = { yaw, pitch } : direction affichée (autres joueurs : lissée)
local renderRunning = false

local function notify(text)
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started' and pcall(function() exports[chat]:addPrivate({ title = 'Projecteur', text = text }) end) then return end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end

--- Place du joueur dans ce véhicule -> projecteur tenu ('d', 'p') ou nil
local function seatSide(ped, vehicle)
    local m = modelOf(vehicle)
    if not m then return nil end
    if GetPedInVehicleSeat(vehicle, -1) == ped then return m.d and 'd' or nil end
    if GetPedInVehicleSeat(vehicle, 0) == ped and m.p then return 'p' end
    return nil
end

local function published(vehicle, side)
    local st = Entity(vehicle).state.rpSpot
    return type(st) == 'table' and type(st[side]) == 'table' and st[side] or nil
end

local function send(force)
    if not my then return end
    local now = GetGameTimer()
    if not force and now - lastSend < (C.SendMs or 100) then return end
    lastSend = now
    TriggerServerEvent('rp_spotlight:set', VehToNet(my.veh), my.side, {
        on = my.on, yaw = math.floor(my.yaw * 10 + 0.5) / 10, pitch = math.floor(my.pitch * 10 + 0.5) / 10,
        mode = my.mode, tx = my.tx, ty = my.ty, tz = my.tz, net = my.net, strobe = my.strobe })
end

-- Panneau d'état (mode, plaque suivie, stroboscope) et réticule
local lastUi = nil
local function sendUi()
    local key = my and my.on and ('%d:%s:%s:%s:%s'):format(my.mode, tostring(my.plate), tostring(my.strobe), my.side, tostring(aiming)) or 'off'
    if key == lastUi then return end
    lastUi = key
    if not (my and my.on) then
        SendNUIMessage({ action = 'status', data = { show = false, aim = aiming } })
    else
        SendNUIMessage({ action = 'status', data = { show = true, mode = my.mode, plate = my.plate, strobe = my.strobe,
            side = my.side == 'p' and 'Passager' or 'Conducteur', aim = aiming } })
    end
end

local startRender -- défini plus bas

local function setOn(on)
    if not my then return end
    my.on = on
    if not on then my.mode, my.net, my.plate = 0, nil, nil end
    send(true)
    sendUi()
    if on then lit[my.veh] = true; startRender() end
end

--- Point / entité visés par la caméra (réticule au centre de l'écran)
local function cameraAim(vehicle)
    local cam = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(z) * math.cos(x), math.cos(z) * math.cos(x), math.sin(x))
    local dist = C.RaycastDistance or 120.0
    local to = cam + dir * dist
    local handle = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, -1, vehicle, 4)
    local _, hit, point, _, entity = GetShapeTestResult(handle)
    if hit == 1 or hit == true then return point, entity end
    return to, 0
end

--- Direction actuelle d'un projecteur (lumière, lissage) : selon son mode ; retourne aussi si la cible est perdue
local function aimOf(vehicle, side, s, origin)
    if s.mode == 1 and tonumber(s.tx) then
        local yaw, pitch = toRelative(vehicle, norm(vector3(s.tx, s.ty, s.tz) - origin))
        return clampAngles(side, yaw, pitch)
    elseif s.mode == 2 and s.net then
        local entity = NetworkDoesNetworkIdExist(s.net) and NetworkGetEntityFromNetworkId(s.net) or 0
        if entity ~= 0 and DoesEntityExist(entity) then
            local target = GetEntityCoords(entity) + vector3(0.0, 0.0, IsEntityAPed(entity) and 0.3 or 0.6)
            if #(target - origin) <= (C.RaycastDistance or 120.0) * 1.5 then
                local yaw, pitch = toRelative(vehicle, norm(target - origin))
                return clampAngles(side, yaw, pitch)
            end
        end
        return s.yaw or 0.0, s.pitch or 0.0, true -- cible perdue
    end
    return s.yaw or 0.0, s.pitch or 0.0
end

-- =========================================================================
-- DESSIN (chez tous) : chaque projecteur allumé à portée, à chaque image
-- =========================================================================
local SHADOW_BASE = 4200
startRender = function()
    if renderRunning then return end
    renderRunning = true
    CreateThread(function()
        local color = L.Color or { 235, 240, 255 }
        local lastFrame = GetGameTimer()
        while next(lit) ~= nil or (my and my.on) do
            local now = GetGameTimer()
            local dt = math.min(0.1, (now - lastFrame) / 1000.0)
            lastFrame = now
            local me = GetEntityCoords(PlayerPedId())
            local strobeOff = math.floor(now / (C.StrobeMs or 75)) % 2 == 1
            local index = 0
            for vehicle in pairs(lit) do
                if not DoesEntityExist(vehicle) then
                    lit[vehicle] = nil
                elseif #(GetEntityCoords(vehicle) - me) <= (C.RenderDistance or 160.0) then
                    for _, side in ipairs({ 'd', 'p' }) do
                        index = index + 1
                        local mine = my and my.veh == vehicle and my.side == side
                        local s = mine and my or published(vehicle, side)
                        local offset = s and s.on and offsetOf(vehicle, side)
                        if offset then
                            local origin = GetOffsetFromEntityInWorldCoords(vehicle, offset.x, offset.y, offset.z)
                            local yaw, pitch, lost = aimOf(vehicle, side, s, origin)
                            if mine and lost then
                                -- cible suivie perdue : retour en manuel, dans sa dernière direction
                                my.mode, my.net, my.plate = 0, nil, nil
                                send(true); sendUi()
                            end
                            local key = tostring(vehicle) .. side
                            local sm = smooth[key]
                            if mine or not sm then
                                sm = { yaw = yaw, pitch = pitch }
                                smooth[key] = sm
                            else
                                local k = math.min(1.0, dt * 12.0)
                                sm.yaw = sm.yaw + (yaw - sm.yaw) * k
                                sm.pitch = sm.pitch + (pitch - sm.pitch) * k
                            end
                            if mine and my.mode ~= 0 then my.yaw, my.pitch = yaw, pitch end
                            if not (s.strobe and strobeOff) then
                                local dir = toWorld(vehicle, sm.yaw, sm.pitch)
                                DrawSpotLightWithShadow(origin.x, origin.y, origin.z, dir.x, dir.y, dir.z, color[1], color[2], color[3],
                                    L.Distance or 90.0, L.Brightness or 22.0, L.Roundness or 4.0, L.Radius or 9.0, L.Falloff or 60.0,
                                    SHADOW_BASE + index)
                                if L.Lamp ~= false then
                                    local glow = origin + dir * 0.12
                                    DrawLightWithRange(glow.x, glow.y, glow.z, color[1], color[2], color[3], 0.6, 3.0)
                                end
                            end
                        end
                    end
                end
            end
            -- le sien, pas encore publié (ou éteint chez les autres) : dessiné quand même
            if my and my.on and not lit[my.veh] then lit[my.veh] = true end
            Wait(0)
        end
        renderRunning = false
    end)
end

AddStateBagChangeHandler('rpSpot', nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle == 0 then return end
    if type(value) == 'table' and ((value.d and value.d.on) or (value.p and value.p.on)) then
        lit[vehicle] = true
        startRender()
    else
        lit[vehicle] = nil
    end
end)

-- =========================================================================
-- VISÉE (touche maintenue) : le projecteur suit la caméra ; clic gauche verrouille, clic droit suit
-- =========================================================================
local function aimLoop()
    CreateThread(function()
        while aiming and my do
            local ped = PlayerPedId()
            if GetVehiclePedIsIn(ped, false) ~= my.veh or IsPauseMenuActive() then break end
            -- clics : au projecteur, pas aux armes / au klaxon
            for _, c in ipairs({ 24, 25, 68, 69, 70, 91, 92, 114, 140, 141, 142, 257, 263 }) do DisableControlAction(0, c, true) end
            local offset = offsetOf(my.veh, my.side)
            local origin = GetOffsetFromEntityInWorldCoords(my.veh, offset.x, offset.y, offset.z)
            local point, entity = cameraAim(my.veh)
            local yaw, pitch = clampAngles(my.side, toRelative(my.veh, norm(point - origin)))
            local lock = IsDisabledControlJustPressed(0, 24) or IsDisabledControlJustPressed(0, 69) or IsDisabledControlJustPressed(0, 92)
            local track = IsDisabledControlJustPressed(0, 25) or IsDisabledControlJustPressed(0, 68) or IsDisabledControlJustPressed(0, 91)
            if lock then
                if my.mode == 1 then my.mode = 0
                else my.mode, my.tx, my.ty, my.tz, my.net, my.plate = 1, point.x, point.y, point.z, nil, nil end
                send(true); sendUi()
            elseif track then
                if my.mode == 2 then
                    my.mode, my.net, my.plate = 0, nil, nil
                elseif entity ~= 0 and DoesEntityExist(entity) and (IsEntityAVehicle(entity) or IsEntityAPed(entity))
                    and NetworkGetEntityIsNetworked(entity) then
                    my.mode, my.net = 2, NetworkGetNetworkIdFromEntity(entity)
                    my.plate = IsEntityAVehicle(entity) and GetVehicleNumberPlateText(entity):gsub('^%s+', ''):gsub('%s+$', '') or nil
                else
                    notify('Rien à suivre ici : visez un véhicule ou une personne.')
                end
                send(true); sendUi()
            end
            if my.mode == 0 then
                my.yaw, my.pitch = yaw, pitch
                send(false)
            end
            Wait(0)
        end
        aiming = false
        SendNUIMessage({ action = 'aim', data = { on = false } })
        if my then send(true) end
        sendUi()
    end)
end

local pressAt, holding = 0, false
RegisterCommand('+rp_spotlight', function()
    if not my or IsPauseMenuActive() then return end
    pressAt, holding = GetGameTimer(), true
    local pressed = pressAt
    SetTimeout(C.HoldMs or 220, function()
        if holding and pressAt == pressed and my and not aiming then
            if not my.on then setOn(true) end
            aiming = true
            SendNUIMessage({ action = 'aim', data = { on = true } })
            sendUi()
            aimLoop()
        end
    end)
end, false)
RegisterCommand('-rp_spotlight', function()
    if not holding then return end
    holding = false
    if aiming then aiming = false return end
    if my and GetGameTimer() - pressAt < (C.HoldMs or 220) then setOn(not my.on) end -- appui court : allumer / éteindre
end, false)
RegisterKeyMapping('+rp_spotlight', 'Projecteur : allumer / éteindre (appui), viser (maintenir)', 'keyboard', C.Key or 'LCONTROL')

RegisterCommand('rp_spotlight_strobe', function()
    if not my or not my.on then return end
    my.strobe = not my.strobe
    send(true); sendUi()
end, false)
RegisterKeyMapping('rp_spotlight_strobe', 'Projecteur : stroboscope', 'keyboard', C.StrobeKey or 'RSHIFT')

-- =========================================================================
-- PLACE DU JOUEUR : quel projecteur il tient (toutes les 500 ms à bord d'un véhicule ; 1 s sinon)
-- =========================================================================
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local side = vehicle ~= 0 and seatSide(ped, vehicle) or nil
        if not side then
            if my then my = nil; aiming = false; sendUi() end
        elseif not my or my.veh ~= vehicle or my.side ~= side then
            -- reprend l'état publié (projecteur déjà allumé par un collègue, ou laissé allumé)
            local p = published(vehicle, side) or {}
            my = { veh = vehicle, side = side, on = p.on == true, yaw = tonumber(p.yaw) or 0.0, pitch = tonumber(p.pitch) or -2.0,
                mode = tonumber(p.mode) or 0, tx = p.tx, ty = p.ty, tz = p.tz, net = p.net, strobe = p.strobe == true }
            if my.mode == 2 and not (my.net and NetworkDoesNetworkIdExist(my.net)) then my.mode, my.net = 0, nil end
            sendUi()
            if my.on then lit[vehicle] = true; startRender() end
        end
        Wait(vehicle ~= 0 and 500 or 1000)
    end
end)

-- =========================================================================
-- RÉGLAGE EN JEU : /editspotlight (projecteur conducteur), /editspotlightside (projecteur passager)
-- Point rouge sur le départ de la lumière, faisceau d'essai, panneau en haut au milieu ; ligne de config.lua à copier
-- =========================================================================
local editing = nil -- { veh, side }
local function configLine(vehicle)
    local m = modelOf(vehicle)
    local parts = {}
    for _, side in ipairs({ 'd', 'p' }) do
        local o = offsetOf(vehicle, side)
        if o then
            parts[#parts + 1] = ('%s = { offset = { %.2f, %.2f, %.2f } }'):format(side == 'd' and 'driver' or 'passenger', o.x, o.y, o.z)
        end
    end
    return ('%s = { %s },'):format(m.name, table.concat(parts, ', '))
end

--- Pendant le réglage, à chaque image : point rouge au départ de la lumière ; faisceau d'essai si ce projecteur est éteint
local function editLoop()
    CreateThread(function()
        local color = L.Color or { 235, 240, 255 }
        while editing do
            local vehicle, side = editing.veh, editing.side
            local offset = DoesEntityExist(vehicle) and offsetOf(vehicle, side)
            if not offset then break end
            local o = GetOffsetFromEntityInWorldCoords(vehicle, offset.x, offset.y, offset.z)
            DrawMarker(28, o.x, o.y, o.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.07, 0.07, 0.07, 255, 20, 20, 230,
                false, false, 2, false, nil, nil, false)
            local s = (my and my.veh == vehicle and my.side == side) and my or published(vehicle, side)
            if not (s and s.on) then
                local dir = toWorld(vehicle, 0.0, -4.0)
                DrawSpotLightWithShadow(o.x, o.y, o.z, dir.x, dir.y, dir.z, color[1], color[2], color[3],
                    L.Distance or 90.0, L.Brightness or 22.0, L.Roundness or 4.0, L.Radius or 9.0, L.Falloff or 60.0, 4299)
            end
            Wait(0)
        end
        if editing then editing = nil; SetNuiFocus(false, false); SendNUIMessage({ action = 'adjust', data = { on = false } }) end
    end)
end

local function startEdit(side)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    local m = vehicle ~= 0 and modelOf(vehicle)
    if not m then return notify('Montez dans un véhicule de la liste des projecteurs (config.lua : Vehicles).') end
    if not m[side] then
        return notify(side == 'p' and 'Ce véhicule n\'a pas de projecteur côté passager (config.lua : passenger).'
            or 'Ce véhicule n\'a pas de projecteur côté conducteur (config.lua : driver).')
    end
    if editing then return end
    editing = { veh = vehicle, side = side }
    local o = offsetOf(vehicle, side)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'adjust', data = { on = true, x = o.x, y = o.y, z = o.z, side = side == 'p' and 'passager (droite)' or 'conducteur (gauche)',
        model = m.name, line = configLine(vehicle) } })
    editLoop()
end
RegisterCommand(C.AdjustCommand or 'editspotlight', function() startEdit('d') end, false)
RegisterCommand(C.AdjustSideCommand or 'editspotlightside', function() startEdit('p') end, false)

RegisterNUICallback('offset', function(d, cb)
    cb({ ok = true })
    if not (editing and type(d) == 'table') then return end
    local hash = u32(GetEntityModel(editing.veh))
    override[hash] = override[hash] or {}
    override[hash][editing.side] = vector3(math.max(-3.0, math.min(3.0, tonumber(d.x) or 0.0)),
        math.max(-4.0, math.min(4.0, tonumber(d.y) or 0.0)), math.max(-1.0, math.min(3.0, tonumber(d.z) or 0.0)))
    SendNUIMessage({ action = 'line', data = { line = configLine(editing.veh) } })
end)

RegisterNUICallback('adjustDone', function(_, cb)
    cb({ ok = true })
    local vehicle = editing and editing.veh
    editing = nil
    SetNuiFocus(false, false)
    if vehicle and DoesEntityExist(vehicle) then
        local line = configLine(vehicle)
        print('[rp_spotlight] ligne pour config.lua (Vehicles) : ' .. line)
        notify('Réglage gardé pour vous jusqu\'à la déconnexion. Ligne pour config.lua (aussi dans la console F8) : ' .. line)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    if editing then SetNuiFocus(false, false) end
    if my and my.on then my.on = false; send(true) end
end)

RPSpotlight = { toWorld = toWorld, toRelative = toRelative, clampAngles = clampAngles, seatSide = seatSide, -- tests
    my = function() return my end, lit = lit, setOn = setOn, models = MODELS, offsetOf = offsetOf, editing = function() return editing end }
