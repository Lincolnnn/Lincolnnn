--[[
    Vehicle Control - tonneaux accentués (client, calculé par le CONDUCTEUR)
    ------------------------------------------------------------------------
    Quand le véhicule part DÉJÀ en tonneau (penché de plus de Rollover.StartRoll degrés, plus sur ses quatre roues,
    à au moins MinSpeed MPH), sa rotation est relancée pour qu'il fasse davantage de tonneaux : vitesse de rotation
    autour de son axe avant au moins RollSpeed (rad/s) ou Boost x celle du moment, plus un petit élan vers le haut
    (Lift m/s). Au plus Max relances par accident, une toutes les Interval ms ; chaque relance peut faire éclater une
    vitre (SmashWindow). Remis à zéro dès que le véhicule est de nouveau sur ses roues.
    Le conducteur étant le propriétaire du véhicule, le mouvement est vu par tous les joueurs.
    Performance : une lecture de l'inclinaison dans la boucle du véhicule (100 ms) ; rien d'autre.
]]

local Config = VCConfig.Rollover or {}
local MPH = 2.236936
local rolls = {} -- [véhicule] = { boosts, last }

local function smashOne(vehicle)
    local intact = {}
    for index = 0, 3 do
        if IsVehicleWindowIntact(vehicle, index) then intact[#intact + 1] = index end
    end
    if #intact > 0 then SmashVehicleWindow(vehicle, intact[math.floor(math.random() * #intact) + 1]) end
end

--- Relance la rotation autour de l'axe avant du véhicule, dans le sens où il roule déjà
local function boost(vehicle, roll)
    local f = GetEntityForwardVector(vehicle)
    local w = GetEntityRotationVelocity(vehicle)
    local along = w.x * f.x + w.y * f.y + w.z * f.z -- rotation actuelle autour de l'axe avant
    local sign = math.abs(along) > 0.3 and (along > 0 and 1.0 or -1.0) or (roll > 0 and 1.0 or -1.0)
    local target = math.max(math.abs(along) * (Config.Boost or 1.35), Config.RollSpeed or 4.5) * sign
    local d = target - along
    SetEntityAngularVelocity(vehicle, w.x + f.x * d, w.y + f.y * d, w.z + f.z * d)
    local v = GetEntityVelocity(vehicle)
    local lift = Config.Lift or 1.8
    if v.z < lift then SetEntityVelocity(vehicle, v.x, v.y, lift) end
    if Config.SmashWindow ~= false and math.random() < 0.6 then smashOne(vehicle) end
end

VC.on('tick', function(_, vehicle)
    if Config.Enabled == false or VC.seat ~= -1 then return end
    local roll = GetEntityRoll(vehicle)
    local state = rolls[vehicle]
    if math.abs(roll) < (Config.StartRoll or 55.0) then
        if state and IsVehicleOnAllWheels(vehicle) then rolls[vehicle] = nil end -- retombé sur ses roues
        return
    end
    if IsVehicleOnAllWheels(vehicle) or GetEntitySpeed(vehicle) * MPH < (Config.MinSpeed or 30.0) then return end
    local now = GetGameTimer()
    state = state or { boosts = 0, last = 0 }
    rolls[vehicle] = state
    if state.boosts >= (Config.Max or 2) or now - state.last < (Config.Interval or 650) then return end
    state.boosts, state.last = state.boosts + 1, now
    boost(vehicle, roll)
end)

VC.on('leave', function(vehicle) rolls[vehicle] = nil end)
