--[[
    Vehicle Control - ceinture de sécurité (client)
    -----------------------------------------------
    Touche G (Raccourcis clavier > FiveM > "Véhicule : attacher / détacher la ceinture").
      - Son à l'attache et au retrait ; retirée en descendant du véhicule.
      - Détachée : bip au-dessus de 5 MPH, continu jusqu'à l'arrêt du véhicule (ou jusqu'à l'attache).
      - Détachée, accident violent (voir config.lua, Seatbelt) : éjecté à travers le pare-brise.
        Attachée : jamais éjecté (l'éjection automatique du jeu est désactivée, seule cette règle compte).
      - Sons synchronisés : occupants du véhicule à 100 %, joueurs autour selon la distance (états du
        joueur "seatbelt" / "seatbeltAlarm", lus par les autres clients).
    Boucle du bip des autres joueurs (250 ms) uniquement pendant qu'une alarme est active à portée.
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

--- Volume auquel ce client entend le joueur `serverId` (0 hors de portée, nil s'il n'est plus là)
local function hearVolume(serverId)
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local me = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and vehicle == GetVehiclePedIsIn(me, false) then return 1.0 end
    local distance = #(GetEntityCoords(ped) - GetEntityCoords(me))
    if distance >= Config.HearRange then return 0.0 end
    return (1.0 - distance / Config.HearRange) * Config.OutsideVolume
end

local function beltSound(kind, volume)
    VC.toHud('beltSound', { kind = kind, volume = volume })
end

--- Bip : le plus fort entre le sien (100 %) et ceux des joueurs à portée. Boucle seulement pendant une alarme.
local function beepLoop()
    if beepRunning then return end
    beepRunning = true
    CreateThread(function()
        local last = 0.0
        while alarm or next(alarms) do
            local volume = alarm and 1.0 or 0.0
            for serverId in pairs(alarms) do
                local v = hearVolume(serverId)
                if v == nil then
                    alarms[serverId] = nil -- joueur parti / hors de portée réseau
                elseif v > volume then
                    volume = v
                end
            end
            volume = math.floor(volume * 20 + 0.5) / 20
            if volume ~= last then
                last = volume
                VC.toHud('beltBeep', { volume = volume })
            end
            Wait(250)
        end
        if last ~= 0.0 then VC.toHud('beltBeep', { volume = 0.0 }) end
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
    if not silent then beltSound(state and 'on' or 'off', 1.0) end
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
    local volume = hearVolume(serverId)
    if volume and volume > 0.0 then beltSound(value == true and 'on' or 'off', volume) end
end)

AddStateBagChangeHandler('seatbeltAlarm', nil, function(bagName, _, value)
    local serverId = serverIdOfBag(bagName)
    if not serverId or serverId == GetPlayerServerId(PlayerId()) then return end
    alarms[serverId] = value == true or nil
    if value == true then beepLoop() end
end)

-- Ressource redémarrée : état publié remis à zéro
if LocalPlayer.state.seatbelt then LocalPlayer.state:set('seatbelt', false, true) end
if LocalPlayer.state.seatbeltAlarm then LocalPlayer.state:set('seatbeltAlarm', false, true) end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetPedConfigFlag(PlayerPedId(), 32, true)
    LocalPlayer.state:set('seatbelt', false, true)
    LocalPlayer.state:set('seatbeltAlarm', false, true)
    VC.toHud('beltBeep', { volume = 0.0 })
end)
