--[[
    Mode nuit des menus : réglé dans le MDC (Paramètres > MDC > Apparence : Nuit, sa couleur — vert, jaune, rouge ou
    bleu — et « s'applique à » toutes les interfaces ou aux menus extérieurs). Le MDC le donne au démarrage (exports
    uiTheme, uiNightColor) et à chaque changement (événement client "mdc:uiTheme", theme, color) ; il est envoyé au NUI
    ({ action = 'uiTheme' }), qui pose data-theme="night" et data-night-color sur la page. Sans le MDC : thème jour.
    Aucune boucle.
]]

local function sendTheme(theme, color)
    SendNUIMessage({ action = 'uiTheme', data = { theme = theme == 'night' and 'night' or 'day', color = color or 'green' } })
end

AddEventHandler('mdc:uiTheme', sendTheme)

CreateThread(function()
    Wait(1500) -- le NUI a eu le temps de se charger
    local mdc = GlobalState.mdcResource or 'rp_mdc'
    if GetResourceState(mdc) ~= 'started' then return end
    local ok, theme = pcall(function() return exports[mdc]:uiTheme() end)
    local okColor, color = pcall(function() return exports[mdc]:uiNightColor() end)
    if ok then sendTheme(theme, okColor and color or 'green') end
end)
