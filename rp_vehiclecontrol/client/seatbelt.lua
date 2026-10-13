--[[
    Vehicle Control - ceinture de sécurité (client)
    -----------------------------------------------
    Touche G (Raccourcis clavier > FiveM > "Véhicule : attacher / détacher la ceinture").
      - Sons réels (html/sounds) à l'attache et au retrait ; attachée, impossible de descendre sans la
        détacher (touche F bloquée) ; retirée si le joueur est sorti du véhicule autrement.
      - Détachée : carillon au-dessus de 5 MPH ; coupé net dès que la ceinture est attachée, que le
        joueur descend ou que le véhicule est arrêté (sous StopSpeed).
      - Détachée, accident violent (voir config.lua, Seatbelt) : éjecté à travers le pare-brise.
        Attachée : jamais éjecté (l'éjection automatique du jeu est désactivée, seule cette règle compte).
      - Sons synchronisés (états du joueur "seatbelt" / "seatbeltAlarm", lus par les autres clients) :
        occupants du véhicule à 100 %, joueurs autour du véhicule selon VehicleSounds (3 m portière
        ouverte, 1 m tout fermé et étouffé).
    Boucle du carillon (250 ms) uniquement pendant qu'une alarme est active à portée.
]]

local Config = VCConfig.Seatbelt

local belt, alarm = false, false
local alarms = {}      -- [id serveur] = true : autres joueurs dont l'alarme est active
local beepRunning = false

local function hasBelt(vehicle)
    return not Config.NoBeltClasses[GetVehicleClass(vehicle)]
end

-- =========================================================================
-- SONS : volume selon la distance (occupants du même véhicule : 100 %)
-- =========================================================================
local function serverIdOfBag(bagName)
    return tonumber(bagName:match('^player:(%d+)$'))
end

--- Volume (0 hors de portée, nil si le joueur n'est plus là) et étouffement auxquels ce client entend
--- les sons de ceinture du joueur `serverId` : ils viennent de son véhicule (ou du dernier, s'il vient
--- d'en descendre)
local function hearVolume(serverId)
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then vehicle = GetVehiclePedIsIn(ped, true) end
    if vehicle == 0 then return 0.0, false end
    return VC.hearVehicle(vehicle)
end

local function beltSound(kind, volume, muffled)
    VC.sound(kind == 'on' and 'belt_on' or 'belt_off', volume, nil, muffled)
end

--- Carillon : le plus fort entre le sien (100 %) et ceux des joueurs à portée ; volume 0 = coupé net
local lastChime = '0.00|false'
local function refreshChime()
    local volume, muffled = alarm and 1.0 or 0.0, false
    for serverId in pairs(alarms) do
        local v, m = hearVolume(serverId)
        if v == nil then
            alarms[serverId] = nil -- joueur parti / hors de portée réseau
        elseif v > volume then
            volume, muffled = v, m
        end
    end
    volume = math.floor(volume * 20 + 0.5) / 20
    local key = ('%.2f|%s'):format(volume, tostring(volume > 0 and muffled))
    if key ~= lastChime then
        lastChime = key
        VC.soundLoop('chime', { 'belt_chime' }, 1100, volume, false, muffled) -- carillon du tableau de bord
    end
end

--- Boucle seulement pendant une alarme (la sienne ou celle d'un joueur à portée)
local function beepLoop()
    refreshChime()
    if beepRunning then return end
    beepRunning = true
    CreateThread(function()
        while alarm or next(alarms) do
            Wait(250)
            refreshChime()
        end
        refreshChime()
        beepRunning = false
    end)
end

-- =========================================================================
-- CEINTURE DU JOUEUR
-- =========================================================================
local function setAlarm(state)
    if state == alarm then return end
    alarm = state
    VC.hud.alarm = state
    LocalPlayer.state:set('seatbeltAlarm', state, true) -- entendu par les joueurs proches
    beepLoop()
end

local function setBelt(state, silent)
    if state == belt then return end
    belt = state
    if VC.hud.belt ~= nil then VC.hud.belt = state end
    LocalPlayer.state:set('seatbelt', state, true) -- les joueurs proches entendent le son
    if state then setAlarm(false) end
    if not silent then beltSound(state and 'on' or 'off', 1.0, false) end
end

function VC.isBuckled() return belt end

RegisterCommand('vc_seatbelt', function()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 or not hasBelt(vehicle) or IsPauseMenuActive() then return end
    setBelt(not belt)
end, false)
RegisterKeyMapping('vc_seatbelt', 'Véhicule : attacher / détacher la ceinture', 'keyboard', VCConfig.Keys.seatbelt)

VC.on('enter', function(ped, vehicle)
    SetPedConfigFlag(ped, 32, false) -- pas d'éjection automatique du jeu : seule la règle ci-dessous compte
    if hasBelt(vehicle) then VC.hud.belt = belt else VC.hud.belt = nil end
    VC.hud.alarm = false
end)

VC.on('leave', function()
    if belt then setBelt(false) end
    setAlarm(false)
    VC.hud.belt, VC.hud.alarm = nil, false
end)

-- Attaché : impossible de descendre (touche F bloquée) sans détacher la ceinture d'abord
VC.on('frame', function()
    if belt then DisableControlAction(0, 75, true) end
end)

-- MDC : bouton "Tester" du volume des sons du véhicule
AddEventHandler('rp_vehiclecontrol:testSound', function(volume)
    VC.sound('belt_on', 1.0, volume)
    SetTimeout(600, function() VC.sound('belt_chime', 1.0, volume) end)
end)

VC.on('tick', function(ped, vehicle)
    local speed = GetEntitySpeed(vehicle) * VC.MPH
    -- Descend du véhicule : ceinture retirée (avec le son)
    if belt and GetIsTaskActive(ped, 2) then setBelt(false) end
    if hasBelt(vehicle) and not belt then
        if not alarm and speed > Config.AlarmSpeed then
            setAlarm(true)
        elseif alarm and speed < Config.StopSpeed then
            setAlarm(false)
        end
    elseif alarm then
        setAlarm(false)
    end
end)

-- =========================================================================
-- ÉJECTION : ceinture détachée, accident violent
--   - plus de HighSpeed MPH avant le choc : dès que le choc fait perdre HighSpeedDrop MPH ;
--   - entre MinSpeed et HighSpeed : chute brutale d'au moins SuddenDrop MPH (ex. 45 -> 0) ;
--   - jamais sous MinSpeed.
-- =========================================================================
function VC.isViolentCrash(before, drop)
    if before < Config.MinSpeed then return false end
    if before > Config.HighSpeed and drop >= Config.HighSpeedDrop then return true end
    return drop >= Config.SuddenDrop
end

local function eject(ped, vehicle, velocity)
    local forward = GetEntityForwardVector(vehicle)
    local pos = GetEntityCoords(vehicle)
    SetEntityCoords(ped, pos.x + forward.x * 1.8, pos.y + forward.y * 1.8, pos.z + 0.6, false, false, false, false)
    CreateThread(function()
        Wait(1)
        SetEntityVelocity(ped, velocity.x, velocity.y, velocity.z + 1.5) -- garde l'élan du véhicule
        SetPedToRagdoll(ped, 3500, 3500, 0, false, false, false)
        SetEntityHealth(ped, math.max(GetEntityHealth(ped) - Config.EjectDamage, 102))
    end)
end

VC.on('impact', function(vehicle, before, drop, velocity)
    if belt or not hasBelt(vehicle) then return end
    if not VC.isViolentCrash(before, drop) then return end
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= vehicle then return end
    eject(ped, vehicle, velocity)
end)

-- =========================================================================
-- CEINTURE ET ALARME DES AUTRES JOUEURS
-- =========================================================================
AddStateBagChangeHandler('seatbelt', nil, function(bagName, _, value)
    local serverId = serverIdOfBag(bagName)
    if not serverId or serverId == GetPlayerServerId(PlayerId()) then return end
    local volume, muffled = hearVolume(serverId)
    if volume and volume > 0.0 then beltSound(value == true and 'on' or 'off', volume, muffled) end
end)

AddStateBagChangeHandler('seatbeltAlarm', nil, function(bagName, _, value)
    local serverId = serverIdOfBag(bagName)
    if not serverId or serverId == GetPlayerServerId(PlayerId()) then return end
    alarms[serverId] = value == true or nil
    beepLoop() -- démarre, ou coupe net le carillon de ce joueur
end)

-- Ressource redémarrée : état publié remis à zéro
if LocalPlayer.state.seatbelt then LocalPlayer.state:set('seatbelt', false, true) end
if LocalPlayer.state.seatbeltAlarm then LocalPlayer.state:set('seatbeltAlarm', false, true) end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetPedConfigFlag(PlayerPedId(), 32, true)
    LocalPlayer.state:set('seatbelt', false, true)
    LocalPlayer.state:set('seatbeltAlarm', false, true)
    VC.soundLoop('chime', { 'belt_chime' }, 1100, 0.0)
end)
