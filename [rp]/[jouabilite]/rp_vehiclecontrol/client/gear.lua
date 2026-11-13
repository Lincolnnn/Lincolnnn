--[[
    Vehicle Control - marche avant / marche arrière (client, conducteur)
    --------------------------------------------------------------------
    Touche Keys.gear (flèche haut par défaut) : passe de D (marche avant) à R (marche arrière) et inversement,
    SEULEMENT presque arrêté (MaxShiftMph, 5 MPH par défaut) : au-delà, refusé (message).
    LA MÊME TOUCHE FAIT ROULER dans les deux rapports : l'accélérateur (Z / W).
      - D : Z / W AVANCE ; S FREINE, puis, véhicule arrêté, le retient au lieu de reculer ;
      - R : Z / W RECULE (comme une boîte automatique en marche arrière, à la pression de la pédale) ; S FREINE, puis,
        véhicule arrêté, le retient au lieu d'avancer.
    Le rapport est affiché sur le car HUD du MDC (R au-dessus de D, le passage de l'un à l'autre glisse en douceur).
    Chaque véhicule part en D. Pas de rapport sur les vélos, bateaux, hélicoptères, avions, trains (SkipClasses).
    Performance : seulement à bord, au volant (événement 'frame' du véhicule).
]]

local Config = VCConfig.Gear or {}
local ACCELERATE, BRAKE = 71, 72
local MPH = 2.236936
local lastRefusal = -10000

VC.gear = 'D'
local holding = false -- le script serre le frein à main (véhicule retenu à l'arrêt)

local function hasGear(vehicle)
    return Config.Enabled ~= false and not (Config.SkipClasses or {})[GetVehicleClass(vehicle)]
end

local function release(vehicle)
    if holding then
        holding = false
        if DoesEntityExist(vehicle) then SetVehicleHandbrake(vehicle, false) end
    end
end

--- Passe au rapport `gear` ('D' ou 'R') ; sans argument : bascule
function VC.setGear(gear)
    local vehicle = VC.vehicle
    if vehicle == 0 or VC.seat ~= -1 or not hasGear(vehicle) then return false end
    gear = gear or (VC.gear == 'D' and 'R' or 'D')
    if gear == VC.gear then return true end
    -- au-delà de MaxShiftMph : impossible de passer de D à R (ou l'inverse) en roulant
    local limit = Config.MaxShiftMph or 5.0
    if GetEntitySpeed(vehicle) * MPH > limit then
        PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        if GetGameTimer() - lastRefusal > 2500 then
            lastRefusal = GetGameTimer()
            VC.chat(('Ralentissez sous %d MPH pour passer en %s.'):format(math.floor(limit), gear == 'R' and 'marche arrière (R)' or 'marche avant (D)'))
        end
        return false
    end
    VC.gear = gear
    VC.hud.gear = gear
    release(vehicle)
    local snd = Config.Sound
    if snd then PlaySoundFrontend(-1, snd[1], snd[2], true) end
    VC.sendHud(vehicle)
    return true
end

RegisterCommand('vc_gear', function() VC.setGear() end, false)
RegisterKeyMapping('vc_gear', 'Véhicule : marche avant (D) / marche arrière (R)', 'keyboard', VCConfig.Keys.gear or 'UP')

VC.on('enter', function(_, vehicle, seat)
    VC.gear = 'D'
    VC.hud.gear = (seat == -1 and hasGear(vehicle)) and 'D' or nil
end)

VC.on('seat', function(_, vehicle, seat)
    release(vehicle)
    VC.gear = 'D'
    VC.hud.gear = (seat == -1 and hasGear(vehicle)) and 'D' or nil
end)

VC.on('leave', function(vehicle)
    release(vehicle)
    VC.gear = 'D'
    VC.hud.gear = nil
end)

-- À chaque image, au volant : l'accélérateur (Z / W) roule dans le sens du rapport ; le frein (S) freine, puis retient
-- le véhicule arrêté
VC.on('frame', function(_, vehicle)
    if VC.seat ~= -1 or not hasGear(vehicle) then return end
    if VC.pushedNow then return release(vehicle) end -- poussé par un autre joueur (push.lua) : rien à bloquer
    local forward = GetEntitySpeedVector(vehicle, true).y -- m/s, positif : vers l'avant
    local stop = Config.StopSpeed or 0.5
    local hold = false
    if VC.gear == 'D' then
        -- frein : il freine tant que le véhicule avance ; arrêté (ou reculant), il le retient
        if (IsControlPressed(0, BRAKE) or IsDisabledControlPressed(0, BRAKE)) and forward <= stop then
            DisableControlAction(0, BRAKE, true)
            hold = true
        end
    else
        -- R : l'accélérateur (Z / W) RECULE (il pilote la marche arrière du jeu, à sa pression) ; le frein (S) freine,
        -- puis retient le véhicule (il ne fait jamais avancer)
        -- (comme push.lua : les deux pédales du jeu bloquées, puis remplies par le script : la marche avant est
        -- coupée net, sinon accélérateur et marche arrière agissent ensemble et le véhicule ne bouge pas)
        local gas = math.max(GetControlNormal(0, ACCELERATE), GetDisabledControlNormal(0, ACCELERATE))
        local brake = IsControlPressed(0, BRAKE) or IsDisabledControlPressed(0, BRAKE)
        DisableControlAction(0, ACCELERATE, true) -- jamais vers l'avant en R
        DisableControlAction(0, BRAKE, true)
        SetControlNormal(0, ACCELERATE, 0.0)
        if brake then
            SetControlNormal(0, BRAKE, 0.0)
            hold = true
        else
            SetControlNormal(0, BRAKE, gas > 0.05 and gas or 0.0) -- marche arrière du jeu, à la pression de Z / W
        end
    end
    if hold then
        holding = true
        SetVehicleHandbrake(vehicle, true)
        SetVehicleBrakeLights(vehicle, true)
    elseif holding then
        release(vehicle)
    end
end)
