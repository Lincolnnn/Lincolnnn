--[[
    MDC Standalone - Client
    -----------------------
    Performance : ce fichier ne crée AUCUNE boucle (pas de CreateThread / Wait(0)).
    Tout fonctionne par événements (commande, key mapping, callbacks NUI, net events),
    ce qui garantit 0.00ms dans le resmon quand le MDC est fermé.

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
}

-- Statuts autorisés (doivent correspondre aux data-status de index.html
-- et à la table Statuses de server.lua)
local VALID_STATUSES = {
    available    = true, -- Disponible
    unavailable  = true, -- Indisponible
    traffic_stop = true, -- Contrôle Routier
    busy         = true, -- Occupé
    on_scene     = true, -- Sur Place
    en_route     = true, -- En route
}

-- =========================================================================
-- ÉTAT LOCAL
-- =========================================================================
local isOpen = false
local currentStatus = 'available'

-- Le matricule (indicatif) est sauvegardé localement chez le joueur (KVP).
-- >>> BASE DE DONNÉES : si vous avez une table "officers", récupérez plutôt
-- >>> le matricule côté serveur (voir server.lua > GetOfficerProfile).
local callsign = GetResourceKvpString('mdc_callsign') or ''

-- =========================================================================
-- MINI-SYSTÈME DE "SERVER CALLBACKS" (standalone, remplace ESX.TriggerServerCallback)
-- =========================================================================
local pendingRequests = {}
local requestId = 0

--- Envoie une requête au serveur et appelle `cb(result)` à la réponse.
---@param name string     nom du handler déclaré côté serveur (RegisterMDCCallback)
---@param payload any      données envoyées
---@param cb function      callback(result)
local function serverRequest(name, payload, cb)
    requestId = requestId + 1
    local id = requestId
    pendingRequests[id] = cb

    TriggerServerEvent('mdc:server:request', name, id, payload)

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
    -- >>> Si vous ajoutez un système de métiers, vérifiez ici que le joueur
    -- >>> est policier (ou faites-le côté serveur dans le handler "open").

    isOpen = true
    SetNuiFocus(true, true)

    local playerId = PlayerId()
    SendNUIMessage({
        action = 'open',
        data = {
            status   = currentStatus,
            callsign = callsign,
            name     = GetPlayerName(playerId),
            serverId = GetPlayerServerId(playerId),
        }
    })

    -- Indique au serveur que ce joueur consulte le MDC
    -- (il recevra alors les mises à jour des unités/interventions en temps réel)
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

-- Changement de statut
RegisterNUICallback('setStatus', function(data, cb)
    local status = type(data) == 'table' and data.status or nil

    if type(status) ~= 'string' or not VALID_STATUSES[status] then
        cb({ ok = false, error = 'Statut invalide.' })
        return
    end

    currentStatus = status
    TriggerServerEvent('mdc:server:setStatus', status, callsign)
    cb({ ok = true, status = status })
end)

-- Mise à jour du matricule
RegisterNUICallback('setCallsign', function(data, cb)
    local value = type(data) == 'table' and data.callsign or ''
    if type(value) ~= 'string' then value = '' end

    -- Nettoyage basique : 12 caractères max, alphanumérique + tiret
    value = value:gsub('[^%w%-]', ''):sub(1, 12):upper()

    callsign = value
    SetResourceKvp('mdc_callsign', value)
    TriggerServerEvent('mdc:server:setStatus', currentStatus, callsign)
    cb({ ok = true, callsign = value })
end)

-- Callbacks génériques relayés au serveur (requête -> réponse)
-- Le NUI attend la réponse du serveur avant de résoudre son fetch.
local function relay(nuiName, serverName)
    RegisterNUICallback(nuiName, function(data, cb)
        serverRequest(serverName, data, cb)
    end)
end

relay('getUnits',          'getUnits')          -- Onglet "Unités"
relay('search',            'search')            -- Onglet "Recherches"
relay('getInterventions',  'getInterventions')  -- Onglet "Interventions"
relay('updateIntervention','updateIntervention')-- Prendre / clôturer une intervention
relay('create',            'create')            -- Onglet "Créations"

-- =========================================================================
-- PUSH SERVEUR -> NUI (uniquement si le MDC est ouvert)
-- =========================================================================
RegisterNetEvent('mdc:client:push', function(kind, payload)
    if not isOpen then return end
    SendNUIMessage({ action = kind, data = payload })
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
