--[[
    Vehicle Control - dégâts visuels : le véhicule perd des morceaux (client, calculé par le CONDUCTEUR)
    ---------------------------------------------------------------------------------------------------
    À chaque choc FORT (mur, voiture, poteau… pas un piéton ni un plot : voir client/main.lua), selon la perte de
    vitesse brutale (MPH) et le CÔTÉ touché (avant, arrière, gauche, droite : déduit du changement de vitesse) :
      - Light  (ex. 18 MPH) : vitres du côté touché qui éclatent (au hasard) ;
      - Heavy  (ex. 30 MPH) : pare-choc avant / arrière arraché, capot (avant) ou coffre (arrière) qui tombe,
        portière du côté touché qui tombe (côté) ;
      - Severe (ex. 45 MPH) : pare-brise éjecté (avant), une roue du côté touché arrachée, parfois deux.
    Chaque morceau ne tombe qu'une fois ; tout revient à la réparation (/repair, SetVehicleFixed…). Pas de dégâts
    visuels sur les motos, vélos, bateaux, hélicoptères, avions (SkipClasses). Le conducteur étant le propriétaire du
    véhicule, les morceaux perdus se voient chez tous les joueurs (synchronisation des dégâts du jeu).
    Performance : rien en dehors d'un choc.
]]

local Config = VCConfig.Bodywork or {}

local WHEELS = { -- os des roues -> numéro de roue du jeu
    { bone = 'wheel_lf', index = 0, front = true, left = true },
    { bone = 'wheel_rf', index = 1, front = true, left = false },
    { bone = 'wheel_lr', index = 2, front = false, left = true },
    { bone = 'wheel_rr', index = 3, front = false, left = false },
}
local SIDE_DOORS = { left = { 0, 2 }, right = { 1, 3 } }       -- portières avant / arrière
local SIDE_WINDOWS = { left = { 0, 2 }, right = { 1, 3 }, front = { 0, 1 }, rear = { 2, 3 } }

local function chance(key)
    local c = Config.Chances and Config.Chances[key]
    return math.random() < (c or 0.5)
end

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

local function smashWindows(vehicle, side)
    for _, index in ipairs(SIDE_WINDOWS[side] or {}) do
        if IsVehicleWindowIntact(vehicle, index) and chance('Window') then SmashVehicleWindow(vehicle, index) end
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

local function dropDoor(vehicle, door)
    if GetIsDoorValid(vehicle, door) and not IsVehicleDoorDamaged(vehicle, door) then
        SetVehicleDoorBroken(vehicle, door, false) -- false : elle tombe au sol (pas supprimée)
        return true
    end
    return false
end

--- Roues du côté touché, encore en place
local function wheelsOn(vehicle, side)
    local list = {}
    for _, w in ipairs(WHEELS) do
        local match = (side == 'front' and w.front) or (side == 'rear' and not w.front)
            or (side == 'left' and w.left) or (side == 'right' and not w.left)
        if match and GetEntityBoneIndexByName(vehicle, w.bone) ~= -1 and not (VC.lostWheels[vehicle] or {})[w.index] then
            list[#list + 1] = w
        end
    end
    return list
end

VC.lostWheels = {} -- [véhicule] = { [roue] = true } (le jeu ne dit pas si une roue est déjà partie)

local function breakWheel(vehicle, side)
    local list = wheelsOn(vehicle, side)
    if #list == 0 then return false end
    local w = table.remove(list, math.min(#list, math.floor(math.random() * #list) + 1))
    BreakOffVehicleWheel(vehicle, w.index, true, false, true, false) -- traînée de débris, roue au sol, pas de feu
    VC.lostWheels[vehicle] = VC.lostWheels[vehicle] or {}
    VC.lostWheels[vehicle][w.index] = true
    return true
end

--- Dégâts visuels d'un choc fort : renvoie la liste des morceaux perdus (pour les tests / un autre script)
function VC.bodywork(vehicle, drop, side)
    if Config.Enabled == false or not DoesEntityExist(vehicle) then return {} end
    if (Config.SkipClasses or {})[GetVehicleClass(vehicle)] then return {} end
    local lost = {}
    if drop >= (Config.Light or 18.0) then
        smashWindows(vehicle, side)
    end
    if drop >= (Config.Heavy or 30.0) then
        if (side == 'front' or side == 'rear') and chance('Bumper') and breakBumper(vehicle, side == 'front') then
            lost[#lost + 1] = side == 'front' and 'bumper_f' or 'bumper_r'
        end
        if side == 'front' and chance('HoodTrunk') and dropDoor(vehicle, 4) then lost[#lost + 1] = 'hood' end
        if side == 'rear' and chance('HoodTrunk') and dropDoor(vehicle, 5) then lost[#lost + 1] = 'trunk' end
        if SIDE_DOORS[side] then
            for _, door in ipairs(SIDE_DOORS[side]) do
                if chance('Door') and dropDoor(vehicle, door) then lost[#lost + 1] = 'door' .. door end
            end
        end
    end
    if drop >= (Config.Severe or 45.0) then
        if side == 'front' and chance('Windscreen') and IsVehicleWindowIntact(vehicle, 6) then
            PopOutVehicleWindscreen(vehicle)
            lost[#lost + 1] = 'windscreen'
        end
        if chance('Wheel') and breakWheel(vehicle, side) then
            lost[#lost + 1] = 'wheel'
            if chance('SecondWheel') and breakWheel(vehicle, side) then lost[#lost + 1] = 'wheel' end
        end
    end
    return lost
end

VC.on('impact', function(vehicle, _, drop, velocity, hit)
    if VC.seat ~= -1 or (hit and hit.severity == 'light') then return end
    if drop < (Config.Light or 18.0) then return end
    local side = VC.impactSide(vehicle, velocity or vector3(0.0, 0.0, 0.0), GetEntityVelocity(vehicle))
    VC.bodywork(vehicle, drop, side)
end)

-- Réparé : les roues reviennent
VC.on('tick', function(_, vehicle)
    local lost = VC.lostWheels[vehicle]
    if lost and GetVehicleBodyHealth(vehicle) >= 999.0 and GetVehicleEngineHealth(vehicle) >= 999.0 then
        VC.lostWheels[vehicle] = nil
    end
end)

VC.on('leave', function(vehicle, _, info)
    if info and info.gone then VC.lostWheels[vehicle] = nil end
end)
