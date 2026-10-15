--[[
    Vehicle Control - ceinture de sécurité et carillons (client)
    -----------------------------------------------------------
    Touche G (Raccourcis clavier > FiveM > "Véhicule : attacher / détacher la ceinture").
      - Sons réels (html/sounds) à l'attache et au retrait ; attachée, impossible de descendre sans la
        détacher (touche F bloquée) ; retirée si le joueur est sorti du véhicule autrement.
      - CARILLON DE CEINTURE, par véhicule, dès que le véhicule roule (au-dessus de AlarmSpeed MPH, 1) : en boucle,
        sans jamais s'arrêter, jusqu'à l'arrêt du véhicule ou l'attache (muet hors de portée, jamais coupé) :
          UN occupant détaché          -> belt_chime.ogg (un seul, en boucle) ;
          PLUSIEURS détachés en même temps -> belt_chime coupé net, fast_belt_chime.ogg (en boucle) ;
          l'un d'eux s'attache (il n'en reste qu'un) -> fast_belt_chime coupé, belt_chime relancé du début.
        Coupé net quand le véhicule s'arrête (sous StopSpeed pendant StopDelay ms) ; relancé du début quand il
        roule à nouveau. Une coupure très courte (moins de 1,5 s) reprend là où il en était, sans repartir du début.
      - CARILLON DE PORTIÈRE (door_chime.ogg, en boucle), moteur allumé uniquement : une portière ou plus
        ouverte(s), jusqu'à ce qu'elles soient refermées ou que le moteur soit coupé. Il vient du VÉHICULE :
        chaque joueur le calcule lui-même pour les véhicules au moteur allumé (état "vcEngine"), même vides
        (personne à bord) : entendu à bord, et dehors autour de la carrosserie (VehicleSounds), en continu comme
        à bord : en boucle sans jamais s'arrêter tant que le moteur tourne portière ouverte (muet hors de
        portée, réentendu là où il en est) ; arrêté seulement moteur coupé ou portière refermée.
      - Diagnostic : "setr vc_debug_sound 1" (console F8) affiche chaque changement des carillons.
      - Jamais deux fois le même son en même temps (le NUI coupe le précédent avant de rejouer).
      - Détachée, accident violent (voir config.lua, Seatbelt) : éjecté à travers le pare-brise.
        Attachée : jamais éjecté (l'éjection automatique du jeu est désactivée, seule cette règle compte).
      - Sons synchronisés (états du joueur "seatbelt", "seatbeltAlarm" = détaché en roulant, lus par les autres
        clients ; carillon de portière : état du véhicule "vcEngine" + portières, vues par tous) : occupants du véhicule à 100 %, joueurs autour du
        véhicule selon VehicleSounds (3 m portière ouverte, 1 m tout fermé et étouffé).
    Boucle des carillons (250 ms) uniquement pendant qu'un carillon de ceinture sonne à portée ou qu'un
    véhicule au moteur allumé (par Vehicle Control) est à portée réseau ; aucune sinon.
]]

local Config = VCConfig.Seatbelt
local Chime = VCConfig.DoorChime or {}

local belt, alarm = false, false
local alarms = {}      -- [id serveur] = true : autres joueurs dont le carillon de ceinture sonne
local engines = {}     -- [nom du state bag] = true : véhicules au moteur allumé (vcEngine), même vides
local chimeRunning = false
local stoppedSince = nil -- véhicule sous StopSpeed depuis (carillon de ceinture coupé après StopDelay)

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

--- Attache / retrait de la ceinture (volume : BeltSoundVolume)
local function beltSound(kind, volume, muffled)
    VC.sound(kind == 'on' and 'belt_on' or 'belt_off', volume * (Config.BeltSoundVolume or 1.0), nil, muffled)
end

local doorSeen = {} -- [véhicule] = dernier moment où une portière a été vue ouverte

--- Une portière (avant / arrière) ouverte ? Encore vraie DoorHold ms après (une portière qui bouge un
--- instant ne coupe pas le carillon)
local function doorOpen(vehicle)
    local now = GetGameTimer()
    for door = 0, 3 do
        if GetVehicleDoorAngleRatio(vehicle, door) > 0.05 then
            doorSeen[vehicle] = now
            return true
        end
    end
    local seen = doorSeen[vehicle]
    if seen and now - seen < (Chime.DoorHold or 800) then return true end
    doorSeen[vehicle] = nil
    return false
end

--- Moteur allumé ? État voulu "vcEngine" (le même pour tous, stable même véhicule laissé vide, quand le jeu
--- le coupe un instant avant que Vehicle Control le relance) ou moteur qui tourne
local function engineOn(vehicle)
    return VC.state(vehicle, 'vcEngine') == true or GetIsVehicleEngineRunning(vehicle)
end

--- Diagnostic (F8) : setr vc_debug_sound 1
local function debugSound(text)
    if GetConvarInt('vc_debug_sound', 0) == 1 then print(('[rp_vehiclecontrol] %s'):format(text)) end
end

local lastBelt, lastDoor = '|0.00|false', 'false|0.00|false'

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
    -- Le véhicule le plus fort donne le son ; aucun à portée mais un carillon en cours : gardé muet (keep)
    local count, volume, muffled = 0, 0.0, false
    for vehicle, n in pairs(unbuckled) do
        local v, m = VC.hearVehicle(vehicle)
        if v > volume or count == 0 then count, volume, muffled = n, v, m end
    end
    volume = math.floor(volume * 20 + 0.5) / 20
    local active = count > 0
    local file = count >= 2 and 'fast_belt_chime' or 'belt_chime'
    local key = ('%s|%.2f|%s'):format(active and file or '', volume, tostring(volume > 0 and muffled))
    if key ~= lastBelt then
        lastBelt = key
        debugSound(('carillon de ceinture : %s (alarme %s, autres %d)'):format(key, tostring(alarm), (function() local n = 0 for _ in pairs(alarms) do n = n + 1 end return n end)()))
        -- Un seul fichier en boucle, sans jamais s'arrêter tant qu'un occupant est détaché véhicule roulant ;
        -- changer de fichier (1 <-> plusieurs détachés) coupe net l'autre
        VC.soundLoop('chime', { file }, 0, volume * (Config.ChimeVolume or 1.0), true, muffled, active)
    end

    -- Carillon de portière : vient du véhicule (moteur allumé + portière ouverte), même vide ; le plus fort
    local dVolume, dMuffled, dActive = 0.0, false, false
    for vehicle in pairs(doorSeen) do
        if not DoesEntityExist(vehicle) then doorSeen[vehicle] = nil end -- véhicule supprimé
    end
    if Chime.Enabled ~= false then
        local checked = {}
        local function consider(vehicle)
            if vehicle == 0 or checked[vehicle] or not DoesEntityExist(vehicle) then return end
            checked[vehicle] = true
            if not engineOn(vehicle) or not doorOpen(vehicle) then return end
            local v, m = VC.hearVehicle(vehicle)
            if v > dVolume or not dActive then dVolume, dMuffled = v, m end
            dActive = true
        end
        consider(VC.vehicle or 0) -- le sien (même sans état vcEngine)
        for bagName in pairs(engines) do
            local vehicle = GetEntityFromStateBagName(bagName) or 0
            if vehicle == 0 then engines[bagName] = nil -- hors de portée : repris quand il revient (état du véhicule)
            else consider(vehicle) end
        end
    end
    dVolume = math.floor(dVolume * 20 + 0.5) / 20
    key = ('%s|%.2f|%s'):format(tostring(dActive), dVolume, tostring(dVolume > 0 and dMuffled))
    if key ~= lastDoor then
        lastDoor = key
        debugSound(('carillon de portière : %s'):format(key))
        -- En boucle sans jamais s'arrêter tant que le moteur tourne portière ouverte (muet hors de portée)
        VC.soundLoop('door', { 'door_chime' }, 0, dVolume * (Chime.Volume or 1.0), true, dMuffled, dActive)
    end
end

--- Boucle seulement pendant un carillon (le sien ou celui d'un joueur à portée)
local function chimeLoop()
    refreshChimes()
    if chimeRunning then return end
    chimeRunning = true
    CreateThread(function()
        while alarm or next(alarms) or next(engines) or (VC.vehicle or 0) ~= 0 do
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
local function setAlarm(state)
    if state == alarm then return end
    alarm = state
    stoppedSince = nil
    VC.hud.alarm = state
    LocalPlayer.state:set('seatbeltAlarm', state, true) -- entendu par les joueurs proches
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

VC.on('enter', function() chimeLoop() end) -- à bord : carillon de portière de son véhicule suivi

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
    VC.sound('belt_on', Config.BeltSoundVolume or 1.0, volume)
    SetTimeout(600, function() VC.sound('belt_chime', Config.ChimeVolume or 1.0, volume) end)
end)

VC.on('tick', function(ped, vehicle)
    local speed = GetEntitySpeed(vehicle) * VC.MPH
    -- Descend du véhicule : ceinture retirée (avec le son)
    if belt and GetIsTaskActive(ped, 2) then setBelt(false) end
    -- Carillon de ceinture : détachée, au-dessus de AlarmSpeed ; coupé sous StopSpeed
    -- (coupé seulement après StopDelay ms d'affilée sous StopSpeed : une lecture isolée ne le coupe pas)
    if hasBelt(vehicle) and not belt then
        if speed >= Config.StopSpeed then stoppedSince = nil end
        if not alarm and speed > Config.AlarmSpeed then
            setAlarm(true)
        elseif alarm and speed < Config.StopSpeed then
            local now = GetGameTimer()
            stoppedSince = stoppedSince or now
            if now - stoppedSince >= (Config.StopDelay or 0) then
                debugSound(('arrêt (%.1f MPH) : carillon de ceinture coupé'):format(speed))
                setAlarm(false)
            end
        end
    elseif alarm then
        setAlarm(false)
    end
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

--- Distance idéale de projection (m) selon la vitesse (pas une limite) ; `cfg` : réglages (voitures par défaut,
--- VCConfig.Bike pour les motos) avec MinSpeed, IdealMinDistance, IdealMaxDistance, MaxDistanceSpeed
function VC.throwDistance(before, cfg)
    cfg = cfg or Config
    local t = math.min(math.max((before - cfg.MinSpeed) / math.max(cfg.MaxDistanceSpeed - cfg.MinSpeed, 1.0), 0.0), 1.0)
    return cfg.IdealMinDistance + (cfg.IdealMaxDistance - cfg.IdealMinDistance) * t
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

--- Projette le joueur en ragdoll (voitures et motos). opts :
---   dir      : direction horizontale (vecteur unitaire) ;
---   distance : distance IDÉALE (m), une part en vol (AirShare), le reste en glissade ;
---   cap      : vitesse horizontale maximale (m/s) : c'est la vitesse du véhicule qui donne l'élan ;
---   start    : point de départ (nil : là où se trouve le joueur, ex. déjà désarçonné par le jeu) ;
---   height   : hauteur du départ au-dessus du sol (m) ; lift : élan vers le haut ; damage : points de vie perdus ;
---   velocity : vitesse de départ imposée (vector3) à la place de dir / distance (ex. chute de moto : son élan) ;
---   pushTime : ms pendant lesquelles l'élan est réappliqué (PushTime par défaut).
function VC.launch(ped, opts)
    local vx, vy, vz
    if opts.velocity then
        vx, vy, vz = opts.velocity.x, opts.velocity.y, opts.velocity.z
    else
        local lift = opts.lift or Config.ThrowLift
        local hSpeed = VC.throwSpeed(opts.distance * Config.AirShare, lift, math.max(opts.height or 1.0, 0.5))
        if opts.cap then hSpeed = math.min(hSpeed, opts.cap) end
        vx, vy, vz = opts.dir.x * hSpeed, opts.dir.y * hSpeed, hSpeed * lift
    end

    -- Sorti du véhicule tout de suite (sinon le jeu le garde assis / debout), corps inerte autorisé
    if GetVehiclePedIsIn(ped, false) ~= 0 then ClearPedTasksImmediately(ped) end
    SetPedCanRagdoll(ped, true)
    if opts.start then SetEntityCoords(ped, opts.start.x, opts.start.y, opts.start.z, false, false, false, false) end
    SetPedToRagdoll(ped, 5000, 7000, 0, false, false, false)
    SetEntityVelocity(ped, vx, vy, vz)
    if (opts.damage or 0) > 0 then SetEntityHealth(ped, math.max(GetEntityHealth(ped) - opts.damage, 102)) end
    CreateThread(function()
        -- Premières images : l'impulsion est réappliquée (le ragdoll du jeu peut la perdre en s'activant).
        -- Pendant tout le vol : ragdoll maintenu (jamais debout en l'air). Aucune vitesse coupée ensuite.
        local now = GetGameTimer()
        local pushUntil, flyUntil = now + (opts.pushTime or Config.PushTime), now + 4000
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

local function eject(ped, vehicle, before, velocity)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    -- Départ : au-dessus du pare-brise ; direction : celle de la course (sinon l'avant du véhicule)
    local start = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, max.y * 0.3, max.z + 0.7)
    local dir = vector3(velocity.x, velocity.y, 0.0)
    if #dir < 1.0 then
        local f = GetEntityForwardVector(vehicle)
        dir = vector3(f.x, f.y, 0.0)
    end
    VC.launch(ped, {
        dir = dir / #dir, distance = VC.throwDistance(before), cap = before * MPS,
        start = start, height = (max.z + 0.7) - min.z, damage = Config.EjectDamage,
    })
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

-- Véhicules au moteur allumé (par Vehicle Control) : leur carillon de portière est calculé ici, même vides
AddStateBagChangeHandler('vcEngine', nil, function(bagName, _, value)
    engines[bagName] = value == true or nil
    if value == true then chimeLoop() end
end)

-- Ressource redémarrée : état publié remis à zéro
if LocalPlayer.state.seatbelt then LocalPlayer.state:set('seatbelt', false, true) end
if LocalPlayer.state.seatbeltAlarm then LocalPlayer.state:set('seatbeltAlarm', false, true) end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetPedConfigFlag(PlayerPedId(), 32, true)
    LocalPlayer.state:set('seatbelt', false, true)
    LocalPlayer.state:set('seatbeltAlarm', false, true)
    VC.soundLoop('chime', { 'belt_chime' }, 0, 0.0)
    VC.soundLoop('door', { 'door_chime' }, 0, 0.0)
end)
