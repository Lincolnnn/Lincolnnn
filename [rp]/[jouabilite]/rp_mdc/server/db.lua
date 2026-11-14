--[[
    MDC - BASE DE DONNÉES MySQL / MariaDB (oxmysql)
    ------------------------------------------------
    Toutes les données du MDC sont enregistrées dans MySQL : fiches (identités, véhicules, rapports, BOLO), unités et
    leurs membres connectés, statuts, interventions / incidents, unités affectées, notes, fiches liées, messagerie
    (unités, dispatch, civils), agents (nom RP, grade), réglages (mode Dispatch) et journal des actions.

    Principe :
      - au démarrage : migrations (sql/migrations/*.sql, une seule fois chacune), import UNIQUE des anciens fichiers
        data/*.json (si la table est vide), puis chargement en mémoire (lecture rapide pour le jeu) ;
      - chaque modification est écrite tout de suite dans MySQL par une FILE D'ÉCRITURE séquentielle : les requêtes
        partent dans l'ordre (jamais une ancienne version après une nouvelle), une seule écriture par objet modifié
        plusieurs fois dans la même image ;
      - requêtes préparées uniquement (paramètres « ? »), jamais de texte du joueur collé dans le SQL ;
      - le serveur FiveM est le SEUL à écrire dans ces tables (le site du dispatch lit MySQL et passe par l'API de la
        ressource pour agir) : pas de doublons, identifiants attribués ici.
    Les valeurs NULL passent par NULLIF(?, 0) / NULLIF(?, '') : oxmysql ne transmet pas les nil d'un tableau Lua.
]]

MDCDB = {
    ready = false,       -- migrations faites et données chargées
    failed = nil,        -- message d'erreur si la base est injoignable
    knownCalls = {},     -- [id] = true : appels présents dans mdc_calls (clé étrangère des rapports)
    identifierOf = nil,  -- fonction(src) -> identifiant (défini par server.lua)
}

local RESOURCE = GetCurrentResourceName()
local MIGRATIONS = { '001_init' } -- fichiers de sql/migrations, dans l'ordre

-- =========================================================================
-- FILE D'ÉCRITURE
-- =========================================================================
local queue, pending, running = {}, {}, false
local onIdle = {} -- fonctions appelées quand la file est vide (signal au site du dispatch)

local function runQueue()
    if running then return end
    running = true
    CreateThread(function()
        while #queue > 0 do
            local job = table.remove(queue, 1)
            if job.key then pending[job.key] = nil end
            local ok, err = pcall(job.fn)
            if not ok then print(('^1[MDC] MySQL : écriture échouée (%s) : %s^0'):format(job.key or job.label or '?', tostring(err))) end
        end
        running = false
        for _, fn in ipairs(onIdle) do pcall(fn) end
    end)
end

--- Ajoute une écriture à la file. `key` : une seule écriture en attente par clé (l'état le plus récent est lu au
--- moment de l'écriture).
function MDCDB.enqueue(fn, key, label)
    if key then
        if pending[key] then return end
        pending[key] = true
    end
    queue[#queue + 1] = { fn = fn, key = key, label = label }
    runQueue()
end

function MDCDB.onIdle(fn) onIdle[#onIdle + 1] = fn end
function MDCDB.busy() return running or #queue > 0 end

-- Raccourcis (dans un thread : oxmysql attend la réponse)
local function query(sql, params) return MySQL.query.await(sql, params or {}) end
local function exec(sql, params) return MySQL.update.await(sql, params or {}) end
local function scalar(sql, params) return MySQL.scalar.await(sql, params or {}) end

local function nz(v) return tonumber(v) or 0 end          -- nombre (0 = NULL via NULLIF)
local function s(v, max)                                   -- texte (tronqué à la taille de la colonne)
    if v == nil then return '' end
    v = tostring(v)
    if max and #v > max then v = v:sub(1, max) end
    return v
end
local function b(v) return v and 1 or 0 end

-- =========================================================================
-- MIGRATIONS
-- =========================================================================
local function splitSql(text)
    local list = {}
    text = text:gsub('\r', '')
    local clean = {}
    for line in (text .. '\n'):gmatch('(.-)\n') do
        if not line:match('^%s*%-%-') then clean[#clean + 1] = line end
    end
    for stmt in (table.concat(clean, '\n') .. ';'):gmatch('(.-);') do
        if stmt:match('%S') then list[#list + 1] = stmt end
    end
    return list
end

local function migrate()
    exec([[CREATE TABLE IF NOT EXISTS mdc_schema_migrations (
        version VARCHAR(64) NOT NULL PRIMARY KEY, applied_at INT UNSIGNED NOT NULL DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    for _, version in ipairs(MIGRATIONS) do
        local done = scalar('SELECT COUNT(*) FROM mdc_schema_migrations WHERE version = ?', { version })
        if nz(done) == 0 then
            local text = LoadResourceFile(RESOURCE, ('sql/migrations/%s.sql'):format(version))
            if not text then error(('fichier sql/migrations/%s.sql introuvable'):format(version)) end
            for _, stmt in ipairs(splitSql(text)) do exec(stmt) end
            exec('INSERT INTO mdc_schema_migrations (version, applied_at) VALUES (?, ?)', { version, os.time() })
            print(('^5[MDC]^0 MySQL : migration %s appliquée.'):format(version))
        end
    end
end

-- =========================================================================
-- RÉGLAGES
-- =========================================================================
local Settings = {}

function MDCDB.getSetting(name, default)
    local v = Settings[name]
    if v == nil then return default end
    return v
end

function MDCDB.setSetting(name, value)
    Settings[name] = value ~= nil and tostring(value) or nil
    local v = Settings[name] or ''
    MDCDB.enqueue(function()
        exec('INSERT INTO mdc_settings (name, value, updated_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value), updated_at = VALUES(updated_at)',
            { name, v, os.time() })
    end, 'setting:' .. name)
end

-- =========================================================================
-- FICHES (identités, véhicules, rapports, BOLO) : colonnes indexées + fiche complète en JSON
-- =========================================================================
local STORES = {
    identities = {
        table = 'mdc_identities',
        cols = { 'created_by', 'lastname', 'firstname', 'dob', 'ssn' },
        values = function(r) return { s(r.createdBy, 80), s(r.lastname, 40), s(r.firstname, 40), s(r.dob, 10), s(r.ssn, 11) } end,
        nullable = {},
    },
    vehicles = {
        table = 'mdc_vehicles',
        cols = { 'created_by', 'plate', 'vin', 'owner_id' },
        values = function(r) return { s(r.createdBy, 80), s(r.plate, 16), s(r.vin, 17), nz(r.ownerId) } end,
        -- propriétaire : seulement s'il existe (ancienne fiche supprimée -> sans lien, la fiche garde ownerId)
        nullable = { owner_id = '(SELECT i.id FROM mdc_identities i WHERE i.id = NULLIF(?, 0))' },
    },
    reports = {
        table = 'mdc_reports',
        cols = { 'number', 'type', 'call_id', 'created_by' },
        values = function(r)
            local callId = type(r.call) == 'table' and tonumber(r.call.id) or nil
            if callId and (not MDCDB.knownCalls[callId] or r.call.session ~= MDCDB.SESSION) then callId = nil end
            return { s(r.number, 12), s(r.type, 32), nz(callId), s(r.createdBy, 80) }
        end,
        nullable = { call_id = '(SELECT c.id FROM mdc_calls c WHERE c.id = NULLIF(?, 0))' },
    },
    bolos = {
        table = 'mdc_bolos',
        cols = { 'number', 'kind', 'agency' },
        values = function(r) return { s(r.number, 12), s(r.kind, 16), s(r.agency, 16) } end,
        nullable = {},
    },
}
MDCDB.SESSION = 'db' -- lien rapport <-> appel : les appels gardent leur numéro interne d'un démarrage à l'autre

local StoreCache = { identities = {}, vehicles = {}, reports = {}, bolos = {} } -- [kind][id] = JSON enregistré

local function upsertSql(def)
    local cols = { 'id' }
    local marks = { '?' }
    local updates = {}
    for _, c in ipairs(def.cols) do
        cols[#cols + 1] = c
        marks[#marks + 1] = def.nullable[c] or '?'
        updates[#updates + 1] = ('%s = VALUES(%s)'):format(c, c)
    end
    for _, c in ipairs({ 'data', 'created_at', 'updated_at' }) do
        cols[#cols + 1] = c
        marks[#marks + 1] = '?'
        if c ~= 'created_at' then updates[#updates + 1] = ('%s = VALUES(%s)'):format(c, c) end
    end
    return ('INSERT INTO %s (%s) VALUES (%s) ON DUPLICATE KEY UPDATE %s'):format(def.table, table.concat(cols, ', '),
        table.concat(marks, ', '), table.concat(updates, ', '))
end

--- Lit toutes les fiches d'un type (au démarrage)
function MDCDB.loadStore(kind)
    local def = STORES[kind]
    local rows = query(('SELECT id, data FROM %s ORDER BY id'):format(def.table))
    local list = {}
    for _, row in ipairs(rows or {}) do
        local ok, record = pcall(json.decode, row.data)
        if ok and type(record) == 'table' then
            record.id = tonumber(row.id)
            list[#list + 1] = record
        else
            print(('^1[MDC] MySQL : fiche %s n°%s illisible (JSON), ignorée.^0'):format(kind, tostring(row.id)))
        end
    end
    return list
end

--- Mémorise l'état chargé (après les mises à niveau) : seules les fiches modifiées ensuite seront réécrites
function MDCDB.primeStore(kind, list)
    local cache = {}
    for _, r in ipairs(list) do cache[r.id] = json.encode(r) end
    StoreCache[kind] = cache
end

--- Écrit les fiches ajoutées / modifiées et supprime les fiches retirées (appelé après chaque modification)
function MDCDB.syncStore(kind, list)
    local def, cache = STORES[kind], StoreCache[kind]
    local upserts, deletes, seen = {}, {}, {}
    for _, r in ipairs(list) do
        if type(r.id) == 'number' then
            seen[r.id] = true
            local encoded = json.encode(r)
            if cache[r.id] ~= encoded then
                cache[r.id] = encoded
                local params = { r.id }
                for _, v in ipairs(def.values(r)) do params[#params + 1] = v end
                params[#params + 1] = encoded
                params[#params + 1] = nz(r.createdAt)
                params[#params + 1] = nz(r.updatedAt or r.createdAt)
                upserts[#upserts + 1] = params
            end
        end
    end
    for id in pairs(cache) do
        if not seen[id] then deletes[#deletes + 1] = id; cache[id] = nil end
    end
    if #upserts == 0 and #deletes == 0 then return true end
    local sql = upsertSql(def)
    MDCDB.enqueue(function()
        for _, params in ipairs(upserts) do exec(sql, params) end
        for _, id in ipairs(deletes) do exec(('DELETE FROM %s WHERE id = ?'):format(def.table), { id }) end
    end, nil, 'store:' .. kind)
    return true
end

--- Import unique des anciens fichiers data/<kind>.json (table vide et jamais importé)
local function importJson(kind, file)
    local flag = 'imported_' .. kind
    if MDCDB.getSetting(flag) then return end
    local count = nz(scalar(('SELECT COUNT(*) FROM %s'):format(STORES[kind].table)))
    local raw = LoadResourceFile(RESOURCE, file)
    if count == 0 and raw and raw:match('%S') then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            local def, sql, n = STORES[kind], upsertSql(STORES[kind]), 0
            for _, r in ipairs(decoded) do
                if type(r) == 'table' and type(r.id) == 'number' then
                    local params = { r.id }
                    -- les anciens rapports pointaient vers des appels effacés : sans lien
                    for i, v in ipairs(def.values(r)) do params[#params + 1] = (kind == 'reports' and i == 3) and 0 or v end
                    params[#params + 1] = json.encode(r)
                    params[#params + 1] = nz(r.createdAt)
                    params[#params + 1] = nz(r.updatedAt or r.createdAt)
                    exec(sql, params)
                    n = n + 1
                end
            end
            print(('^5[MDC]^0 MySQL : %d fiche(s) importée(s) depuis %s.'):format(n, file))
        else
            print(('^1[MDC] MySQL : %s illisible, non importé (corrigez-le puis redémarrez).^0'):format(file))
            return
        end
    end
    Settings[flag] = '1'
    exec('INSERT INTO mdc_settings (name, value, updated_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value)', { flag, '1', os.time() })
end

-- =========================================================================
-- AGENTS (nom RP, grade)
-- =========================================================================
local Agents = {} -- [identifier] = { rpName, grade, agency }

function MDCDB.agent(identifier) return Agents[identifier] end

function MDCDB.saveAgent(identifier, fields, serverId)
    if not identifier or identifier == '' then return end
    local a = Agents[identifier] or { rpName = '', grade = '', agency = '' }
    for k, v in pairs(fields) do a[k] = v end
    Agents[identifier] = a
    MDCDB.enqueue(function()
        exec([[INSERT INTO mdc_agents (identifier, rp_name, grade, agency, last_server_id, last_seen) VALUES (?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE rp_name = VALUES(rp_name), grade = VALUES(grade), agency = VALUES(agency),
            last_server_id = VALUES(last_server_id), last_seen = VALUES(last_seen)]],
            { identifier, s(a.rpName, 40), s(a.grade, 40), s(a.agency, 16), nz(serverId), os.time() })
    end, 'agent:' .. identifier)
end

-- =========================================================================
-- UNITÉS, MEMBRES, STATUTS
-- =========================================================================
function MDCDB.saveUnit(unit)
    MDCDB.enqueue(function()
        local shared = unit.shared and json.encode(unit.shared) or ''
        exec([[INSERT INTO mdc_units (id, agency, name, tag, color, status, memo, shared, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), ?, ?)
            ON DUPLICATE KEY UPDATE agency = VALUES(agency), name = VALUES(name), tag = VALUES(tag), color = VALUES(color),
            status = VALUES(status), memo = VALUES(memo), shared = VALUES(shared), updated_at = VALUES(updated_at)]],
            { unit.id, s(unit.agency, 16), s(unit.name, 30), s(unit.tag, 10), s(unit.color, 16), s(unit.status, 16),
              s(unit.memo), shared, nz(unit.createdAt), nz(unit.updatedAt) })
        -- membres connectés (identifiant + n° de joueur)
        exec('DELETE FROM mdc_unit_members WHERE unit_id = ?', { unit.id })
        for key in pairs(unit.members or {}) do
            local identifier = unit.memberIds and unit.memberIds[key]
            if identifier then
                exec('INSERT INTO mdc_unit_members (unit_id, identifier, server_id, joined_at) VALUES (?, ?, ?, ?)',
                    { unit.id, identifier, tonumber(key), os.time() })
            end
        end
    end, 'unit:' .. unit.id)
end

function MDCDB.deleteUnit(id)
    MDCDB.enqueue(function() exec('DELETE FROM mdc_units WHERE id = ?', { id }) end, nil, 'unit-delete')
end

function MDCDB.statusLog(unitId, status, by, source)
    MDCDB.enqueue(function()
        exec('INSERT INTO mdc_unit_status_log (unit_id, status, changed_by, source, created_at) VALUES (?, ?, ?, ?, ?)',
            { unitId, s(status, 16), s(by, 80), s(source, 16), os.time() })
    end, nil, 'status-log')
end

--- Unités enregistrées. `connected(serverId, identifier)` : le joueur est-il encore là (redémarrage de la ressource
--- avec des joueurs en jeu : ils restent dans leur unité) ?
function MDCDB.loadUnits(connected)
    local units = {}
    for _, row in ipairs(query('SELECT * FROM mdc_units ORDER BY id') or {}) do
        local shared = nil
        if row.shared and row.shared ~= '' then
            local ok, decoded = pcall(json.decode, row.shared)
            if ok and type(decoded) == 'table' then shared = decoded end
        end
        units[#units + 1] = {
            id = tonumber(row.id), agency = row.agency, name = row.name, tag = row.tag or '', color = row.color,
            status = row.status, memo = row.memo or '', shared = shared, createdAt = nz(row.created_at),
            updatedAt = nz(row.updated_at), members = {}, memberIds = {},
        }
    end
    local byId = {}
    for _, u in ipairs(units) do byId[u.id] = u end
    local stale = 0
    for _, row in ipairs(query('SELECT unit_id, identifier, server_id FROM mdc_unit_members') or {}) do
        local unit = byId[tonumber(row.unit_id)]
        local key = tostring(row.server_id)
        if unit and connected(tonumber(row.server_id), row.identifier) then
            unit.members[key] = true
            unit.memberIds[key] = row.identifier
        else
            stale = stale + 1
        end
    end
    if stale > 0 then
        -- joueurs déconnectés pendant l'arrêt : retirés de leur unité
        for _, u in ipairs(units) do MDCDB.saveUnit(u) end
    end
    return units
end

-- =========================================================================
-- INTERVENTIONS / INCIDENTS : appel, unités affectées, notes, fiches liées
-- =========================================================================
local CALL_SQL = [[INSERT INTO mdc_calls (id, number, kind, title, caller, phone, priority, response_code, agency,
    ideal_units, address, cross_street, block, sector, description, unit_name, backup, requested_by, coords, closed,
    clear_code, dispatch_state, dispatch_reason, dispatch_by, dispatch_at, created_by, created_by_name, created_at,
    updated_at, updated_by_name, closed_at, closed_by_name, next_note_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, NULLIF(?, 0), ?, NULLIF(?, 0), ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), ?, NULLIF(?, ''),
    NULLIF(?, ''), ?, ?, NULLIF(?, 0), ?, ?, ?, NULLIF(?, 0), ?, NULLIF(?, 0), ?, ?)
    ON DUPLICATE KEY UPDATE number = VALUES(number), kind = VALUES(kind), title = VALUES(title), caller = VALUES(caller),
    phone = VALUES(phone), priority = VALUES(priority), response_code = VALUES(response_code), agency = VALUES(agency),
    ideal_units = VALUES(ideal_units), address = VALUES(address), cross_street = VALUES(cross_street),
    block = VALUES(block), sector = VALUES(sector), description = VALUES(description), unit_name = VALUES(unit_name),
    backup = VALUES(backup), requested_by = VALUES(requested_by), coords = VALUES(coords), closed = VALUES(closed),
    clear_code = VALUES(clear_code), dispatch_state = VALUES(dispatch_state), dispatch_reason = VALUES(dispatch_reason),
    dispatch_by = VALUES(dispatch_by), dispatch_at = VALUES(dispatch_at), updated_at = VALUES(updated_at),
    updated_by_name = VALUES(updated_by_name), closed_at = VALUES(closed_at), closed_by_name = VALUES(closed_by_name),
    next_note_id = VALUES(next_note_id)]]

local function callParams(c)
    local coords = ''
    if type(c.coords) == 'table' then coords = ('%.2f,%.2f,%.2f'):format(nz(c.coords.x), nz(c.coords.y), nz(c.coords.z)) end
    return {
        c.id, s(c.number, 12), s(c.kind, 16), s(c.title, 60), s(c.caller, 60), s(c.phone, 20), s(c.priority, 16),
        nz(c.responseCode), s(c.agency, 32), nz(c.idealUnits), s(c.address, 80), s(c.crossStreet, 80), s(c.block, 40),
        s(c.sector, 40), s(c.description), s(c.unitName, 30), b(c.backup), s(c.requestedBy, 16), coords, b(c.closed),
        s(c.clear, 1), s(c.dispatch, 16), s(c.dispatchReason, 200), s(c.dispatchBy, 60), nz(c.dispatchAt),
        s(c.createdBy, 80), s(c.createdByName, 60), nz(c.createdAt), nz(c.updatedAt), s(c.updatedByName, 60),
        nz(c.closedAt), s(c.closedByName, 60), nz(c.nextNoteId) > 0 and nz(c.nextNoteId) or 1,
    }
end

--- Enregistre l'appel complet (une écriture par appel modifié plusieurs fois dans la même image)
function MDCDB.saveCall(call)
    MDCDB.knownCalls[call.id] = true
    MDCDB.enqueue(function()
        if call.deleted then return end
        exec(CALL_SQL, callParams(call))
        exec('DELETE FROM mdc_call_units WHERE call_id = ?', { call.id })
        for key in pairs(call.units or {}) do
            local unitId = tonumber(key)
            if unitId then
                exec('INSERT IGNORE INTO mdc_call_units (call_id, unit_id, assigned_at) SELECT ?, id, ? FROM mdc_units WHERE id = ?',
                    { call.id, nz(call.unitsAt and call.unitsAt[key]) > 0 and nz(call.unitsAt[key]) or os.time(), unitId })
            end
        end
        for _, n in ipairs(call.notes or {}) do
            exec([[INSERT INTO mdc_call_notes (call_id, note_id, unit_id, unit_name, unit_tag, unit_color, author_name, text,
                backup, dispatch, created_at, updated_at) VALUES (?, ?, NULLIF(?, 0), ?, ?, ?, ?, ?, NULLIF(?, ''), ?, ?, NULLIF(?, 0))
                ON DUPLICATE KEY UPDATE text = VALUES(text), updated_at = VALUES(updated_at)]],
                { call.id, n.id, nz(n.unitId), s(n.unitName, 30), s(n.unitTag, 10), s(n.unitColor, 16), s(n.authorName, 60),
                  s(n.text), s(n.backup, 8), b(n.dispatch), nz(n.createdAt), nz(n.updatedAt) })
        end
        exec('DELETE FROM mdc_call_links WHERE call_id = ?', { call.id })
        for _, l in ipairs(call.links or {}) do
            exec('INSERT IGNORE INTO mdc_call_links (call_id, kind, record_id, added_by, added_at) VALUES (?, ?, ?, ?, ?)',
                { call.id, s(l.kind, 16), nz(l.recordId), s(l.addedBy, 60), nz(l.addedAt) })
        end
    end, 'call:' .. call.id)
end

function MDCDB.deleteCall(id)
    MDCDB.knownCalls[id] = nil
    MDCDB.enqueue(function() exec('DELETE FROM mdc_calls WHERE id = ?', { id }) end, nil, 'call-delete')
end

--- Appels à garder en mémoire : en cours, en attente, et terminés depuis moins de `keepSeconds`
function MDCDB.loadCalls(keepSeconds)
    for _, row in ipairs(query('SELECT id FROM mdc_calls') or {}) do MDCDB.knownCalls[tonumber(row.id)] = true end
    local since = os.time() - (keepSeconds or 0)
    local rows = query('SELECT * FROM mdc_calls WHERE closed = 0 OR closed_at >= ? ORDER BY id', { since }) or {}
    local calls, byId = {}, {}
    for _, r in ipairs(rows) do
        local coords
        if r.coords and r.coords ~= '' then
            local x, y, z = tostring(r.coords):match('^([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)$')
            if x then coords = { x = tonumber(x), y = tonumber(y), z = tonumber(z) } end
        end
        local call = {
            id = tonumber(r.id), number = r.number, kind = r.kind, title = r.title, caller = r.caller ~= '' and r.caller or nil,
            phone = r.phone ~= '' and r.phone or nil, priority = r.priority ~= '' and r.priority or nil,
            responseCode = tonumber(r.response_code), agency = r.agency, idealUnits = tonumber(r.ideal_units),
            address = r.address, crossStreet = r.cross_street, block = r.block, sector = r.sector ~= '' and r.sector or nil,
            description = r.description or '', unitName = r.unit_name ~= '' and r.unit_name or nil,
            backup = tonumber(r.backup) == 1 or nil, requestedBy = r.requested_by ~= '' and r.requested_by or nil,
            coords = coords, closed = tonumber(r.closed) == 1, clear = r.clear_code,
            dispatch = r.dispatch_state, dispatchReason = r.dispatch_reason ~= '' and r.dispatch_reason or nil,
            dispatchBy = r.dispatch_by ~= '' and r.dispatch_by or nil, dispatchAt = tonumber(r.dispatch_at),
            createdBy = r.created_by, createdByName = r.created_by_name, createdAt = nz(r.created_at),
            updatedAt = tonumber(r.updated_at), updatedByName = r.updated_by_name ~= '' and r.updated_by_name or nil,
            closedAt = tonumber(r.closed_at), closedByName = r.closed_by_name ~= '' and r.closed_by_name or nil,
            nextNoteId = nz(r.next_note_id), units = {}, unitsAt = {}, notes = {}, links = {}, reports = {},
        }
        calls[#calls + 1] = call
        byId[call.id] = call
    end
    if #calls > 0 then
        for _, r in ipairs(query('SELECT * FROM mdc_call_units ORDER BY assigned_at') or {}) do
            local call = byId[tonumber(r.call_id)]
            if call then
                call.units[tostring(r.unit_id)] = true
                call.unitsAt[tostring(r.unit_id)] = nz(r.assigned_at)
            end
        end
        for _, r in ipairs(query('SELECT * FROM mdc_call_notes ORDER BY call_id, note_id') or {}) do
            local call = byId[tonumber(r.call_id)]
            if call then
                call.notes[#call.notes + 1] = {
                    id = tonumber(r.note_id), unitId = tonumber(r.unit_id), unitName = r.unit_name, unitTag = r.unit_tag,
                    unitColor = r.unit_color, authorName = r.author_name, text = r.text, backup = r.backup,
                    dispatch = tonumber(r.dispatch) == 1 or nil, createdAt = nz(r.created_at), updatedAt = tonumber(r.updated_at),
                }
            end
        end
        for _, r in ipairs(query('SELECT * FROM mdc_call_links ORDER BY added_at') or {}) do
            local call = byId[tonumber(r.call_id)]
            if call then
                call.links[#call.links + 1] = { kind = r.kind, recordId = tonumber(r.record_id), addedBy = r.added_by, addedAt = nz(r.added_at) }
            end
        end
    end
    local maxId = nz(scalar('SELECT COALESCE(MAX(id), 0) FROM mdc_calls'))
    return calls, maxId
end

-- =========================================================================
-- SYNCHRONISATION DES LISTES EN MÉMOIRE (appelée après chaque modification affichée)
-- Chaque unité / appel n'est réécrit que si son contenu a changé ; un élément retiré de la liste est supprimé.
-- =========================================================================
local Signatures = { units = {}, calls = {} }

local function signature(item)
    local ok, encoded = pcall(json.encode, item)
    return ok and encoded or tostring(os.clock())
end

function MDCDB.primeUnits(list)
    Signatures.units = {}
    for _, u in ipairs(list) do Signatures.units[u.id] = signature(u) end
end

function MDCDB.primeCalls(list)
    Signatures.calls = {}
    for _, c in ipairs(list) do Signatures.calls[c.id] = signature(c) end
end

function MDCDB.syncUnits(list)
    if not MDCDB.ready then return end
    local seen = {}
    for _, u in ipairs(list) do
        seen[u.id] = true
        local sig = signature(u)
        if Signatures.units[u.id] ~= sig then
            Signatures.units[u.id] = sig
            MDCDB.saveUnit(u)
        end
    end
    for id in pairs(Signatures.units) do
        if not seen[id] then Signatures.units[id] = nil; MDCDB.deleteUnit(id) end
    end
end

--- `list` : appels en mémoire ; un appel absent de la liste n'est supprimé que s'il est marqué `deleted`
--- (suppression par un admin) : les appels anciens peuvent ne pas être chargés en mémoire.
function MDCDB.syncCalls(list, deleted)
    if not MDCDB.ready then return end
    for _, c in ipairs(list) do
        local sig = signature(c)
        if Signatures.calls[c.id] ~= sig then
            Signatures.calls[c.id] = sig
            MDCDB.saveCall(c)
        end
    end
    for _, c in ipairs(deleted or {}) do
        Signatures.calls[c.id] = nil
        MDCDB.deleteCall(c.id)
    end
end

-- =========================================================================
-- MESSAGERIE
-- =========================================================================
local nextMessageId = 1

function MDCDB.newMessageId()
    local id = nextMessageId
    nextMessageId = nextMessageId + 1
    return id
end

function MDCDB.saveMessage(m)
    MDCDB.enqueue(function()
        exec([[INSERT INTO mdc_messages (id, channel, call_id, sender_type, sender_unit_id, sender_name, sender_identifier, text, created_at)
            SELECT ?, ?, (SELECT id FROM mdc_calls WHERE id = NULLIF(?, 0)), ?, NULLIF(?, 0), ?, ?, ?, ?]],
            { m.id, s(m.channel, 32), nz(m.callId), s(m.senderType, 16), nz(m.from), s(m.author, 60), s(m.identifier, 80),
              s(m.text), nz(m.at) })
    end, nil, 'message')
end

function MDCDB.setRead(channel, reader, lastId)
    MDCDB.enqueue(function()
        exec([[INSERT INTO mdc_message_reads (channel, reader, last_id) VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE last_id = GREATEST(last_id, VALUES(last_id))]], { s(channel, 32), s(reader, 96), nz(lastId) })
    end, 'read:' .. channel .. ':' .. reader)
end

--- Derniers messages de chaque canal (`perChannel` au plus) et pointeurs de lecture
function MDCDB.loadMessages(perChannel)
    local rows = query([[SELECT * FROM (
            SELECT m.*, ROW_NUMBER() OVER (PARTITION BY channel ORDER BY id DESC) AS rn FROM mdc_messages m
        ) t WHERE rn <= ? ORDER BY id]], { perChannel }) or {}
    local channels = {}
    for _, r in ipairs(rows) do
        local ch = channels[r.channel] or { messages = {}, read = {} }
        channels[r.channel] = ch
        ch.messages[#ch.messages + 1] = {
            id = tonumber(r.id), channel = r.channel, callId = tonumber(r.call_id), senderType = r.sender_type,
            from = tonumber(r.sender_unit_id), author = r.sender_name, identifier = r.sender_identifier ~= '' and r.sender_identifier or nil,
            text = r.text, at = nz(r.created_at),
        }
    end
    for _, r in ipairs(query('SELECT * FROM mdc_message_reads') or {}) do
        local ch = channels[r.channel] or { messages = {}, read = {} }
        channels[r.channel] = ch
        ch.read[r.reader] = nz(r.last_id)
    end
    nextMessageId = nz(scalar('SELECT COALESCE(MAX(id), 0) FROM mdc_messages')) + 1
    return channels
end

-- =========================================================================
-- JOURNAL DES ACTIONS IMPORTANTES
-- =========================================================================
function MDCDB.log(source, actorId, actorName, action, callId, unitId, details)
    local text = type(details) == 'table' and json.encode(details) or s(details)
    MDCDB.enqueue(function()
        exec([[INSERT INTO mdc_action_log (source, actor_id, actor_name, action, call_id, unit_id, details, created_at)
            VALUES (?, ?, ?, ?, NULLIF(?, 0), NULLIF(?, 0), ?, ?)]],
            { s(source, 16), s(actorId, 80), s(actorName, 60), s(action, 48), nz(callId), nz(unitId), text, os.time() })
    end, nil, 'log')
end

-- =========================================================================
-- DÉMARRAGE
-- =========================================================================
--- Migrations, import des anciens fichiers JSON, réglages, agents. `files` : { kind = 'data/xxx.json' }
function MDCDB.start(files)
    migrate()
    for _, r in ipairs(query('SELECT name, value FROM mdc_settings') or {}) do Settings[r.name] = r.value end
    -- ordre fixe : les identités avant les véhicules (propriétaire), les appels n'existent pas encore pour les rapports
    for _, kind in ipairs({ 'identities', 'vehicles', 'reports', 'bolos' }) do
        if files[kind] then importJson(kind, files[kind]) end
    end
    for _, r in ipairs(query('SELECT identifier, rp_name, grade, agency FROM mdc_agents') or {}) do
        Agents[r.identifier] = { rpName = r.rp_name, grade = r.grade, agency = r.agency }
    end
end
