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

--- Attache / retrait de la ceinture (volume renforcé : BeltSoundVolume)
local function beltSound(kind, volume, muffled)
    VC.sound(kind == 'on' and 'belt_on' or 'belt_off', volume * (Config.BeltSoundVolume or 1.725), nil, muffled)
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
        -- carillon du tableau de bord (volume renforcé : ChimeVolume)
        VC.soundLoop('chime', { 'belt_chime' }, 1100, volume * (Config.ChimeVolume or 1.56), false, muffled)
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
    VC.sound('belt_on', Config.BeltSoundVolume or 1.725, volume)
    SetTimeout(600, function() VC.sound('belt_chime', Config.ChimeVolume or 1.56, volume) end)
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
-- ÉJECTION : ceinture détachée, à partir de MinSpeed MPH (60) avant le choc, vrai accident seulement
--   - arrêt brutal (vitesse tombée à SuddenStopSpeed MPH ou moins, ex. 60 -> 20) : SuddenChance (70 %) ;
--   - accident sans chute brutale (perte d'au moins AccidentDrop MPH) : CrashChance (45 %) ;
--   - jamais sous MinSpeed, jamais pour un simple accrochage, jamais ceinture attachée.
-- Le joueur est PROJETÉ loin de l'accident : entre MinDistance et MaxDistance m du véhicule (plus loin
-- s'il roulait plus vite), par-dessus le toit, dans le sens de la course (ou de côté si l'obstacle percuté
-- bloque la trajectoire). Son élan horizontal est entretenu pendant le vol jusqu'à la distance voulue.
-- =========================================================================
local MPS = 0.44704 -- 1 MPH en m/s

--- Chance d'éjection (0..1) pour ce choc : 0 si pas d'éjection possible
function VC.ejectChance(before, drop)
    if before < Config.MinSpeed or drop < Config.AccidentDrop then return 0.0 end
    if before - drop <= Config.SuddenStopSpeed then return Config.SuddenChance end
    return Config.CrashChance
end

--- Distance de projection (m) : de MinDistance (à MinSpeed) à MaxDistance (à MaxDistanceSpeed), +/- 15 %
local function throwDistance(before)
    local t = math.min(math.max((before - Config.MinSpeed) / math.max(Config.MaxDistanceSpeed - Config.MinSpeed, 1.0), 0.0), 1.0)
    local d = Config.MinDistance + (Config.MaxDistance - Config.MinDistance) * t
    d = d * (0.85 + math.random() * 0.3)
    return math.min(math.max(d, Config.MinDistance), Config.MaxDistance)
end

--- Direction libre (horizontale) : sens de la course, sinon de côté (l'obstacle percuté bloque)
local function throwDirection(vehicle, velocity, start)
    local dir = vector3(velocity.x, velocity.y, 0.0)
    if #dir < 1.0 then
        local f = GetEntityForwardVector(vehicle)
        dir = vector3(f.x, f.y, 0.0)
    end
    dir = dir / #dir
    for _, angle in ipairs({ 0, 20, -20, 45, -45, 75, -75, 110, -110, 180 }) do
        local r = math.rad(angle)
        local d = vector3(dir.x * math.cos(r) - dir.y * math.sin(r), dir.x * math.sin(r) + dir.y * math.cos(r), 0.0)
        local to = start + d * 10.0
        local ray = StartExpensiveSynchronousShapeTestLosProbe(start.x, start.y, start.z, to.x, to.y, to.z, 19, vehicle, 7)
        local _, hit = GetShapeTestResult(ray)
        if hit ~= 1 and hit ~= true then return d end
    end
    return dir
end

local function eject(ped, vehicle, before, velocity)
    local origin = GetEntityCoords(vehicle)
    local _, max = GetModelDimensions(GetEntityModel(vehicle))
    -- Départ : au-dessus du pare-brise (par-dessus un muret, une voiture percutée…)
    local start = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, max.y * 0.3, max.z + 0.7)
    local dir = throwDirection(vehicle, velocity, start)
    local distance = throwDistance(before)
    local hSpeed = math.max(before * MPS * Config.ThrowSpeedFactor, Config.ThrowMinSpeed)
    local vSpeed = hSpeed * Config.ThrowLift

    SetEntityCoords(ped, start.x, start.y, start.z, false, false, false, false)
    CreateThread(function()
        Wait(1)
        SetPedToRagdoll(ped, 6000, 6000, 0, false, false, false)
        SetEntityVelocity(ped, dir.x * hSpeed, dir.y * hSpeed, vSpeed)
        SetEntityHealth(ped, math.max(GetEntityHealth(ped) - Config.EjectDamage, 102))
        -- Vol guidé : vitesse horizontale entretenue jusqu'à la distance voulue (4 s max) ; arrêt si un
        -- obstacle le bloque (plus d'avancée pendant 300 ms)
        local deadline, lastGain, best = GetGameTimer() + 4000, GetGameTimer(), 0.0
        while GetGameTimer() < deadline and DoesEntityExist(ped) and not IsEntityDead(ped) do
            local pos = GetEntityCoords(ped)
            local travelled = #(vector3(pos.x - origin.x, pos.y - origin.y, 0.0))
            if travelled >= distance - hSpeed * 0.04 then -- (une image d'avance)
                -- Distance atteinte : élan horizontal coupé (il retombe ici, pas plus loin que MaxDistance)
                SetEntityVelocity(ped, 0.0, 0.0, GetEntityVelocity(ped).z)
                break
            end
            if travelled > best + 0.05 then best, lastGain = travelled, GetGameTimer()
            elseif GetGameTimer() - lastGain > 300 then break end
            local v = GetEntityVelocity(ped)
            SetEntityVelocity(ped, dir.x * hSpeed, dir.y * hSpeed, v.z)
            Wait(0)
        end
        -- Bloqué trop près de l'accident : posé au sol à MinDistance, dans la direction libre
        local pos = GetEntityCoords(ped)
        if #(vector3(pos.x - origin.x, pos.y - origin.y, 0.0)) < Config.MinDistance and not IsEntityDead(ped) then
            local target = origin + dir * Config.MinDistance
            local found, groundZ = GetGroundZFor_3dCoord(target.x, target.y, target.z + 5.0, false)
            SetEntityCoords(ped, target.x, target.y, found and groundZ + 0.3 or target.z, false, false, false, false)
            SetPedToRagdoll(ped, 3000, 3000, 0, false, false, false)
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
