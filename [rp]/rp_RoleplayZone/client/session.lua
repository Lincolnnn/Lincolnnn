--[[
    RP RoleplayZone - client : messages de session (/sessionon, /sessionoff)
    -------------------------------------------------------------------------
    Le serveur envoie le message à tous : affiché en haut au milieu (même style que l'entrée dans une zone de recherche),
    avec un son de message reçu, pendant Session.Duration ms. Aucune boucle.
]]

RegisterNetEvent('rp_scene:session', function(data)
    if type(data) ~= 'table' then return end
    if data.denied then
        return TriggerEvent('chat:addMessage', { args = { 'Session', 'Commande réservée aux administrateurs.' } })
    end
    SendNUIMessage({ action = 'session', data = { kind = data.kind, title = data.title, text = data.text,
        duration = tonumber(data.duration) or 12000 } })
    RZ.sound('message')
end)
