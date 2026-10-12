--[[
    Vehicle Control - noyau (client)
    --------------------------------
    Une seule boucle suit le véhicule du joueur et appelle les modules (ceinture, essence, dégâts,
    moteur, portières, frein de parcage) :
      - 'enter' / 'leave' / 'seat' : montée, descente, changement de place ;
      - 'frame' : à chaque image, UNIQUEMENT à bord d'un véhicule (touches bloquées par le frein de
        parcage, puissance réduite d'un moteur abîmé, détection des chocs) ;
      - 'tick'  : toutes les 100 ms à bord (essence, dégâts, alarme de ceinture, car HUD) ;
      - 'impact' : choc violent (vitesse avant le choc, perte de vitesse, vitesse du véhicule) ;
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

-- État d'un véhicule (moteur, frein, portières, essence, cassé) : état du véhicule en réseau ("state
-- bag", écrit par le serveur et lu par tous) ; véhicule local (non synchronisé) : gardé ici.
local localStates = {}

function VC.state(vehicle, key)
    if NetworkGetEntityIsNetworked(vehicle) then return Entity(vehicle).state[key] end
    return localStates[vehicle] and localStates[vehicle][key]
end

function VC.setState(vehicle, key, value)
    if NetworkGetEntityIsNetworked(vehicle) then
        Entity(vehicle).state:set(key, value, false) -- tout de suite chez ce client
        TriggerServerEvent('rp_vehiclecontrol:state', VehToNet(vehicle), key, value)
    else
        localStates[vehicle] = localStates[vehicle] or {}
        localStates[vehicle][key] = value
    end
end

function VC.isDriver() return VC.vehicle ~= 0 and VC.seat == -1 end

local function seatOf(ped, vehicle)
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then return seat end
    end
    return nil
end

-- =========================================================================
-- CHOCS : perte de vitesse brutale pendant un contact (mur, objet fixe, véhicule)
-- =========================================================================
local history = {}  -- vitesses des 400 dernières ms : { t, speed }
local crash = nil   -- choc en cours : { before, min, untilTime, velocity }
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
            crash = { before = before, min = speed, untilTime = now + 250, velocity = lastVelocity }
        end
    end
    if crash then
        if speed < crash.min then crash.min = speed end
        -- Fin du choc : 250 ms écoulées, ou véhicule arrêté net
        if now >= crash.untilTime or crash.min < 2.0 then
            emit('impact', vehicle, crash.before, crash.before - crash.min, crash.velocity)
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
    history, crash = {}, nil
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

local function sendHud(data)
    local key = data.show and ('%d|%.2f|%s|%s|%s|%s|%s|%s'):format(data.speed, data.rpm, tostring(data.fuel),
        tostring(data.belt), tostring(data.alarm), tostring(data.broken), tostring(data.parked), tostring(data.paused)) or 'hidden'
    if key == lastKey then return end
    lastKey = key
    VC.toHud('carHud', data)
end

-- Enregistré en dernier (fichier hud.lua) : les modules ont déjà rempli VC.hud
function VC.sendHud(vehicle)
    local speed = GetEntitySpeed(vehicle) * VC.MPH
    local rpm = GetIsVehicleEngineRunning(vehicle) and GetVehicleCurrentRpm(vehicle) or 0.0
    rpm = math.max(0.0, math.min(1.0, (rpm - 0.2) / 0.8)) -- ralenti ~0.2 -> 0 %, régime maximal -> 100 %
    local h = VC.hud
    local data = {
        show = true,
        speed = math.floor(speed + 0.5),
        rpm = math.floor(rpm * 50 + 0.5) / 50,
        fuel = h.fuel and math.floor(h.fuel + 0.5) or nil, -- nil : pas de réservoir (jauge masquée)
        alarm = h.alarm == true,
        broken = VC.state(vehicle, 'vcBroken') == true,  -- logo rouge "véhicule cassé"
        parked = VC.state(vehicle, 'vcBrake') == true,    -- frein de parcage : vitesse grisée
        paused = IsPauseMenuActive() or IsScreenFadedOut(),
    }
    if h.belt ~= nil then data.belt = h.belt end -- absent : pas de ceinture (logo masqué)
    sendHud(data)
end

function VC.hideHud()
    sendHud({ show = false })
end

-- MDC (re)démarré / NUI rechargé : état renvoyé à la prochaine mise à jour
AddEventHandler('mdc:hudReady', function() lastKey = nil end)
