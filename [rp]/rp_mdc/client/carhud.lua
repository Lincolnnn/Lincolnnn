--[[
    MDC Standalone - Car HUD (client)
    ---------------------------------
    Le car HUD (vitesse en MPH, barre d'accélération, jauge d'essence, logos ceinture / véhicule cassé,
    notification du moteur) est dessiné par le NUI du MDC et réglé dans "Paramètres > HUD & Display".
    Ses données viennent de Vehicle Control (ressource rp_vehiclecontrol : essence, dégâts, ceinture,
    moteur), par l'événement local "mdc:carHud". Sans rp_vehiclecontrol, le car HUD
    n'apparaît pas.
    Les sons du véhicule (ceinture, carillon, clignotants) sont de vrais sons joués par rp_vehiclecontrol,
    au volume réglé ici (export "carSoundVolume", client/hud.lua).
    Aucune boucle : simple relais vers le NUI.
]]

local ACTIONS = {
    carHud = true,     -- { inVehicle, show, mode = 'driver' | 'passenger', engine, speed, rpm, fuel, belt, alarm, broken, damaged, paused }
    carNotice = true,  -- { key, text, hint, duration } : notification au-dessus du car HUD
    carNoticeHide = true, -- touche du moteur utilisée : notification masquée
}

AddEventHandler('mdc:carHud', function(action, data)
    if ACTIONS[action] and type(data) == 'table' then SendNUIMessage({ action = action, data = data }) end
end)

-- Riven Impact Dynamics : ses voyants de dégâts se placent juste au-dessus du car HUD et le suivent
-- (rp_vehiclecontrol/riven/bridge.lua, chargé dans la ressource de Riven, reçoit sa place par "rp_mdc:carHudRect")
local carRect = { visible = false } -- { visible, x, y, w, h (fractions de l'écran), scale }
RegisterNUICallback('carHudRect', function(data, cb)
    cb({ ok = true })
    if type(data) ~= 'table' then return end
    carRect = data
    TriggerEvent('rp_mdc:carHudRect', carRect)
end)
AddEventHandler('rp_mdc:carHudRectRequest', function() TriggerEvent('rp_mdc:carHudRect', carRect) end)

-- Voyants allumés : la notification du moteur monte d'un cran pour ne pas les cacher
AddEventHandler('riven-impact-dynamics:lamps', function(list)
    SendNUIMessage({ action = 'rivenLamps', data = { count = type(list) == 'table' and #list or 0 } })
end)
