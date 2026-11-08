--[[
    RP RoleplayZone - client : messages de session (/sessionon, /sessionoff, connexion pendant une session)
    ------------------------------------------------------------------------------------------------------
    Le serveur envoie le message à tous : affiché en haut au milieu (même style que l'entrée dans une zone de recherche),
    avec un son de message reçu, pendant Session.Duration ms. Aucune boucle.
    Connexion pendant une session : message « session en cours » qui RESTE affiché (sticky) jusqu'à Échap (le menu pause
    ne s'ouvre pas) ; boucle à chaque image seulement tant qu'il est affiché.
]]

local sticky = false

local function hideSticky()
    if not sticky then return end
    sticky = false
    SendNUIMessage({ action = 'sessionHide' })
end

local function showSticky(data)
    if sticky then return end
    -- après l'écran de chargement et le fondu du début (sinon le joueur ne le verrait pas)
    while GetIsLoadingScreenActive() or IsScreenFadedOut() or IsScreenFadingIn() or not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
    Wait(1500)
    sticky = true
    SendNUIMessage({ action = 'session', data = { kind = data.kind or 'on', sticky = true, title = data.title,
        subtitle = data.subtitle, text = data.text, hint = data.hint } })
    RZ.sound('message')
    CreateThread(function()
        while sticky do
            -- Échap : ferme le message ; le menu pause du jeu ne s'ouvre pas
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 322, true)
            if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322) then
                hideSticky()
                local untilTime = GetGameTimer() + 600
                while GetGameTimer() < untilTime do
                    DisableControlAction(0, 200, true)
                    DisableControlAction(0, 322, true)
                    if IsPauseMenuActive() then SetPauseMenuActive(false) end
                    Wait(0)
                end
                break
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent('rp_scene:session', function(data)
    if type(data) ~= 'table' then return end
    if data.denied then
        return TriggerEvent('chat:addMessage', { args = { 'Session', 'Commande réservée aux administrateurs.' } })
    end
    if data.sticky then return CreateThread(function() showSticky(data) end) end
    hideSticky() -- /sessionon, /sessionoff : remplacent le message « session en cours »
    SendNUIMessage({ action = 'session', data = { kind = data.kind, title = data.title, text = data.text,
        duration = tonumber(data.duration) or 12000 } })
    RZ.sound('message')
end)

-- Jeu prêt : le serveur envoie le message « session en cours » si ce joueur vient de se connecter pendant une session
CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    TriggerServerEvent('rp_scene:sessionReady')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then sticky = false end
end)
