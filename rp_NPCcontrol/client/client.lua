--[[
    RP NPC Control - client
    -----------------------
    - Services d'urgence du jeu coupés (envoi de police / pompiers / ambulances, policiers au hasard, courses-poursuites
      aléatoires), modèles de PNJ et de véhicules d'urgence retirés de la population du jeu, scénarios de police
      désactivés. Les PNJ / véhicules d'urgence du jeu encore présents (démarrage de la ressource) sont retirés.
      Les entités créées par un joueur ou un script (population "mission") ne sont JAMAIS touchées.
    - Indice de recherche : jamais.
    - Chasse à l'homme (GlobalState.npcManhunt, config Manhunt) : la police du jeu redevient normale (étoiles,
      policiers PNJ, renforts, poursuites, tirs) ; pompiers / ambulanciers restent supprimés, les autres PNJ calmes.
    - « Everyone ignore player » : les PNJ ignorent les joueurs, n'ont plus peur, ne réagissent plus aux fusillades,
      aux explosions ni aux morts, et ne se battent pas (véhicule volé, klaxon, bousculade).
    - Densité du trafic, des véhicules garés et des piétons (0.0 à 3.0), réglée par le serveur (GlobalState.npcDensity).
    Performance :
      - boucle d'1 s (PNJ du jeu à proximité : réglages "pas de peur", retrait des services d'urgence) : ~0.01 ms ;
      - alerte (le joueur vise, tire, vole un véhicule, klaxonne, se bat, explosion ou PNJ mort à proximité) : boucle
        de 250 ms seulement pendant ce moment (PNJ proches calmés : conducteurs et piétons) ;
      - boucle à chaque image SEULEMENT si une densité n'est pas 1.0 ou si SuppressShockingEvents est actif
        (les densités du jeu doivent être redonnées à chaque image) : ~0.01 ms ; sinon aucune.
]]

local Config = NPCConfig
local MISSION = { [6] = true, [7] = true } -- PNJ / véhicules créés par un script (joueurs, menus) : jamais touchés
local PLAYER_GROUP = GetHashKey('PLAYER')

local COP_GROUP = GetHashKey('COP')
local emergencyPed, emergencyVehicle, nonPolice = {}, {}, {}
for _, name in ipairs(Config.EmergencyPeds or {}) do emergencyPed[GetHashKey(name)] = true end
for _, name in ipairs(Config.EmergencyVehicles or {}) do emergencyVehicle[GetHashKey(name)] = true end
for _, name in ipairs(Config.NonPoliceModels or {}) do nonPolice[GetHashKey(name)] = true end
-- Renforts de police du jeu (types de "dispatch") : voitures, hélicoptères, SWAT, motards, barrages, bateaux
local POLICE_SERVICES = { [1] = true, [2] = true, [4] = true, [6] = true, [7] = true, [8] = true, [9] = true,
    [10] = true, [12] = true, [13] = true }

--- Chasse à l'homme active (la police du jeu redevient normale)
local function manhunt() return GlobalState.npcManhunt == true end

--- Modèle d'urgence supprimé en ce moment (en chasse à l'homme : seulement pompiers / ambulanciers)
local function blockedModel(hash, list)
    return list[hash] == true and (not manhunt() or nonPolice[hash] == true)
end

--- Policier du jeu (modèle de police ou groupe COP) : en chasse à l'homme, jamais calmé ni retiré
local function isCop(ped)
    local model = GetEntityModel(ped)
    return (emergencyPed[model] and not nonPolice[model]) or GetPedRelationshipGroupHash(ped) == COP_GROUP
end
local function huntingCop(ped) return manhunt() and isCop(ped) end

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
    local hunt = manhunt()
    if Config.DisableEmergencyServices then
        for service = 1, 15 do
            -- plus de renforts (police, pompiers, ambulances…) ; chasse à l'homme : ceux de la police reviennent
            local allow = hunt and POLICE_SERVICES[service] == true
            EnableDispatchService(service, allow)
            BlockDispatchServiceResourceCreation(service, not allow)
        end
        SetCreateRandomCops(hunt)                            -- policiers au hasard (trafic, à pied)
        SetCreateRandomCopsNotOnScenarios(hunt)
        SetCreateRandomCopsOnScenarios(hunt)                 -- aux commissariats (scénarios)
        SetRandomEventFlag(false)                            -- plus de courses-poursuites / événements aléatoires
        DistantCopCarSirens(hunt)
        SetDispatchCopsForPlayer(player, hunt)
        SetAudioFlag('PoliceScannerDisabled', not hunt)
        for hash in pairs(emergencyPed) do SetPedModelIsSuppressed(hash, blockedModel(hash, emergencyPed)) end
        for hash in pairs(emergencyVehicle) do SetVehicleModelIsSuppressed(hash, blockedModel(hash, emergencyVehicle)) end
        for _, scenario in ipairs(Config.EmergencyScenarios or {}) do SetScenarioTypeEnabled(scenario, hunt) end
    end
    if hunt then
        -- Chasse à l'homme : étoiles et police du jeu normales (elle ne l'ignore plus)
        SetMaxWantedLevel(5)
        SetWantedLevelMultiplier(1.0)
        SetPoliceIgnorePlayer(player, false)
    elseif Config.DisableWantedLevel then
        SetMaxWantedLevel(0)
        SetWantedLevelMultiplier(0.0)
        SetPoliceIgnorePlayer(player, true)
        if GetPlayerWantedLevel(player) ~= 0 then
            ClearPlayerWantedLevel(player)
            SetPlayerWantedLevelNow(player, false)
        end
    end
    if Config.EveryoneIgnorePlayer then
        SetEveryoneIgnorePlayer(player, not hunt) -- chasse à l'homme : la police doit le voir (civils calmés à part)
        SetPlayerCanBeHassledByGangs(player, false)
        SetIgnoreLowPriorityShockingEvents(player, true)
        -- Groupes de PNJ (civils, vigiles, gangs…) : respect envers les joueurs, jamais hostiles
        for _, group in ipairs(Config.CalmGroups or {}) do
            SetRelationshipBetweenGroups(1, GetHashKey(group), PLAYER_GROUP)
        end
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
    TaskSetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)        -- ne fuit plus
    SetPedCombatAttributes(ped, 17, false)     -- "toujours fuir" désactivé
    SetPedCombatAttributes(ped, 58, true)      -- ne fuit pas un combat
    SetPedCombatAttributes(ped, 5, false)      -- ne se bat pas (même contre quelqu'un d'armé)
    SetPedCombatAttributes(ped, 46, false)     -- ne cherche jamais le combat (véhicule volé, klaxon, bousculade)
    SetPedCanEvasiveDive(ped, false)           -- ne plonge pas pour esquiver
    SetPedCanCowerInCover(ped, false)          -- ne se recroqueville pas
    if Config.NoPerception ~= false then
        -- Ne voit plus les morts / les armes et n'entend plus les tirs / klaxons : rien qui puisse lui faire peur
        SetPedSeeingRange(ped, Config.SeeingRange or 0.0)
        SetPedHearingRange(ped, Config.HearingRange or 0.0)
        SetPedAlertness(ped, 0)
    end
end

-- =========================================================================
-- ALERTE : le joueur vise, tire, vole un véhicule (tire le conducteur dehors), klaxonne, se bat, une explosion ou un
-- PNJ mort à proximité. Pendant ces moments (et AlertTime ms après), les PNJ du jeu proches que ce client contrôle :
--   - conducteurs : reprennent une conduite normale (une fois au début de l'alerte, puis s'ils se remettent à fuir) ;
--   - à pied (CalmRange m) : s'ils fuient ou veulent se battre avec un joueur (conducteur tiré de son véhicule,
--     klaxonné…), ils se calment et reprennent leur promenade.
-- Performance : boucle de 250 ms seulement pendant une alerte.
-- =========================================================================
local alertUntil, driversRunning = 0, false
local calmedDrivers = {} -- [conducteur] = heure de la dernière remise en conduite normale

local function driveCalmly(ped, vehicle)
    ClearPedTasks(ped)
    calm(ped)
    TaskVehicleDriveWander(ped, vehicle, Config.DriverSpeed or 15.0, Config.DrivingStyle or 786603)
    SetPedKeepTask(ped, true)
end

--- Veut se battre avec un joueur (n'importe lequel à proximité) ?
local function fightingPlayer(ped)
    if IsPedInMeleeCombat(ped) then return true end
    for _, player in ipairs(GetActivePlayers()) do
        if IsPedInCombat(ped, GetPlayerPed(player)) then return true end
    end
    return false
end

local function calmOnFoot(ped)
    ClearPedTasks(ped)
    calm(ped)
    TaskWanderStandard(ped, 10.0, 10)
    SetPedKeepTask(ped, true)
end

local WANDER = GetHashKey('SCRIPT_TASK_WANDER_STANDARD')
local DRIVE_WANDER = GetHashKey('SCRIPT_TASK_VEHICLE_DRIVE_WANDER')

--- PNJ du jeu MIS EN JOUE par le joueur : traité en priorité, toutes les 250 ms tant qu'il est visé. S'il est contrôlé
--- par un autre joueur, ce client en demande le contrôle (pour pouvoir le calmer lui-même). Il reste calme et
--- continue sa route (sans être relancé sans cesse : seulement s'il ne marche / ne roule plus normalement).
local function calmAimed()
    local found, ped = GetEntityPlayerIsFreeAimingAt(PlayerId())
    if not found or not ped or ped == 0 or not DoesEntityExist(ped) or GetEntityType(ped) ~= 1 then return end
    if IsPedAPlayer(ped) or MISSION[GetEntityPopulationType(ped)] or IsPedDeadOrDying(ped, true) or huntingCop(ped) then return end
    if not controlled(ped) then
        NetworkRequestControlOfEntity(ped)
        return
    end
    calm(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        if GetPedInVehicleSeat(vehicle, -1) == ped and GetScriptTaskStatus(ped, DRIVE_WANDER) == 7 then
            driveCalmly(ped, vehicle)
        end
    elseif not IsPedRagdoll(ped) and GetScriptTaskStatus(ped, WANDER) == 7 then
        calmOnFoot(ped)
    end
end

local function calmDrivers()
    local me = PlayerPedId()
    local pos = GetEntityCoords(me)
    local now = GetGameTimer()
    calmAimed()
    -- À pied : plus de fuite ni de bagarre avec les joueurs
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and not IsPedInAnyVehicle(ped, true) and not IsPedDeadOrDying(ped, true)
            and not IsPedRagdoll(ped) and not IsPedBeingJacked(ped) and not MISSION[GetEntityPopulationType(ped)]
            and controlled(ped) and #(GetEntityCoords(ped) - pos) < (Config.CalmRange or 40.0)
            and not huntingCop(ped) and (IsPedFleeing(ped) or fightingPlayer(ped)) then
            local last = calmedDrivers[ped]
            if not last or now - last > 500 then
                calmedDrivers[ped] = now
                calmOnFoot(ped)
            end
        end
    end
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local ped = GetPedInVehicleSeat(vehicle, -1)
        if ped ~= 0 and not IsPedAPlayer(ped) and not MISSION[GetEntityPopulationType(ped)] and controlled(ped)
            and #(GetEntityCoords(vehicle) - pos) < (Config.DriverRange or 80.0)
            and not huntingCop(ped) and not (manhunt() and emergencyVehicle[GetEntityModel(vehicle)]) then
            local last = calmedDrivers[ped]
            if not last or IsPedFleeing(ped) or fightingPlayer(ped) then
                if not last or now - last > 500 then
                    calmedDrivers[ped] = now
                    driveCalmly(ped, vehicle)
                end
            end
        end
    end
end

local function driversLoop()
    if driversRunning then return end
    driversRunning = true
    CreateThread(function()
        while GetGameTimer() < alertUntil do
            calmDrivers()
            Wait(250)
        end
        calmedDrivers = {}
        driversRunning = false
    end)
end

--- Alerte (PNJ proches calmés)
local function raiseAlert()
    alertUntil = GetGameTimer() + (Config.AlertTime or 4000)
    driversLoop()
end

--- Le joueur vise, tire, vole un véhicule, klaxonne, se bat, ou une explosion a lieu près de lui : alerte
local function checkAlert()
    if not Config.NoFear then return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if IsPlayerFreeAiming(PlayerId()) or IsPedShooting(ped) or IsPedJacking(ped) or IsPedInMeleeCombat(ped)
        or (vehicle ~= 0 and IsControlPressed(0, 86))  -- klaxon
        or (GetVehiclePedIsTryingToEnter(ped) ~= 0)      -- monte dans un véhicule (peut-être le vole)
        or IsExplosionInSphere(-1, GetEntityCoords(ped), Config.DriverRange or 80.0) then
        raiseAlert()
    end
end

local tick = 0
local deadSeen = {} -- [PNJ mort] = déjà signalé
local function scan()
    tick = tick + 1
    local seen = {}
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and not MISSION[GetEntityPopulationType(ped)] then
            if Config.DisableEmergencyServices and blockedModel(GetEntityModel(ped), emergencyPed) then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle == 0 or not hasPlayerInside(vehicle) then remove(ped, false) end
            elseif huntingCop(ped) then
                -- chasse à l'homme : policier du jeu laissé tel quel (il poursuit, il tire)
            elseif Config.NoFear and controlled(ped) then
                seen[ped] = true
                if not calmed[ped] then calm(ped) end
                -- PNJ mort à proximité : les autres ne doivent pas avoir peur en le voyant
                if IsPedDeadOrDying(ped, true) and not deadSeen[ped]
                    and #(GetEntityCoords(ped) - GetEntityCoords(PlayerPedId())) < (Config.CalmRange or 40.0) then
                    deadSeen[ped] = true
                    raiseAlert()
                end
            end
        end
    end
    calmed = seen
    for ped in pairs(deadSeen) do
        if not DoesEntityExist(ped) then deadSeen[ped] = nil end
    end
    -- Véhicules d'urgence du jeu (vides ou conduits par un PNJ), toutes les 3 s
    if Config.DisableEmergencyServices and tick % 3 == 0 then
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if blockedModel(GetEntityModel(vehicle), emergencyVehicle) and not MISSION[GetEntityPopulationType(vehicle)]
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
        checkAlert() -- (vérifié aussi à chaque image quand la boucle par image tourne)
        if GetGameTimer() - lastRules >= 10000 then
            lastRules = GetGameTimer()
            applyRules() -- certains réglages du joueur sont remis à zéro par le jeu (réapparition, changement de modèle)
        end
        Wait(1000)
    end
end)

-- Personnage (ré)apparu (spawnmanager) : réglages du joueur redonnés tout de suite
AddEventHandler('playerSpawned', applyRules)

-- Chasse à l'homme activée / coupée (npcmanhunt) : réglages redonnés tout de suite ; coupée : étoiles effacées, les
-- policiers du jeu sont retirés au passage suivant
AddStateBagChangeHandler('npcManhunt', 'global', function()
    SetTimeout(0, function()
        applyRules()
        if not manhunt() and Config.DisableWantedLevel then
            local player = PlayerId()
            ClearPlayerWantedLevel(player)
            SetPlayerWantedLevelNow(player, false)
        end
    end)
end)

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
            if Config.SuppressShockingEvents then
                SuppressShockingEventsNextFrame()
                SuppressAgitationEventsNextFrame() -- klaxon, bousculade, véhicule volé : pas d'énervement
            end
            checkAlert()
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
    for _, group in ipairs(Config.CalmGroups or {}) do ClearRelationshipBetweenGroups(1, GetHashKey(group), PLAYER_GROUP) end
    SetDispatchCopsForPlayer(player, true)
    SetAudioFlag('PoliceScannerDisabled', false)
    for hash in pairs(emergencyPed) do SetPedModelIsSuppressed(hash, false) end
    for hash in pairs(emergencyVehicle) do SetVehicleModelIsSuppressed(hash, false) end
    for _, scenario in ipairs(Config.EmergencyScenarios or {}) do SetScenarioTypeEnabled(scenario, true) end
    SetGarbageTrucks(true)
    SetRandomBoats(true)
end)
