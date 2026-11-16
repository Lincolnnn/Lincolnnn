--[[
    MDC - LIVEVIEW (MDC Web du dispatch)
    ------------------------------------
    Quand un dispatcher regarde l'écran de ce joueur sur le MDC Web, le serveur envoie l'ordre (mdc:client:liveview) :
    une capture de l'image du jeu (ressource screenshot-basic, rien d'autre que le jeu) est prise à cadence fixe.
    - Vidéo WebRTC (relais LiveKit configuré sur le site) : le NUI du MDC dessine chaque capture dans un canevas
      publié en vidéo (~2 images / s, 640 x 360 en mosaïque, 1280 x 720 agrandie, débit plafonné) vers le relais,
      avec un jeton émetteur limité à la salle de CE joueur ;
    - repli (pas de relais, ou publication impossible) : capture réduite (480 x 270 / 960 x 540), JPEG, envoyée
      DIRECTEMENT au site (jeton à usage limité), sans passer par le serveur FiveM.
    Aucune capture sans ordre ; arrêt automatique sans nouvel ordre pendant `ttl` secondes (dispatcher parti, site
    coupé). 0,00 ms hors LiveView : la boucle n'existe que pendant une diffusion.
]]

local live = { on = false, until_ = 0, cfg = nil, busy = false, running = false }

local function stop()
    live.on, live.cfg = false, nil
    SendNUIMessage({ action = 'liveStop' })
end

local function loop()
    if live.running then return end
    live.running = true
    CreateThread(function()
        while live.on and GetGameTimer() < live.until_ do
            local cfg = live.cfg
            if not live.busy then
                live.busy = true
                local ok = pcall(function()
                    exports['screenshot-basic']:requestScreenshot({ encoding = 'jpg', quality = cfg.rtc and 0.92 or 0.85 }, function(data)
                        if live.on and type(data) == 'string' then
                            SendNUIMessage({ action = 'liveFrame', data = { img = data, token = cfg.token, url = cfg.url,
                                w = cfg.w, h = cfg.h, q = cfg.q, rtc = cfg.rtc } })
                        end
                        live.busy = false
                    end)
                end)
                if not ok then live.busy = false end
            end
            Wait(cfg.interval)
        end
        live.running = false
        if live.on then stop() end
    end)
end

RegisterNetEvent('mdc:client:liveview', function(data)
    if type(data) ~= 'table' then return end
    if not data.on then return stop() end
    if GetResourceState('screenshot-basic') ~= 'started' then return end
    live.cfg = {
        token = tostring(data.token or ''), url = tostring(data.url or ''),
        w = math.floor(tonumber(data.w) or 480), h = math.floor(tonumber(data.h) or 270),
        q = math.min(0.9, math.max(0.2, tonumber(data.q) or 0.5)),
        interval = math.max(250, math.floor(tonumber(data.interval) or 2000)),
    }
    if type(data.rtc) == 'table' and data.rtc.token then
        live.cfg.rtc = data.rtc
        live.cfg.interval = math.max(250, math.floor(1000 / math.max(1, tonumber(data.rtc.fps) or 2)))
    end
    live.on = true
    live.until_ = GetGameTimer() + math.max(5, tonumber(data.ttl) or 25) * 1000
    loop()
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then live.on = false end
end)
