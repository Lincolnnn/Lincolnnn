--[[
    Vehicle Control - marche avant / marche arrière (client, conducteur)
    --------------------------------------------------------------------
    Touche Keys.gear (flèche haut par défaut) : passe de D (marche avant) à R (marche arrière) et inversement.
      - D : on ne peut qu'AVANCER et FREINER : le frein (S) freine, puis, véhicule arrêté, le retient au lieu de
        reculer ;
      - R : on ne peut que FREINER et RECULER : la marche arrière (S) recule, l'accélérateur (W) ne sert qu'à freiner
        la marche arrière, puis, véhicule arrêté, le retient au lieu d'avancer.
    Le rapport est affiché sur le car HUD du MDC (R au-dessus de D, le passage de l'un à l'autre glisse en douceur).
    Chaque véhicule part en D. Pas de rapport sur les vélos, bateaux, hélicoptères, avions, trains (SkipClasses).
    Performance : seulement à bord, au volant (événement 'frame' du véhicule).
]]

local Config = VCConfig.Gear or {}
local ACCELERATE, BRAKE = 71, 72

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

-- À chaque image, au volant : la pédale « interdite » par le rapport ne fait que freiner, puis retient le véhicule
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
        -- accélérateur : il freine tant que le véhicule recule ; arrêté (ou avançant), il le retient
        if (IsControlPressed(0, ACCELERATE) or IsDisabledControlPressed(0, ACCELERATE)) and forward >= -stop then
            DisableControlAction(0, ACCELERATE, true)
            hold = true
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
