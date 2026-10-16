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
      - sous Damaged : puissance un peu réduite ;
      - PALIER 1, sous Critical : moteur TRÈS ABÎMÉ : il roule très lentement (puissance très réduite, vitesse
        bridée à CriticalMaxSpeed MPH), il cale (il repart tout seul après quelques secondes, ou avec la touche
        du moteur), de la fumée sort du capot (vue par tous : état du véhicule "vcDamaged") et les WARNINGS
        s'allument tout seuls (moteur allumé). Ils s'éteignent tout seuls quand le moteur est coupé (touche du
        moteur), quand le moteur passe au palier 2 ou quand il est réparé. Logo moteur orange sur le car HUD ;
      - PALIER 2, sous Broken : moteur DÉTRUIT : véhicule éteint, moteur coupé, impossible à rallumer, logo
        rouge sur le car HUD (état du véhicule "vcBroken", vu par tous les occupants).
      Réparé (/repair, script de mécanicien, SetVehicleFixed…) : tout redevient normal tout seul.
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

--- Palier du moteur : 0 en état de rouler, 1 très abîmé, 2 détruit
function VC.damageStage(vehicle)
    local engine = GetVehicleEngineHealth(vehicle)
    if engine <= Config.Broken then return 2 end
    if engine < Config.Critical then return 1 end
    return 0
end

local function stageOf(engine)
    if engine <= Config.Broken then return 2 end
    if engine < Config.Critical then return 1 end
    return 0
end

-- Vitesse bridée (palier 1), appliquée par le conducteur ; 0 = vitesse normale
local capped = { vehicle = 0, mps = 0.0 }
local function capSpeed(vehicle, mph)
    local mps = (mph or 0.0) / VC.MPH
    if capped.vehicle == vehicle and capped.mps == mps then return end
    if capped.vehicle ~= 0 and capped.vehicle ~= vehicle and DoesEntityExist(capped.vehicle) then
        SetVehicleMaxSpeed(capped.vehicle, 0.0)
    end
    capped = { vehicle = vehicle, mps = mps }
    SetVehicleMaxSpeed(vehicle, mps > 0.0 and mps or 0.0) -- 0 : vitesse d'origine
end

-- Warnings automatiques (palier 1) : allumés une fois par démarrage du moteur ; éteints au moteur coupé
-- (touche), au palier 2 ou à la réparation. Le conducteur peut les éteindre lui-même : ils ne sont pas rallumés
-- de force.
local autoHazards = nil -- véhicule dont les warnings ont été allumés automatiquement

local function updateHazards(vehicle, stage)
    if Config.CriticalHazards == false or not VC.setSignal then return end
    local wantedOn = VC.state(vehicle, 'vcEngine') == true
    if stage == 1 and wantedOn then
        if autoHazards ~= vehicle then
            autoHazards = vehicle
            if VC.state(vehicle, 'vcSignal') ~= 'hazard' then VC.setSignal(vehicle, 'hazard') end
        end
    elseif autoHazards == vehicle then
        -- Moteur coupé (touche du moteur), détruit (palier 2) ou réparé : warnings éteints
        autoHazards = nil
        if VC.state(vehicle, 'vcSignal') == 'hazard' then VC.setSignal(vehicle, false) end
    end
end

local function updateState(vehicle, engine)
    local stage = stageOf(engine)
    local broken = stage == 2
    if broken then
        if GetIsVehicleEngineRunning(vehicle) then SetVehicleEngineOn(vehicle, false, true, true) end
        SetVehicleUndriveable(vehicle, true)
        if VC.state(vehicle, 'vcEngine') == true then VC.setState(vehicle, 'vcEngine', false) end
    end
    if (VC.state(vehicle, 'vcBroken') == true) ~= broken then
        if not broken then SetVehicleUndriveable(vehicle, false) end -- réparé
        VC.setState(vehicle, 'vcBroken', broken)
    end
    -- Fumée sous le capot (palier 1 et 2), vue par tous
    local damaged = stage >= 1
    if (VC.state(vehicle, 'vcDamaged') == true) ~= damaged then
        VC.setState(vehicle, 'vcDamaged', damaged)
        VC.smokeLocal(vehicle, damaged)
    end
    capSpeed(vehicle, stage == 1 and Config.CriticalMaxSpeed or 0.0)
    updateHazards(vehicle, stage)
    power = (stage >= 1 and Config.CriticalPower) or (engine < Config.Damaged and Config.DamagedPower) or 1.0
end

VC.on('enter', function(_, vehicle, seat)
    last = { vehicle = vehicle, engine = GetVehicleEngineHealth(vehicle), body = GetVehicleBodyHealth(vehicle) }
    autoHazards = nil
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

    -- Palier 1 (très abîmé) : calages au hasard en roulant ; il repart tout seul après StallTime ms (vrai
    -- démarrage), ou tout de suite avec la touche du moteur
    if engine < Config.Critical and engine > Config.Broken and GetIsVehicleEngineRunning(vehicle)
        and GetEntitySpeed(vehicle) * VC.MPH > 3.0 and math.random() < Config.StallChance * dt and VC.stall then
        local t = Config.StallTime or { 2000, 4000 }
        VC.stall(vehicle, math.random(t[1] or 2000, t[2] or t[1] or 4000))
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

VC.on('leave', function(vehicle, _, info)
    power = 1.0
    autoHazards = nil
    -- Vitesse d'origine rendue (le prochain conducteur bride lui-même si le moteur est très abîmé)
    if capped.vehicle ~= 0 then
        if not (info and info.gone) and DoesEntityExist(capped.vehicle) then SetVehicleMaxSpeed(capped.vehicle, 0.0) end
        capped = { vehicle = 0, mps = 0.0 }
    end
end)

-- =========================================================================
-- FUMÉE SOUS LE CAPOT (paliers 1 et 2), pour TOUS les joueurs : véhicules à l'état "vcDamaged"
-- Performance : boucle d'1 s seulement tant qu'un véhicule fumant est connu (aucune sinon).
-- =========================================================================
local Smoke = Config.Smoke or {}
local smoking = {}       -- [clé] = { vehicle, fx, lostSince } (réseau : nom du state bag ; local : "local:<n°>")
local smokeRunning = false

local function stopFx(entry)
    if entry.fx then
        StopParticleFxLooped(entry.fx, false)
        entry.fx = nil
    end
end

local function startFx(vehicle)
    if not HasNamedPtfxAssetLoaded(Smoke.Asset) then
        RequestNamedPtfxAsset(Smoke.Asset) -- chargé : fumée lancée au passage suivant
        return nil
    end
    local o = Smoke.Offset or { 0.0, 0.0, 0.25 }
    UseParticleFxAssetNextCall(Smoke.Asset)
    local bone = GetEntityBoneIndexByName(vehicle, 'engine')
    if bone == -1 then bone = GetEntityBoneIndexByName(vehicle, 'bonnet') end
    if bone == -1 then
        local _, max = GetModelDimensions(GetEntityModel(vehicle))
        return StartParticleFxLoopedOnEntity(Smoke.Name, vehicle, 0.0, max.y * 0.6, o[3], 0.0, 0.0, 0.0, Smoke.Scale or 0.5, false, false, false)
    end
    return StartParticleFxLoopedOnEntityBone(Smoke.Name, vehicle, o[1], o[2], o[3], 0.0, 0.0, 0.0, bone, Smoke.Scale or 0.5, false, false, false)
end

local function vehicleOfKey(key, entry)
    if key:sub(1, 6) == 'local:' then return DoesEntityExist(entry.vehicle) and entry.vehicle or 0 end
    return GetEntityFromStateBagName(key) or 0
end

local function smokeLoop()
    if smokeRunning then return end
    smokeRunning = true
    CreateThread(function()
        while next(smoking) do
            local pos, now = GetEntityCoords(PlayerPedId()), GetGameTimer()
            for key, entry in pairs(smoking) do
                local vehicle = vehicleOfKey(key, entry)
                if vehicle ~= entry.vehicle then
                    stopFx(entry)
                    if key:sub(1, 6) ~= 'local:' then entry.vehicle = vehicle end
                end
                if vehicle ~= 0 and DoesEntityExist(vehicle) then
                    entry.lostSince = nil
                    if #(GetEntityCoords(vehicle) - pos) <= (Smoke.Distance or 120.0) then
                        if not entry.fx then entry.fx = startFx(vehicle) end
                    else
                        stopFx(entry)
                    end
                else
                    stopFx(entry)
                    -- Hors de portée réseau depuis 10 s : oublié (repris par l'état du véhicule à son retour)
                    entry.lostSince = entry.lostSince or now
                    if now - entry.lostSince > 10000 then smoking[key] = nil end
                end
            end
            Wait(1000)
        end
        smokeRunning = false
    end)
end

local function setSmoke(key, vehicle, on)
    if Smoke.Enabled == false then return end
    local entry = smoking[key]
    if on then
        if not entry then
            smoking[key] = { vehicle = vehicle or 0 }
            smokeLoop()
        end
    elseif entry then
        stopFx(entry)
        smoking[key] = nil
    end
end

--- Véhicule local (non synchronisé) : fumée gérée ici (les véhicules en réseau passent par leur état)
function VC.smokeLocal(vehicle, on)
    if NetworkGetEntityIsNetworked(vehicle) then return end
    setSmoke(('local:%d'):format(vehicle), vehicle, on)
end

AddStateBagChangeHandler('vcDamaged', nil, function(bagName, _, value)
    setSmoke(bagName, 0, value == true)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, entry in pairs(smoking) do stopFx(entry) end
    if capped.vehicle ~= 0 and DoesEntityExist(capped.vehicle) then SetVehicleMaxSpeed(capped.vehicle, 0.0) end
end)

-- =========================================================================
-- /repair : moteur seul remis à neuf (carrosserie et dégâts visibles inchangés)
-- =========================================================================
local Repair = VCConfig.Repair or {}

local function repairTarget()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then return vehicle end
    local pos, best, bestDistance = GetEntityCoords(ped), nil, Repair.Distance or 5.0
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(v) - pos)
        if d <= bestDistance then best, bestDistance = v, d end
    end
    return best
end

if Repair.Command then
    RegisterCommand(Repair.Command, function()
        local vehicle = repairTarget()
        if not vehicle then
            return VC.chat(('Aucun véhicule dans un rayon de %d m.'):format(math.floor(Repair.Distance or 5.0)))
        end
        NetworkRequestControlOfEntity(vehicle)
        CreateThread(function()
            local timeout = GetGameTimer() + 1500
            while NetworkGetEntityIsNetworked(vehicle) and not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < timeout do
                Wait(50)
                NetworkRequestControlOfEntity(vehicle)
            end
            if not DoesEntityExist(vehicle) then return end
            SetVehicleEngineHealth(vehicle, 1000.0) -- moteur seulement : ni SetVehicleFixed, ni carrosserie
            SetVehicleUndriveable(vehicle, false)
            if last.vehicle == vehicle then last.engine = 1000.0 end
            if VC.state(vehicle, 'vcBroken') == true then VC.setState(vehicle, 'vcBroken', false) end
            if VC.state(vehicle, 'vcDamaged') == true then
                VC.setState(vehicle, 'vcDamaged', false)
                VC.smokeLocal(vehicle, false)
            end
            if VC.vehicle == vehicle and VC.seat == -1 then updateState(vehicle, 1000.0) end
            VC.chat('Moteur réparé (la carrosserie n\'est pas réparée).')
        end)
    end, Repair.Restricted == true)
end
