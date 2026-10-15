--[[
    Vehicle Control - ceinture de sécurité et carillons (client)
    -----------------------------------------------------------
    Touche G (Raccourcis clavier > FiveM > "Véhicule : attacher / détacher la ceinture").
      - Sons réels (html/sounds) à l'attache et au retrait ; attachée, impossible de descendre sans la
        détacher (touche F bloquée) ; retirée si le joueur est sorti du véhicule autrement.
      - CARILLON DE CEINTURE, par véhicule, véhicule roulant (au-dessus de AlarmSpeed MPH) :
          UN occupant détaché          -> belt_chime.ogg (un seul, en boucle) ;
          PLUSIEURS détachés en même temps -> belt_chime coupé net, fast_belt_chime.ogg (en boucle) ;
          l'un d'eux s'attache (il n'en reste qu'un) -> fast_belt_chime coupé, belt_chime relancé du début.
        Coupé net quand le véhicule s'arrête (sous StopSpeed) ; relancé du début quand il roule à nouveau.
      - CARILLON DE PORTIÈRE (door_chime.ogg, en boucle), moteur allumé uniquement : une portière ou plus
        ouverte(s), jusqu'à ce qu'elles soient refermées ou que le moteur soit coupé.
      - Jamais deux fois le même son en même temps (le NUI coupe le précédent avant de rejouer).
        Publié par le conducteur, puis, s'il descend en laissant le moteur tourner, tant qu'il reste près
        du véhicule (DoorChime.FollowDistance) et qu'aucun autre conducteur n'y monte.
      - Détachée, accident violent (voir config.lua, Seatbelt) : éjecté à travers le pare-brise.
        Attachée : jamais éjecté (l'éjection automatique du jeu est désactivée, seule cette règle compte).
      - Sons synchronisés (états du joueur "seatbelt", "seatbeltAlarm" = détaché en roulant, "doorChime" = 0 / 1,
        lus par les autres clients) : occupants du véhicule à 100 %, joueurs autour du
        véhicule selon VehicleSounds (3 m portière ouverte, 1 m tout fermé et étouffé).
    Boucle des carillons (250 ms) uniquement pendant qu'un carillon est actif à portée ; surveillance (250 ms)
    après la descente seulement si le moteur tourne et qu'une portière est ouverte, joueur à côté.
]]

local Config = VCConfig.Seatbelt
local Chime = VCConfig.DoorChime or {}

local belt, alarm, doorLevel = false, false, 0
local watching = 0     -- véhicule laissé moteur tournant par ce joueur (carillon tant qu'une portière est ouverte)
local alarms = {}      -- [id serveur] = true : autres joueurs dont le carillon de ceinture sonne
local doorChimes = {}  -- [id serveur] = true : autres joueurs dont le carillon de portière sonne
local chimeRunning = false

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
--- les sons du joueur `serverId` : ils viennent de son véhicule (ou du dernier, s'il vient d'en descendre)
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

local lastBelt, lastDoor = '|0.00|false', '0.00|false'

--- Véhicule d'où viennent les sons du joueur `serverId` (0 : aucun, nil : joueur parti)
local function vehicleOf(serverId)
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then vehicle = GetVehiclePedIsIn(ped, true) end
    return vehicle
end

--- Carillons : pour chaque véhicule, le nombre d'occupants détachés (soi compris) ; le véhicule le plus
--- fort pour ce joueur donne le son (1 détaché : belt_chime, plusieurs : fast_belt_chime) ; volume 0 = coupé net
local function refreshChimes()
    local unbuckled = {} -- [véhicule] = nombre d'occupants détachés, véhicule roulant
    local mine = VC.vehicle or 0
    if alarm and mine ~= 0 then unbuckled[mine] = 1 end
    for serverId in pairs(alarms) do
        local vehicle = vehicleOf(serverId)
        if vehicle == nil then alarms[serverId] = nil
        elseif vehicle ~= 0 then unbuckled[vehicle] = (unbuckled[vehicle] or 0) + 1 end
    end
    local count, volume, muffled = 0, 0.0, false
    for vehicle, n in pairs(unbuckled) do
        local v, m = VC.hearVehicle(vehicle)
        if v > volume then count, volume, muffled = n, v, m end
    end
    volume = math.floor(volume * 20 + 0.5) / 20
    local file = count >= 2 and 'fast_belt_chime' or 'belt_chime'
    local key = ('%s|%.2f|%s'):format(volume > 0 and file or '', volume, tostring(volume > 0 and muffled))
    if key ~= lastBelt then
        lastBelt = key
        -- Un seul fichier en boucle ; changer de fichier (1 <-> plusieurs détachés) coupe net l'autre
        VC.soundLoop('chime', { file }, 0, volume * (Config.ChimeVolume or 1.56), true, muffled)
    end

    -- Carillon de portière : le sien (à bord : 100 % ; descendu : selon la distance), puis les autres
    local dVolume, dMuffled = 0.0, false
    if doorLevel > 0 then
        dVolume = 1.0
        if watching ~= 0 then dVolume, dMuffled = VC.hearVehicle(watching) end
    end
    for serverId in pairs(doorChimes) do
        local v, m = hearVolume(serverId)
        if v == nil then doorChimes[serverId] = nil
        elseif v > dVolume then dVolume, dMuffled = v, m end
    end
    dVolume = math.floor(dVolume * 20 + 0.5) / 20
    key = ('%.2f|%s'):format(dVolume, tostring(dVolume > 0 and dMuffled))
    if key ~= lastDoor then
        lastDoor = key
        VC.soundLoop('door', { 'door_chime' }, 0, dVolume * (Chime.Volume or 1.56), true, dMuffled)
    end
end

--- Boucle seulement pendant un carillon (le sien ou celui d'un joueur à portée)
local function chimeLoop()
    refreshChimes()
    if chimeRunning then return end
    chimeRunning = true
    CreateThread(function()
        while alarm or doorLevel > 0 or next(alarms) or next(doorChimes) do
            Wait(250)
            refreshChimes()
        end
        refreshChimes()
        chimeRunning = false
    end)
end

-- =========================================================================
-- CEINTURE DU JOUEUR ET CARILLON DE PORTIÈRE
-- =========================================================================
--- Nombre de portières (avant / arrière) ouvertes
local function openDoors(vehicle)
    local n = 0
    for door = 0, 3 do
        if GetVehicleDoorAngleRatio(vehicle, door) > 0.05 then n = n + 1 end
    end
    return n
end

--- Carillon de portière voulu : 1 (au moins une portière ouverte, moteur allumé), sinon 0
local function doorChimeLevel(vehicle)
    if Chime.Enabled == false or not DoesEntityExist(vehicle) or not GetIsVehicleEngineRunning(vehicle) then return 0 end
    return openDoors(vehicle) > 0 and 1 or 0
end

local function setAlarm(state)
    if state == alarm then return end
    alarm = state
    VC.hud.alarm = state
    LocalPlayer.state:set('seatbeltAlarm', state, true) -- entendu par les joueurs proches
    chimeLoop()
end

local function setDoorChime(level)
    if level == doorLevel then return end
    doorLevel = level
    LocalPlayer.state:set('doorChime', level, true) -- entendu par les joueurs proches
    chimeLoop()
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

--- Après la descente du conducteur : carillon de portière tant que le moteur tourne, portière ouverte,
--- joueur à côté
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
            setDoorChime(doorChimeLevel(vehicle))
            Wait(250)
        end
        if watching == vehicle then watching = 0; setDoorChime(0) end
    end)
end

VC.on('leave', function(vehicle, seat)
    if belt then setBelt(false) end
    setAlarm(false)
    VC.hud.belt, VC.hud.alarm = nil, false
    if seat == -1 and vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and GetIsVehicleEngineRunning(vehicle) then
        watchLeftVehicle(vehicle) -- moteur laissé allumé : le carillon de portière continue si une portière est ouverte
    else
        setDoorChime(0)
    end
end)

-- Attaché : impossible de descendre (touche F bloquée) sans détacher la ceinture d'abord
VC.on('frame', function()
    if belt then DisableControlAction(0, 75, true) end
end)

-- MDC : bouton "Tester" du volume des sons du véhicule
AddEventHandler('rp_vehiclecontrol:testSound', function(volume)
    VC.sound('belt_on', Config.BeltSoundVolume or 1.725, volume)
    SetTimeout(600, function() VC.sound('belt_chime', Config.ChimeVolume or 1.56, volume) end)
end)

VC.on('tick', function(ped, vehicle)
    local speed = GetEntitySpeed(vehicle) * VC.MPH
    -- Descend du véhicule : ceinture retirée (avec le son)
    if belt and GetIsTaskActive(ped, 2) then setBelt(false) end
    -- Carillon de ceinture : détachée, au-dessus de AlarmSpeed ; coupé sous StopSpeed
    if hasBelt(vehicle) and not belt then
        if not alarm and speed > Config.AlarmSpeed then
            setAlarm(true)
        elseif alarm and speed < Config.StopSpeed then
            setAlarm(false)
        end
    elseif alarm then
        setAlarm(false)
    end
    -- Carillon de portière : publié par le conducteur
    watching = 0
    setDoorChime(VC.seat == -1 and doorChimeLevel(vehicle) or 0)
end)

-- =========================================================================
-- ÉJECTION : ceinture détachée, à partir de MinSpeed MPH (60) avant le choc, vrai accident seulement
--   - arrêt brutal (vitesse tombée à SuddenStopSpeed MPH ou moins, ex. 60 -> 20) : SuddenChance (70 %) ;
--   - accident sans chute brutale (perte d'au moins AccidentDrop MPH) : CrashChance (45 %) ;
--   - jamais sous MinSpeed, jamais pour un simple accrochage, jamais ceinture attachée.
-- Le joueur est PROJETÉ par l'élan du véhicule, en ragdoll (corps inerte du jeu) : une impulsion de départ,
-- calculée pour une distance IDÉALE selon la vitesse (IdealMinDistance à MinSpeed MPH -> IdealMaxDistance à
-- MaxDistanceSpeed MPH), jamais plus rapide que le véhicule. Ensuite, la physique du jeu décide : il peut
-- aller un peu plus loin (glissade, roulé) ou moins loin (obstacle), sans arrêt net.
-- =========================================================================
local MPS = 0.44704 -- 1 MPH en m/s

--- Chance d'éjection (0..1) pour ce choc : 0 si pas d'éjection possible
function VC.ejectChance(before, drop)
    if before < Config.MinSpeed or drop < Config.AccidentDrop then return 0.0 end
    if before - drop <= Config.SuddenStopSpeed then return Config.SuddenChance end
    return Config.CrashChance
end

--- Distance idéale de projection (m) selon la vitesse (pas une limite)
function VC.throwDistance(before)
    local t = math.min(math.max((before - Config.MinSpeed) / math.max(Config.MaxDistanceSpeed - Config.MinSpeed, 1.0), 0.0), 1.0)
    return Config.IdealMinDistance + (Config.IdealMaxDistance - Config.IdealMinDistance) * t
end

local GRAVITY = 9.81

--- Portée en l'air (m) d'un départ à `h` m du sol, vitesse horizontale `vh`, verticale vh * lift
local function airRange(vh, lift, h)
    local vz = vh * lift
    return vh * (vz + math.sqrt(vz * vz + 2.0 * GRAVITY * h)) / GRAVITY
end

--- Vitesse horizontale (m/s) pour que le vol (avant la glissade) fasse `range` m
function VC.throwSpeed(range, lift, h)
    local lo, hi = 1.0, 80.0
    for _ = 1, 30 do
        local mid = (lo + hi) / 2
        if airRange(mid, lift, h) < range then lo = mid else hi = mid end
    end
    return (lo + hi) / 2
end

local function eject(ped, vehicle, before, velocity)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    -- Départ : au-dessus du pare-brise ; direction : celle de la course (sinon l'avant du véhicule)
    local start = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, max.y * 0.3, max.z + 0.7)
    local dir = vector3(velocity.x, velocity.y, 0.0)
    if #dir < 1.0 then
        local f = GetEntityForwardVector(vehicle)
        dir = vector3(f.x, f.y, 0.0)
    end
    dir = dir / #dir
    -- Impulsion calculée pour la distance idéale (une part en vol, le reste en glissade), plafonnée à la
    -- vitesse du véhicule : c'est sa vitesse qui donne l'élan
    local height = math.max((max.z + 0.7) - min.z, 1.0)
    local lift = Config.ThrowLift
    local hSpeed = VC.throwSpeed(VC.throwDistance(before) * Config.AirShare, lift, height)
    hSpeed = math.min(hSpeed, before * MPS)
    local vx, vy, vz = dir.x * hSpeed, dir.y * hSpeed, hSpeed * lift

    -- Sorti du véhicule tout de suite (sinon le jeu le garde assis / debout), corps inerte autorisé
    ClearPedTasksImmediately(ped)
    SetPedCanRagdoll(ped, true)
    SetEntityCoords(ped, start.x, start.y, start.z, false, false, false, false)
    SetPedToRagdoll(ped, 5000, 7000, 0, false, false, false)
    SetEntityVelocity(ped, vx, vy, vz)
    SetEntityHealth(ped, math.max(GetEntityHealth(ped) - Config.EjectDamage, 102))
    CreateThread(function()
        -- Premières images : l'impulsion est réappliquée (le ragdoll du jeu peut la perdre en s'activant).
        -- Pendant tout le vol : ragdoll maintenu (jamais debout en l'air). Aucune vitesse coupée ensuite.
        local now = GetGameTimer()
        local pushUntil, flyUntil = now + Config.PushTime, now + 4000
        while GetGameTimer() < flyUntil and DoesEntityExist(ped) and not IsEntityDead(ped) do
            if not IsPedRagdoll(ped) then SetPedToRagdoll(ped, 4000, 6000, 0, false, false, false) end
            if GetGameTimer() < pushUntil then
                SetEntityVelocity(ped, vx, vy, GetEntityVelocity(ped).z)
            elseif not IsPedFalling(ped) and #GetEntityVelocity(ped) < 1.5 then
                break -- retombé et arrêté
            end
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
    chimeLoop() -- démarre, ou coupe net le carillon de ce joueur
end)

AddStateBagChangeHandler('doorChime', nil, function(bagName, _, value)
    local serverId = serverIdOfBag(bagName)
    if not serverId or serverId == GetPlayerServerId(PlayerId()) then return end
    doorChimes[serverId] = (tonumber(value) or 0) > 0 or nil
    chimeLoop() -- démarre, ou coupe net
end)

-- Ressource redémarrée : état publié remis à zéro
if LocalPlayer.state.seatbelt then LocalPlayer.state:set('seatbelt', false, true) end
if LocalPlayer.state.seatbeltAlarm then LocalPlayer.state:set('seatbeltAlarm', false, true) end
if LocalPlayer.state.doorChime then LocalPlayer.state:set('doorChime', 0, true) end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetPedConfigFlag(PlayerPedId(), 32, true)
    LocalPlayer.state:set('seatbelt', false, true)
    LocalPlayer.state:set('seatbeltAlarm', false, true)
    LocalPlayer.state:set('doorChime', 0, true)
    VC.soundLoop('chime', { 'belt_chime' }, 0, 0.0)
    VC.soundLoop('door', { 'door_chime' }, 0, 0.0)
end)
