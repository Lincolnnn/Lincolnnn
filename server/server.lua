--[[
    MDC Standalone - Serveur
    ------------------------
    STOCKAGE PERSISTANT (sans base de données) :
      Les identités, véhicules et interventions sont sauvegardés dans des fichiers
      JSON à l'intérieur de la ressource :
          data/identities.json
          data/vehicles.json
          data/interventions.json

      Le script ne SUPPRIME JAMAIS une entrée de ces fichiers. Seuls les cadres
      du serveur peuvent retirer une entrée, manuellement :
          1. Ouvrez le fichier JSON voulu et supprimez l'objet { ... } concerné
             (attention aux virgules : le fichier doit rester un JSON valide).
          2. Tapez "mdc_reload" dans la console serveur (ou redémarrez la ressource).
      Si un fichier est illisible (JSON invalide), le script refuse de l'écraser
      pour ne rien perdre, et affiche une erreur dans la console.

    ⚠ Lors d'une mise à jour du script, NE remplacez PAS le dossier data/.

    BASE DE DONNÉES : pour passer à MySQL plus tard, remplacez uniquement les
    fonctions loadStore() / saveStore() (voir les commentaires ">>> BASE DE DONNÉES").
]]

-- =========================================================================
-- CONFIGURATION
-- =========================================================================
local Config = {
    -- Permissions ACE (optionnel). Si true, seuls les joueurs ayant l'ACE
    -- "mdc.use" peuvent utiliser le MDC. Exemple dans server.cfg :
    --   add_ace group.police mdc.use allow
    --   add_principal identifier.license:xxxxxxxx group.police
    UseAcePermission = false,
    AcePermission = 'mdc.use',

    StatusCooldown = 500,   -- délai mini (ms) entre deux changements de statut
    CreateCooldown = 1500,  -- délai mini (ms) entre deux créations
    MaxSearchResults = 50,
}

local RESOURCE = GetCurrentResourceName()

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
-- STOCKAGE PERSISTANT (fichiers JSON)
-- =========================================================================
local DATA_FILES = {
    identities    = 'data/identities.json',
    vehicles      = 'data/vehicles.json',
    interventions = 'data/interventions.json',
}

local Store  = { identities = {}, vehicles = {}, interventions = {} }
local NextId = { identities = 1, vehicles = 1, interventions = 1 }
local Locked = {} -- [kind] = true si le fichier est corrompu (on ne l'écrase pas)

--- Charge un fichier JSON en mémoire.
local function loadStore(kind)
    -- >>> BASE DE DONNÉES : remplacez par un SELECT * FROM mdc_<kind>
    local raw = LoadResourceFile(RESOURCE, DATA_FILES[kind])
    local list = {}
    Locked[kind] = nil

    if raw and raw:match('%S') then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            for _, record in ipairs(decoded) do
                if type(record) == 'table' then list[#list + 1] = record end
            end
        else
            Locked[kind] = true
            print(('^1[MDC] ERREUR : %s est illisible (JSON invalide). Les nouvelles créations de ce type ' ..
                'sont bloquées pour ne pas écraser le fichier. Corrigez-le puis tapez mdc_reload.^0')
                :format(DATA_FILES[kind]))
        end
    end

    local maxId = 0
    for _, record in ipairs(list) do
        if type(record.id) == 'number' and record.id > maxId then maxId = record.id end
        if kind == 'interventions' then record.units = {} end -- les unités assignées ne survivent pas à un reboot
    end

    Store[kind] = list
    NextId[kind] = maxId + 1
    print(('^5[MDC]^0 %d entrée(s) chargée(s) depuis %s'):format(#list, DATA_FILES[kind]))
end

--- Écrit un fichier JSON sur le disque (indenté pour rester lisible par les cadres).
local function saveStore(kind)
    if Locked[kind] then return false end
    -- >>> BASE DE DONNÉES : remplacez par un INSERT / UPDATE ciblé
    local ok = SaveResourceFile(RESOURCE, DATA_FILES[kind], json.encode(Store[kind], { indent = true }), -1)
    if not ok then
        print(('^1[MDC] ERREUR : impossible d\'écrire %s (le dossier data/ existe-t-il ?)^0'):format(DATA_FILES[kind]))
    end
    return ok
end

local function loadAll()
    for kind in pairs(DATA_FILES) do loadStore(kind) end
end

loadAll()

-- Rechargement manuel après modification des fichiers (console serveur uniquement)
RegisterCommand('mdc_reload', function(source)
    if source ~= 0 then return end
    loadAll()
    print('^5[MDC]^0 Fichiers de données rechargés.')
end, true)

-- =========================================================================
-- ÉTAT EN MÉMOIRE (non persistant)
-- =========================================================================
local Units = {}            -- [source] = { id, name, callsign, status, updatedAt }
local Viewers = {}          -- [source] = true (joueurs ayant le MDC ouvert)
local lastStatusChange = {}
local lastCreate = {}

-- =========================================================================
-- OUTILS
-- =========================================================================
local function hasAccess(src)
    if not Config.UseAcePermission then return true end
    return IsPlayerAceAllowed(src, Config.AcePermission)
end

--- Identifiant stable du joueur : sert à retrouver "ses" créations dans le registre.
local function getIdentifier(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return ('source:%d'):format(src)
end

local function clean(str, maxLen)
    if type(str) ~= 'string' then
        if type(str) == 'number' then str = tostring(str) else return '' end
    end
    str = str:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return str:sub(1, maxLen or 255)
end

-- Comme clean() mais conserve les retours à la ligne (zones de texte)
local function cleanMultiline(str, maxLen)
    if type(str) ~= 'string' then return '' end
    str = str:gsub('\r', ''):gsub('[\1-\9\11-\31]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return str:sub(1, maxLen or 2000)
end

local function normalizePlate(plate)
    return clean(plate, 16):upper():gsub('[^%w]', ''):sub(1, 8)
end

local function normalizeName(str)
    return (clean(str, 120):lower():gsub('%s+', ' '))
end

--- Copie d'un enregistrement sans les données privées (licence du créateur).
local function publicView(record, kind)
    local copy = {}
    for k, v in pairs(record) do
        if k ~= 'createdBy' then copy[k] = v end
    end
    copy.kind = kind
    return copy
end

local function unitsList()
    local list = {}
    for _, unit in pairs(Units) do list[#list + 1] = unit end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function openInterventions()
    local list = {}
    for _, intervention in ipairs(Store.interventions) do
        if not intervention.closed then list[#list + 1] = publicView(intervention, 'intervention') end
    end
    return list
end

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

local function authorName(src)
    local unit = ensureUnit(src)
    return unit.callsign ~= '' and ('%s (%s)'):format(unit.name, unit.callsign) or unit.name
end

-- =========================================================================
-- SYSTÈME DE CALLBACKS (requête client -> réponse serveur)
-- =========================================================================
local Handlers = {}

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

    local now = GetGameTimer()
    if lastStatusChange[src] and now - lastStatusChange[src] < Config.StatusCooldown then return end
    lastStatusChange[src] = now

    unit.status = status
    unit.updatedAt = os.time()

    -- Notification console
    print(('^5[MDC]^0 %s%s (ID %d) : ^3%s^0 -> ^2%s^0'):format(
        unit.name,
        unit.callsign ~= '' and (' [' .. unit.callsign .. ']') or '',
        src,
        Statuses[oldStatus] or oldStatus,
        Statuses[status]
    ))

    -- >>> BASE DE DONNÉES : historiser le changement de statut si besoin

    pushToViewers('units', unitsList())
end)

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
    return { ok = true, units = unitsList() }
end)

AddEventHandler('playerDropped', function()
    local src = source
    local wasUnit = Units[src] ~= nil
    Units[src], Viewers[src], lastStatusChange[src], lastCreate[src] = nil, nil, nil, nil

    local key, changed = tostring(src), false
    for _, intervention in ipairs(Store.interventions) do
        if intervention.units and intervention.units[key] then
            intervention.units[key] = nil
            changed = true
        end
    end

    if wasUnit then pushToViewers('units', unitsList()) end
    if changed then pushToViewers('interventions', openInterventions()) end
end)

-- =========================================================================
-- LIENS ENTRE IDENTITÉS ET VÉHICULES
-- (le propriétaire d'un véhicule est saisi sous la forme "Prénom Nom",
--  "Prénom Middle Nom" ou "Nom Prénom" ; majuscules ignorées)
-- =========================================================================

--- Toutes les écritures acceptées du nom d'une identité : { ["john doe"] = true, ... }
local function identityNames(identity)
    local first, middle, last = normalizeName(identity.firstname), normalizeName(identity.middlename), normalizeName(identity.lastname)
    local names = {
        [first .. ' ' .. last] = true,
        [last .. ' ' .. first] = true,
    }
    if middle ~= '' then
        names[first .. ' ' .. middle .. ' ' .. last] = true
        names[last .. ' ' .. first .. ' ' .. middle] = true
    end
    return names
end

local function vehiclesOf(identity)
    local names = identityNames(identity)
    local list = {}
    for _, vehicle in ipairs(Store.vehicles) do
        if names[normalizeName(vehicle.owner)] then
            list[#list + 1] = publicView(vehicle, 'vehicle')
        end
    end
    return list
end

local function ownerOf(vehicle)
    local owner = normalizeName(vehicle.owner)
    if owner == '' then return nil end
    for _, identity in ipairs(Store.identities) do
        if identityNames(identity)[owner] then return publicView(identity, 'identity') end
    end
    return nil
end

--- L'identité correspond-elle à la recherche ? (nom, prénom, middle name, DoB, SSN, n° de permis)
local function identityMatches(identity, query)
    for name in pairs(identityNames(identity)) do
        if name:find(query, 1, true) then return true end
    end

    local fields = { identity.dob, identity.ssn, identity.licenseNumber }
    for _, value in ipairs(fields) do
        if type(value) == 'string' and value:lower():find(query, 1, true) then return true end
    end

    -- SSN saisi sans tirets (ex : 123456789) : uniquement si la recherche ne contient que des chiffres
    if query:match('^[%d%-%s]+$') then
        local digits = query:gsub('%D', '')
        if #digits >= 4 and type(identity.ssn) == 'string' and identity.ssn:gsub('%D', ''):find(digits, 1, true) then
            return true
        end
    end
    return false
end

-- =========================================================================
-- RECHERCHES (identités et immatriculations enregistrées via "Créations")
-- =========================================================================
RegisterMDCCallback('search', function(_, payload)
    local query = clean(payload.query, 64):lower()
    if #query < 2 then
        return { ok = false, error = 'Saisissez au moins 2 caractères.' }
    end

    local results = {}

    if payload.type == 'identity' then
        for _, identity in ipairs(Store.identities) do
            if identityMatches(identity, query) then
                local entry = publicView(identity, 'identity')
                entry.vehicles = vehiclesOf(identity)
                results[#results + 1] = entry
                if #results >= Config.MaxSearchResults then break end
            end
        end

    elseif payload.type == 'vehicle' then
        local plateQuery = normalizePlate(query)
        for _, vehicle in ipairs(Store.vehicles) do
            local plateMatch = plateQuery ~= '' and (vehicle.plate or ''):find(plateQuery, 1, true)
            local modelMatch = (vehicle.model or ''):lower():find(query, 1, true)
            if plateMatch or modelMatch then
                local entry = publicView(vehicle, 'vehicle')
                entry.ownerIdentity = ownerOf(vehicle)
                results[#results + 1] = entry
                if #results >= Config.MaxSearchResults then break end
            end
        end
    else
        return { ok = false, error = 'Type de recherche invalide.' }
    end

    return { ok = true, results = results }
end)

-- =========================================================================
-- INTERVENTIONS
-- =========================================================================
RegisterMDCCallback('getInterventions', function()
    return { ok = true, interventions = openInterventions() }
end)

RegisterMDCCallback('updateIntervention', function(src, payload)
    local id = tonumber(payload.id)
    local action = payload.action

    for _, intervention in ipairs(Store.interventions) do
        if intervention.id == id and not intervention.closed then
            local unit = ensureUnit(src)
            local key = tostring(src)
            intervention.units = intervention.units or {}

            if action == 'attach' then
                intervention.units[key] = unit.callsign ~= '' and unit.callsign or unit.name
            elseif action == 'detach' then
                intervention.units[key] = nil
            elseif action == 'close' then
                -- Une intervention clôturée n'est PAS supprimée : elle reste dans le
                -- fichier (et dans le registre de son créateur) avec closed = true.
                intervention.closed = true
                intervention.closedAt = os.time()
                intervention.closedByName = authorName(src)
                intervention.units = {}
                saveStore('interventions')
                print(('^5[MDC]^0 Intervention #%d clôturée par %s'):format(id, unit.name))
            else
                return { ok = false, error = 'Action invalide.' }
            end

            pushToViewers('interventions', openInterventions())
            return { ok = true }
        end
    end

    return { ok = false, error = 'Intervention introuvable ou déjà clôturée.' }
end)

-- =========================================================================
-- CRÉATIONS (identités, véhicules, interventions)
-- =========================================================================
local VEHICLE_STATUSES = { valid = true, stolen = true, wanted = true }
local PRIORITIES = { low = true, medium = true, high = true }

-- Listes de l'identité (doivent correspondre aux <option> de index.html)
local LICENSE_CLASSES = {
    ['N/A'] = true,
    ['Class C - Standard'] = true,
    ['Class F - Lourd'] = true,
    ['Class E - Combiné'] = true,
    ['Class M - Moto'] = true,
    ['CDL A'] = true,
    ['CDL B'] = true,
    ['CDL C'] = true,
    ['Prob - Class CP'] = true,
    ['Prob - Class D'] = true,
    ['Prob - Class MP'] = true,
}
local RESTRICTIONS = { weapon = true }  -- weapon = Port d'arme (liste vide = N/A)
local CONDITIONS = { none = true, wanted = true, missing = true, deceased = true }

--- Date au format JJ/MM/AAAA
local function validDate(date)
    if type(date) ~= 'string' then return false end
    local d, m, y = date:match('^(%d%d)/(%d%d)/(%d%d%d%d)$')
    d, m, y = tonumber(d), tonumber(m), tonumber(y)
    return d and d >= 1 and d <= 31 and m >= 1 and m <= 12 and y >= 1900 and y <= 2100 or false
end

local function ssnTaken(ssn)
    for _, identity in ipairs(Store.identities) do
        if identity.ssn == ssn then return identity end
    end
    return nil
end

--- Génère un Social Security Number unique au format XXX-XX-XXXX
local function generateSSN()
    while true do
        local area = math.random(1, 899)
        if area ~= 666 then
            local ssn = ('%03d-%02d-%04d'):format(area, math.random(1, 99), math.random(1, 9999))
            if not ssnTaken(ssn) then return ssn end
        end
    end
end

-- Chaque builder valide les données reçues et retourne (record) ou (nil, erreur)
local Builders = {}

Builders.identities = function(p)
    local r = {
        firstname     = clean(p.firstname, 40),
        middlename    = clean(p.middlename, 40),
        lastname      = clean(p.lastname, 40),
        dob           = clean(p.dob, 10),
        address       = clean(p.address, 80),
        ssn           = clean(p.ssn, 11),
        job           = clean(p.job, 40),
        licenseClass  = LICENSE_CLASSES[p.licenseClass] and p.licenseClass or 'N/A',
        licenseNumber = clean(p.licenseNumber, 20):upper(),
        licenseState  = clean(p.licenseState, 40),
        restrictions  = {},
        condition     = CONDITIONS[p.condition] and p.condition or 'none',
        wantedReason  = '',
        wantedSince   = '',
    }

    -- Champs obligatoires : Prénom, Nom, DoB, Adresse (+ SSN, généré si vide)
    if r.firstname == '' or r.lastname == '' then return nil, 'Le prénom et le nom de famille sont obligatoires.' end
    if not validDate(r.dob) then return nil, 'Date de naissance invalide (format JJ/MM/AAAA).' end
    if r.address == '' then return nil, 'L\'adresse est obligatoire.' end

    if r.ssn == '' then
        r.ssn = generateSSN()
    elseif not r.ssn:match('^%d%d%d%-%d%d%-%d%d%d%d$') then
        return nil, 'SSN invalide (format XXX-XX-XXXX).'
    else
        local other = ssnTaken(r.ssn)
        if other then return nil, ('Ce SSN est déjà attribué (fiche #%d).'):format(other.id) end
    end

    -- Interdictions : liste de clés connues, sans doublon (vide = N/A)
    if type(p.restrictions) == 'table' then
        local seen = {}
        for _, key in ipairs(p.restrictions) do
            if RESTRICTIONS[key] and not seen[key] then
                seen[key] = true
                r.restrictions[#r.restrictions + 1] = key
            end
        end
    end

    -- Raison et date de début uniquement si la personne est recherchée
    if r.condition == 'wanted' then
        r.wantedReason = cleanMultiline(p.wantedReason, 500)
        r.wantedSince = clean(p.wantedSince, 10)
        if r.wantedSince ~= '' and not validDate(r.wantedSince) then
            return nil, 'Date de début de recherche invalide (format JJ/MM/AAAA).'
        end
    end

    local fullName = normalizeName(r.firstname .. ' ' .. r.lastname)
    for _, identity in ipairs(Store.identities) do
        if identity.dob == r.dob and identityNames(identity)[fullName] then
            return nil, ('Cette identité existe déjà (fiche #%d).'):format(identity.id)
        end
    end

    return r
end

Builders.vehicles = function(p)
    local r = {
        plate  = normalizePlate(p.plate),
        model  = clean(p.model, 40),
        color  = clean(p.color, 30),
        owner  = clean(p.owner, 80),
        status = VEHICLE_STATUSES[p.status] and p.status or 'valid',
        notes  = cleanMultiline(p.notes, 1000),
    }

    if r.plate == '' then return nil, 'La plaque est obligatoire (lettres et chiffres, 8 max).' end
    if r.model == '' then return nil, 'Le modèle est obligatoire.' end

    for _, vehicle in ipairs(Store.vehicles) do
        if vehicle.plate == r.plate then
            return nil, ('La plaque %s est déjà enregistrée (fiche #%d).'):format(r.plate, vehicle.id)
        end
    end

    return r
end

Builders.interventions = function(p)
    local r = {
        title       = clean(p.title, 80),
        location    = clean(p.location, 80),
        priority    = PRIORITIES[p.priority] and p.priority or 'medium',
        description = cleanMultiline(p.description, 2000),
        closed      = false,
        units       = {},
    }
    if r.title == '' then return nil, 'Le titre est obligatoire.' end
    return r
end

local KIND_TO_STORE = { identity = 'identities', vehicle = 'vehicles', intervention = 'interventions' }

RegisterMDCCallback('create', function(src, payload)
    local storeName = KIND_TO_STORE[payload.kind]
    if not storeName then return { ok = false, error = 'Type de création invalide.' } end

    if Locked[storeName] then
        return { ok = false, error = 'Enregistrement bloqué : fichier de données corrompu (voir console serveur).' }
    end

    local now = GetGameTimer()
    if lastCreate[src] and now - lastCreate[src] < Config.CreateCooldown then
        return { ok = false, error = 'Patientez un instant avant une nouvelle création.' }
    end

    local record, err = Builders[storeName](payload)
    if not record then return { ok = false, error = err } end

    lastCreate[src] = now
    record.id = NextId[storeName]
    record.createdAt = os.time()
    record.createdByName = authorName(src)
    record.createdBy = getIdentifier(src) -- privé : jamais envoyé aux clients (voir publicView)

    NextId[storeName] = NextId[storeName] + 1
    Store[storeName][#Store[storeName] + 1] = record

    if not saveStore(storeName) then
        return { ok = false, error = 'Erreur d\'écriture sur le serveur (voir console).' }
    end

    print(('^5[MDC]^0 Nouvelle création [%s #%d] par %s'):format(payload.kind, record.id, record.createdByName))

    if storeName == 'interventions' then
        pushToViewers('interventions', openInterventions())
    end

    return { ok = true, id = record.id }
end)

-- =========================================================================
-- REGISTRE : uniquement les créations du joueur qui consulte
-- =========================================================================
RegisterMDCCallback('getRegistry', function(src)
    local me = getIdentifier(src)
    local records = {}

    for storeName, kind in pairs({ identities = 'identity', vehicles = 'vehicle', interventions = 'intervention' }) do
        for _, record in ipairs(Store[storeName]) do
            if record.createdBy == me then
                local entry = publicView(record, kind)
                if kind == 'identity' then entry.vehicles = vehiclesOf(record) end
                if kind == 'vehicle' then entry.ownerIdentity = ownerOf(record) end
                records[#records + 1] = entry
            end
        end
    end

    table.sort(records, function(a, b) return (a.createdAt or 0) > (b.createdAt or 0) end)
    return { ok = true, records = records }
end)
