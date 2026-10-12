--[[
    Vehicle Control - car HUD (client) : chargé en DERNIER, après les modules qui remplissent VC.hud
    (ceinture, essence). Le car HUD est dessiné par le MDC (événement local "mdc:carHud").
]]

VC.on('tick', function(_, vehicle)
    VC.sendHud(vehicle)
end)

VC.on('leave', function()
    VC.hideHud()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    VC.toHud('carHud', { show = false })
end)
