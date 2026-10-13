--[[
    Vehicle Control - moteur et portières (client)
    --------------------------------------------------------------
    MOTEUR (touche O par défaut, conducteur ; un véhicule apparaît moteur COUPÉ) :
      - O, moteur coupé : vrai démarrage (démarreur, durée complète : on ne peut pas accélérer pendant
        EngineStartTime ms), et le moteur est marqué "toujours allumé" (état "vcEngine") : il le reste,
        même quand le joueur descend ;
      - O, moteur allumé : coupé ;
      - accélérer, moteur coupé : vrai démarrage aussi, mais le moteur s'éteint quand le conducteur descend.
      En montant côté conducteur, une notification (car HUD du MDC) présente la touche :
      « O » Pour allumer le moteur et le maintenir allumé / ou accélérer pour allumer le moteur. Elle
      disparaît au bout de 8 s (EngineNoticeDuration), même sans appuyer, ou dès que la touche est utilisée.
      Panne sèche ou véhicule cassé : impossible à démarrer.
    PORTIÈRES (depuis l'intérieur, sans notification à l'écran : un message privé dans le chat) :
      - touche U : sa portière (avant gauche pour le conducteur, avant droite pour le passager avant) ;
      - touche I (conducteur) : les deux portières avant ensemble.
      Même touche pour refermer. Priorité à celui qui a ouvert : la portière ouverte par l'un n'est pas
      refermée par la touche de l'autre (état "vcDoors" : qui a ouvert chaque portière).
    Touches modifiables : Paramètres > Raccourcis clavier > FiveM.
]]

local Config = VCConfig

local function me() return GetPlayerServerId(PlayerId()) end

local function controlled(vehicle)
    return not NetworkGetEntityIsNetworked(vehicle) or NetworkHasControlOfEntity(vehicle)
end

-- =========================================================================
-- MOTEUR
-- =========================================================================
local entering = nil      -- { vehicle, running } : moteur avant la montée (vu en approchant)
local keepOffUntil = 0     -- montée : le jeu démarre le moteur tout seul, on le garde coupé jusque-là
local startedByPlayer = false
local startingUntil = 0    -- démarrage en cours : pas d'accélération avant la fin (vrai démarrage)

local function canStart(vehicle)
    return not VC.isBroken(vehicle) and VC.hasFuel(vehicle)
end

local function engineNotice(vehicle)
    if VC.isBroken(vehicle) then return end
    local running = GetIsVehicleEngineRunning(vehicle)
    local marked = VC.state(vehicle, 'vcEngine') == true
    VC.toHud('carNotice', {
        key = VC.keyLabel('vc_engine', Config.Keys.engine),
        text = running and 'Pour couper le moteur' or 'Pour allumer le moteur et le maintenir allumé',
        hint = running and (marked and 'Moteur maintenu allumé, même en descendant' or 'Il s\'éteindra quand vous descendrez')
            or 'ou accélérer pour allumer le moteur',
        duration = Config.EngineNoticeDuration,
    })
end

--- Vrai démarrage (démarreur, pot d'échappement) : pas instantané, durée complète conservée
local function startEngine(vehicle)
    SetVehicleEngineOn(vehicle, true, false, true)
    startingUntil = GetGameTimer() + (Config.EngineStartTime or 1200)
    keepOffUntil, startedByPlayer = 0, true
end

local function becomeDriver(ped, vehicle)
    SetPedConfigFlag(ped, 429, true) -- le personnage ne démarre plus le moteur en montant
    local marked = VC.state(vehicle, 'vcEngine')
    local wasRunning = entering and entering.vehicle == vehicle and entering.running
    entering = nil
    startedByPlayer = false
    if marked == true then
        if canStart(vehicle) and not GetIsVehicleEngineRunning(vehicle) then SetVehicleEngineOn(vehicle, true, true, false) end
    elseif marked == nil or not wasRunning then
        -- Véhicule qui vient d'apparaître, ou moteur coupé avant la montée : il reste coupé
        keepOffUntil = GetGameTimer() + 1500
        SetVehicleEngineOn(vehicle, false, true, true)
        if marked == nil and NetworkGetEntityIsNetworked(vehicle) then VC.setState(vehicle, 'vcEngine', false) end
    end
    engineNotice(vehicle)
end

local function toggleEngine()
    local vehicle = VC.vehicle
    if not VC.isDriver() or IsPauseMenuActive() then return end
    VC.toHud('carNoticeHide', {}) -- touche utilisée : la notification disparaît
    if GetIsVehicleEngineRunning(vehicle) or VC.state(vehicle, 'vcEngine') == true then
        -- Allumé (par la touche ou en accélérant) : coupé
        if VC.state(vehicle, 'vcEngine') ~= false then VC.setState(vehicle, 'vcEngine', false) end
        SetVehicleKeepEngineOnWhenAbandoned(vehicle, false)
        SetVehicleEngineOn(vehicle, false, false, true)
        startedByPlayer, startingUntil = false, 0
        return
    end
    if VC.isBroken(vehicle) then return VC.chat('Le véhicule est hors d\'usage.') end
    if not VC.hasFuel(vehicle) then return VC.chat('Le réservoir est vide.') end
    VC.setState(vehicle, 'vcEngine', true) -- maintenu allumé, même en descendant
    SetVehicleKeepEngineOnWhenAbandoned(vehicle, true)
    startEngine(vehicle)
end
RegisterCommand('vc_engine', toggleEngine, false)
RegisterKeyMapping('vc_engine', 'Véhicule : allumer (maintenu allumé) / couper le moteur', 'keyboard', Config.Keys.engine)

VC.on('enter', function(ped, vehicle, seat)
    if seat == -1 then becomeDriver(ped, vehicle) end
end)

VC.on('seat', function(ped, vehicle, seat)
    if seat == -1 then becomeDriver(ped, vehicle) end
end)

-- Approche d'un véhicule : moteur allumé ou non AVANT que le jeu le démarre à la montée
VC.on('idle', function(ped)
    local target = GetVehiclePedIsTryingToEnter(ped)
    if target ~= 0 and (not entering or entering.vehicle ~= target) then
        entering = { vehicle = target, running = GetIsVehicleEngineRunning(target) }
    elseif target == 0 then
        entering = nil
    end
end)

VC.on('frame', function(_, vehicle)
    if VC.seat ~= -1 then return end
    local running = GetIsVehicleEngineRunning(vehicle)
    -- Accélérer démarre le moteur (vrai démarrage), sans le maintenir allumé (sauf panne sèche / cassé)
    if not running
        and (IsControlJustPressed(0, 71) or IsDisabledControlJustPressed(0, 71)) then
        if canStart(vehicle) then
            startEngine(vehicle)
            running = true
        end
    end
    -- Démarrage en cours : on ne part pas avant la fin du démarreur
    if GetGameTimer() < startingUntil then
        DisableControlAction(0, 71, true)
        DisableControlAction(0, 72, true)
    end
    if GetGameTimer() < keepOffUntil and running and not startedByPlayer then
        SetVehicleEngineOn(vehicle, false, true, true) -- démarrage automatique du jeu pendant la montée
    end
    if running and not canStart(vehicle) then SetVehicleEngineOn(vehicle, false, true, true) end
end)

-- Descente du conducteur : moteur "maintenu allumé" (touche O) relancé si le jeu le coupe ; moteur
-- allumé en accélérant (non maintenu) : coupé
VC.on('leave', function(vehicle, seat)
    startingUntil = 0
    if seat ~= -1 or not DoesEntityExist(vehicle) then return end
    local keep = VC.state(vehicle, 'vcEngine') == true
    SetVehicleKeepEngineOnWhenAbandoned(vehicle, keep)
    CreateThread(function()
        local untilTime = GetGameTimer() + 2500
        while GetGameTimer() < untilTime and DoesEntityExist(vehicle) and VC.vehicle ~= vehicle do
            if GetPedInVehicleSeat(vehicle, -1) ~= 0 then break end -- quelqu'un a repris le volant
            if keep then
                if VC.state(vehicle, 'vcEngine') ~= true or not canStart(vehicle) then break end
                if not GetIsVehicleEngineRunning(vehicle) and controlled(vehicle) then SetVehicleEngineOn(vehicle, true, true, false) end
            elseif GetIsVehicleEngineRunning(vehicle) and controlled(vehicle) then
                SetVehicleEngineOn(vehicle, false, false, true)
            end
            Wait(100)
        end
    end)
end)

-- =========================================================================
-- PORTIÈRES AVANT (depuis l'intérieur)
-- =========================================================================
local function isOpen(vehicle, door) return GetVehicleDoorAngleRatio(vehicle, door) > 0.05 end

local function applyDoors(vehicle, actions)
    for _, a in ipairs(actions) do
        if a.open then SetVehicleDoorOpen(vehicle, a.door, false, false) else SetVehicleDoorShut(vehicle, a.door, false) end
    end
end

--- Portières concernées par la touche et décision (ouvrir / refermer), selon la priorité
function VC.doorActions(vehicle, seat, mode, owners, myId, openCheck)
    local doors
    if mode == 'door' then
        if seat == -1 then doors = { 0 } elseif seat == 0 then doors = { 1 } else return nil end
    else
        if seat ~= -1 then return nil end
        doors = { 0, 1 }
    end
    owners = owners or {}
    local actions = {}
    -- Ouvertes par lui : il les referme
    for _, door in ipairs(doors) do
        if openCheck(door) and owners[tostring(door)] == myId then actions[#actions + 1] = { door = door, open = false } end
    end
    if #actions > 0 then return actions end
    for _, door in ipairs(doors) do
        local owner = owners[tostring(door)]
        if not openCheck(door) then
            actions[#actions + 1] = { door = door, open = true }
        elseif mode == 'door' and (owner == nil or owner == false) then
            -- ouverte autrement (à la main, par un policier…) : sa touche la referme
            actions[#actions + 1] = { door = door, open = false }
        end
        -- ouverte par l'autre occupant : priorité à lui, on n'y touche pas
    end
    return actions
end

local function doorKey(mode)
    local vehicle = VC.vehicle
    if vehicle == 0 or IsPauseMenuActive() or GetVehicleDoorLockStatus(vehicle) == 4 then return end
    -- Seules comptent les portières ouvertes par un joueur encore à bord
    local owners = {}
    for door, id in pairs(VC.state(vehicle, 'vcDoors') or {}) do
        local player = GetPlayerFromServerId(id)
        if player ~= -1 and GetVehiclePedIsIn(GetPlayerPed(player), false) == vehicle then owners[door] = id end
    end
    local actions = VC.doorActions(vehicle, VC.seat, mode, owners, me(), function(door) return isOpen(vehicle, door) end)
    if not actions or #actions == 0 then return end
    if controlled(vehicle) then applyDoors(vehicle, actions) end
    if NetworkGetEntityIsNetworked(vehicle) then
        TriggerServerEvent('rp_vehiclecontrol:doors', VehToNet(vehicle), actions)
    else
        local owners = VC.state(vehicle, 'vcDoors') or {}
        for _, a in ipairs(actions) do owners[tostring(a.door)] = a.open and me() or nil end
        VC.setState(vehicle, 'vcDoors', owners)
        applyDoors(vehicle, actions)
    end
    local open = actions[1].open
    if #actions > 1 then
        VC.chat(open and 'Portières ouvertes.' or 'Portières fermées.')
    else
        VC.chat(open and 'Portière ouverte.' or 'Portière fermée.')
    end
end

RegisterCommand('vc_door', function() doorKey('door') end, false)
RegisterCommand('vc_frontdoors', function() doorKey('front') end, false)
RegisterKeyMapping('vc_door', 'Véhicule : ouvrir / fermer sa portière (avant)', 'keyboard', Config.Keys.door)
RegisterKeyMapping('vc_frontdoors', 'Véhicule : ouvrir / fermer les deux portières avant (conducteur)', 'keyboard', Config.Keys.frontDoors)

-- Le serveur demande au propriétaire réseau du véhicule d'appliquer les portières
RegisterNetEvent('rp_vehiclecontrol:applyDoors', function(netId, actions)
    local vehicle = NetToVeh(netId)
    if vehicle ~= 0 and DoesEntityExist(vehicle) and type(actions) == 'table' then applyDoors(vehicle, actions) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetPedConfigFlag(PlayerPedId(), 429, false)
end)
