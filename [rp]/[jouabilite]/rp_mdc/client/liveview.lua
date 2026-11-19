--[[
    MDC - LIVEVIEW (MDC Web du dispatch)
    ------------------------------------
    Quand un dispatcher regarde l'écran de ce joueur sur le MDC Web, le serveur relaie l'ordre du site
    (mdc:client:liveview) : adresse du site + jeton de diffusion à usage limité. Le NUI du MDC (html/liveview.js) :
      - dessine le RENDU DU JEU (texture du jeu en WebGL : l'image du jeu seule, sans le MDC ni les autres
        interfaces) dans un canevas, transformé en piste vidéo (30 images / s par défaut) ;
      - se connecte au site (Socket.IO, espace /live, avec le jeton) pour la signalisation WebRTC ;
      - envoie la vidéo directement à chaque dispatcher qui regarde (WebRTC, chiffrée ; par un serveur TURN si besoin).
    Rien ne passe par le serveur FiveM. Arrêt : ordre du site, ou aucun renouvellement pendant `ttl` secondes (site
    coupé). 0,00 ms hors LiveView : le minuteur n'existe que pendant une diffusion ; la capture se fait dans le NUI.
]]

local live = { on = false, untilAt = 0, watching = false }

local function stop()
    live.on = false
    SendNUIMessage({ action = 'liveStop' })
end

local function watchdog()
    if live.watching then return end
    live.watching = true
    CreateThread(function()
        while live.on and GetGameTimer() < live.untilAt do Wait(1000) end
        live.watching = false
        if live.on then stop() end
    end)
end

RegisterNetEvent('mdc:client:liveview', function(data)
    if type(data) ~= 'table' then return end
    if not data.on then return stop() end
    local token = tostring(data.token or ''):gsub('[^%w]', ''):sub(1, 64)
    local url = tostring(data.url or '')
    if #token < 24 or not url:match('^https?://[%w%.%-:]+[%w/%-%._]*$') then return end
    live.on = true
    live.untilAt = GetGameTimer() + math.max(15, math.min(120, tonumber(data.ttl) or 45)) * 1000
    -- même jeton : simple renouvellement (le NUI garde sa diffusion) ; nouveau jeton : nouvelle diffusion
    SendNUIMessage({ action = 'liveStart', data = { url = url, token = token } })
    watchdog()
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then live.on = false end
end)
