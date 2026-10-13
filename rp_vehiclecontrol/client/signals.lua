--[[
    Vehicle Control - clignotants et warnings (client)
    --------------------------------------------------
    Conducteur : flèche gauche / flèche droite (clignotants), flèche bas (warnings / feux de détresse) ;
    même touche pour arrêter (Raccourcis clavier > FiveM > "Véhicule : clignotant…").
      - Feux visibles par tous les joueurs (état du véhicule "vcSignal", appliqué par chaque client).
      - Son du relais (html/sounds/indicators_sound.ogg, un seul fichier pour les clignotants et les
        warnings) joué en boucle (SignalSoundMode = 'loop', ou rejoué toutes les SignalInterval ms :
        'repeat') TANT QUE le clignotant n'est pas coupé, même si tout le monde est descendu : entendu à
        100 % à bord, et autour du véhicule (VehicleSounds : 3 m portière ouverte, 1 m tout fermé et
        étouffé). Chaque client suit les véhicules dont les clignotants sont allumés (état "vcSignal").
      - Comme dans une vraie voiture, un clignotant s'arrête tout seul après le virage (volant revenu
        droit après avoir tourné de SignalCancelAngle degrés). Les warnings restent jusqu'à la touche.
      - Les warnings / clignotants restent allumés quand le conducteur descend.
    Performance : arrêt automatique dans la mise à jour du véhicule (100 ms, à bord) ; son : boucle de
    200 ms seulement tant qu'un véhicule proche a ses clignotants / warnings allumés.
]]

local Config = VCConfig
local SIGNALS = { left = true, right = true, hazard = true }
local turn = nil       -- clignotant gauche / droit : { heading, turned } pour l'arrêt automatique
local SOUND = { 'indicators_sound' }

-- =========================================================================
-- SON DU RELAIS : véhicules aux clignotants allumés, entendus selon la position du joueur
-- =========================================================================
local tracked = {}     -- [clé] = { vehicle, since } (réseau : "entity:<netId>" ; local : "local:<handle>")
local sent = {}        -- [clé] = dernier envoi au NUI ("volume|étouffé")
local soundRunning = false

local function keyOf(vehicle)
    if NetworkGetEntityIsNetworked(vehicle) then return ('entity:%d'):format(VehToNet(vehicle)) end
    return ('local:%d'):format(vehicle)
end

local function sendSound(key, volume, muffled)
    volume = math.floor(volume * 100 + 0.5) / 100
    local id = 'signal:' .. key
    local mark = ('%.2f|%s'):format(volume, tostring(volume > 0 and muffled))
    if sent[key] == mark then return end
    sent[key] = volume > 0 and mark or nil
    VC.soundLoop(id, SOUND, Config.SignalInterval, volume, Config.SignalSoundMode ~= 'repeat', muffled)
end

local function untrack(key)
    tracked[key] = nil
    if sent[key] then sendSound(key, 0.0, false) end
    sent[key] = nil
end

local function soundLoop()
    if soundRunning then return end
    soundRunning = true
    CreateThread(function()
        while next(tracked) do
            for key, entry in pairs(tracked) do
                local vehicle = entry.vehicle
                if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
                    untrack(key) -- hors de portée : repris quand le véhicule revient (état du véhicule)
                elseif GetGameTimer() - entry.since > 1000 and not SIGNALS[VC.state(vehicle, 'vcSignal')] then
                    -- (l'état est vérifié après 1 s : un changement reçu n'est appliqué qu'après son annonce)
                    untrack(key) -- clignotant coupé : son coupé net
                else
                    local hear, muffled = VC.hearVehicle(vehicle)
                    sendSound(key, (Config.SignalVolume or 1.594) * hear, muffled)
                end
            end
            Wait(200)
        end
        soundRunning = false
    end)
end

--- Clignotants allumés sur ce véhicule : son suivi (ou coupé)
local function track(vehicle, on)
    local key = keyOf(vehicle)
    if on then
        if not tracked[key] then tracked[key] = { vehicle = vehicle, since = GetGameTimer() } end
        local hear, muffled = VC.hearVehicle(vehicle)
        sendSound(key, (Config.SignalVolume or 1.594) * hear, muffled) -- tout de suite (touche du conducteur)
        soundLoop()
    elseif tracked[key] then
        untrack(key)
    end
end

local function applyLights(vehicle, signal)
    SetVehicleIndicatorLights(vehicle, 1, signal == 'left' or signal == 'hazard')  -- 1 : gauche
    SetVehicleIndicatorLights(vehicle, 0, signal == 'right' or signal == 'hazard') -- 0 : droite
end

local function expectedMask(signal)
    if signal == 'hazard' then return 3 end
    if signal == 'left' then return 1 end
    if signal == 'right' then return 2 end
    return 0
end

local function setSignal(vehicle, signal)
    signal = SIGNALS[signal] and signal or false
    VC.setState(vehicle, 'vcSignal', signal)
    applyLights(vehicle, signal)
    track(vehicle, signal ~= false)
    turn = (signal == 'left' or signal == 'right') and { heading = GetEntityHeading(vehicle), turned = false } or nil
end

local function press(kind)
    local vehicle = VC.vehicle
    if not VC.isDriver() or IsPauseMenuActive() then return end
    setSignal(vehicle, VC.state(vehicle, 'vcSignal') ~= kind and kind or false)
end

RegisterCommand('vc_signal_left', function() press('left') end, false)
RegisterCommand('vc_signal_right', function() press('right') end, false)
RegisterCommand('vc_hazards', function() press('hazard') end, false)
RegisterKeyMapping('vc_signal_left', 'Véhicule : clignotant gauche', 'keyboard', Config.Keys.indicatorLeft)
RegisterKeyMapping('vc_signal_right', 'Véhicule : clignotant droit', 'keyboard', Config.Keys.indicatorRight)
RegisterKeyMapping('vc_hazards', 'Véhicule : warnings (feux de détresse)', 'keyboard', Config.Keys.hazards)

local function angleDiff(a, b)
    return math.abs((a - b + 540.0) % 360.0 - 180.0)
end

VC.on('tick', function(_, vehicle)
    local signal = VC.state(vehicle, 'vcSignal')
    if not SIGNALS[signal] then signal = false end

    -- Son du relais : véhicule suivi tant que ses clignotants sont allumés (s'il ne l'est pas déjà)
    if signal and not tracked[keyOf(vehicle)] then track(vehicle, true) end

    if VC.seat ~= -1 then return end
    -- Feux toujours conformes à l'état (changement de propriétaire réseau…)
    if GetVehicleIndicatorLights(vehicle) ~= expectedMask(signal) then applyLights(vehicle, signal) end

    -- Arrêt automatique après le virage
    if turn and (Config.SignalCancelAngle or 0) > 0 then
        if not turn.turned and angleDiff(GetEntityHeading(vehicle), turn.heading) >= Config.SignalCancelAngle then
            turn.turned = true
        elseif turn.turned and math.abs(GetVehicleSteeringAngle(vehicle)) < 5.0 then
            setSignal(vehicle, false)
        end
    end
end)

VC.on('enter', function(_, vehicle, seat)
    turn = nil
    if seat == -1 then
        local signal = VC.state(vehicle, 'vcSignal')
        if signal == 'left' or signal == 'right' then turn = { heading = GetEntityHeading(vehicle), turned = false } end
    end
end)

VC.on('leave', function()
    turn = nil -- le son continue (véhicule suivi) tant que les clignotants restent allumés
end)

-- Tous les joueurs : feux du véhicule appliqués dès que son état change (ou qu'il arrive à portée)
AddStateBagChangeHandler('vcSignal', nil, function(bagName, _, value)
    CreateThread(function()
        local timeout = GetGameTimer() + 3000
        local entity = GetEntityFromStateBagName(bagName)
        while (not entity or entity == 0) and GetGameTimer() < timeout do
            Wait(100)
            entity = GetEntityFromStateBagName(bagName)
        end
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            applyLights(entity, SIGNALS[value] and value or false)
            track(entity, SIGNALS[value] == true)
        end
    end)
end)
