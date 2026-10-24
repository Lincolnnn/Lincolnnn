--[[
    Vehicle Control - dégâts visuels des accidents (client, calculé par le CONDUCTEUR ; véhicule percuté sans
    conducteur joueur : calculé par celui qui le contrôle, voir plus bas)
    ---------------------------------------------------------------------------------------------------
    Violence d'un choc : la perte de vitesse (on percute) ou la secousse (on est percuté, même à l'arrêt ou par
    l'arrière), en MPH. Le côté touché (avant, arrière, gauche, droite) vient du sens du choc ; pour un choc de côté,
    l'endroit (vers l'avant ou vers l'arrière du véhicule) vient de la position de l'autre véhicule.
    CE QUI S'OUVRE (ne se détache JAMAIS : le jeu ne peut plus arracher capot, coffre et portières) :
      - choc à l'ARRIÈRE (percuté par l'arrière, ou recule violemment dans un obstacle) : le COFFRE s'ouvre ;
      - choc à l'AVANT (percute, ou un véhicule recule dans le sien) : le CAPOT se soulève ;
      - choc de CÔTÉ : les PORTIÈRES touchées (avant / arrière selon l'endroit) s'ouvrent ;
      - très gros choc avant / arrière : une portière peut s'entrebâiller ; la sécurité saute (déverrouillé).
    CE QUI SE DÉTACHE (gros choc ou addition de chocs, usure par côté) : pare-chocs, pare-brise, roues.
    CE QUI S'ABÎME : bosses en plus au point d'impact (Deform : la carrosserie, les phares / feux à cet endroit),
    vitres du côté touché, pneu de la roue la plus proche qui éclate (Tyre).
    Véhicule percuté sans conducteur joueur (garé, PNJ) : le même calcul lui est appliqué par celui qui le contrôle
    (relayé par le serveur). Gros accident (Glass.MinDrop) : verre brisé au sol sous les vitres qui viennent de casser
    (client/glass.lua). Tout revient à la réparation. Pas de dégâts visuels sur les motos, vélos, bateaux, aéronefs,
    trains (SkipClasses). Performance : rien en dehors d'un choc.
]]

local Config = VCConfig.Bodywork or {}

local WHEELS = { -- os des roues -> numéro de roue et de pneu du jeu
    { bone = 'wheel_lf', index = 0, tyre = 0, front = true, left = true },
    { bone = 'wheel_rf', index = 1, tyre = 1, front = true, left = false },
    { bone = 'wheel_lr', index = 2, tyre = 4, front = false, left = true },
    { bone = 'wheel_rr', index = 3, tyre = 5, front = false, left = false },
}
VC.WHEELS = WHEELS
local SIDE_DOORS = { left = { front = 0, rear = 2 }, right = { front = 1, rear = 3 } }
local ALL_DOORS = { 0, 1, 2, 3 }
local HOOD, TRUNK = 4, 5
local SIDE_WINDOWS = { left = { 0, 2 }, right = { 1, 3 }, front = { 0, 1 }, rear = { 2, 3 } }
-- vitres (n° du jeu) et leur os, pour poser le verre brisé au bon endroit
local WINDOW_BONES = { [0] = 'window_lf', [1] = 'window_rf', [2] = 'window_lr', [3] = 'window_rr',
    [4] = 'window_lm', [5] = 'window_rm', [6] = 'windscreen', [7] = 'windscreen_r' }

local function part(key) return Config[key] or {} end
local function roll(key) return math.random() < (part(key).Chance or 0.5) end
local function opening(key) return (Config.Open or {})[key] or {} end

--- Côté touché : le choc pousse le véhicule à l'opposé de l'obstacle ; changement de vitesse ramené au véhicule
function VC.impactSide(vehicle, before, after)
    local dx, dy = before.x - after.x, before.y - after.y -- vers l'obstacle
    if dx * dx + dy * dy < 0.01 then return 'front' end
    local f = GetEntityForwardVector(vehicle)
    local forward = dx * f.x + dy * f.y
    local right = dx * f.y - dy * f.x
    if math.abs(forward) >= math.abs(right) then return forward >= 0 and 'front' or 'rear' end
    return right >= 0 and 'right' or 'left'
end

--- Côté de `vehicle` touché par `other` (position de l'autre dans le repère du véhicule) et endroit le long du
--- véhicule (-1 arrière … 1 avant)
function VC.sideFrom(vehicle, other)
    local p = GetOffsetFromEntityGivenWorldCoords(vehicle, GetEntityCoords(other))
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local halfL, halfW = math.max(0.5, (max.y - min.y) / 2), math.max(0.4, (max.x - min.x) / 2)
    local where = math.max(-1.0, math.min(1.0, p.y / halfL))
    if math.abs(p.y) / halfL >= math.abs(p.x) / halfW then return p.y >= 0 and 'front' or 'rear', where end
    return p.x >= 0 and 'right' or 'left', where
end

local function smashWindows(vehicle, side)
    for _, index in ipairs(SIDE_WINDOWS[side] or {}) do
        if IsVehicleWindowIntact(vehicle, index) and roll('Windows') then SmashVehicleWindow(vehicle, index) end
    end
end

--- Pare-choc arraché : grosse déformation à son emplacement (le jeu le détache), répétée au besoin
local function breakBumper(vehicle, front)
    if IsVehicleBumperBrokenOff(vehicle, front) then return false end
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local y = front and (max.y - 0.15) or (min.y + 0.15)
    local z = min.z + 0.45
    for _ = 1, 4 do
        SetVehicleDamage(vehicle, 0.0, y, z, Config.BumperForce or 900.0, 0.8, true)
        if IsVehicleBumperBrokenOff(vehicle, front) then return true end
    end
    return IsVehicleBumperBrokenOff(vehicle, front)
end

--- Capot, coffre ou portière qui s'OUVRE sous le choc (angle entre Angle[1] et Angle[2], 1 = grand ouvert) ; il
--- reste attaché au véhicule
local function openPanel(vehicle, door, angle)
    if not GetIsDoorValid(vehicle, door) or IsVehicleDoorDamaged(vehicle, door) then return false end
    angle = angle or { 0.2, 0.6 }
    if GetVehicleDoorAngleRatio(vehicle, door) >= angle[1] then return false end -- déjà ouvert
    SetDoorAllowedToBeBrokenOff(vehicle, door, false)
    SetVehicleDoorControl(vehicle, door, 1, angle[1] + math.random() * (angle[2] - angle[1]))
    return true
end

--- Capot, coffre et portières qui ne se détachent jamais (le jeu les arracherait sur un gros choc)
function VC.keepDoors(vehicle)
    if (Config.Open or {}).NeverFall == false then return end
    for door = 0, 5 do
        if GetIsDoorValid(vehicle, door) then SetDoorAllowedToBeBrokenOff(vehicle, door, false) end
    end
end

--- Roues du côté touché (et de l'endroit, pour un choc de côté), encore en place
local function wheelsOn(vehicle, side, where)
    local list = {}
    for _, w in ipairs(WHEELS) do
        local match = (side == 'front' and w.front) or (side == 'rear' and not w.front)
            or (side == 'left' and w.left) or (side == 'right' and not w.left)
        if match and where and (side == 'left' or side == 'right') and math.abs(where) > 0.3 then
            match = (where > 0) == w.front
        end
        if match and GetEntityBoneIndexByName(vehicle, w.bone) ~= -1 and not (VC.lostWheels[vehicle] or {})[w.index] then
            list[#list + 1] = w
        end
    end
    return list
end

VC.lostWheels = {} -- [véhicule] = { [roue] = true } (le jeu ne dit pas si une roue est déjà partie)

--- Une roue se détache (traînée de débris, roue au sol, pas de feu) ; `w` : une roue de WHEELS
function VC.breakWheel(vehicle, w)
    if not w or (VC.lostWheels[vehicle] or {})[w.index] or GetEntityBoneIndexByName(vehicle, w.bone) == -1 then return false end
    BreakOffVehicleWheel(vehicle, w.index, true, false, true, false)
    VC.lostWheels[vehicle] = VC.lostWheels[vehicle] or {}
    VC.lostWheels[vehicle][w.index] = true
    -- roues perdues, vues par tous (/inspectvehicle)
    local list = {}
    for index in pairs(VC.lostWheels[vehicle]) do list[#list + 1] = index end
    table.sort(list)
    if VC.setState then VC.setState(vehicle, 'vcWheels', list) end
    return true
end

local function breakWheel(vehicle, side, where)
    local list = wheelsOn(vehicle, side, where)
    if #list == 0 then return false end
    return VC.breakWheel(vehicle, list[math.min(#list, math.floor(math.random() * #list) + 1)])
end

--- Bosses en plus au point d'impact : la carrosserie (et les phares / feux qui s'y trouvent) se déforme davantage
local function deform(vehicle, sev, side, where)
    local D = part('Deform')
    if D.Enabled == false or sev < (D.Min or 24.0) then return end
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local halfL = (max.y - min.y) / 2
    local cy = (max.y + min.y) / 2
    local z = min.z + (max.z - min.z) * 0.4
    local x, y = 0.0, 0.0
    if side == 'front' then y = max.y - 0.1
    elseif side == 'rear' then y = min.y + 0.1
    else
        x = side == 'right' and (max.x - 0.05) or (min.x + 0.05)
        y = cy + (where or 0.0) * halfL * 0.8
    end
    local amount = math.min(D.Max or 450.0, (sev - (D.Min or 24.0)) * (D.Factor or 7.0) + 60.0)
    SetVehicleDamage(vehicle, x, y, z, amount, D.Radius or 0.8, true)
end

--- Pneu qui éclate : la roue la plus proche du point d'impact
local function burstTyre(vehicle, side, where)
    local list = wheelsOn(vehicle, side, where)
    if #list == 0 then return false end
    local w = list[math.min(#list, math.floor(math.random() * #list) + 1)]
    if IsVehicleTyreBurst(vehicle, w.tyre, false) then return false end
    SetVehicleTyreBurst(vehicle, w.tyre, false, 1000.0)
    return true
end

VC.wear = {} -- [véhicule] = { front, rear, left, right } : usure accumulée par côté

--- Usure ajoutée par un choc fort : le côté touché ; un choc de côté abîme aussi un peu les pare-chocs
local function addWear(vehicle, drop, side)
    local w = VC.wear[vehicle] or { front = 0.0, rear = 0.0, left = 0.0, right = 0.0 }
    VC.wear[vehicle] = w
    w[side] = w[side] + drop
    if side == 'left' or side == 'right' then
        local k = Config.SideToBumpers or 0.4
        w.front, w.rear = w.front + drop * k, w.rear + drop * k
    end
    return w
end

--- Dégâts visuels d'un choc fort (sev : violence en MPH ; side ; where : endroit le long du véhicule, -1 arrière …
--- 1 avant, ou nil) : renvoie la liste de ce qui s'est ouvert, détaché ou abîmé (pour les tests / un autre script)
function VC.bodywork(vehicle, sev, side, where)
    if Config.Enabled == false or not DoesEntityExist(vehicle) then return {} end
    if (Config.SkipClasses or {})[GetVehicleClass(vehicle)] then return {} end
    if sev < (Config.MinDrop or 22.0) then return {} end -- accrochage : ne compte pas
    local w = addWear(vehicle, sev, side)
    -- carrosserie déjà très abîmée : les pièces lâchent plus tôt
    local k = GetVehicleBodyHealth(vehicle) < (Config.WornBody or 400.0) and (Config.WornFactor or 0.75) or 1.0
    local function worn(key, pool) return pool >= (part(key).Wear or math.huge) * k end
    local lost = {}
    deform(vehicle, sev, side, where)
    if worn('Windows', w[side]) then smashWindows(vehicle, side) end

    -- CE QUI S'OUVRE (jamais détaché)
    local O = Config.Open or {}
    local wornOpen = w[side] >= (O.Wear or math.huge) * k
    local opened = false
    local function tryOpen(key, door, name)
        local o = opening(key)
        if (sev >= (o.Min or 25.0) or wornOpen) and math.random() < (o.Chance or 0.6) and openPanel(vehicle, door, o.Angle) then
            lost[#lost + 1] = name
            opened = true
        end
    end
    if side == 'rear' then tryOpen('Trunk', TRUNK, 'trunk_open') end
    if side == 'front' then tryOpen('Hood', HOOD, 'hood_open') end
    if SIDE_DOORS[side] then
        local o = opening('Doors')
        if sev >= (o.Min or 24.0) or wornOpen then
            local doors = SIDE_DOORS[side]
            local list = (where and where > 0.25) and { doors.front } or (where and where < -0.25) and { doors.rear }
                or { doors.front, doors.rear }
            local count = 0
            for _, door in ipairs(list) do
                if count < (o.Max or 2) and math.random() < (o.Chance or 0.6) and openPanel(vehicle, door, o.Angle) then
                    count = count + 1
                    opened = true
                    lost[#lost + 1] = 'door_open' .. door
                end
            end
        end
    else
        -- très gros choc avant / arrière : une portière peut s'entrebâiller (la sécurité saute)
        local o = opening('FrontRear')
        if sev >= (o.Min or 40.0) and math.random() < (o.Chance or 0.25) then
            for _, door in ipairs(ALL_DOORS) do
                if openPanel(vehicle, door, o.Angle) then
                    opened = true
                    lost[#lost + 1] = 'door_open' .. door
                    break
                end
            end
        end
    end
    if opened and O.Unlock ~= false then SetVehicleDoorsLocked(vehicle, 1) end -- 1 : déverrouillé

    -- CE QUI SE DÉTACHE : pare-chocs (le choc de côté les use aussi), pare-brise, roues
    for _, front in ipairs({ true, false }) do
        local pool = front and w.front or w.rear
        local hitThisEnd = side == (front and 'front' or 'rear') or side == 'left' or side == 'right'
        if hitThisEnd and worn('Bumper', pool) and roll('Bumper') and breakBumper(vehicle, front) then
            lost[#lost + 1] = front and 'bumper_f' or 'bumper_r'
        end
    end
    if side == 'front' and worn('Windscreen', w.front) and IsVehicleWindowIntact(vehicle, 6) and roll('Windscreen') then
        PopOutVehicleWindscreen(vehicle)
        lost[#lost + 1] = 'windscreen'
    end
    local W = part('Wheel')
    if (sev >= (W.Drop or 60.0) or worn('Wheel', w[side])) and roll('Wheel') and breakWheel(vehicle, side, where) then
        lost[#lost + 1] = 'wheel'
        if math.random() < (W.Second or 0.25) and breakWheel(vehicle, side, where) then lost[#lost + 1] = 'wheel' end
    end
    -- CE QUI S'ABÎME : pneu le plus proche qui éclate
    local T = part('Tyre')
    if sev >= (T.Min or 35.0) and math.random() < (T.Chance or 0.35) and burstTyre(vehicle, side, where) then
        lost[#lost + 1] = 'tyre'
    end
    return lost
end

-- =========================================================================
-- VERRE BRISÉ AU SOL : vitres qui viennent de casser lors d'un GROS accident (le jeu ou ce script)
-- =========================================================================
VC.windows = {} -- [véhicule] = { [n° vitre] = intacte } : état relevé juste AVANT le choc (pas pendant)
local windowBones = {} -- [véhicule] = { [n° vitre] = os } : vitres présentes sur ce modèle

local function windowState(vehicle)
    local bones = windowBones[vehicle]
    if not bones then
        bones = {}
        for index, bone in pairs(WINDOW_BONES) do
            local b = GetEntityBoneIndexByName(vehicle, bone)
            if b ~= -1 then bones[index] = b end
        end
        windowBones[vehicle] = bones
    end
    local state = {}
    for index in pairs(bones) do state[index] = IsVehicleWindowIntact(vehicle, index) end
    return state
end

--- Points au sol sous les vitres qui viennent de casser (vitre à l'extérieur du véhicule)
function VC.brokenGlass(vehicle, before)
    local points = {}
    local center = GetEntityCoords(vehicle)
    for index, intact in pairs(before or {}) do
        if intact and not IsVehicleWindowIntact(vehicle, index) then
            local p = GetWorldPositionOfEntityBone(vehicle, (windowBones[vehicle] or {})[index]
                or GetEntityBoneIndexByName(vehicle, WINDOW_BONES[index]))
            local dx, dy = p.x - center.x, p.y - center.y
            local len = math.sqrt(dx * dx + dy * dy)
            local out = (Config.Glass or {}).Outside or 0.35
            local x, y = p.x, p.y
            if len > 0.01 then x, y = p.x + dx / len * out, p.y + dy / len * out end
            local found, ground = GetGroundZFor_3dCoord(x, y, p.z + 0.5, false)
            points[#points + 1] = { x = x, y = y, z = (found and ground ~= 0.0) and ground or (p.z - 1.0), window = index }
        end
    end
    return points
end

--- Véhicule percuté sans conducteur joueur (garé, PNJ) : le serveur relaie à celui qui le contrôle
local function hitOther(vehicle, other, sev)
    local O = part('Other')
    if O.Enabled == false or not other or other == 0 or not DoesEntityExist(other) or GetEntityType(other) ~= 2 then return end
    local driver = GetPedInVehicleSeat(other, -1)
    if driver ~= 0 and IsPedAPlayer(driver) then return end -- son conducteur s'en occupe (secousse du choc)
    if not NetworkGetEntityIsNetworked(other) then return end
    local side, where = VC.sideFrom(other, vehicle)
    TriggerServerEvent('rp_vehiclecontrol:bodyworkOther', VehToNet(other), sev, side, where)
end

RegisterNetEvent('rp_vehiclecontrol:bodyworkOther', function(netId, sev, side, where)
    local vehicle = NetToVeh(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if vehicle == VC.vehicle and VC.seat == -1 then return end -- on le conduit : notre propre choc s'en occupe
    if not NetworkHasControlOfEntity(vehicle) then
        NetworkRequestControlOfEntity(vehicle)
        local untilTime = GetGameTimer() + 500
        while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < untilTime do Wait(0) end
    end
    VC.bodywork(vehicle, tonumber(sev) or 0.0, side, tonumber(where))
end)

VC.lastSideHit = nil -- { at, side } : choc de côté par un véhicule (PIT…) : tonneaux plus faciles (rollover.lua)

VC.on('impact', function(vehicle, _, drop, velocity, hit, jolt, after)
    if VC.seat ~= -1 or (hit and hit.severity == 'light') then return end
    local sev = math.max(drop or 0.0, (jolt or 0.0) * (Config.JoltFactor or 1.0))
    if sev < (Config.MinDrop or 22.0) then return end
    local side, where = VC.impactSide(vehicle, velocity or vector3(0.0, 0.0, 0.0), after or GetEntityVelocity(vehicle)), nil
    if hit and hit.kind == 'vehicle' and hit.entity and DoesEntityExist(hit.entity) then
        local s, w = VC.sideFrom(vehicle, hit.entity)
        if s == side or ((s == 'left' or s == 'right') and (side == 'left' or side == 'right')) then where = w end
        if side == 'left' or side == 'right' then VC.lastSideHit = { at = GetGameTimer(), side = side } end
        hitOther(vehicle, hit.entity, sev)
    end
    local before = VC.windows[vehicle]
    VC.bodywork(vehicle, sev, side, where)
    local G = Config.Glass or {}
    if G.Enabled ~= false and sev >= (G.MinDrop or 35.0) and before then
        local points = VC.brokenGlass(vehicle, before)
        if #points > 0 then TriggerServerEvent('rp_vehiclecontrol:glass', points) end
    end
    VC.windows[vehicle] = windowState(vehicle)
end)

VC.on('enter', function(_, vehicle)
    VC.windows[vehicle] = windowState(vehicle)
    if VC.seat == -1 then VC.keepDoors(vehicle) end
end)

-- Réparé : roues revenues, usure remise à zéro
VC.on('tick', function(_, vehicle)
    if (VC.lostWheels[vehicle] or VC.wear[vehicle]) and GetVehicleBodyHealth(vehicle) >= 999.0
        and GetVehicleEngineHealth(vehicle) >= 999.0 then
        VC.lostWheels[vehicle], VC.wear[vehicle] = nil, nil
        if VC.seat == -1 and VC.state(vehicle, 'vcWheels') then VC.setState(vehicle, 'vcWheels', false) end
    end
    -- vitres cassées entre deux chocs (balles…) : pas de verre au prochain choc ; jamais relevé pendant un choc
    if VC.seat == -1 and not VC.inCrash then VC.windows[vehicle] = windowState(vehicle) end
end)

VC.on('leave', function(vehicle, _, info)
    if info and info.gone then VC.lostWheels[vehicle], VC.wear[vehicle] = nil, nil end
    VC.windows[vehicle], windowBones[vehicle] = nil, nil
end)
