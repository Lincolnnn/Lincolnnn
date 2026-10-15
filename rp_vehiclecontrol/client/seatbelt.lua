--[[
    Vehicle Control - ceinture de sécurité (client)
    -----------------------------------------------
    Touche G (Raccourcis clavier > FiveM > "Véhicule : attacher / détacher la ceinture").
      - Sons réels (html/sounds) à l'attache et au retrait ; attachée, impossible de descendre sans la
        détacher (touche F bloquée) ; retirée si le joueur est sorti du véhicule autrement.
      - CARILLON DE PORTIÈRE (son belt_chime.ogg) : moteur tournant et une portière ouverte, comme une clé
        restée sur le contact. Publié par le conducteur, puis, s'il descend en laissant le moteur tourner,
        tant qu'il reste près du véhicule (DoorChime.FollowDistance) et qu'aucun autre conducteur n'y monte.
        Coupé net dès que les portières sont fermées ou le moteur coupé. (Plus de carillon de ceinture.)
      - Détachée, accident violent (voir config.lua, Seatbelt) : éjecté à travers le pare-brise.
        Attachée : jamais éjecté (l'éjection automatique du jeu est désactivée, seule cette règle compte).
      - Sons synchronisés (états du joueur "seatbelt" / "seatbeltAlarm" = carillon, lus par les autres clients) :
        occupants du véhicule à 100 %, joueurs autour du véhicule selon VehicleSounds (3 m portière
        ouverte, 1 m tout fermé et étouffé).
    Boucle du carillon (250 ms) uniquement pendant qu'un carillon est actif à portée ; surveillance (250 ms)
    après la descente seulement si le moteur tourne, portière ouverte, joueur à côté.
]]

local Config = VCConfig.Seatbelt
local Chime = VCConfig.DoorChime or {}

local belt, alarm = false, false
local watching = 0     -- véhicule laissé moteur tournant par ce joueur (carillon tant qu'une portière est ouverte)
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

--- Attache / retrait de la ceinture (volume renforcé : BeltSoundVolume)
local function beltSound(kind, volume, muffled)
    VC.sound(kind == 'on' and 'belt_on' or 'belt_off', volume * (Config.BeltSoundVolume or 1.725), nil, muffled)
end

--- Carillon : le plus fort entre le sien (100 %) et ceux des joueurs à portée ; volume 0 = coupé net
local lastChime = '0.00|false'
local function refreshChime()
    -- Le sien : 100 % à bord ; descendu (moteur laissé tournant), selon sa distance au véhicule
    local volume, muffled = alarm and 1.0 or 0.0, false
    if alarm and watching ~= 0 then volume, muffled = VC.hearVehicle(watching) end
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
        -- carillon du tableau de bord (volume renforcé : ChimeVolume)
        VC.soundLoop('chime', { 'belt_chime' }, 1100, volume * (Chime.Volume or 1.56), false, muffled)
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
-- CEINTURE DU JOUEUR ET CARILLON DE PORTIÈRE
-- =========================================================================
--- Une portière (avant / arrière) ouverte ?
local function doorOpen(vehicle)
    for door = 0, 3 do
        if GetVehicleDoorAngleRatio(vehicle, door) > 0.05 then return true end
    end
    return false
end

--- Carillon voulu pour ce véhicule : moteur tournant, une portière ouverte
local function chimeWanted(vehicle)
    return Chime.Enabled ~= false and DoesEntityExist(vehicle) and GetIsVehicleEngineRunning(vehicle) and doorOpen(vehicle)
end

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

--- Après la descente du conducteur : carillon tant que le moteur tourne, portière ouverte, joueur à côté
local function watchLeftVehicle(vehicle)
    watching = vehicle
    CreateThread(function()
        while watching == vehicle do
            local ped = PlayerPedId()
            local driver = DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) or 0
            if not DoesEntityExist(vehicle) or GetVehiclePedIsIn(ped, false) ~= 0 or (driver ~= 0 and driver ~= ped)
                or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > (Chime.FollowDistance or 15.0)
                or not GetIsVehicleEngineRunning(vehicle) then
                break
            end
            setAlarm(chimeWanted(vehicle))
            Wait(250)
        end
        if watching == vehicle then watching = 0; setAlarm(false) end
    end)
end

VC.on('leave', function(vehicle, seat)
    if belt then setBelt(false) end
    VC.hud.belt, VC.hud.alarm = nil, false
    if seat == -1 and vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and GetIsVehicleEngineRunning(vehicle) then
        watchLeftVehicle(vehicle) -- moteur laissé allumé : le carillon continue si une portière est ouverte
    else
        setAlarm(false)
    end
end)

-- Attaché : impossible de descendre (touche F bloquée) sans détacher la ceinture d'abord
VC.on('frame', function()
    if belt then DisableControlAction(0, 75, true) end
end)

-- MDC : bouton "Tester" du volume des sons du véhicule
AddEventHandler('rp_vehiclecontrol:testSound', function(volume)
    VC.sound('belt_on', Config.BeltSoundVolume or 1.725, volume)
    SetTimeout(600, function() VC.sound('belt_chime', Chime.Volume or 1.56, volume) end)
end)

VC.on('tick', function(ped, vehicle)
    -- Descend du véhicule : ceinture retirée (avec le son)
    if belt and GetIsTaskActive(ped, 2) then setBelt(false) end
    -- Carillon de portière : publié par le conducteur
    watching = 0
    setAlarm(VC.seat == -1 and chimeWanted(vehicle))
end)

-- =========================================================================
-- ÉJECTION : ceinture détachée, à partir de MinSpeed MPH (60) avant le choc, vrai accident seulement
--   - arrêt brutal (vitesse tombée à SuddenStopSpeed MPH ou moins, ex. 60 -> 20) : SuddenChance (70 %) ;
--   - accident sans chute brutale (perte d'au moins AccidentDrop MPH) : CrashChance (45 %) ;
--   - jamais sous MinSpeed, jamais pour un simple accrochage, jamais ceinture attachée.
-- Le joueur est PROJETÉ par l'élan du véhicule : distance et vitesse de projection selon la vitesse avant le
-- choc (MinDistance à MinSpeed MPH, MaxDistance à MaxDistanceSpeed MPH), par-dessus le toit, dans le sens de
-- la course. Même trajectoire quoi qu'il y ait devant : un obstacle l'arrête plus tôt, tant pis.
-- =========================================================================
local MPS = 0.44704 -- 1 MPH en m/s

--- Chance d'éjection (0..1) pour ce choc : 0 si pas d'éjection possible
function VC.ejectChance(before, drop)
    if before < Config.MinSpeed or drop < Config.AccidentDrop then return 0.0 end
    if before - drop <= Config.SuddenStopSpeed then return Config.SuddenChance end
    return Config.CrashChance
end

--- Distance de projection (m) selon la vitesse : MinDistance à MinSpeed MPH -> MaxDistance à MaxDistanceSpeed MPH
function VC.throwDistance(before)
    local t = math.min(math.max((before - Config.MinSpeed) / math.max(Config.MaxDistanceSpeed - Config.MinSpeed, 1.0), 0.0), 1.0)
    return Config.MinDistance + (Config.MaxDistance - Config.MinDistance) * t
end

local function eject(ped, vehicle, before, velocity)
    local origin = GetEntityCoords(vehicle)
    local _, max = GetModelDimensions(GetEntityModel(vehicle))
    -- Départ : au-dessus du pare-brise ; direction : celle de la course (sinon l'avant du véhicule)
    local start = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, max.y * 0.3, max.z + 0.7)
    local dir = vector3(velocity.x, velocity.y, 0.0)
    if #dir < 1.0 then
        local f = GetEntityForwardVector(vehicle)
        dir = vector3(f.x, f.y, 0.0)
    end
    dir = dir / #dir
    local distance = VC.throwDistance(before)
    local hSpeed = math.max(before * MPS * Config.ThrowSpeedFactor, Config.ThrowMinSpeed)
    local vSpeed = hSpeed * Config.ThrowLift

    SetEntityCoords(ped, start.x, start.y, start.z, false, false, false, false)
    CreateThread(function()
        Wait(1)
        SetPedToRagdoll(ped, 6000, 6000, 0, false, false, false)
        SetEntityVelocity(ped, dir.x * hSpeed, dir.y * hSpeed, vSpeed)
        SetEntityHealth(ped, math.max(GetEntityHealth(ped) - Config.EjectDamage, 102))
        -- Élan entretenu jusqu'à la distance due à la vitesse (4 s max) ; s'arrête là où un obstacle le bloque
        local deadline, lastGain, best = GetGameTimer() + 4000, GetGameTimer(), 0.0
        while GetGameTimer() < deadline and DoesEntityExist(ped) and not IsEntityDead(ped) do
            local pos = GetEntityCoords(ped)
            local travelled = #(vector3(pos.x - origin.x, pos.y - origin.y, 0.0))
            if travelled >= distance - hSpeed * 0.04 then -- (une image d'avance)
                -- Distance atteinte : élan horizontal coupé (il retombe ici)
                SetEntityVelocity(ped, 0.0, 0.0, GetEntityVelocity(ped).z)
                break
            end
            if travelled > best + 0.05 then best, lastGain = travelled, GetGameTimer()
            elseif GetGameTimer() - lastGain > 300 then break end -- bloqué : il reste là
            local v = GetEntityVelocity(ped)
            SetEntityVelocity(ped, dir.x * hSpeed, dir.y * hSpeed, v.z)
            Wait(0)
        end
    end)
end

VC.on('impact', function(vehicle, before, drop, velocity)
    if not Config.Eject then return end -- éjection désactivée (config.lua : Seatbelt.Eject)
    if belt or not hasBelt(vehicle) then return end
    local chance = VC.ejectChance(before, drop)
    if chance <= 0.0 or math.random() >= chance then return end
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= vehicle then return end
    eject(ped, vehicle, before, velocity)
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
