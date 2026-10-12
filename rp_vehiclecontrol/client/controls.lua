--[[
    Vehicle Control - moteur et portières (client)
    --------------------------------------------------------------
    MOTEUR (touche O, conducteur) : un véhicule apparaît moteur COUPÉ. O l'allume et le marque
      "toujours allumé" (état "vcEngine") : il le reste, même quand le joueur descend. O de nouveau :
      coupé. Accélérer démarre aussi le moteur comme dans le jeu de base (sans le marquer).
      En montant côté conducteur, une notification (car HUD du MDC) présente la touche ; elle disparaît
      au bout de 8 s (EngineNoticeDuration), même sans appuyer, ou dès que la touche est utilisée.
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

local function canStart(vehicle)
    return not VC.isBroken(vehicle) and VC.hasFuel(vehicle)
end

local function engineNotice(vehicle)
    if VC.isBroken(vehicle) then return end
    local on = VC.state(vehicle, 'vcEngine') == true
    VC.toHud('carNotice', {
        key = VC.keyLabel('vc_engine', Config.Keys.engine),
        text = on and 'Couper le moteur' or 'Allumer le moteur',
        hint = on and 'Moteur laissé allumé' or 'Il reste allumé, même en descendant',
        duration = Config.EngineNoticeDuration,
    })
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
    if VC.state(vehicle, 'vcEngine') == true then
        VC.setState(vehicle, 'vcEngine', false)
        SetVehicleKeepEngineOnWhenAbandoned(vehicle, false)
        SetVehicleEngineOn(vehicle, false, false, true)
        startedByPlayer = false
        return
    end
    if VC.isBroken(vehicle) then return VC.chat('Le véhicule est hors d\'usage.') end
    if not VC.hasFuel(vehicle) then return VC.chat('Le réservoir est vide.') end
    VC.setState(vehicle, 'vcEngine', true)
    SetVehicleKeepEngineOnWhenAbandoned(vehicle, true)
    SetVehicleEngineOn(vehicle, true, false, true)
    keepOffUntil, startedByPlayer = 0, true
end
RegisterCommand('vc_engine', toggleEngine, false)
RegisterKeyMapping('vc_engine', 'Véhicule : moteur toujours allumé / coupé', 'keyboard', Config.Keys.engine)

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
    -- Accélérer démarre le moteur, comme dans le jeu de base (sauf panne sèche / véhicule cassé)
    if not running
        and (IsControlJustPressed(0, 71) or IsDisabledControlJustPressed(0, 71)) then
        if canStart(vehicle) then
            SetVehicleEngineOn(vehicle, true, false, true)
            keepOffUntil, startedByPlayer, running = 0, true, true
        end
    end
    if GetGameTimer() < keepOffUntil and running and not startedByPlayer then
        SetVehicleEngineOn(vehicle, false, true, true) -- démarrage automatique du jeu pendant la montée
    end
    if running and not canStart(vehicle) then SetVehicleEngineOn(vehicle, false, true, true) end
end)

-- Moteur marqué "toujours allumé" : relancé après la descente (le jeu le coupe en descendant)
VC.on('leave', function(vehicle, seat)
    if seat ~= -1 or not DoesEntityExist(vehicle) or VC.state(vehicle, 'vcEngine') ~= true then return end
    SetVehicleKeepEngineOnWhenAbandoned(vehicle, true)
    CreateThread(function()
        local untilTime = GetGameTimer() + 2500
        while GetGameTimer() < untilTime and DoesEntityExist(vehicle) and VC.vehicle ~= vehicle do
            if VC.state(vehicle, 'vcEngine') ~= true or not canStart(vehicle) then break end
            if not GetIsVehicleEngineRunning(vehicle) and controlled(vehicle) then SetVehicleEngineOn(vehicle, true, true, false) end
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
