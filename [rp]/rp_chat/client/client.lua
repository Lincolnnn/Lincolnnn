--[[
    RP Chat - Client
    ----------------
    Performance : aucune boucle dans ce fichier (0.00ms dans le resmon). Tout fonctionne par
    événements (key mapping, callbacks NUI, net events). La seule boucle de la ressource est
    celle de client/overhead.lua, active UNIQUEMENT pendant qu'un /me est affiché au-dessus
    d'une tête (option du joueur), puis arrêtée.

    Ouverture : touche T par défaut (RegisterKeyMapping). Chaque joueur la change dans
      Échap > Paramètres > Raccourcis clavier > FiveM > "Chat : ouvrir / fermer".
    Navigation : PageUp / PageDown par défaut ("Chat : remonter / descendre dans la conversation"), chat
      ouvert ou fermé (fermé : il s'affiche le temps de lire) ; chat ouvert, aussi la molette.
    Fermeture : Échap, ou la même touche quand la ligne de saisie est vide (géré par le NUI).

    Réglages : propres à chaque joueur (KVP "rpchat_settings"), modifiables dans l'onglet
    "Paramètres" du MDC (catégorie "Chat écrit et commandes") via les exports ci-dessous.
]]

local Config = ChatConfig
local COMMAND = 'rpchat'
local KVP_KEY = 'rpchat_settings'

-- Commandes gérées par ce chat (envoyées au serveur). Les autres commandes tapées dans le
-- chat (/mdc, commandes d'autres ressources…) sont exécutées normalement.
local RP_COMMANDS = { nomrp = true, me = true, info = true, qst = true, rep = true, hrp = true }
-- Commandes possibles même sans nom RP (/nomrp) : /tuto, /dv (supprimer un véhicule), /fichecivil (profils,
-- rp_interact), /eup (tenues, rp_interact), /repair (moteur, rp_vehiclecontrol)
local NO_NAME_COMMANDS = {
    dv = true, eup = true, fichecivil = true, repair = true, [(Config.Tuto and Config.Tuto.Command) or 'tuto'] = true,
}

local isOpen = false
local nuiReady = false

-- Chat intégré de GTA Online (touche T du jeu) : désactivé, comme le faisait le chat d'origine
-- de FiveM. Sans cette ligne, il réapparaît dès que la ressource "chat" n'est plus démarrée.
SetTextChatEnabled(false)

-- =========================================================================
-- RÉGLAGES DU JOUEUR
-- Par défaut : fond sombre bleu nuit à 80 % d'opacité, contour BLANC fin de 1 px, coins presque carrés (comme le MDC).
-- =========================================================================
local DEFAULTS = {
    shade = 22,             -- teinte du fond : 0 = noir … 100 = gris bleuté (22 : bleu nuit du MDC)
    opacity = 80,           -- opacité du fond (%)
    fontSize = 14,          -- taille du texte (px)
    width = 32,             -- largeur du chat (% de l'écran)
    height = 30,            -- hauteur du chat (% de l'écran)
    border = true,          -- contour affiché (couleur automatique : blanc le jour, couleur du mode nuit la nuit)
    borderWidth = 1,        -- épaisseur du contour (px)
    meMode = 'chat',        -- /me : 'chat' (dans le chat, rayon 50 m) ou 'head' (au-dessus des têtes)
    feed = 'fade',          -- nouveaux messages chat fermé : 'fade' (affichés 8 s), 'always', 'never'
}
local RANGES = {
    shade = { 0, 100, 1 }, opacity = { 10, 100, 1 }, fontSize = { 10, 24, 1 },
    width = { 20, 60, 1 }, height = { 15, 70, 1 }, borderWidth = { 1, 4, 0.5 },
}
local CHOICES = { meMode = { chat = true, head = true }, feed = { fade = true, always = true, never = true } }

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

--- Réglages reçus (MDC ou KVP) -> réglages valides (valeurs par défaut pour le reste)
local function sanitize(input)
    local out = copy(DEFAULTS)
    if type(input) ~= 'table' then return out end
    for key, range in pairs(RANGES) do
        local value = tonumber(input[key])
        if value then
            value = math.floor(value / range[3] + 0.5) * range[3]
            out[key] = math.min(math.max(value, range[1]), range[2])
        end
    end
    for key, set in pairs(CHOICES) do
        if set[input[key]] then out[key] = input[key] end
    end
    if type(input.border) == 'boolean' then out.border = input.border end
    -- (ancien réglage borderColor ignoré : la couleur du contour suit le thème)
    return out
end

local function loadSettings()
    local raw = GetResourceKvpString(KVP_KEY)
    local ok, decoded = pcall(json.decode, raw or '')
    return sanitize(ok and decoded or nil)
end

local settings = loadSettings()
local saveTimer = 0

local function saveSettings()
    -- Enregistrement groupé (les curseurs du MDC envoient beaucoup de valeurs d'affilée)
    saveTimer = saveTimer + 1
    local ticket = saveTimer
    SetTimeout(500, function()
        if ticket == saveTimer then SetResourceKvp(KVP_KEY, json.encode(settings)) end
    end)
end

local function sendSettings(preview)
    SendNUIMessage({ action = 'settings', data = settings, preview = preview or nil })
end

-- =========================================================================
-- NOM RP (partagé avec le MDC : état du joueur "rpName", voir server/server.lua)
-- =========================================================================
local function myRpName()
    local name = LocalPlayer.state.rpName
    return type(name) == 'string' and name or ''
end

local function system(text, kind)
    SendNUIMessage({ action = 'message', data = { type = kind or 'system', text = text } })
end

-- Nom RP modifié (/nomrp ou MDC) : confirmation dans le chat
AddStateBagChangeHandler('rpName', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    if type(value) == 'string' and value ~= '' then
        system(('Nom RP : %s'):format(value), 'success')
    end
end)

-- =========================================================================
-- OUVERTURE / FERMETURE
-- =========================================================================

--- Touche d'ouverture choisie par le joueur (pour fermer le chat avec la même touche)
local function keyLabel()
    local ok, button = pcall(GetControlInstructionalButton, 0, GetHashKey(COMMAND) | 0x80000000, true)
    if ok and type(button) == 'string' and button:sub(1, 2) == 't_' then
        return button:sub(3)
    end
    return nil
end

local function openChat()
    if isOpen or IsPauseMenuActive() then return end
    isOpen = true
    SetNuiFocus(true, false)
    SendNUIMessage({ action = 'open', data = { key = keyLabel(), hasName = myRpName() ~= '' } })
end

local function closeChat()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterCommand(COMMAND, function()
    if isOpen then closeChat() else openChat() end
end, false)
RegisterKeyMapping(COMMAND, 'Chat : ouvrir / fermer', 'keyboard', Config.DefaultKey)

-- Naviguer dans la conversation : chat fermé, il s'affiche et défile (chat ouvert, le NUI a la main et gère
-- lui-même ces touches et la molette)
local function scrollChat(dir)
    if isOpen or IsPauseMenuActive() then return end
    SendNUIMessage({ action = 'scroll', data = { dir = dir } })
end
RegisterCommand('rpchat_up', function() scrollChat(-1) end, false)
RegisterCommand('rpchat_down', function() scrollChat(1) end, false)
RegisterKeyMapping('rpchat_up', 'Chat : remonter dans la conversation', 'keyboard', Config.ScrollUpKey or 'PAGEUP')
RegisterKeyMapping('rpchat_down', 'Chat : descendre dans la conversation', 'keyboard', Config.ScrollDownKey or 'PAGEDOWN')

-- =========================================================================
-- CALLBACKS NUI
-- =========================================================================
RegisterNUICallback('close', function(_, cb)
    closeChat()
    cb({ ok = true })
end)

-- Le NUI est chargé : réglages, puis derniers messages /info, /qst, /rep du serveur
RegisterNUICallback('ready', function(_, cb)
    nuiReady = true
    sendSettings()
    TriggerServerEvent('rp_chat:server:ready')
    cb({ ok = true })
end)

local HELP = 'Commandes : /nomrp [nom RP], /me [action], /info [texte], /qst [question], /rep [réponse], /dv, /eup, /tuto, /fichecivil, /repair, /hrp [message].'

-- =========================================================================
-- /dv : supprime UN véhicule (celui où l'on se trouve, sinon celui qu'on regarde, sinon le plus proche,
-- dans un rayon de DvDistance mètres). La suppression est faite par le serveur (vérifications).
-- =========================================================================
--- Véhicule regardé (caméra), à DvDistance m du joueur au plus
local function aimedVehicle(ped)
    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local to = cam + dir * (Config.DvDistance + 10.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 2, ped, 7)
    local _, hit, _, _, entity = GetShapeTestResult(ray)
    if hit == 1 and entity and entity ~= 0 and GetEntityType(entity) == 2
        and #(GetEntityCoords(entity) - GetEntityCoords(ped)) <= Config.DvDistance then
        return entity
    end
    return nil
end

local function closestVehicle(ped)
    local pos, best, bestDistance = GetEntityCoords(ped), nil, Config.DvDistance
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(vehicle) - pos)
        if d <= bestDistance then best, bestDistance = vehicle, d end
    end
    return best
end

local function deleteVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then vehicle = aimedVehicle(ped) or closestVehicle(ped) or 0 end
    if vehicle == 0 then
        return system(('Aucun véhicule dans un rayon de %d m.'):format(math.floor(Config.DvDistance)), 'error')
    end
    if NetworkGetEntityIsNetworked(vehicle) then
        TriggerServerEvent('rp_chat:server:dv', VehToNet(vehicle)) -- une commande = un véhicule
    else
        -- Véhicule propre à ce joueur (non synchronisé) : supprimé ici
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteVehicle(vehicle)
        system('Véhicule supprimé.')
    end
end
RegisterCommand('dv', deleteVehicle, false)

-- Réponse du serveur (sans OneSync : suppression par ce client, qui a le véhicule à portée)
RegisterNetEvent('rp_chat:client:dv', function(result, netId)
    if result == 'fallback' then
        local vehicle = NetToVeh(netId)
        if vehicle == 0 or not DoesEntityExist(vehicle) then return system('Véhicule introuvable.', 'error') end
        NetworkRequestControlOfEntity(vehicle)
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteVehicle(vehicle)
        if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
        return system('Véhicule supprimé.')
    end
    if result == 'ok' then return system('Véhicule supprimé.') end
    system(result, 'error')
end)

-- Ligne validée avec Entrée
RegisterNUICallback('submit', function(data, cb)
    cb({ ok = true })
    closeChat()

    local text = type(data) == 'table' and type(data.text) == 'string' and data.text or ''
    text = text:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then return end

    local command, rest = text:match('^/(%S+)%s*(.*)$')
    if not command then
        system('Utilisez une commande. ' .. HELP, 'error')
        return
    end
    command = command:lower()

    if RP_COMMANDS[command] then
        TriggerServerEvent('rp_chat:server:command', command, rest)
        return
    end

    -- Sans nom RP, seules /nomrp et les commandes de NO_NAME_COMMANDS sont autorisées
    if myRpName() == '' and not NO_NAME_COMMANDS[command] then
        system('Définissez d\'abord votre nom RP : /nomrp [nom RP]', 'error')
        return
    end
    -- Commande d'une autre ressource (/mdc, …)
    ExecuteCommand(text:sub(2))
end)

-- =========================================================================
-- MESSAGES
-- =========================================================================
local function senderInRange(sender, maxDistance)
    if sender == GetPlayerServerId(PlayerId()) then return true end
    local player = GetPlayerFromServerId(sender)
    if player == -1 then return false end
    local a, b = GetEntityCoords(PlayerPedId()), GetEntityCoords(GetPlayerPed(player))
    return #(a - b) <= maxDistance
end

RegisterNetEvent('rp_chat:client:message', function(message)
    if type(message) ~= 'table' then return end
    if message.type == 'me' then
        -- Serveur sans OneSync : la distance est vérifiée ici
        if message.checkDistance and not senderInRange(message.sender, message.checkDistance) then return end
        -- Option du joueur : /me au-dessus des têtes plutôt que dans le chat
        if settings.meMode == 'head' and RPChatOverhead then
            RPChatOverhead.add(message.sender, message.text)
            return
        end
    end
    SendNUIMessage({ action = 'message', data = message })
end)

RegisterNetEvent('rp_chat:client:history', function(list)
    SendNUIMessage({ action = 'history', data = list })
end)

-- ---- Compatibilité avec le chat d'origine (autres ressources) ----
-- TriggerEvent / TriggerClientEvent('chat:addMessage', { args = { 'Auteur', 'Texte' }, color = { r, g, b } })
local function externalMessage(message)
    if type(message) == 'string' then message = { args = { message } } end
    if type(message) ~= 'table' then return end
    local args = type(message.args) == 'table' and message.args or {}
    local author, text
    if #args >= 2 then author, text = tostring(args[1]), tostring(args[2]) else text = tostring(args[1] or message.message or '') end
    if text == '' then return end
    SendNUIMessage({ action = 'message', data = {
        type = 'external', name = author, text = text,
        color = type(message.color) == 'table' and message.color or nil,
    } })
end

RegisterNetEvent('chat:addMessage', externalMessage)
RegisterNetEvent('chatMessage', function(author, color, text)
    externalMessage({ args = { author, text }, color = color })
end)
RegisterNetEvent('chat:clear', function() SendNUIMessage({ action = 'clear' }) end)
-- Suggestions / modèles du chat d'origine : sans effet ici
for _, name in ipairs({ 'chat:addSuggestion', 'chat:addSuggestions', 'chat:removeSuggestion', 'chat:addTemplate' }) do
    RegisterNetEvent(name, function() end)
end

-- =========================================================================
-- EXPORTS (utilisés par le MDC, onglet "Paramètres" > "Chat écrit et commandes")
-- =========================================================================
exports('getSettings', function()
    return { settings = copy(settings), defaults = copy(DEFAULTS), key = keyLabel() or Config.DefaultKey, distance = Config.MeDistance }
end)

exports('setSettings', function(input)
    settings = sanitize(input)
    saveSettings()
    if nuiReady then sendSettings(true) end -- aperçu du chat pendant le réglage
    return copy(settings)
end)

exports('resetSettings', function()
    settings = copy(DEFAULTS)
    saveSettings()
    if nuiReady then sendSettings(true) end
    return copy(settings)
end)

-- Chat d'origine : exports.chat:addMessage(...)
exports('addMessage', externalMessage)

-- =========================================================================
-- /tuto : affiche des touches et fonctionnalités (config.lua : Tuto) en haut de l'écran, au milieu, sans focus
-- (ni souris ni clavier : le joueur continue de jouer) ; /tuto à nouveau la retire.
-- Rappel privé dans le chat à chaque connexion.
-- =========================================================================
local Tuto = Config.Tuto or {}
local tutoShown = false

local function toggleTuto()
    tutoShown = not tutoShown
    SendNUIMessage({ action = 'tuto', data = tutoShown and {
        show = true, title = Tuto.Title or '', command = '/' .. (Tuto.Command or 'tuto'),
        sections = Tuto.Sections or {}, footer = Tuto.Footer or '',
    } or { show = false } })
end
RegisterCommand(Tuto.Command or 'tuto', toggleTuto, false)

-- Rappel privé à la connexion : attend l'arrivée en jeu (fin de l'écran de chargement), une seule fois.
-- Boucle courte (1 s) uniquement pendant le chargement, puis arrêtée.
if type(Tuto.JoinMessage) == 'string' and Tuto.JoinMessage ~= '' then
    CreateThread(function()
        while not nuiReady or not NetworkIsPlayerActive(PlayerId()) or GetIsLoadingScreenActive() or IsScreenFadedOut() do
            Wait(1000)
        end
        Wait(Tuto.JoinDelay or 5000)
        SendNUIMessage({ action = 'message', data = { type = 'tuto', title = 'Bienvenue', text = Tuto.JoinMessage } })
    end)
end

-- Message PRIVÉ (affiché uniquement chez ce joueur), ex. résultat d'une inspection rp_interact :
--   exports.rp_chat:addPrivate({ title = 'Fouille du coffre', subject = 'Bravado Buffalo', text = '…' })
exports('addPrivate', function(data)
    if type(data) ~= 'table' or type(data.text) ~= 'string' or data.text == '' then return end
    SendNUIMessage({ action = 'message', data = {
        type = 'private', title = tostring(data.title or ''), name = data.subject and tostring(data.subject) or nil, text = data.text,
    } })
end)

-- =========================================================================
-- SÉCURITÉ : relâche le focus si la ressource est arrêtée
-- =========================================================================
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then SetNuiFocus(false, false) end
end)
