--[[
    Vehicle Control - dégâts visuels : le véhicule perd des morceaux (client, calculé par le CONDUCTEUR)
    ---------------------------------------------------------------------------------------------------
    Seulement après de VRAIS gros accidents, ou une addition d'accidents : chaque choc FORT (mur, voiture, poteau… pas
    un piéton ni un plot ; perte de vitesse brutale d'au moins MinDrop MPH) ajoute de l'USURE au côté touché (avant,
    arrière, gauche, droite : déduit du changement de vitesse ; un choc de côté abîme aussi un peu les pare-chocs).
    Quand l'usure d'un côté dépasse un seuil, la pièce peut tomber, par ordre de priorité :
      1. pare-choc (avant / arrière), 2. capot (avant) ou coffre (arrière), 3. pare-brise (avant),
      4. portières (côté, beaucoup plus tard et plus rarement), 5. roues (choc très violent ou usure extrême).
    Vitres du côté touché : peuvent éclater dès une usure moyenne. Carrosserie déjà très abîmée (WornBody) : seuils
    plus bas. Chaque morceau ne tombe qu'une fois ; tout revient à la réparation (usure remise à zéro). Pas de dégâts
    visuels sur les motos, vélos, bateaux, hélicoptères, avions, trains (SkipClasses). Le conducteur étant le
    propriétaire du véhicule, les morceaux perdus se voient chez tous les joueurs.
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

local function part(key) return Config[key] or {} end
local function roll(key) return math.random() < (part(key).Chance or 0.5) end

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

--- Dégâts visuels d'un choc fort : renvoie la liste des morceaux perdus (pour les tests / un autre script)
function VC.bodywork(vehicle, drop, side)
    if Config.Enabled == false or not DoesEntityExist(vehicle) then return {} end
    if (Config.SkipClasses or {})[GetVehicleClass(vehicle)] then return {} end
    if drop < (Config.MinDrop or 22.0) then return {} end -- accrochage : ne compte pas
    local w = addWear(vehicle, drop, side)
    -- carrosserie déjà très abîmée : les pièces lâchent plus tôt
    local k = GetVehicleBodyHealth(vehicle) < (Config.WornBody or 400.0) and (Config.WornFactor or 0.75) or 1.0
    local function worn(key, pool) return pool >= (part(key).Wear or math.huge) * k end
    local lost = {}
    if worn('Windows', w[side]) then smashWindows(vehicle, side) end
    -- 1. pare-chocs (le choc de côté les use aussi)
    for _, front in ipairs({ true, false }) do
        local pool = front and w.front or w.rear
        local hitThisEnd = side == (front and 'front' or 'rear') or side == 'left' or side == 'right'
        if hitThisEnd and worn('Bumper', pool) and roll('Bumper') and breakBumper(vehicle, front) then
            lost[#lost + 1] = front and 'bumper_f' or 'bumper_r'
        end
    end
    -- 2. capot / coffre
    if side == 'front' and worn('HoodTrunk', w.front) and roll('HoodTrunk') and dropDoor(vehicle, 4) then lost[#lost + 1] = 'hood' end
    if side == 'rear' and worn('HoodTrunk', w.rear) and roll('HoodTrunk') and dropDoor(vehicle, 5) then lost[#lost + 1] = 'trunk' end
    -- 3. pare-brise
    if side == 'front' and worn('Windscreen', w.front) and IsVehicleWindowIntact(vehicle, 6) and roll('Windscreen') then
        PopOutVehicleWindscreen(vehicle)
        lost[#lost + 1] = 'windscreen'
    end
    -- 4. portières : beaucoup plus tard, une au plus par choc
    if SIDE_DOORS[side] and worn('Door', w[side]) then
        for _, door in ipairs(SIDE_DOORS[side]) do
            if roll('Door') and dropDoor(vehicle, door) then
                lost[#lost + 1] = 'door' .. door
                break
            end
        end
    end
    -- 5. roues : choc très violent, ou usure extrême du côté
    local W = part('Wheel')
    if (drop >= (W.Drop or 60.0) or worn('Wheel', w[side])) and roll('Wheel') and breakWheel(vehicle, side) then
        lost[#lost + 1] = 'wheel'
        if math.random() < (W.Second or 0.25) and breakWheel(vehicle, side) then lost[#lost + 1] = 'wheel' end
    end
    return lost
end

VC.on('impact', function(vehicle, _, drop, velocity, hit)
    if VC.seat ~= -1 or (hit and hit.severity == 'light') then return end
    if drop < (Config.MinDrop or 22.0) then return end
    local side = VC.impactSide(vehicle, velocity or vector3(0.0, 0.0, 0.0), GetEntityVelocity(vehicle))
    VC.bodywork(vehicle, drop, side)
end)

-- Réparé : roues revenues, usure remise à zéro
VC.on('tick', function(_, vehicle)
    if (VC.lostWheels[vehicle] or VC.wear[vehicle]) and GetVehicleBodyHealth(vehicle) >= 999.0
        and GetVehicleEngineHealth(vehicle) >= 999.0 then
        VC.lostWheels[vehicle], VC.wear[vehicle] = nil, nil
    end
end)

VC.on('leave', function(vehicle, _, info)
    if info and info.gone then VC.lostWheels[vehicle], VC.wear[vehicle] = nil, nil end
end)
