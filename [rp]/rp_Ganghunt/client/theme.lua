--[[
    Mode nuit des menus : réglé dans le MDC (Paramètres > MDC > Apparence : Nuit, appliqué à « toutes les interfaces »
    ou aux « menus extérieurs »). Le MDC le donne au démarrage (export uiTheme) et à chaque changement (événement
    client "mdc:uiTheme") ; il est envoyé au NUI ({ action = 'uiTheme' }), qui pose data-theme="night" sur la page.
    Sans le MDC : thème jour. Aucune boucle.
]]

local function sendTheme(theme)
    SendNUIMessage({ action = 'uiTheme', data = { theme = theme == 'night' and 'night' or 'day' } })
end

AddEventHandler('mdc:uiTheme', sendTheme)

CreateThread(function()
    Wait(1500) -- le NUI a eu le temps de se charger
    local mdc = GlobalState.mdcResource or 'rp_mdc'
    if GetResourceState(mdc) ~= 'started' then return end
    local ok, theme = pcall(function() return exports[mdc]:uiTheme() end)
    if ok then sendTheme(theme) end
end)
