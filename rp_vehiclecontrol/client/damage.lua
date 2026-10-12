--[[
    Vehicle Control - dégâts réalistes (client, calculés par le CONDUCTEUR)
    ----------------------------------------------------------------------
    Santé du moteur (1000 = neuf) :
      - les dégâts reçus par le moteur sont multipliés (EngineMultiplier) et une partie des dégâts de
        la carrosserie s'y ajoute (BodyToEngine) : un accrochage abîme, un vrai choc casse ;
      - choc violent (perte de vitesse brutale) : dégâts supplémentaires selon la violence du choc ;
      - sous Damaged : puissance réduite ; sous Critical : encore moins de puissance et calages ;
      - sous Broken : véhicule CASSÉ : moteur coupé, impossible à redémarrer, logo rouge sur le car HUD
        (état du véhicule "vcBroken", vu par tous les occupants). Réparé (script de mécanicien,
        SetVehicleFixed…) : tout redevient normal tout seul.
    Ce script n'abaisse jamais le moteur sous EngineFloor : pas d'incendie causé par lui.
    Réservoir percé : fuite d'essence (fuel.lua).
]]

local Config = VCConfig.Damage

local last = { vehicle = 0, engine = 1000.0, body = 1000.0 }
local power = 1.0 -- puissance appliquée à chaque image (moteur abîmé)

--- Retire `amount` à la santé du moteur, sans descendre sous EngineFloor
local function hurtEngine(vehicle, engine, amount)
    if amount <= 0.0 or engine <= Config.EngineFloor then return engine end
    local health = math.max(engine - amount, Config.EngineFloor)
    SetVehicleEngineHealth(vehicle, health)
    return health
end

function VC.isBroken(vehicle)
    return GetVehicleEngineHealth(vehicle) <= Config.Broken
end

local function updateState(vehicle, engine)
    local broken = engine <= Config.Broken
    if broken then
        if GetIsVehicleEngineRunning(vehicle) then SetVehicleEngineOn(vehicle, false, true, true) end
        SetVehicleUndriveable(vehicle, true)
        if VC.state(vehicle, 'vcEngine') == true then VC.setState(vehicle, 'vcEngine', false) end
    end
    if (VC.state(vehicle, 'vcBroken') == true) ~= broken then
        if not broken then SetVehicleUndriveable(vehicle, false) end -- réparé
        VC.setState(vehicle, 'vcBroken', broken)
    end
    power = (engine < Config.Critical and Config.CriticalPower) or (engine < Config.Damaged and Config.DamagedPower) or 1.0
end

VC.on('enter', function(_, vehicle, seat)
    last = { vehicle = vehicle, engine = GetVehicleEngineHealth(vehicle), body = GetVehicleBodyHealth(vehicle) }
    if seat == -1 then updateState(vehicle, last.engine) end
end)

VC.on('seat', function(_, vehicle, seat)
    if seat == -1 then updateState(vehicle, GetVehicleEngineHealth(vehicle)) end
end)

VC.on('tick', function(_, vehicle, dt)
    local engine, body = GetVehicleEngineHealth(vehicle), GetVehicleBodyHealth(vehicle)
    if VC.seat ~= -1 then
        last.engine, last.body = engine, body
        return
    end
    -- Dégâts reçus depuis la dernière mesure (une hausse = réparation : simple mise à jour)
    local extra = math.max(last.engine - engine, 0.0) * (Config.EngineMultiplier - 1.0)
        + math.max(last.body - body, 0.0) * Config.BodyToEngine
    engine = hurtEngine(vehicle, engine, extra)
    last.engine, last.body = engine, body

    -- Moteur critique : calages au hasard en roulant (il redémarre comme d'habitude)
    if engine < Config.Critical and engine > Config.Broken and GetIsVehicleEngineRunning(vehicle)
        and GetEntitySpeed(vehicle) * VC.MPH > 5.0 and math.random() < Config.StallChance * dt then
        SetVehicleEngineOn(vehicle, false, true, false)
    end
    updateState(vehicle, engine)
end)

-- Choc violent : dégâts supplémentaires selon la perte de vitesse
VC.on('impact', function(vehicle, _, drop)
    if VC.seat ~= -1 or drop <= Config.ImpactMinDrop then return end
    local engine = GetVehicleEngineHealth(vehicle)
    engine = hurtEngine(vehicle, engine, (drop - Config.ImpactMinDrop) ^ 1.5 * Config.ImpactFactor)
    last.engine = engine
    updateState(vehicle, engine)
end)

-- Puissance réduite (à chaque image, seulement au volant d'un véhicule abîmé)
VC.on('frame', function(_, vehicle)
    if power < 1.0 and VC.seat == -1 then SetVehicleCheatPowerIncrease(vehicle, power) end
end)

VC.on('leave', function()
    power = 1.0
end)
