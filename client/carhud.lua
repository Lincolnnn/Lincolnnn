--[[
    MDC Standalone - Car HUD (client)
    ---------------------------------
    Le car HUD (vitesse en MPH, barre d'accélération, jauge d'essence, logos ceinture / véhicule cassé,
    notification du moteur) est dessiné par le NUI du MDC et réglé dans "Paramètres > HUD & Display".
    Ses données viennent de Vehicle Control (ressource rp_vehiclecontrol : essence, dégâts, ceinture,
    moteur, frein de parcage), par l'événement local "mdc:carHud". Sans rp_vehiclecontrol, le car HUD
    n'apparaît pas.
    Aucune boucle : simple relais vers le NUI.
]]

local ACTIONS = {
    carHud = true,     -- { inVehicle, show, mode = 'driver' | 'passenger', speed, rpm, fuel, belt, alarm, broken, parked, paused }
    beltSound = true,  -- { kind = 'on' | 'off', volume }
    beltBeep = true,   -- { volume } (0 = arrêt)
    carNotice = true,  -- { key, text, hint, duration } : notification au-dessus du car HUD
    carNoticeHide = true, -- touche du moteur utilisée : notification masquée
}

AddEventHandler('mdc:carHud', function(action, data)
    if ACTIONS[action] and type(data) == 'table' then SendNUIMessage({ action = action, data = data }) end
end)
