--[[
    Vehicle Control - clignotants et warnings (client)
    --------------------------------------------------
    Conducteur : flèche gauche / flèche droite (clignotants), flèche bas (warnings / feux de détresse) ;
    même touche pour arrêter (Raccourcis clavier > FiveM > "Véhicule : clignotant…").
      - Feux visibles par tous les joueurs (état du véhicule "vcSignal", appliqué par chaque client).
      - Son du relais (html/sounds/indicators_sound.ogg, un seul fichier pour les clignotants et les
        warnings) entendu par les occupants : joué en boucle (SignalSoundMode = 'loop') ou rejoué toutes
        les SignalInterval ms ('repeat').
      - Comme dans une vraie voiture, un clignotant s'arrête tout seul après le virage (volant revenu
        droit après avoir tourné de SignalCancelAngle degrés). Les warnings restent jusqu'à la touche.
      - Les warnings / clignotants restent allumés quand le conducteur descend.
    Aucune boucle en plus : vérifications dans la mise à jour du véhicule (100 ms, à bord).
]]

local Config = VCConfig
local SIGNALS = { left = true, right = true, hazard = true }
local turn = nil       -- clignotant gauche / droit : { heading, turned } pour l'arrêt automatique
local soundOn = nil    -- son du relais en cours (valeur du clignotant)
local SOUND = { 'indicators_sound' }

local function signalSound(on)
    VC.soundLoop('signal', SOUND, Config.SignalInterval, on and (Config.SignalVolume or 1.0625) or 0.0,
        Config.SignalSoundMode ~= 'repeat')
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

    -- Son du relais pour les occupants
    if signal ~= soundOn then
        soundOn = signal
        signalSound(signal ~= false)
    end

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
    turn = nil
    if soundOn then
        soundOn = nil
        signalSound(false)
    end
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
        if entity and entity ~= 0 and DoesEntityExist(entity) then applyLights(entity, SIGNALS[value] and value or false) end
    end)
end)
