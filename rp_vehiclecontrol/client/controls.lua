--[[
    Vehicle Control - moteur et portières (client)
    --------------------------------------------------------------
    MOTEUR : SEULE LA TOUCHE (O par défaut, configurable, conducteur) l'allume et l'éteint.
      - O, moteur coupé : vrai démarrage (démarreur, durée complète : on ne peut pas accélérer pendant
        EngineStartTime ms). Il reste allumé, même quand le joueur descend, jusqu'à ce qu'on le coupe.
      - O, moteur allumé : coupé.
      - Il ne démarre jamais tout seul (ni en montant, ni en accélérant) et ne s'éteint jamais tout seul
        (ni en descendant) ; seules exceptions : panne sèche et véhicule cassé.
      L'état voulu est porté par le véhicule ("vcEngine" : true allumé, false coupé), pour tous les joueurs.
      En montant côté conducteur, une notification (car HUD du MDC) présente la touche ; elle disparaît au
      bout de 8 s (EngineNoticeDuration), même sans appuyer, ou dès que la touche est utilisée.
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
local startingUntil = 0    -- démarrage en cours : pas d'accélération avant la fin (vrai démarrage)

local function canStart(vehicle)
    return not VC.isBroken(vehicle) and VC.hasFuel(vehicle)
end

--- Moteur voulu allumé (touche O) ?
local function wanted(vehicle)
    return VC.state(vehicle, 'vcEngine') == true
end

local function engineNotice(vehicle)
    if VC.isBroken(vehicle) then return end
    local on = wanted(vehicle)
    VC.toHud('carNotice', {
        key = VC.keyLabel('vc_engine', Config.Keys.engine),
        text = on and 'Pour couper le moteur' or 'Pour allumer le moteur',
        hint = on and 'Il reste allumé, même en descendant' or 'Seule cette touche l\'allume et l\'éteint',
        duration = Config.EngineNoticeDuration,
    })
end

local function becomeDriver(ped, vehicle)
    SetPedConfigFlag(ped, 429, true) -- le personnage ne démarre plus le moteur en montant
    local state = VC.state(vehicle, 'vcEngine')
    if state == nil and GetIsVehicleEngineRunning(vehicle) and not VC.isFreshSpawn(vehicle) and canStart(vehicle) then
        -- Véhicule ambiant (circulation, PNJ) ou laissé moteur allumé par un autre joueur : il le reste
        VC.setState(vehicle, 'vcEngine', true)
        SetVehicleKeepEngineOnWhenAbandoned(vehicle, true)
    elseif wanted(vehicle) then
        if canStart(vehicle) and not GetIsVehicleEngineRunning(vehicle) then SetVehicleEngineOn(vehicle, true, true, false) end
    else
        -- Véhicule qui vient d'apparaître de la main du joueur, ou coupé : moteur éteint, seule la touche l'allume
        -- Jamais démarré par la touche (véhicule qui vient d'apparaître, de la circulation…) : coupé
        SetVehicleEngineOn(vehicle, false, true, true)
        if VC.state(vehicle, 'vcEngine') == nil and NetworkGetEntityIsNetworked(vehicle) then VC.setState(vehicle, 'vcEngine', false) end
    end
    engineNotice(vehicle)
end

local function toggleEngine()
    local vehicle = VC.vehicle
    if not VC.isDriver() or IsPauseMenuActive() then return end
    VC.toHud('carNoticeHide', {}) -- touche utilisée : la notification disparaît
    if wanted(vehicle) or GetIsVehicleEngineRunning(vehicle) then
        VC.setState(vehicle, 'vcEngine', false)
        SetVehicleKeepEngineOnWhenAbandoned(vehicle, false)
        SetVehicleEngineOn(vehicle, false, false, true)
        startingUntil = 0
        return
    end
    if VC.isBroken(vehicle) then return VC.chat('Le véhicule est hors d\'usage.') end
    if not VC.hasFuel(vehicle) then return VC.chat('Le réservoir est vide.') end
    VC.setState(vehicle, 'vcEngine', true)
    SetVehicleKeepEngineOnWhenAbandoned(vehicle, true)
    SetVehicleEngineOn(vehicle, true, false, true) -- vrai démarrage (pas instantané)
    startingUntil = GetGameTimer() + (Config.EngineStartTime or 1200)
end
RegisterCommand('vc_engine', toggleEngine, false)
RegisterKeyMapping('vc_engine', 'Véhicule : allumer / couper le moteur', 'keyboard', Config.Keys.engine)

VC.on('enter', function(ped, vehicle, seat)
    if seat == -1 then becomeDriver(ped, vehicle) end
end)

VC.on('seat', function(ped, vehicle, seat)
    if seat == -1 then becomeDriver(ped, vehicle) end
end)

VC.on('frame', function(_, vehicle)
    if VC.seat ~= -1 then return end
    local running = GetIsVehicleEngineRunning(vehicle)
    -- Démarrage en cours : on ne part pas avant la fin du démarreur
    if GetGameTimer() < startingUntil then
        DisableControlAction(0, 71, true)
        DisableControlAction(0, 72, true)
    end
    -- Panne sèche / véhicule cassé : le moteur n'est plus voulu allumé (pas de redémarrage tout seul ensuite)
    if wanted(vehicle) and not canStart(vehicle) then VC.setState(vehicle, 'vcEngine', false) end
    if running then
        -- Le jeu le démarre tout seul (montée, accélération) : coupé, seule la touche compte
        if not wanted(vehicle) or not canStart(vehicle) then SetVehicleEngineOn(vehicle, false, true, true) end
    elseif wanted(vehicle) and canStart(vehicle) and GetGameTimer() >= startingUntil then
        SetVehicleEngineOn(vehicle, true, true, false) -- le jeu l'a coupé tout seul : relancé
    end
end)

-- Descente du conducteur : le moteur garde son état (allumé par la touche : il le reste ; coupé : il le reste)
VC.on('leave', function(vehicle, seat, info)
    startingUntil = 0
    if seat ~= -1 or not DoesEntityExist(vehicle) or (info and info.gone) then return end
    if info and info.swap then
        -- Passé directement dans un autre véhicule : l'ancien s'arrête (moteur coupé, plus "toujours allumé")
        VC.setState(vehicle, 'vcEngine', false)
        SetVehicleKeepEngineOnWhenAbandoned(vehicle, false)
        if controlled(vehicle) then SetVehicleEngineOn(vehicle, false, true, true) end
        return
    end
    local keep = wanted(vehicle)
    SetVehicleKeepEngineOnWhenAbandoned(vehicle, keep)
    CreateThread(function()
        local untilTime = GetGameTimer() + 2500
        while GetGameTimer() < untilTime and DoesEntityExist(vehicle) and VC.vehicle ~= vehicle do
            if GetPedInVehicleSeat(vehicle, -1) ~= 0 then break end -- quelqu'un a repris le volant
            if wanted(vehicle) ~= keep or not controlled(vehicle) then break end
            local running = GetIsVehicleEngineRunning(vehicle)
            if keep and not running and canStart(vehicle) then
                SetVehicleEngineOn(vehicle, true, true, false)
            elseif not keep and running then
                SetVehicleEngineOn(vehicle, false, true, true)
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

-- Descendre portière ouverte : elle RESTE ouverte. Le jeu referme la portière à la fin de la descente ; les
-- portières déjà ouvertes avant de descendre (touche U / I, ou ouvertes par quelqu'un) sont rouvertes.
local exitDoors = nil -- { vehicle, doors = { [n°] = true } } : portières ouvertes au début de la descente
VC.on('frame', function(ped, vehicle)
    if not GetIsTaskActive(ped, 2) then exitDoors = nil return end
    if exitDoors and exitDoors.vehicle == vehicle then return end
    local doors = {}
    for door = 0, 3 do
        if GetVehicleDoorAngleRatio(vehicle, door) > 0.5 then doors[door] = true end
    end
    exitDoors = { vehicle = vehicle, doors = doors }
end)

VC.on('leave', function(vehicle, _, info)
    local snapshot = exitDoors
    exitDoors = nil
    if Config.KeepDoorOpenOnExit == false or (info and (info.swap or info.gone)) then return end
    if not snapshot or snapshot.vehicle ~= vehicle or not next(snapshot.doors) then return end
    CreateThread(function()
        local untilTime = GetGameTimer() + 3000
        -- Chaque portière n'est rouverte qu'une fois (quand le jeu la referme) : on ne lutte jamais contre une
        -- fermeture voulue ensuite
        while GetGameTimer() < untilTime and DoesEntityExist(vehicle) and VC.vehicle == 0 and next(snapshot.doors) do
            if controlled(vehicle) then
                for door in pairs(snapshot.doors) do
                    if GetVehicleDoorAngleRatio(vehicle, door) < 0.3 then
                        SetVehicleDoorOpen(vehicle, door, false, false)
                        snapshot.doors[door] = nil
                    end
                end
            end
            Wait(100)
        end
    end)
end)

-- Le serveur demande au propriétaire réseau du véhicule d'appliquer les portières
RegisterNetEvent('rp_vehiclecontrol:applyDoors', function(netId, actions)
    local vehicle = NetToVeh(netId)
    if vehicle ~= 0 and DoesEntityExist(vehicle) and type(actions) == 'table' then applyDoors(vehicle, actions) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetPedConfigFlag(PlayerPedId(), 429, false)
end)
