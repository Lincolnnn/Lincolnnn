--[[
    RP NPC Control - client
    -----------------------
    - Services d'urgence du jeu coupés (envoi de police / pompiers / ambulances, policiers au hasard, courses-poursuites
      aléatoires), modèles de PNJ et de véhicules d'urgence retirés de la population du jeu, scénarios de police
      désactivés. Les PNJ / véhicules d'urgence du jeu encore présents (démarrage de la ressource) sont retirés.
      Les entités créées par un joueur ou un script (population "mission") ne sont JAMAIS touchées.
    - Indice de recherche : jamais.
    - « Everyone ignore player » : les PNJ ignorent les joueurs, n'ont plus peur, ne réagissent plus aux fusillades
      ni aux explosions.
    - Densité du trafic, des véhicules garés et des piétons (0.0 à 3.0), réglée par le serveur (GlobalState.npcDensity).
    Performance :
      - boucle d'1 s (PNJ du jeu à proximité : réglages "pas de peur", retrait des services d'urgence) : ~0.01 ms ;
      - boucle à chaque image SEULEMENT si une densité n'est pas 1.0 ou si SuppressShockingEvents est actif
        (les densités du jeu doivent être redonnées à chaque image) : ~0.01 ms ; sinon aucune.
]]

local Config = NPCConfig
local MISSION = { [6] = true, [7] = true } -- PNJ / véhicules créés par un script (joueurs, menus) : jamais touchés

local emergencyPed, emergencyVehicle = {}, {}
for _, name in ipairs(Config.EmergencyPeds or {}) do emergencyPed[GetHashKey(name)] = true end
for _, name in ipairs(Config.EmergencyVehicles or {}) do emergencyVehicle[GetHashKey(name)] = true end

local function clampDensity(value)
    value = tonumber(value) or 1.0
    return math.max(0.0, math.min(3.0, value))
end

local density = { Traffic = 1.0, Parked = 1.0, Peds = 1.0 }
local function readDensity()
    local d = GlobalState.npcDensity or Config.Density or {}
    density = { Traffic = clampDensity(d.Traffic), Parked = clampDensity(d.Parked or d.Traffic), Peds = clampDensity(d.Peds) }
end

-- =========================================================================
-- RÉGLAGES DU JEU (au démarrage, à chaque apparition du personnage, et redonnés toutes les 10 s)
-- =========================================================================
local function applyRules()
    local player = PlayerId()
    if Config.DisableEmergencyServices then
        for service = 1, 15 do
            EnableDispatchService(service, false)            -- plus de renforts (police, pompiers, ambulances…)
            BlockDispatchServiceResourceCreation(service, true)
        end
        SetCreateRandomCops(false)                           -- plus de policiers au hasard (trafic, à pied)
        SetCreateRandomCopsNotOnScenarios(false)
        SetCreateRandomCopsOnScenarios(false)                -- ni aux commissariats (scénarios)
        SetRandomEventFlag(false)                            -- plus de courses-poursuites / événements aléatoires
        DistantCopCarSirens(false)
        SetDispatchCopsForPlayer(player, false)
        SetAudioFlag('PoliceScannerDisabled', true)
        for hash in pairs(emergencyPed) do SetPedModelIsSuppressed(hash, true) end
        for hash in pairs(emergencyVehicle) do SetVehicleModelIsSuppressed(hash, true) end
        for _, scenario in ipairs(Config.EmergencyScenarios or {}) do SetScenarioTypeEnabled(scenario, false) end
    end
    if Config.DisableWantedLevel then
        SetMaxWantedLevel(0)
        SetWantedLevelMultiplier(0.0)
        SetPoliceIgnorePlayer(player, true)
        if GetPlayerWantedLevel(player) ~= 0 then
            ClearPlayerWantedLevel(player)
            SetPlayerWantedLevelNow(player, false)
        end
    end
    if Config.EveryoneIgnorePlayer then
        SetEveryoneIgnorePlayer(player, true)
        SetPlayerCanBeHassledByGangs(player, false)
        SetIgnoreLowPriorityShockingEvents(player, true)
    end
end

-- =========================================================================
-- PNJ DU JEU À PROXIMITÉ (toutes les secondes) : pas de peur ; services d'urgence du jeu retirés
-- =========================================================================
local calmed = {} -- [ped] = true : réglages déjà donnés (par ce client, propriétaire du PNJ)

local function controlled(entity)
    return not NetworkGetEntityIsNetworked(entity) or NetworkHasControlOfEntity(entity)
end

--- Retire une entité du jeu (si ce client la contrôle ; sinon il demande le contrôle, retiré au passage suivant)
local function remove(entity, isVehicle)
    if not controlled(entity) then
        NetworkRequestControlOfEntity(entity)
        return
    end
    SetEntityAsMissionEntity(entity, true, true)
    if isVehicle then DeleteVehicle(entity) else DeletePed(entity) end
    if DoesEntityExist(entity) then DeleteEntity(entity) end
end

local function hasPlayerInside(vehicle)
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and IsPedAPlayer(ped) then return true end
    end
    return false
end

local function calm(ped)
    SetBlockingOfNonTemporaryEvents(ped, true) -- ne réagit plus aux événements (joueurs, coups de feu, explosions)
    SetPedFleeAttributes(ped, 0, false)        -- ne fuit plus
    SetPedCombatAttributes(ped, 17, false)     -- "toujours fuir" désactivé
end

local tick = 0
local function scan()
    tick = tick + 1
    local seen = {}
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and not MISSION[GetEntityPopulationType(ped)] then
            if Config.DisableEmergencyServices and emergencyPed[GetEntityModel(ped)] then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle == 0 or not hasPlayerInside(vehicle) then remove(ped, false) end
            elseif Config.NoFear and controlled(ped) then
                seen[ped] = true
                if not calmed[ped] then calm(ped) end
            end
        end
    end
    calmed = seen
    -- Véhicules d'urgence du jeu (vides ou conduits par un PNJ), toutes les 3 s
    if Config.DisableEmergencyServices and tick % 3 == 0 then
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if emergencyVehicle[GetEntityModel(vehicle)] and not MISSION[GetEntityPopulationType(vehicle)]
                and not hasPlayerInside(vehicle) then
                remove(vehicle, true)
            end
        end
    end
end

CreateThread(function()
    readDensity()
    applyRules()
    local lastRules = GetGameTimer()
    while true do
        if Config.NoFear or Config.DisableEmergencyServices then scan() end
        if GetGameTimer() - lastRules >= 10000 then
            lastRules = GetGameTimer()
            applyRules() -- certains réglages du joueur sont remis à zéro par le jeu (réapparition, changement de modèle)
        end
        Wait(1000)
    end
end)

-- Personnage (ré)apparu (spawnmanager) : réglages du joueur redonnés tout de suite
AddEventHandler('playerSpawned', applyRules)

-- =========================================================================
-- À CHAQUE IMAGE (seulement si nécessaire) : densités, réactions "choquées" des passants
-- =========================================================================
local frameRunning = false

local function needFrames()
    return Config.SuppressShockingEvents == true or density.Traffic ~= 1.0 or density.Parked ~= 1.0 or density.Peds ~= 1.0
end

local function frameLoop()
    if frameRunning then return end
    frameRunning = true
    CreateThread(function()
        while needFrames() do
            local d = density
            if d.Traffic ~= 1.0 or d.Parked ~= 1.0 or d.Peds ~= 1.0 then
                SetVehicleDensityMultiplierThisFrame(d.Traffic)
                SetRandomVehicleDensityMultiplierThisFrame(d.Traffic)
                SetParkedVehicleDensityMultiplierThisFrame(d.Parked)
                SetPedDensityMultiplierThisFrame(d.Peds)
                SetScenarioPedDensityMultiplierThisFrame(d.Peds, d.Peds)
            end
            if Config.SuppressShockingEvents then SuppressShockingEventsNextFrame() end
            Wait(0)
        end
        frameRunning = false
    end)
end

--- Densités appliquées : boucle à chaque image si besoin ; plus de population possible au-delà de 1.0 ;
--- trafic à 0 : ni camions poubelles ni bateaux du jeu
local function applyDensity()
    readDensity()
    -- Au-delà de 1.0 : population maximale du jeu autorisée (sinon, celle du jeu, inchangée)
    if density.Traffic > 1.0 or density.Parked > 1.0 then SetVehiclePopulationBudget(3) end
    if density.Peds > 1.0 then SetPedPopulationBudget(3) end
    SetGarbageTrucks(density.Traffic > 0.0)
    SetRandomBoats(density.Traffic > 0.0)
    if needFrames() then frameLoop() end
end

AddStateBagChangeHandler('npcDensity', 'global', function()
    SetTimeout(0, applyDensity) -- GlobalState à jour après l'appel
end)

CreateThread(applyDensity)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- Ressource arrêtée : le jeu reprend ses règles par défaut
    local player = PlayerId()
    for service = 1, 15 do
        EnableDispatchService(service, true)
        BlockDispatchServiceResourceCreation(service, false)
    end
    SetCreateRandomCops(true)
    SetCreateRandomCopsNotOnScenarios(true)
    SetCreateRandomCopsOnScenarios(true)
    SetRandomEventFlag(true)
    SetMaxWantedLevel(5)
    SetWantedLevelMultiplier(1.0)
    SetPoliceIgnorePlayer(player, false)
    SetEveryoneIgnorePlayer(player, false)
    SetDispatchCopsForPlayer(player, true)
    SetAudioFlag('PoliceScannerDisabled', false)
    for hash in pairs(emergencyPed) do SetPedModelIsSuppressed(hash, false) end
    for hash in pairs(emergencyVehicle) do SetVehicleModelIsSuppressed(hash, false) end
    for _, scenario in ipairs(Config.EmergencyScenarios or {}) do SetScenarioTypeEnabled(scenario, true) end
    SetGarbageTrucks(true)
    SetRandomBoats(true)
end)
