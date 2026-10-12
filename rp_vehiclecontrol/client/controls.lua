--[[
    Vehicle Control - moteur, portières, frein de parcage (client)
    --------------------------------------------------------------
    MOTEUR (touche O, conducteur) : un véhicule apparaît moteur COUPÉ. O l'allume et le marque
      "toujours allumé" (état "vcEngine") : il le reste, même quand le joueur descend. O de nouveau :
      coupé. Accélérer démarre aussi le moteur comme dans le jeu de base (sans le marquer).
      En montant côté conducteur, une notification (car HUD du MDC) présente la touche.
      Panne sèche ou véhicule cassé : impossible à démarrer.
    PORTIÈRES (depuis l'intérieur, sans notification à l'écran : un message privé dans le chat) :
      - touche U : sa portière (avant gauche pour le conducteur, avant droite pour le passager avant) ;
      - touche I (conducteur) : les deux portières avant ensemble.
      Même touche pour refermer. Priorité à celui qui a ouvert : la portière ouverte par l'un n'est pas
      refermée par la touche de l'autre (état "vcDoors" : qui a ouvert chaque portière).
    FREIN DE PARCAGE (touche L, conducteur ; état "vcBrake") : serré, le véhicule ne bouge pas et
      n'avance pas (accélérer / reculer bloqués) ; il faut le desserrer. Desserré, le véhicule laissé est
      libre : il roule en pente, se déplace s'il est percuté, et un joueur à pied peut le pousser.
      Car HUD : vitesse grisée et transparente tant qu'il est serré.
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
    -- Accélérer démarre le moteur, comme dans le jeu de base (sauf panne sèche / cassé / frein serré)
    if not running and VC.state(vehicle, 'vcBrake') ~= true
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

-- =========================================================================
-- FREIN DE PARCAGE
-- =========================================================================
RegisterCommand('vc_parkingbrake', function()
    local vehicle = VC.vehicle
    if not VC.isDriver() or IsPauseMenuActive() then return end
    local on = VC.state(vehicle, 'vcBrake') ~= true
    VC.setState(vehicle, 'vcBrake', on)
    if not on then SetVehicleHandbrake(vehicle, false) end
end, false)
RegisterKeyMapping('vc_parkingbrake', 'Véhicule : frein de parcage', 'keyboard', Config.Keys.parkingBrake)

-- Serré : immobile, accélérer et reculer bloqués (à chaque image, au volant)
VC.on('frame', function(_, vehicle)
    if VC.seat ~= -1 or VC.state(vehicle, 'vcBrake') ~= true then return end
    DisableControlAction(0, 71, true) -- accélérer
    DisableControlAction(0, 72, true) -- freiner / reculer
    SetVehicleHandbrake(vehicle, true)
end)

-- Véhicule laissé SANS frein de parcage : libre, comme si quelqu'un était au volant sans rien toucher
-- (le jeu serre le frein à main d'un véhicule abandonné : on le desserre). Suivi tant que le joueur
-- qui l'a laissé reste à moins de ParkedRange m et que personne ne prend le volant.
local function watchParked(vehicle)
    CreateThread(function()
        Wait(1200) -- fin de la descente
        local woke = 0
        while DoesEntityExist(vehicle) and VC.vehicle ~= vehicle and GetPedInVehicleSeat(vehicle, -1) == 0
            and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle)) < Config.ParkedRange do
            if VC.state(vehicle, 'vcBrake') == true then
                SetVehicleHandbrake(vehicle, true)
                Wait(500)
            else
                if controlled(vehicle) then
                    SetVehicleHandbrake(vehicle, false)
                    if GetGameTimer() >= woke then
                        ActivatePhysics(vehicle) -- réveille la physique : il roule en pente
                        woke = GetGameTimer() + 1000
                    end
                end
                Wait(100)
            end
        end
    end)
end

VC.on('leave', function(vehicle, seat)
    if seat == -1 and DoesEntityExist(vehicle) then watchParked(vehicle) end
end)

-- Pousser un véhicule sans frein de parcage, sans conducteur : à pied, contre l'avant ou l'arrière,
-- en avançant (boucle à chaque image seulement au contact d'un tel véhicule)
local pushing = false

local function pushLoop(vehicle)
    pushing = true
    CreateThread(function()
        while true do
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) or not DoesEntityExist(vehicle)
                or GetPedInVehicleSeat(vehicle, -1) ~= 0 or VC.state(vehicle, 'vcBrake') == true
                or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 4.0 then
                break
            end
            if IsEntityTouchingEntity(ped, vehicle) and IsControlPressed(0, 32) then
                if controlled(vehicle) then
                    local vf, pf = GetEntityForwardVector(vehicle), GetEntityForwardVector(ped)
                    local sign = (vf.x * pf.x + vf.y * pf.y) >= 0.0 and 1.0 or -1.0 -- pousse vers l'avant ou l'arrière
                    SetVehicleHandbrake(vehicle, false)
                    SetVehicleForwardSpeed(vehicle, sign * Config.PushSpeed)
                else
                    NetworkRequestControlOfEntity(vehicle)
                end
            end
            Wait(0)
        end
        pushing = false
    end)
end

VC.on('idle', function(ped)
    if pushing or IsEntityDead(ped) then return end
    local pos = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(pos.x, pos.y, pos.z, 3.5, 0, 70)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == 0 and VC.state(vehicle, 'vcBrake') ~= true
        and GetVehicleClass(vehicle) <= 12 then
        pushLoop(vehicle)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetPedConfigFlag(PlayerPedId(), 429, false)
end)
