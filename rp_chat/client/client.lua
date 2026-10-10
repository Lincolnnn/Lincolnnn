--[[
    RP Chat - Client
    ----------------
    Performance : aucune boucle dans ce fichier (0.00ms dans le resmon). Tout fonctionne par
    événements (key mapping, callbacks NUI, net events). La seule boucle de la ressource est
    celle de client/overhead.lua, active UNIQUEMENT pendant qu'un /me est affiché au-dessus
    d'une tête (option du joueur), puis arrêtée.

    Ouverture : touche T par défaut (RegisterKeyMapping). Chaque joueur la change dans
      Échap > Paramètres > Raccourcis clavier > FiveM > "Chat : ouvrir / fermer".
    Fermeture : Échap, ou la même touche quand la ligne de saisie est vide (géré par le NUI).

    Réglages : propres à chaque joueur (KVP "rpchat_settings"), modifiables dans l'onglet
    "Paramètres" du MDC (catégorie "Chat écrit et commandes") via les exports ci-dessous.
]]

local Config = ChatConfig
local COMMAND = 'rpchat'
local KVP_KEY = 'rpchat_settings'

-- Commandes gérées par ce chat (envoyées au serveur). Les autres commandes tapées dans le
-- chat (/mdc, commandes d'autres ressources…) sont exécutées normalement.
local RP_COMMANDS = { nomrp = true, me = true, info = true, qst = true, rep = true }

local isOpen = false
local nuiReady = false

-- Chat intégré de GTA Online (touche T du jeu) : désactivé, comme le faisait le chat d'origine
-- de FiveM. Sans cette ligne, il réapparaît dès que la ressource "chat" n'est plus démarrée.
SetTextChatEnabled(false)

-- =========================================================================
-- RÉGLAGES DU JOUEUR
-- Par défaut : même fond et même contour que le HUD et le display MDC
-- (noir à 62 % d'opacité, contour gris de 1,5 px).
-- =========================================================================
local DEFAULTS = {
    shade = 0,              -- teinte du fond : 0 = noir … 100 = gris
    opacity = 62,           -- opacité du fond (%)
    fontSize = 14,          -- taille du texte (px)
    width = 32,             -- largeur du chat (% de l'écran)
    height = 30,            -- hauteur du chat (% de l'écran)
    border = true,          -- contour affiché
    borderColor = '#7a7a7a',
    borderWidth = 1.5,      -- épaisseur du contour (px)
    meMode = 'chat',        -- /me : 'chat' (dans le chat, rayon 100 m) ou 'head' (au-dessus des têtes)
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
    if type(input.borderColor) == 'string' and input.borderColor:match('^#%x%x%x%x%x%x$') then
        out.borderColor = input.borderColor:lower()
    end
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

local HELP = 'Commandes : /nomrp [nom RP], /me [action], /info [texte], /qst [question], /rep [réponse].'

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

    -- Sans nom RP, seule /nomrp est autorisée
    if myRpName() == '' then
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
-- SÉCURITÉ : relâche le focus si la ressource est arrêtée
-- =========================================================================
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then SetNuiFocus(false, false) end
end)
