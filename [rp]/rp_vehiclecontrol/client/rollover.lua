--[[
    Vehicle Control - tonneaux (client, calculé par le CONDUCTEUR)
    --------------------------------------------------------------
    1. DÉPART EN TONNEAU (Rollover.Trip) : un véhicule part plus facilement en tonneau quand il glisse sur le côté à
       une vitesse inadaptée :
         - DÉRAPAGE : il glisse latéralement d'au moins Trip.Slide m/s à au moins Trip.MinSpeed MPH ;
         - VIRAGE MAL ENGAGÉ : il penche déjà fort (roulis d'au moins Trip.Lean degrés, roues au sol) : chance x2 ;
         - PIT : juste après un choc de côté par un autre véhicule (Trip.PitWindow ms), une glissade moindre
           (Trip.PitSlide m/s) suffit et la chance est plus forte (Trip.PitChance).
       Chance toutes les 100 ms, selon l'intensité de la glissade et le type de véhicule (ClassFactor : SUV, utilitaires,
       tout-terrain plus hauts basculent plus vite ; sportives, supercars plus bas basculent moins). Le véhicule bascule
       du côté où il glisse (rotation Trip.RollSpeed rad/s, petit élan vers le haut Trip.Lift m/s).
    2. TONNEAUX ACCENTUÉS : quand il part en tonneau (penché de plus de StartRoll degrés, plus sur ses quatre roues, à
       au moins MinSpeed MPH), sa rotation est relancée pour qu'il en fasse davantage et plus vite : au moins RollSpeed
       rad/s ou Boost x celle du moment, plus un élan vers le haut (Lift) ; au plus Max relances par accident, une
       toutes les Interval ms ; chaque relance peut faire éclater une vitre (SmashWindow).
    Remis à zéro dès que le véhicule est de nouveau sur ses roues. Le conducteur étant le propriétaire du véhicule,
    le mouvement est vu par tous les joueurs. Pas de tonneaux forcés : motos, vélos, bateaux, aéronefs, trains.
    Performance : quelques lectures dans la boucle du véhicule (100 ms) ; rien d'autre.
]]

local Config = VCConfig.Rollover or {}
local Trip = Config.Trip or {}
local MPH = 2.236936
local rolls = {} -- [véhicule] = { boosts, last }
local lastTrip = 0

local function smashOne(vehicle)
    local intact = {}
    for index = 0, 3 do
        if IsVehicleWindowIntact(vehicle, index) then intact[#intact + 1] = index end
    end
    if #intact > 0 then SmashVehicleWindow(vehicle, intact[math.floor(math.random() * #intact) + 1]) end
end

--- Rotation autour de l'axe avant du véhicule portée à `target` rad/s (signe : côté du basculement) + élan vers le haut
local function spin(vehicle, target, lift)
    local f = GetEntityForwardVector(vehicle)
    local w = GetEntityRotationVelocity(vehicle)
    local along = w.x * f.x + w.y * f.y + w.z * f.z -- rotation actuelle autour de l'axe avant
    local d = target - along
    SetEntityAngularVelocity(vehicle, w.x + f.x * d, w.y + f.y * d, w.z + f.z * d)
    local v = GetEntityVelocity(vehicle)
    if v.z < lift then SetEntityVelocity(vehicle, v.x, v.y, lift) end
end

--- Relance la rotation dans le sens où il roule déjà
local function boost(vehicle, roll)
    local f = GetEntityForwardVector(vehicle)
    local w = GetEntityRotationVelocity(vehicle)
    local along = w.x * f.x + w.y * f.y + w.z * f.z
    local sign = math.abs(along) > 0.3 and (along > 0 and 1.0 or -1.0) or (roll > 0 and 1.0 or -1.0)
    spin(vehicle, math.max(math.abs(along) * (Config.Boost or 1.35), Config.RollSpeed or 4.5) * sign, Config.Lift or 1.8)
    if Config.SmashWindow ~= false and math.random() < 0.6 then smashOne(vehicle) end
end

--- Glissade latérale (m/s, positive : vers la droite du véhicule)
local function lateral(vehicle)
    local f = GetEntityForwardVector(vehicle)
    local v = GetEntityVelocity(vehicle)
    return v.x * f.y - v.y * f.x -- droite du véhicule = (f.y, -f.x)
end

--- Départ en tonneau : dérapage, virage mal engagé, PIT (voir l'en-tête)
local function tryTrip(vehicle, speedMph, roll)
    if Trip.Enabled == false or speedMph < (Trip.MinSpeed or 35.0) or not IsVehicleOnAllWheels(vehicle) then return false end
    local now = GetGameTimer()
    if now - lastTrip < (Trip.Cooldown or 4000) then return false end
    local slide = lateral(vehicle)
    local pit = VC.lastSideHit and now - VC.lastSideHit.at <= (Trip.PitWindow or 2500)
    local need = pit and (Trip.PitSlide or 5.0) or (Trip.Slide or 9.0)
    if math.abs(slide) < need then return false end
    local chance = (pit and (Trip.PitChance or 0.3) or (Trip.Chance or 0.05)) * math.min(2.0, math.abs(slide) / need)
    if math.abs(roll) >= (Trip.Lean or 14.0) then chance = chance * 2.0 end -- virage mal engagé : il penche déjà
    chance = chance * ((Trip.ClassFactor or {})[GetVehicleClass(vehicle)] or 1.0)
    if math.random() >= chance then return false end
    lastTrip = now
    spin(vehicle, (slide > 0 and 1.0 or -1.0) * (Trip.RollSpeed or 3.2), Trip.Lift or 2.4)
    return true
end
VC.tryTrip = tryTrip -- pour les tests

VC.on('tick', function(_, vehicle)
    if Config.Enabled == false or VC.seat ~= -1 or (Config.SkipClasses or {})[GetVehicleClass(vehicle)] then return end
    local roll = GetEntityRoll(vehicle)
    local speed = GetEntitySpeed(vehicle) * MPH
    local state = rolls[vehicle]
    if math.abs(roll) < (Config.StartRoll or 55.0) then
        if state and IsVehicleOnAllWheels(vehicle) then rolls[vehicle] = nil end -- retombé sur ses roues
        if not state then tryTrip(vehicle, speed, roll) end
        return
    end
    if IsVehicleOnAllWheels(vehicle) or speed < (Config.MinSpeed or 30.0) then return end
    local now = GetGameTimer()
    state = state or { boosts = 0, last = 0 }
    rolls[vehicle] = state
    if state.boosts >= (Config.Max or 2) or now - state.last < (Config.Interval or 650) then return end
    state.boosts, state.last = state.boosts + 1, now
    boost(vehicle, roll)
end)

VC.on('leave', function(vehicle) rolls[vehicle] = nil end)
