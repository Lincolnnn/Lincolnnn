--[[
    MDC Standalone - Serveur
    ------------------------
    Toutes les données sont stockées EN MÉMOIRE (tables Lua) : elles sont perdues
    au redémarrage de la ressource. Chaque endroit où brancher votre propre base
    de données (oxmysql, mysql-async, ghmattimysql, KVP, fichiers JSON...) est
    signalé par un commentaire  ">>> BASE DE DONNÉES".

    Exemple avec oxmysql (à ajouter dans fxmanifest : server_script '@oxmysql/lib/MySQL.lua') :
        local rows = MySQL.query.await('SELECT * FROM mdc_reports WHERE id = ?', { id })
]]

-- =========================================================================
-- CONFIGURATION
-- =========================================================================
local Config = {
    -- Permissions ACE (optionnel). Si true, seuls les joueurs ayant l'ACE
    -- "mdc.use" peuvent utiliser le MDC côté serveur. Exemple dans server.cfg :
    --   add_ace group.police mdc.use allow
    --   add_principal identifier.license:xxxxxxxx group.police
    UseAcePermission = false,
    AcePermission = 'mdc.use',

    -- Anti-spam : délai minimum (ms) entre deux changements de statut d'un joueur
    StatusCooldown = 500,
}

-- Statuts : clé technique -> libellé (doit correspondre à client.lua et index.html)
local Statuses = {
    available    = 'Disponible',
    unavailable  = 'Indisponible',
    traffic_stop = 'Contrôle Routier',
    busy         = 'Occupé',
    on_scene     = 'Sur Place',
    en_route     = 'En route',
}

-- =========================================================================
-- STOCKAGE EN MÉMOIRE
-- =========================================================================
local Units = {}          -- [source] = { id, name, callsign, status, updatedAt }
local Viewers = {}        -- [source] = true  (joueurs ayant le MDC ouvert)
local Interventions = {}  -- liste des interventions
local Reports = {}        -- rapports
local Bolos = {}          -- avis de recherche
local nextId = { intervention = 1, report = 1, bolo = 1 }
local lastStatusChange = {}

-- =========================================================================
-- OUTILS
-- =========================================================================
local function hasAccess(src)
    if not Config.UseAcePermission then return true end
    return IsPlayerAceAllowed(src, Config.AcePermission)
end

local function getIdentifier(src)
    -- Identifiant stable du joueur, utile comme clé en base de données.
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return ('source:%d'):format(src)
end

local function clean(str, maxLen)
    if type(str) ~= 'string' then return '' end
    str = str:gsub('^%s+', ''):gsub('%s+$', '')
    return str:sub(1, maxLen or 255)
end

local function unitsList()
    local list = {}
    for _, unit in pairs(Units) do list[#list + 1] = unit end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

--- Envoie une mise à jour à tous les joueurs ayant le MDC ouvert.
local function pushToViewers(kind, payload)
    for src in pairs(Viewers) do
        TriggerClientEvent('mdc:client:push', src, kind, payload)
    end
end

local function ensureUnit(src)
    if not Units[src] then
        Units[src] = {
            id = src,
            name = GetPlayerName(src) or ('Joueur %d'):format(src),
            callsign = '',
            status = 'available',
            updatedAt = os.time(),
        }
    end
    return Units[src]
end

-- =========================================================================
-- SYSTÈME DE CALLBACKS (requête client -> réponse serveur)
-- =========================================================================
local Handlers = {}

--- Déclare un handler appelable depuis le client via serverRequest(name, ...)
---@param name string
---@param fn fun(src: number, payload: any): table
local function RegisterMDCCallback(name, fn)
    Handlers[name] = fn
end

RegisterNetEvent('mdc:server:request', function(name, id, payload)
    local src = source
    if type(name) ~= 'string' or type(id) ~= 'number' then return end

    local handler = Handlers[name]
    local result

    if not hasAccess(src) then
        result = { ok = false, error = 'Accès refusé.' }
    elseif not handler then
        result = { ok = false, error = ('Action inconnue : %s'):format(name) }
    else
        local success, res = pcall(handler, src, type(payload) == 'table' and payload or {})
        if success then
            result = res or { ok = true }
        else
            print(('^1[MDC] Erreur dans le handler "%s" : %s^0'):format(name, res))
            result = { ok = false, error = 'Erreur serveur.' }
        end
    end

    TriggerClientEvent('mdc:client:response', src, id, result)
end)

-- =========================================================================
-- STATUT DES UNITÉS
-- =========================================================================
RegisterNetEvent('mdc:server:setStatus', function(status, callsign)
    local src = source
    if not hasAccess(src) then return end
    if type(status) ~= 'string' or not Statuses[status] then return end

    local unit = ensureUnit(src)
    local oldStatus = unit.status
    unit.callsign = clean(callsign, 12)

    -- Simple mise à jour du matricule (même statut) : pas de log ni d'anti-spam
    if status == oldStatus then
        pushToViewers('units', unitsList())
        return
    end

    -- Anti-spam sur les changements de statut
    local now = GetGameTimer()
    if lastStatusChange[src] and now - lastStatusChange[src] < Config.StatusCooldown then return end
    lastStatusChange[src] = now

    unit.status = status
    unit.updatedAt = os.time()

    -- Notification console (demandée pour la version standalone)
    print(('^5[MDC]^0 %s%s (ID %d) : ^3%s^0 -> ^2%s^0'):format(
        unit.name,
        unit.callsign ~= '' and (' [' .. unit.callsign .. ']') or '',
        src,
        Statuses[oldStatus] or oldStatus,
        Statuses[status]
    ))

    -- >>> BASE DE DONNÉES : historiser le changement de statut, par ex. :
    -- >>> MySQL.insert('INSERT INTO mdc_status_logs (identifier, status, date) VALUES (?, ?, NOW())',
    -- >>>     { getIdentifier(src), status })

    -- >>> DISCORD : vous pouvez aussi envoyer un webhook ici (PerformHttpRequest).

    pushToViewers('units', unitsList())
end)

-- Le client signale l'ouverture/fermeture du MDC
RegisterNetEvent('mdc:server:viewer', function(isViewing)
    local src = source
    if isViewing and hasAccess(src) then
        Viewers[src] = true
        ensureUnit(src)
        pushToViewers('units', unitsList())
    else
        Viewers[src] = nil
    end
end)

RegisterMDCCallback('getUnits', function()
    -- >>> BASE DE DONNÉES : vous pouvez enrichir chaque unité avec les infos de
    -- >>> votre table d'agents (grade, nom RP, véhicule...) via getIdentifier(src).
    return { ok = true, units = unitsList() }
end)

-- Nettoyage à la déconnexion
AddEventHandler('playerDropped', function()
    local src = source
    local wasUnit = Units[src] ~= nil
    Units[src], Viewers[src], lastStatusChange[src] = nil, nil, nil

    for _, intervention in ipairs(Interventions) do
        intervention.units[tostring(src)] = nil
    end

    if wasUnit then pushToViewers('units', unitsList()) end
end)

-- =========================================================================
-- RECHERCHES
-- =========================================================================
RegisterMDCCallback('search', function(_, payload)
    local searchType = payload.type
    local query = clean(payload.query, 64):lower()

    if #query < 2 then
        return { ok = false, error = 'Saisissez au moins 2 caractères.' }
    end

    local results = {}

    if searchType == 'person' then
        -- >>> BASE DE DONNÉES : remplacez ce bloc par une recherche dans votre table
        -- >>> de personnages / casiers judiciaires, par ex. :
        -- >>> MySQL.query.await('SELECT firstname, lastname, dob FROM characters
        -- >>>     WHERE CONCAT(firstname, " ", lastname) LIKE ?', { '%' .. query .. '%' })
        --
        -- Version standalone : on cherche parmi les joueurs connectés.
        for _, playerId in ipairs(GetPlayers()) do
            local name = GetPlayerName(playerId) or ''
            if name:lower():find(query, 1, true) then
                results[#results + 1] = {
                    title = name,
                    subtitle = ('Joueur connecté - ID %s'):format(playerId),
                    tag = 'Citoyen',
                }
            end
        end

    elseif searchType == 'vehicle' then
        -- >>> BASE DE DONNÉES : recherche de plaque dans votre table de véhicules, par ex. :
        -- >>> MySQL.query.await('SELECT plate, model, owner FROM vehicles WHERE plate LIKE ?',
        -- >>>     { '%' .. query .. '%' })
        --
        -- Version standalone : aucune table de véhicules, on ne cherche que dans les avis de recherche.
    else
        return { ok = false, error = 'Type de recherche invalide.' }
    end

    -- Dans tous les cas, on remonte les avis de recherche (BOLO) correspondants.
    for _, bolo in ipairs(Bolos) do
        local haystack = (bolo.title .. ' ' .. bolo.description):lower()
        if haystack:find(query, 1, true) then
            results[#results + 1] = {
                title = bolo.title,
                subtitle = bolo.description,
                tag = 'Avis de recherche',
                danger = true,
            }
        end
    end

    return { ok = true, results = results }
end)

-- =========================================================================
-- INTERVENTIONS
-- =========================================================================
RegisterMDCCallback('getInterventions', function()
    -- >>> BASE DE DONNÉES : SELECT * FROM mdc_interventions WHERE closed = 0
    return { ok = true, interventions = Interventions }
end)

RegisterMDCCallback('updateIntervention', function(src, payload)
    local id = tonumber(payload.id)
    local action = payload.action

    for index, intervention in ipairs(Interventions) do
        if intervention.id == id then
            local unit = ensureUnit(src)
            local key = tostring(src) -- clé string pour une sérialisation JSON propre

            if action == 'attach' then
                intervention.units[key] = unit.callsign ~= '' and unit.callsign or unit.name
            elseif action == 'detach' then
                intervention.units[key] = nil
            elseif action == 'close' then
                table.remove(Interventions, index)
                print(('^5[MDC]^0 Intervention #%d clôturée par %s'):format(id, unit.name))
                -- >>> BASE DE DONNÉES : UPDATE mdc_interventions SET closed = 1 WHERE id = ?
            else
                return { ok = false, error = 'Action invalide.' }
            end

            -- >>> BASE DE DONNÉES : sauvegarder les unités assignées si besoin
            pushToViewers('interventions', Interventions)
            return { ok = true }
        end
    end

    return { ok = false, error = 'Intervention introuvable.' }
end)

-- =========================================================================
-- CRÉATIONS (rapports, avis de recherche, interventions)
-- =========================================================================
RegisterMDCCallback('create', function(src, payload)
    local kind = payload.kind
    local title = clean(payload.title, 80)
    local description = clean(payload.description, 2000)
    local author = ensureUnit(src)

    if title == '' then
        return { ok = false, error = 'Le titre est obligatoire.' }
    end

    local entry = {
        title = title,
        description = description,
        author = author.callsign ~= '' and author.callsign or author.name,
        createdAt = os.time(),
    }

    -- Identifiant stable de l'auteur : à utiliser comme clé en BDD.
    -- Volontairement NON stocké dans `entry` (qui est envoyé aux clients).
    local authorIdentifier = getIdentifier(src) -- luacheck: ignore

    if kind == 'report' then
        entry.id = nextId.report
        nextId.report = nextId.report + 1
        Reports[#Reports + 1] = entry
        -- >>> BASE DE DONNÉES :
        -- >>> MySQL.insert('INSERT INTO mdc_reports (title, description, author, created_at)
        -- >>>     VALUES (?, ?, ?, NOW())', { title, description, authorIdentifier })

    elseif kind == 'bolo' then
        entry.id = nextId.bolo
        nextId.bolo = nextId.bolo + 1
        Bolos[#Bolos + 1] = entry
        -- >>> BASE DE DONNÉES : INSERT INTO mdc_bolos (...)

    elseif kind == 'intervention' then
        entry.id = nextId.intervention
        nextId.intervention = nextId.intervention + 1
        entry.location = clean(payload.location, 80)
        entry.priority = (payload.priority == 'high' or payload.priority == 'low') and payload.priority or 'medium'
        entry.units = {}
        Interventions[#Interventions + 1] = entry
        -- >>> BASE DE DONNÉES : INSERT INTO mdc_interventions (...)
        pushToViewers('interventions', Interventions)
    else
        return { ok = false, error = 'Type de création invalide.' }
    end

    print(('^5[MDC]^0 Nouvelle création [%s #%d] "%s" par %s'):format(kind, entry.id, title, author.name))

    return { ok = true, id = entry.id }
end)
