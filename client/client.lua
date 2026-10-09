--[[
    MDC Standalone - Client
    -----------------------
    Performance : ce fichier ne crée AUCUNE boucle (pas de CreateThread / Wait(0)).
    Tout fonctionne par événements (commande, key mapping, callbacks NUI, net events),
    ce qui garantit 0.00ms dans le resmon quand le MDC est fermé.
    Le HUD (client/hud.lua) a une seule boucle lente, active uniquement quand le
    joueur est dans une unité et que le PLD est affiché.

    La touche Échap est gérée côté NUI (script.js) qui appelle le callback "close"
    ci-dessous pour relâcher le focus (SetNuiFocus(false, false)).
]]

-- =========================================================================
-- CONFIGURATION
-- =========================================================================
local Config = {
    -- Nom de la commande (tapez /mdc dans le chat pour ouvrir le MDC)
    Command = 'mdc',

    -- Touche par défaut. Chaque joueur peut la changer dans :
    -- Échap > Paramètres > Raccourcis clavier > FiveM > "Ouvrir le MDC (Police)"
    -- NB : une fois le mapping enregistré chez un joueur, changer cette valeur
    -- n'affecte plus ce joueur (comportement normal de RegisterKeyMapping).
    DefaultKey = 'K',

    -- Délai max (ms) d'attente d'une réponse serveur avant d'abandonner
    RequestTimeout = 5000,

    -- Débit (octets/s) des événements "latents" utilisés pour les gros envois
    -- (rapports : un DOT-523 complet peut dépasser la taille d'un événement classique)
    LatentBps = 200000,
}

-- =========================================================================
-- ÉTAT LOCAL
-- =========================================================================
local isOpen = false

-- Position / taille de la fenêtre MDC ({ x, y, w, h, maximized }).
-- Gardée en mémoire Lua UNIQUEMENT (pas de KVP) : elle est conservée d'une
-- ouverture à l'autre, mais réinitialisée à chaque reconnexion au serveur.
local windowLayout = nil

-- Nom RP : sauvegardé localement chez le joueur (KVP), il est donc conservé
-- après une reconnexion.
-- >>> BASE DE DONNÉES : si vous avez une table "officers", récupérez-le plutôt côté serveur.
local rpName = GetResourceKvpString('mdc_rpname') or ''

-- =========================================================================
-- MINI-SYSTÈME DE "SERVER CALLBACKS" (standalone, remplace ESX.TriggerServerCallback)
-- =========================================================================
local pendingRequests = {}
local requestId = 0

--- Envoie une requête au serveur et appelle `cb(result)` à la réponse.
---@param name string     nom du handler déclaré côté serveur (RegisterMDCCallback)
---@param payload any      données envoyées
---@param cb function      callback(result)
---@param latent boolean?  true pour les gros envois (envoi progressif, sans limite de taille)
local function serverRequest(name, payload, cb, latent)
    requestId = requestId + 1
    local id = requestId
    pendingRequests[id] = cb

    if latent then
        TriggerLatentServerEvent('mdc:server:request', Config.LatentBps, name, id, payload)
    else
        TriggerServerEvent('mdc:server:request', name, id, payload)
    end

    -- Timeout de sécurité : SetTimeout ne crée qu'un timer ponctuel, pas une boucle.
    SetTimeout(Config.RequestTimeout, function()
        local pending = pendingRequests[id]
        if pending then
            pendingRequests[id] = nil
            pending({ ok = false, error = 'Le serveur ne répond pas.' })
        end
    end)
end

RegisterNetEvent('mdc:client:response', function(id, result)
    local cb = pendingRequests[id]
    if not cb then return end
    pendingRequests[id] = nil
    cb(result)
end)

-- =========================================================================
-- OUVERTURE / FERMETURE
-- =========================================================================
local function openMDC()
    if isOpen then return end

    -- >>> PERMISSIONS : en standalone tout le monde peut ouvrir le MDC.
    -- >>> Si vous ajoutez un système de métiers, vérifiez ici que le joueur est policier.

    isOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'open',
        data = {
            rpName   = rpName,
            serverId = GetPlayerServerId(PlayerId()), -- non affiché : sert à repérer sa propre ligne
            layout   = windowLayout, -- nil = position par défaut (centrée)
        }
    })

    -- Profil (nom RP) puis inscription aux mises à jour en temps réel
    TriggerServerEvent('mdc:server:setProfile', rpName)
    TriggerServerEvent('mdc:server:viewer', true)
end

local function closeMDC()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TriggerServerEvent('mdc:server:viewer', false)
end

-- Commande + Key Mapping (aucune boucle nécessaire pour détecter la touche)
RegisterCommand(Config.Command, function()
    if isOpen then closeMDC() else openMDC() end
end, false)

RegisterKeyMapping(Config.Command, 'Ouvrir le MDC (Police)', 'keyboard', Config.DefaultKey)

-- =========================================================================
-- CALLBACKS NUI (appelés depuis html/script.js via fetch)
-- =========================================================================

-- Fermeture (touche Échap ou bouton de fermeture dans l'UI)
RegisterNUICallback('close', function(_, cb)
    closeMDC()
    cb({ ok = true })
end)

-- Sauvegarde de la position / taille de la fenêtre (après déplacement ou redimensionnement)
RegisterNUICallback('saveLayout', function(data, cb)
    if type(data) == 'table'
        and type(data.x) == 'number' and type(data.y) == 'number'
        and type(data.w) == 'number' and type(data.h) == 'number' then
        windowLayout = {
            x = math.floor(data.x), y = math.floor(data.y),
            w = math.floor(data.w), h = math.floor(data.h),
            maximized = data.maximized == true,
        }
    end
    cb({ ok = true })
end)

-- Heure du jeu (barre d'état du MDC, lue chaque seconde uniquement quand le MDC est ouvert)
RegisterNUICallback('getGameTime', function(_, cb)
    cb({ ok = true, hours = GetClockHours(), minutes = GetClockMinutes() })
end)

-- Nom RP
RegisterNUICallback('setProfile', function(data, cb)
    local value = type(data) == 'table' and data.rpName or nil
    if type(value) ~= 'string' then
        cb({ ok = false, error = 'Nom RP invalide.' })
        return
    end

    -- Espaces superflus retirés, 40 caractères max (le serveur revérifie)
    rpName = value:gsub('%c', ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    local cutAt = utf8.offset(rpName, 41)
    if cutAt then rpName = rpName:sub(1, cutAt - 1) end
    SetResourceKvp('mdc_rpname', rpName)

    TriggerServerEvent('mdc:server:setProfile', rpName)
    cb({ ok = true, rpName = rpName })
end)

-- =========================================================================
-- BOUTON "VÉHICULE ACTUEL" : lit le véhicule dans lequel se trouve le joueur
-- =========================================================================

-- Couleurs GTA (index de GetVehicleColours) regroupées par teinte
local COLOR_GROUPS = {
    Noir   = { 0, 1, 2, 12, 15, 16, 21, 141, 142, 143, 147 },
    Gris   = { 6, 10, 11, 13, 14, 17, 19, 20, 22, 23 },
    Argent = { 3, 4, 5, 7, 8, 9, 18, 24, 25, 26, 117, 118, 119, 120, 156 },
    Blanc  = { 111, 112, 121, 122, 131, 132, 134 },
    Rouge  = { 27, 28, 29, 30, 31, 32, 33, 34, 35, 39, 40, 43, 44, 45, 46, 47, 48, 150 },
    Orange = { 36, 38, 41, 104, 123, 124, 130, 138 },
    Jaune  = { 42, 88, 89, 91, 126 },
    Or     = { 37, 158, 159, 160 },
    Vert   = { 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 92, 125, 128, 133, 139, 144, 151, 152, 155 },
    Bleu   = { 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83,
               84, 85, 86, 87, 127, 140, 146, 157 },
    Marron = { 90, 96, 97, 98, 100, 101, 102, 103, 108, 109, 110, 114, 115, 129, 153 },
    Beige  = { 93, 94, 95, 99, 105, 106, 107, 113, 116, 154 },
    Rose   = { 135, 136, 137 },
    Violet = { 145, 148, 149 },
}

local COLOR_BY_INDEX = {}
for name, indexes in pairs(COLOR_GROUPS) do
    for _, index in ipairs(indexes) do COLOR_BY_INDEX[index] = name end
end

-- Couleurs personnalisées (RGB) : on prend la teinte de référence la plus proche
local COLOR_RGB = {
    Noir = { 15, 15, 15 }, Gris = { 100, 100, 100 }, Argent = { 180, 180, 185 }, Blanc = { 240, 240, 240 },
    Rouge = { 180, 20, 20 }, Orange = { 230, 110, 20 }, Jaune = { 230, 200, 30 }, Vert = { 30, 130, 50 },
    Bleu = { 30, 60, 170 }, Marron = { 100, 60, 30 }, Beige = { 210, 190, 150 }, Rose = { 230, 110, 170 },
    Violet = { 110, 40, 150 },
}

local function nearestColorName(r, g, b)
    local best, bestDist = 'Autre', math.huge
    for name, rgb in pairs(COLOR_RGB) do
        local dist = (r - rgb[1]) ^ 2 + (g - rgb[2]) ^ 2 + (b - rgb[3]) ^ 2
        if dist < bestDist then best, bestDist = name, dist end
    end
    return best
end

local function vehicleColorName(vehicle)
    local primary, secondary = GetVehicleColours(vehicle)

    local first = COLOR_BY_INDEX[primary] or 'Autre'
    if GetIsVehiclePrimaryColourCustom(vehicle) then
        first = nearestColorName(GetVehicleCustomPrimaryColour(vehicle))
    end

    local second = COLOR_BY_INDEX[secondary] or first
    if GetIsVehicleSecondaryColourCustom(vehicle) then
        second = nearestColorName(GetVehicleCustomSecondaryColour(vehicle))
    end

    return second ~= first and ('%s / %s'):format(first, second) or first
end

-- Texte localisé du jeu ("BUFFALO" -> "Buffalo"), avec repli si aucune traduction
local function gameLabel(key)
    if not key or key == '' then return '' end
    local label = GetLabelText(key)
    if label == 'NULL' or label == '' then
        return (key:lower():gsub('^%l', string.upper))
    end
    return label
end

RegisterNUICallback('getCurrentVehicle', function(_, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then
        cb({ ok = false, error = 'Vous devez être à bord d\'un véhicule.' })
        return
    end

    local model = GetEntityModel(vehicle)

    -- Marque : native disponible sur les builds récents du jeu (protégée par pcall)
    local okMake, makeKey = pcall(GetMakeNameFromVehicleModel, model)

    cb({
        ok    = true,
        plate = (GetVehicleNumberPlateText(vehicle) or ''):gsub('^%s+', ''):gsub('%s+$', ''),
        model = gameLabel(GetDisplayNameFromVehicleModel(model)),
        make  = okMake and gameLabel(makeKey) or '',
        color = vehicleColorName(vehicle),
    })
end)

-- =========================================================================
-- Callbacks génériques relayés au serveur (requête -> réponse)
-- Le NUI attend la réponse du serveur avant de résoudre son fetch.
-- =========================================================================
local function relay(nuiName, serverName, latent)
    RegisterNUICallback(nuiName, function(data, cb)
        serverRequest(serverName, data, cb, latent)
    end)
end

-- Unités (le statut de la barre latérale est celui de l'unité du joueur)
relay('getUnits',           'getUnits')
relay('createUnit',         'createUnit')
relay('updateUnit',         'updateUnit')
relay('joinUnit',           'joinUnit')
relay('leaveUnit',          'leaveUnit')
relay('deleteUnit',         'deleteUnit')
relay('setStatus',          'setStatus')

-- Interventions / incidents
relay('getInterventions',   'getInterventions')
relay('createIncident',     'createIncident')     -- Incident déclaré par une unité
relay('interventionAction', 'interventionAction') -- Rejoindre / quitter / terminer
relay('editIntervention',   'editIntervention')
relay('addNote',            'addNote')
relay('editNote',           'editNote')
relay('linkRecord',         'linkRecord')         -- Lier une identité / un véhicule (historique des recherches)
relay('unlinkRecord',       'unlinkRecord')
relay('getRecord',          'getRecord')          -- Fiche complète d'une identité / d'un véhicule lié

-- Recherches et créations
relay('search',            'search')            -- Onglet "Recherches" (identités / immatriculations)
relay('create',            'create')            -- Onglet "Créations" (identité, véhicule, intervention)
relay('update',            'update')            -- Modification d'une identité / d'un véhicule
relay('getRegistry',       'getRegistry')       -- Bouton "Registre" (mes créations)
relay('getMyIdentities',   'getMyIdentities')   -- Liste des propriétaires possibles (véhicule)

-- Rapports (DOT-523, Arrest Report, Incident Report, Citation, Traffic Ticket, Ticket, Warning)
relay('getReportTypes',    'getReportTypes')    -- Modèles des formulaires (définis dans server/reports.lua)
relay('getReports',        'getReports')        -- Liste (filtrée par type / texte)
relay('getReport',         'getReport')         -- Rapport complet
relay('saveReport',        'saveReport', true)  -- Création / modification (envoi latent : peut être volumineux)

-- Espace partagé d'unité (recherches et rapport en cours, communs aux membres de l'unité)
relay('getUnitShared',     'getUnitShared')

-- Modifications en direct (saisie) : envoyées sans attendre de réponse
RegisterNUICallback('unitSync', function(data, cb)
    cb({ ok = true })
    if type(data) ~= 'table' or type(data.scope) ~= 'string' or type(data.payload) ~= 'table' then return end
    local op = data.payload.op
    if op == 'start' or op == 'replace' then
        TriggerLatentServerEvent('mdc:server:unitSync', Config.LatentBps, data.scope, data.payload)
    else
        TriggerServerEvent('mdc:server:unitSync', data.scope, data.payload)
    end
end)

-- =========================================================================
-- PUSH SERVEUR -> NUI (uniquement si le MDC est ouvert)
-- =========================================================================
RegisterNetEvent('mdc:client:push', function(kind, payload)
    if not isOpen then return end
    SendNUIMessage({ action = kind, data = payload })
end)

-- Espace partagé d'unité : toujours transmis (le MDC reste à jour même fermé)
RegisterNetEvent('mdc:client:unitSync', function(scope, payload)
    SendNUIMessage({ action = 'unitSync', data = { scope = scope, payload = payload } })
end)

-- =========================================================================
-- SÉCURITÉ : relâche le focus si la ressource est arrêtée/redémarrée
-- =========================================================================
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if isOpen then
        SetNuiFocus(false, false)
        isOpen = false
    end
end)
