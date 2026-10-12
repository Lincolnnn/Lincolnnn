--[[
    Vehicle Control - dégâts réalistes (client, calculés par le CONDUCTEUR)
    ----------------------------------------------------------------------
    Santé du moteur (1000 = neuf). Le véhicule encaisse comme un vrai, selon ce qu'il a percuté
    (reconnu au moment du choc, client/main.lua) :
      - choc LÉGER (piéton, moto, vélo, barrière, plot, compteur électrique, petits objets) : le moteur
        ne reçoit qu'une petite part des dégâts du jeu (LightMultiplier) ;
      - choc FORT (mur, décor fixe, voiture, lampadaire, poteau…) : dégâts du jeu (HeavyMultiplier),
        une part des dégâts de carrosserie (BodyToEngine) et, si le choc est violent (perte de vitesse
        brutale), des dégâts supplémentaires selon sa violence : un accrochage n'abîme presque rien, un
        vrai choc casse ;
      - sans choc (balles, explosion, chute) : OtherMultiplier ;
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

--- Santé du moteur après les dégâts `loss` reçus du jeu, ramenés à `multiplier` (moins de 1 : le
--- moteur encaisse mieux, une partie des dégâts du jeu est rendue)
local function scaleLoss(vehicle, engine, loss, multiplier)
    if loss <= 0.0 or multiplier == 1.0 then return engine end
    if multiplier > 1.0 then return hurtEngine(vehicle, engine, loss * (multiplier - 1.0)) end
    if engine <= 0.0 then return engine end -- déjà en feu : le jeu décide
    local health = math.min(engine + loss * (1.0 - multiplier), 1000.0)
    SetVehicleEngineHealth(vehicle, health)
    return health
end

local MULTIPLIER = { light = 'LightMultiplier', heavy = 'HeavyMultiplier' }

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
    -- Dégâts reçus depuis la dernière mesure (une hausse = réparation : simple mise à jour), selon ce
    -- qui a été percuté
    local loss, bodyLoss = math.max(last.engine - engine, 0.0), math.max(last.body - body, 0.0)
    if loss > 0.0 or bodyLoss > 0.0 then
        local hit = VC.currentHit(vehicle)
        local severity = hit and hit.severity or nil
        engine = scaleLoss(vehicle, engine, loss, Config[MULTIPLIER[severity] or 'OtherMultiplier'] or 1.0)
        if severity == 'heavy' then engine = hurtEngine(vehicle, engine, bodyLoss * Config.BodyToEngine) end
    end
    last.engine, last.body = engine, body

    -- Moteur critique : calages au hasard en roulant (il redémarre comme d'habitude)
    if engine < Config.Critical and engine > Config.Broken and GetIsVehicleEngineRunning(vehicle)
        and GetEntitySpeed(vehicle) * VC.MPH > 5.0 and math.random() < Config.StallChance * dt then
        SetVehicleEngineOn(vehicle, false, true, false)
    end
    updateState(vehicle, engine)
end)

-- Choc fort et violent (mur, voiture, lampadaire…) : dégâts supplémentaires selon la perte de vitesse
VC.on('impact', function(vehicle, _, drop, _, hit)
    if VC.seat ~= -1 or drop <= Config.ImpactMinDrop then return end
    if hit and hit.severity == 'light' then return end
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
