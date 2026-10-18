--[[
    Vehicle Control - ceinture de sécurité, alarme et éjection (client)
    -------------------------------------------------------------------
    Touche G (Raccourcis clavier > FiveM > "Véhicule : attacher / détacher la ceinture").
      - Sons réels (html/sounds) à l'attache et au retrait ; attachée, impossible de descendre sans la
        détacher (touche F bloquée) ; retirée si le joueur est sorti du véhicule autrement.
      - CARILLON DE CEINTURE (son : client/chimes.lua) : l'alarme du joueur ("seatbeltAlarm") s'allume
        ceinture détachée, moteur allumé, dès que le véhicule dépasse AlarmSpeed MPH (1), et ne s'éteint QUE
        véhicule immobile (StopWhenStopped), ceinture attachée, moteur coupé ou personne descendue.
      - Jamais deux fois le même son en même temps (le NUI coupe le précédent avant de rejouer).
      - Détachée, accident violent (voir config.lua, Seatbelt) : éjecté à travers le pare-brise.
        Attachée : jamais éjecté (l'éjection automatique du jeu est désactivée, seule cette règle compte).
      - Sons d'attache / de retrait synchronisés (état du joueur "seatbelt", lu par les autres clients) :
        occupants du véhicule à 100 %, joueurs autour selon VehicleSounds (3 m portière ouverte, 1 m fermé).
    Performance : aucune boucle ici (mise à jour du véhicule de main.lua, à bord seulement).
]]

local Config = VCConfig.Seatbelt

local belt, alarm = false, false
local stoppedSince = nil -- véhicule sous StopSpeed depuis (StopWhenStopped : carillon coupé après StopDelay)

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

-- =========================================================================
-- CEINTURE DU JOUEUR
-- =========================================================================
local function setAlarm(state)
    if state == alarm then return end
    alarm = state
    stoppedSince = nil
    VC.hud.alarm = state
    LocalPlayer.state:set('seatbeltAlarm', state, true) -- entendu par les joueurs proches
    VC.refreshChimes() -- carillon de ceinture : démarré ou coupé net tout de suite (client/chimes.lua)
end

local function setBelt(state, silent)
    if state == belt then return end
    belt = state
    if VC.hud.belt ~= nil then VC.hud.belt = state end
    -- Les joueurs proches entendent le son ; retrait sans bruit (changement de véhicule) : nil, rien à entendre
    local published = state
    if not state and silent then published = nil end
    LocalPlayer.state:set('seatbelt', published, true)
    if state then setAlarm(false) end
    if not silent then beltSound(state and 'on' or 'off', 1.0, false) end
end

function VC.isBuckled() return belt end
--- Carillon de ceinture du joueur en cours (détaché, moteur allumé, véhicule parti) ?
function VC.beltAlarm() return alarm end

--- Geste en s'attachant : le même que pour changer de station de radio (haut du corps seulement)
local function beltGesture(ped, vehicle)
    local A = VCConfig.Seatbelt.BuckleAnim
    if not A or A.Enabled == false then return end
    local anim = GetPedInVehicleSeat(vehicle, -1) == ped and A.Driver or A.Passenger
    if not anim then return end
    CreateThread(function()
        RequestAnimDict(anim[1])
        local timeout = GetGameTimer() + 1000
        while not HasAnimDictLoaded(anim[1]) and GetGameTimer() < timeout do Wait(10) end
        if not HasAnimDictLoaded(anim[1]) then return end
        TaskPlayAnim(ped, anim[1], anim[2], 4.0, -4.0, A.Duration or 1300, A.Flag or 48, 0.0, false, false, false)
        RemoveAnimDict(anim[1])
    end)
end

RegisterCommand('vc_seatbelt', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not hasBelt(vehicle) or IsPauseMenuActive() then return end
    setBelt(not belt)
    if belt then beltGesture(ped, vehicle) end
end, false)
RegisterKeyMapping('vc_seatbelt', 'Véhicule : attacher / détacher la ceinture', 'keyboard', VCConfig.Keys.seatbelt)

VC.on('enter', function(ped, vehicle)
    SetPedConfigFlag(ped, 32, false) -- pas d'éjection automatique du jeu : seule la règle ci-dessous compte
    if hasBelt(vehicle) then VC.hud.belt = belt else VC.hud.belt = nil end
    VC.hud.alarm = false
end)


VC.on('leave', function(_, _, info)
    -- Passé directement dans un autre véhicule / véhicule supprimé : ceinture retirée sans bruit (le nouveau part de zéro)
    if belt then setBelt(false, info and (info.swap or info.gone)) end
    if alarm then VC.debugSound('descendu du véhicule : carillon de ceinture coupé') end
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
    -- Carillon de ceinture : détachée, moteur allumé, dès que le véhicule dépasse AlarmSpeed (1 MPH). Ensuite il
    -- ne s'arrête QUE véhicule immobile (StopWhenStopped : sous StopSpeed pendant StopDelay ms), ceinture
    -- attachée, moteur coupé ou personne descendue (voir 'leave').
    local running = VC.engineOn(vehicle)
    if hasBelt(vehicle) and not belt and running then
        if speed >= Config.StopSpeed then stoppedSince = nil end
        if not alarm and speed > Config.AlarmSpeed then
            setAlarm(true)
        elseif alarm and Config.StopWhenStopped and speed < Config.StopSpeed then
            local now = GetGameTimer()
            stoppedSince = stoppedSince or now
            if now - stoppedSince >= (Config.StopDelay or 0) then
                VC.debugSound(('véhicule arrêté (%.1f MPH) : carillon de ceinture coupé'):format(speed))
                setAlarm(false)
            end
        end
    elseif alarm then
        VC.debugSound(belt and 'ceinture attachée : carillon de ceinture coupé' or not running and 'moteur coupé : carillon de ceinture coupé' or 'carillon de ceinture coupé')
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

    -- 1. Sorti du siège TOUT DE SUITE (téléporté hors du véhicule) : encore « assis », le personnage serait lancé
    --    dans la pose assise ; le corps inerte (ragdoll) n'est possible qu'une fois hors du véhicule.
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        TaskLeaveVehicle(ped, vehicle, 16) -- 16 : sortie instantanée
        ClearPedTasksImmediately(ped)
    end
    SetPedCanRagdoll(ped, true)
    SetPedRagdollOnCollision(ped, true)
    if opts.start then SetEntityCoords(ped, opts.start.x, opts.start.y, opts.start.z, false, false, false, false) end
    -- 2. Corps inerte : chute libre (bras et jambes ballants) dans le sens de la projection
    local h = math.sqrt(vx * vx + vy * vy)
    local fx, fy = h > 0.01 and vx / h or 0.0, h > 0.01 and vy / h or 1.0
    local function ragdoll()
        SetPedToRagdollWithFall(ped, 5000, 7000, 1, fx, fy, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        SetPedToRagdoll(ped, 5000, 7000, 0, false, false, false)
    end
    ragdoll()
    SetEntityVelocity(ped, vx, vy, vz)
    if (opts.damage or 0) > 0 then SetEntityHealth(ped, math.max(GetEntityHealth(ped) - opts.damage, 102)) end
    CreateThread(function()
        -- Image suivante : vraiment hors du siège -> corps inerte redonné, puis l'élan (sinon il vole assis).
        Wait(0)
        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            ragdoll()
            SetEntityVelocity(ped, vx, vy, vz)
        end
        -- Premières images : l'impulsion est réappliquée (le ragdoll du jeu peut la perdre en s'activant).
        -- Pendant tout le vol : ragdoll maintenu (jamais debout ni assis en l'air). Aucune vitesse coupée ensuite.
        local now = GetGameTimer()
        local pushUntil, flyUntil = now + (opts.pushTime or Config.PushTime), now + 4000
        while GetGameTimer() < flyUntil and DoesEntityExist(ped) and not IsEntityDead(ped) do
            if not IsPedRagdoll(ped) then ragdoll() end
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
    if value == nil or not serverId or serverId == GetPlayerServerId(PlayerId()) then return end -- nil : sans bruit
    local volume, muffled = hearVolume(serverId)
    if volume and volume > 0.0 then beltSound(value == true and 'on' or 'off', volume, muffled) end
end)

-- Ressource redémarrée : état publié remis à zéro
if LocalPlayer.state.seatbelt then LocalPlayer.state:set('seatbelt', false, true) end
if LocalPlayer.state.seatbeltAlarm then LocalPlayer.state:set('seatbeltAlarm', false, true) end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetPedConfigFlag(PlayerPedId(), 32, true)
    LocalPlayer.state:set('seatbelt', false, true)
    LocalPlayer.state:set('seatbeltAlarm', false, true)
end)
