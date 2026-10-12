--[[
    Vehicle Control - noyau (client)
    --------------------------------
    Une seule boucle suit le véhicule du joueur et appelle les modules (ceinture, essence, dégâts,
    moteur, portières, clignotants, poussée) :
      - 'enter' / 'leave' / 'seat' : montée, descente, changement de place ;
      - 'frame' : à chaque image, UNIQUEMENT à bord d'un véhicule (ceinture, véhicule poussé,
        puissance réduite d'un moteur abîmé, détection des chocs) ;
      - 'tick'  : toutes les 100 ms à bord (essence, dégâts, alarme de ceinture, car HUD) ;
      - 'impact' : choc violent (vitesse avant le choc, perte de vitesse, vitesse du véhicule, ce qui a
        été percuté : { severity = 'light' | 'heavy', kind = 'ped' | 'vehicle' | 'object' | 'world' }) ;
      - 'idle'  : toutes les 500 ms à pied (pompes, jerrican, véhicule à pousser).

    Car HUD : dessiné par le MDC (mdc_standalone, Paramètres > HUD & Display), qui reçoit les données
    par l'événement local "mdc:carHud". Sans le MDC, tout fonctionne mais rien n'est affiché.

    Performance : à pied, une vérification toutes les 500 ms (~0.00 ms) ; à bord, ~0.02 ms.
]]

local Config = VCConfig

VC = {
    MPH = 2.236936,  -- m/s -> MPH
    vehicle = 0,     -- véhicule où se trouve le joueur
    seat = nil,      -- -1 conducteur, 0 passager avant, 1+ arrière
    hud = {},        -- données du car HUD remplies par les modules
}

local hooks = { enter = {}, leave = {}, seat = {}, frame = {}, tick = {}, impact = {}, idle = {} }

function VC.on(event, fn) table.insert(hooks[event], fn) end

local function emit(event, ...)
    for _, fn in ipairs(hooks[event]) do fn(...) end
end
VC.emit = emit

-- =========================================================================
-- OUTILS
-- =========================================================================
--- Envoi au car HUD du MDC (carHud, beltSound, beltBeep, carNotice)
function VC.toHud(action, data)
    TriggerEvent('mdc:carHud', action, data)
end

--- Message PRIVÉ dans le chat (rp_chat), ex. "Portière ouverte."
function VC.chat(text)
    local chat = GlobalState.rpChatResource or Config.ChatResource
    if GetResourceState(chat) == 'started'
        and pcall(function() exports[chat]:addPrivate({ title = 'Véhicule', text = text }) end) then
        return
    end
    -- Sans rp_chat : chat d'origine (message affiché chez ce joueur uniquement)
    TriggerEvent('chat:addMessage', { args = { 'Véhicule', text }, color = { 140, 200, 255 } })
end

--- Touche réellement associée à une commande (raccourcis FiveM), ex. "O"
function VC.keyLabel(command, fallback)
    local ok, label = pcall(GetControlInstructionalButton, 0, GetHashKey(command) | 0x80000000, true)
    if ok and type(label) == 'string' and label:sub(1, 2) == 't_' then return label:sub(3) end
    return fallback
end

-- État d'un véhicule (moteur, frein, portières, essence, cassé, clignotants…) : état du véhicule en
-- réseau ("state bag", écrit par le serveur et lu par tous) ; véhicule local (non synchronisé) : gardé ici.
-- Une valeur qui vient d'être demandée au serveur est utilisée tout de suite par ce client, le temps que
-- le serveur la renvoie (dès que l'état du véhicule change, ou au plus PENDING_MS) : la touche répond
-- immédiatement.
local PENDING_MS = 2500
local localStates = {}
local pending = {} -- [véhicule] = { [clé] = { value, before, untilTime } }

local function stored(vehicle, key)
    if NetworkGetEntityIsNetworked(vehicle) then return Entity(vehicle).state[key] end
    return localStates[vehicle] and localStates[vehicle][key]
end

function VC.state(vehicle, key)
    local value = stored(vehicle, key)
    local p = pending[vehicle] and pending[vehicle][key]
    if p then
        -- Le serveur a répondu (l'état a changé) ou délai dépassé : l'état du véhicule fait foi
        if value == p.before and GetGameTimer() < p.untilTime then return p.value end
        pending[vehicle][key] = nil
    end
    return value
end

--- Valeur en attente, sans envoi (ex. essence envoyée par fuel.lua)
function VC.setPending(vehicle, key, value)
    pending[vehicle] = pending[vehicle] or {}
    pending[vehicle][key] = { value = value, before = stored(vehicle, key), untilTime = GetGameTimer() + PENDING_MS }
end

function VC.setState(vehicle, key, value)
    if NetworkGetEntityIsNetworked(vehicle) then
        VC.setPending(vehicle, key, value)
        TriggerServerEvent('rp_vehiclecontrol:state', VehToNet(vehicle), key, value)
    else
        localStates[vehicle] = localStates[vehicle] or {}
        localStates[vehicle][key] = value
    end
end

-- =========================================================================
-- SONS (NUI de ce script, html/sounds/*.ogg) : volume réglé dans le MDC
-- (Paramètres > HUD & Display > volume des sons du véhicule), sinon SoundVolume
-- =========================================================================
function VC.volume()
    local mdc = GlobalState.mdcResource or 'mdc_standalone'
    if GetResourceState(mdc) == 'started' then
        local ok, volume = pcall(function() return exports[mdc]:carSoundVolume() end)
        if ok and type(volume) == 'number' then return math.max(0.0, math.min(1.0, volume)) end
    end
    return Config.SoundVolume or 0.7
end

--- Joue un son une fois (volume 0..1, multiplié par le réglage du joueur, ou par `setting` s'il est donné)
function VC.sound(name, volume, setting)
    SendNUIMessage({ action = 'sound', data = { name = name, volume = (volume or 1.0) * (tonumber(setting) or VC.volume()) } })
end

--- Son répété (clignotant, alarme) : `names` joués à tour de rôle toutes les `interval` ms ; volume 0 = arrêt
function VC.soundLoop(id, names, interval, volume)
    SendNUIMessage({ action = 'soundLoop', data = {
        id = id, names = names, interval = interval, volume = (volume or 0.0) * VC.volume(),
    } })
end

function VC.isDriver() return VC.vehicle ~= 0 and VC.seat == -1 end

local function seatOf(ped, vehicle)
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then return seat end
    end
    return nil
end

-- =========================================================================
-- CE QUI A ÉTÉ PERCUTÉ (au moment du choc ; recherche seulement à cet instant)
--   léger : piéton, moto / vélo, objet de la liste LightModels (ou inconnu, selon UnknownObject)
--   fort  : autre véhicule, objet de la liste HeavyModels, ou rien de mobile : décor fixe (mur…)
-- =========================================================================
local Damage = Config.Damage
local modelSeverity = {}
for _, name in ipairs(Damage.LightModels or {}) do modelSeverity[GetHashKey(name)] = 'light' end
for _, name in ipairs(Damage.HeavyModels or {}) do modelSeverity[GetHashKey(name)] = 'heavy' end

local HIT_MS = 600  -- durée pendant laquelle les dégâts reçus sont attribués à ce choc
local lastHit = nil -- { vehicle, severity, kind, untilTime }

local function touching(vehicle, pool, range, classify)
    local pos = GetEntityCoords(vehicle)
    local found = nil
    for _, entity in ipairs(GetGamePool(pool)) do
        if entity ~= vehicle and #(GetEntityCoords(entity) - pos) <= range and IsEntityTouchingEntity(vehicle, entity)
            -- remorque attelée, objet porté… : toujours au contact, ce n'est pas un choc
            and not IsEntityAttachedToEntity(entity, vehicle) and not IsEntityAttachedToEntity(vehicle, entity) then
            local severity = classify(entity)
            if severity == 'heavy' then return 'heavy' end
            found = severity or found
        end
    end
    return found
end

--- Ce que le véhicule vient de percuter : { severity = 'light' | 'heavy', kind }
function VC.classifyHit(vehicle)
    local ped = PlayerPedId()
    local severity = touching(vehicle, 'CVehicle', 12.0, function(other)
        return Damage.LightVehicleClasses[GetVehicleClass(other)] and 'light' or 'heavy'
    end)
    if severity then return { severity = severity, kind = 'vehicle' } end
    severity = touching(vehicle, 'CObject', 10.0, function(object)
        return modelSeverity[GetEntityModel(object)] or Damage.UnknownObject or 'light'
    end)
    if severity then return { severity = severity, kind = 'object' } end
    severity = touching(vehicle, 'CPed', 6.0, function(other)
        if other == ped or GetVehiclePedIsIn(other, false) == vehicle then return nil end
        return 'light'
    end)
    if severity then return { severity = severity, kind = 'ped' } end
    return { severity = 'heavy', kind = 'world' } -- mur, bâtiment, rocher, décor fixe
end

--- Choc en cours / tout juste reçu par ce véhicule ; s'il vient de toucher quelque chose sans choc
--- enregistré (petite vitesse), il est reconnu maintenant ; nil : aucun choc (balles, explosion…)
function VC.currentHit(vehicle)
    local now = GetGameTimer()
    if lastHit and lastHit.vehicle == vehicle and now <= lastHit.untilTime then return lastHit end
    if not HasEntityCollidedWithAnything(vehicle) then return nil end
    local hit = VC.classifyHit(vehicle)
    lastHit = { vehicle = vehicle, severity = hit.severity, kind = hit.kind, untilTime = now + HIT_MS }
    return lastHit
end

-- =========================================================================
-- CHOCS : perte de vitesse brutale pendant un contact (mur, objet fixe, véhicule)
-- =========================================================================
local history = {}  -- vitesses des 400 dernières ms : { t, speed }
local crash = nil   -- choc en cours : { before, min, untilTime, velocity, hit }
local lastVelocity = vector3(0.0, 0.0, 0.0)

local function recentPeak(now)
    local peak = 0.0
    for i = #history, 1, -1 do
        local h = history[i]
        if now - h.t > 400 then break end
        if h.speed > peak then peak = h.speed end
    end
    return peak
end

local function detectImpact(vehicle)
    local now = GetGameTimer()
    local speed = GetEntitySpeed(vehicle) * VC.MPH
    if not crash and HasEntityCollidedWithAnything(vehicle) then
        local before = math.max(recentPeak(now), speed)
        if before > 5.0 then
            lastHit = nil -- nouveau choc : reconnu maintenant
            crash = { before = before, min = speed, untilTime = now + 250, velocity = lastVelocity, hit = VC.currentHit(vehicle) }
        end
    end
    if crash then
        if speed < crash.min then crash.min = speed end
        -- Fin du choc : 250 ms écoulées, ou véhicule arrêté net
        if now >= crash.untilTime or crash.min < 2.0 then
            emit('impact', vehicle, crash.before, crash.before - crash.min, crash.velocity, crash.hit)
            crash = nil
        end
    end
    history[#history + 1] = { t = now, speed = speed }
    if #history > 60 then table.remove(history, 1) end
    lastVelocity = GetEntityVelocity(vehicle)
end

-- =========================================================================
-- BOUCLE PRINCIPALE
-- =========================================================================
local function leave()
    local vehicle, seat = VC.vehicle, VC.seat
    VC.vehicle, VC.seat = 0, nil
    history, crash, lastHit = {}, nil, nil
    emit('leave', vehicle, seat)
end

CreateThread(function()
    Wait(0) -- tous les fichiers du script chargés (modules enregistrés)
    local lastTick = 0
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 then
            if vehicle ~= VC.vehicle then
                if VC.vehicle ~= 0 then leave() end
                VC.vehicle, VC.seat = vehicle, seatOf(ped, vehicle)
                lastTick = 0
                emit('enter', ped, vehicle, VC.seat)
            else
                local seat = seatOf(ped, vehicle)
                if seat ~= VC.seat then
                    local previous = VC.seat
                    VC.seat = seat
                    emit('seat', ped, vehicle, seat, previous)
                end
            end
            detectImpact(vehicle)
            emit('frame', ped, vehicle)
            local now = GetGameTimer()
            if now - lastTick >= 100 then
                local dt = lastTick == 0 and 0.1 or (now - lastTick) / 1000
                lastTick = now
                emit('tick', ped, vehicle, dt)
            end
            Wait(0)
        else
            if VC.vehicle ~= 0 then leave() end
            emit('idle', ped)
            Wait(500)
        end
    end
end)

-- =========================================================================
-- CAR HUD (MDC) : envoyé seulement quand il change
-- =========================================================================
local lastKey = nil

local HUD_KEYS = { 'inVehicle', 'show', 'mode', 'engine', 'speed', 'rpm', 'fuel', 'belt', 'alarm', 'broken', 'paused' }

local function sendHud(data)
    local parts = {}
    for i, k in ipairs(HUD_KEYS) do parts[i] = tostring(data[k]) end
    local key = table.concat(parts, '|')
    if key == lastKey then return end
    lastKey = key
    VC.toHud('carHud', data)
end

-- Enregistré en dernier (fichier hud.lua) : les modules ont déjà rempli VC.hud.
--   - conducteur : car HUD complet (vitesse, accélération, essence, ceinture, véhicule cassé), toujours
--     affiché ; moteur coupé, tout est grisé (engine = false), il s'illumine au démarrage ;
--   - passagers : uniquement le logo de la ceinture.
function VC.sendHud(vehicle)
    local driver = VC.seat == -1
    local running = GetIsVehicleEngineRunning(vehicle)
    local speed = GetEntitySpeed(vehicle) * VC.MPH
    local rpm = running and GetVehicleCurrentRpm(vehicle) or 0.0
    rpm = math.max(0.0, math.min(1.0, (rpm - 0.2) / 0.8)) -- ralenti ~0.2 -> 0 %, régime maximal -> 100 %
    local h = VC.hud
    local broken = VC.state(vehicle, 'vcBroken') == true
    local show = driver or h.belt ~= nil -- passager sans ceinture (moto…) : rien
    local data = {
        inVehicle = true,
        show = show,
        mode = driver and 'driver' or 'passenger',
        engine = running,                                  -- moteur coupé : car HUD grisé
        speed = math.floor(speed + 0.5),
        rpm = math.floor(rpm * 50 + 0.5) / 50,
        fuel = h.fuel and math.floor(h.fuel + 0.5) or nil, -- nil : pas de réservoir (jauge masquée)
        alarm = h.alarm == true,
        broken = broken,                                   -- logo rouge "véhicule cassé"
        paused = IsPauseMenuActive() or IsScreenFadedOut(),
    }
    if h.belt ~= nil then data.belt = h.belt end -- absent : pas de ceinture (logo masqué)
    sendHud(data)
end

function VC.hideHud()
    sendHud({ inVehicle = false, show = false })
end

-- MDC (re)démarré / NUI rechargé : état renvoyé à la prochaine mise à jour
AddEventHandler('mdc:hudReady', function() lastKey = nil end)
