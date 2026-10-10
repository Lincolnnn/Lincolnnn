--[[
    RP Chat - Serveur
    -----------------
    Commandes (envoyées par le client avec l'événement "rp_chat:server:command") :
      /nomrp <nom>  définit le nom RP (obligatoire avant toute autre commande)
      /me <action>  vert pâle, visible dans un rayon de ChatConfig.MeDistance (100 m)
      /info <texte> rouge Torino sur fond rouge pâle, sans nom RP, visible par tous
      /qst <texte>  orange pâle : "<nom RP> Question : <texte>", visible par tous
      /rep <texte>  violet pâle : "<nom RP> Réponse : <texte>", visible par tous

    NOM RP PARTAGÉ AVEC LE MDC :
      Le nom RP est gardé dans l'état du joueur (state bag) : Player(src).state.rpName.
      Le MDC (ressource mdc_standalone) lit et écrit la même valeur : un /nomrp change le
      nom RP du MDC et inversement. Il n'est enregistré nulle part : il disparaît à la
      déconnexion (le joueur le refait à chaque connexion).
      >>> BASE DE DONNÉES : pour le garder entre deux connexions, chargez-le ici au
      >>> "playerJoining" puis faites Player(src).state:set('rpName', nom, true).

    /me ET DISTANCE :
      Avec OneSync (recommandé), le serveur connaît la position des joueurs et n'envoie le
      /me qu'aux joueurs dans le rayon. Sans OneSync (position inconnue côté serveur),
      le message est envoyé à tous et chaque client vérifie lui-même la distance.
]]

local Config = ChatConfig
local STATE_KEY = 'rpName'

local lastMessage = {}  -- [source] = GetGameTimer() du dernier message
local history = {}      -- derniers /info, /qst, /rep (envoyés aux joueurs qui se connectent)

-- =========================================================================
-- OUTILS
-- =========================================================================

--- Coupe une chaîne à `maxLen` caractères sans casser un caractère accentué (UTF-8).
local function truncate(str, maxLen)
    local length = utf8.len(str)
    if length and length > maxLen then
        return str:sub(1, utf8.offset(str, maxLen + 1) - 1)
    end
    return length and str or str:sub(1, maxLen)
end

--- Texte sur une ligne : caractères de contrôle retirés, espaces superflus réduits.
local function cleanText(str, maxLen)
    if type(str) ~= 'string' then return '' end
    str = str:gsub('%c', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return truncate(str, maxLen)
end

local function rpNameOf(src)
    -- Re-nettoyé à chaque lecture : un client modifié peut écrire lui-même dans son état
    return cleanText(Player(src).state[STATE_KEY], Config.NameMax)
end

local function hasPermission(src, command)
    local ace = Config.Permissions[command]
    return not ace or IsPlayerAceAllowed(src, ace)
end

local function send(target, message)
    TriggerClientEvent('rp_chat:client:message', target, message)
end

local function systemMessage(src, text, kind)
    send(src, { type = kind or 'system', text = text })
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Position du joueur côté serveur (OneSync), ou nil si elle est inconnue.
local function serverCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    if not coords or (coords.x == 0 and coords.y == 0 and coords.z == 0) then return nil end
    return coords
end

-- =========================================================================
-- NOM RP (/nomrp et MDC)
-- =========================================================================

--- Valide un nom RP. Retourne (nom) ou (nil, message d'erreur).
local function validName(raw)
    local name = cleanText(raw, Config.NameMax)
    if utf8.len(name) == nil or utf8.len(name) < Config.NameMin then
        return nil, ('Usage : /nomrp [nom RP] (%d à %d caractères).'):format(Config.NameMin, Config.NameMax)
    end
    return name
end

local function setRpName(src, raw)
    local name, err = validName(raw)
    if not name then
        systemMessage(src, err, 'error')
        return
    end
    -- État du joueur répliqué : visible par le MDC et par tous les clients
    Player(src).state:set(STATE_KEY, name, true)
    print(('^5[RP Chat]^0 %s [%s] : nom RP -> %s'):format(GetPlayerName(src) or '?', src, name))
end

-- =========================================================================
-- COMMANDES RP
-- =========================================================================
local GLOBAL = { info = true, qst = true, rep = true }

local function remember(message)
    history[#history + 1] = message
    while #history > Config.GlobalHistory do table.remove(history, 1) end
end

local function sendMe(src, message)
    local origin = serverCoords(src)
    if not origin then
        -- Sans OneSync : chaque client vérifie la distance avec le joueur qui parle
        message.checkDistance = Config.MeDistance
        send(-1, message)
        return
    end
    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        local coords = target == src and origin or serverCoords(target)
        if coords and distance(coords, origin) <= Config.MeDistance then
            send(target, message)
        end
    end
end

local Commands = {}

Commands.me = function(src, text, name)
    sendMe(src, { type = 'me', name = name, text = text, sender = src })
end

Commands.info = function(_, text)
    local message = { type = 'info', text = text } -- sans nom RP
    remember(message)
    send(-1, message)
end

Commands.qst = function(_, text, name)
    local message = { type = 'qst', name = name, text = text }
    remember(message)
    send(-1, message)
end

Commands.rep = function(_, text, name)
    local message = { type = 'rep', name = name, text = text }
    remember(message)
    send(-1, message)
end

local USAGE = {
    me = '/me [action]',
    info = '/info [texte]',
    qst = '/qst [question]',
    rep = '/rep [réponse]',
}

RegisterNetEvent('rp_chat:server:command', function(command, rawText)
    local src = source
    if type(command) ~= 'string' then return end

    if command == 'nomrp' then
        setRpName(src, rawText)
        return
    end

    local handler = Commands[command]
    if not handler then return end

    local name = rpNameOf(src)
    if name == '' then
        systemMessage(src, 'Définissez d\'abord votre nom RP : /nomrp [nom RP]', 'error')
        return
    end
    if not hasPermission(src, command) then
        systemMessage(src, ('Vous n\'avez pas la permission d\'utiliser /%s.'):format(command), 'error')
        return
    end

    local text = cleanText(rawText, Config.MaxLength)
    if text == '' then
        systemMessage(src, 'Usage : ' .. USAGE[command], 'error')
        return
    end

    local now = GetGameTimer()
    if lastMessage[src] and now - lastMessage[src] < Config.Cooldown then
        systemMessage(src, 'Patientez un instant avant d\'envoyer un nouveau message.', 'error')
        return
    end
    lastMessage[src] = now

    handler(src, text, name)
end)

-- Le chat du joueur est prêt (connexion ou redémarrage de la ressource) :
-- derniers messages /info, /qst, /rep
RegisterNetEvent('rp_chat:server:ready', function()
    TriggerClientEvent('rp_chat:client:history', source, history)
end)

AddEventHandler('playerDropped', function()
    lastMessage[source] = nil
end)

-- =========================================================================
-- REMPLACEMENT DU CHAT D'ORIGINE ("chat" et "chat-theme-gtao")
-- Les dossiers d'origine peuvent rester dans resources/ (ils sont souvent remis par
-- l'hébergeur ou txAdmin) : seule compte leur exécution. S'ils sont démarrés, ils sont
-- arrêtés ici, au démarrage de rp_chat ou dès qu'ils démarrent.
-- =========================================================================
local DEFAULT_CHAT = {}
for _, name in ipairs(Config.DefaultChatResources or {}) do DEFAULT_CHAT[name] = true end

local function isRunning(name)
    local state = GetResourceState(name)
    return state == 'started' or state == 'starting'
end

--- Ressources démarrées (hors chat d'origine) qui déclarent "dependency '<name>'" :
--- arrêter <name> les arrêterait aussi.
local function runningDependents(name)
    local list = {}
    for i = 0, GetNumResources() - 1 do
        local resource = GetResourceByFindIndex(i)
        if resource and not DEFAULT_CHAT[resource] and resource ~= GetCurrentResourceName() and isRunning(resource) then
            for j = 0, GetNumResourceMetadata(resource, 'dependency') - 1 do
                if GetResourceMetadata(resource, 'dependency', j) == name then
                    list[#list + 1] = resource
                    break
                end
            end
        end
    end
    return list
end

local function stopDefaultChat(name)
    if not isRunning(name) then return end
    local dependents = runningDependents(name)
    if #dependents > 0 then
        print(('^3[RP Chat] "%s" est démarré mais n\'est pas arrêté : %s en dépend (dependency \'%s\'). ' ..
            'Retirez cette ligne de leur fxmanifest.lua (rp_chat remplace le chat d\'origine) puis redémarrez le serveur.^0')
            :format(name, table.concat(dependents, ', '), name))
        return
    end
    if StopResource(name) then
        print(('^5[RP Chat]^0 Ressource d\'origine "%s" arrêtée : rp_chat la remplace. ' ..
            'Retirez "ensure %s" de votre server.cfg (ou désactivez-la dans le panel de votre hébergeur).'):format(name, name))
    else
        print(('^1[RP Chat] Impossible d\'arrêter "%s". Retirez "ensure %s" de votre server.cfg, ' ..
            'ou autorisez rp_chat : add_ace resource.%s command.stop allow^0'):format(name, name, GetCurrentResourceName()))
    end
end

local function stopAllDefaultChats()
    for _, name in ipairs(Config.DefaultChatResources or {}) do stopDefaultChat(name) end
end

AddEventHandler('onResourceStart', function(resource)
    if not Config.StopDefaultChat then return end
    -- Arrêt au tick suivant : une ressource ne peut pas être arrêtée pendant son démarrage
    if resource == GetCurrentResourceName() then
        SetTimeout(0, stopAllDefaultChats)
    elseif DEFAULT_CHAT[resource] then
        SetTimeout(0, function() stopDefaultChat(resource) end)
    end
end)
