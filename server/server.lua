--[[
    MDC Standalone - Serveur
    ------------------------
    STOCKAGE PERMANENT (sans base de données) :
      Les IDENTITÉS et les VÉHICULES sont sauvegardés dans des fichiers JSON
      à l'intérieur de la ressource, à chaque création / modification :
          data/identities.json
          data/vehicles.json
      Ils survivent aux déconnexions et aux redémarrages du serveur, restent
      accessibles via les recherches et dans le registre de leur créateur.

      Le script ne SUPPRIME JAMAIS une identité ou un véhicule. Seuls les cadres
      du serveur peuvent retirer une entrée, manuellement :
          1. Ouvrez le fichier JSON voulu et supprimez l'objet { ... } concerné
             (attention aux virgules : le fichier doit rester un JSON valide).
          2. Tapez "mdc_reload" dans la console serveur (ou redémarrez la ressource).
      Si un fichier est illisible (JSON invalide), le script refuse de l'écraser
      pour ne rien perdre, et affiche une erreur dans la console.

    Les INTERVENTIONS, elles, sont gardées en mémoire uniquement : elles
    disparaissent au redémarrage du serveur.

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
    CreateCooldown = 1500,  -- délai mini (ms) entre deux créations / modifications
    MaxSearchResults = 50,
    MaxEntries = 50,        -- nombre max d'antécédents / d'entrées d'historique par fiche
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
-- OUTILS TEXTE
-- =========================================================================

--- Coupe une chaîne à `maxLen` caractères sans casser un caractère accentué (UTF-8).
local function truncate(str, maxLen)
    local length = utf8.len(str)
    if length and length > maxLen then
        return str:sub(1, utf8.offset(str, maxLen + 1) - 1)
    end
    return length and str or str:sub(1, maxLen)
end

local function clean(str, maxLen)
    if type(str) ~= 'string' then
        if type(str) == 'number' then str = tostring(str) else return '' end
    end
    str = str:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return truncate(str, maxLen or 255)
end

-- Comme clean() mais conserve les retours à la ligne (zones de texte)
local function cleanMultiline(str, maxLen)
    if type(str) ~= 'string' then return '' end
    str = str:gsub('\r', ''):gsub('[\1-\9\11-\31]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return truncate(str, maxLen or 2000)
end

local function normalizePlate(plate)
    return (clean(plate, 16):upper():gsub('[^%w]', ''):sub(1, 8))
end

local function normalizeName(str)
    return (clean(str, 120):lower():gsub('%s+', ' '))
end

-- =========================================================================
-- STOCKAGE PERMANENT (fichiers JSON) : identités et véhicules
-- =========================================================================
local DATA_FILES = {
    identities = 'data/identities.json',
    vehicles   = 'data/vehicles.json',
}

local Store  = { identities = {}, vehicles = {} }
local NextId = { identities = 1, vehicles = 1 }
local Locked = {} -- [kind] = true si le fichier est corrompu (on ne l'écrase pas)

-- Mise à niveau des fiches créées avec une version précédente du MDC
local Migrations = {}

Migrations.identities = function(r)
    if type(r.licenseClass) == 'string' then
        r.licenseClass = r.licenseClass:gsub('^Prob %- ', 'Probatoire - ')
    end
    r.licenseClass = r.licenseClass or 'N/A'
    r.licenseStatus = r.licenseStatus or 'valid'
    r.condition = r.condition or 'none'
    if type(r.restrictions) ~= 'table' then r.restrictions = {} end
    if type(r.records) ~= 'table' then r.records = {} end
end

Migrations.vehicles = function(r)
    -- v1.1 : "owner" en texte libre et "status" (valid / stolen / wanted)
    if r.stolen == nil then r.stolen = r.status == 'stolen' end
    r.abandoned = r.abandoned == true
    r.commercial = r.commercial == true
    r.regStatus = r.regStatus or 'valid'
    r.insuranceStatus = r.insuranceStatus or 'none'
    r.ownerName = r.ownerName or r.owner or ''
    if type(r.history) ~= 'table' then r.history = {} end
end

--- Charge un fichier JSON en mémoire. Retourne true si le fichier existait.
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
            print(('^1[MDC] ERREUR : %s est illisible (JSON invalide). Les créations et modifications de ce type ' ..
                'sont bloquées pour ne pas écraser le fichier. Corrigez-le puis tapez mdc_reload.^0')
                :format(DATA_FILES[kind]))
        end
    end

    local maxId = 0
    for _, record in ipairs(list) do
        if type(record.id) == 'number' and record.id > maxId then maxId = record.id end
        Migrations[kind](record)
    end

    Store[kind] = list
    NextId[kind] = maxId + 1
    print(('^5[MDC]^0 %d entrée(s) chargée(s) depuis %s'):format(#list, DATA_FILES[kind]))
    return raw ~= nil
end

--- Écrit un fichier JSON sur le disque (indenté pour rester lisible par les cadres).
local function saveStore(kind)
    if Locked[kind] then return false end
    -- >>> BASE DE DONNÉES : remplacez par un INSERT / UPDATE ciblé
    local ok = SaveResourceFile(RESOURCE, DATA_FILES[kind], json.encode(Store[kind], { indent = true }), -1)
    if not ok then
        print(('^1[MDC] ERREUR : impossible d\'écrire %s. Vérifiez que le dossier "data" existe dans la ' ..
            'ressource et que le serveur a le droit d\'y écrire. LES DONNÉES NE SONT PAS SAUVEGARDÉES.^0')
            :format(DATA_FILES[kind]))
    end
    return ok
end

local function loadAll()
    for kind in pairs(DATA_FILES) do
        -- Premier démarrage : on crée le fichier pour vérifier tout de suite que l'écriture fonctionne
        if not loadStore(kind) and not Locked[kind] then saveStore(kind) end
    end
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
local Units = {}            -- [source] = { id, rpName, callsign, status, updatedAt }
local Viewers = {}          -- [source] = true (joueurs ayant le MDC ouvert)
local Interventions = {}    -- interventions en cours (perdues au redémarrage, c'est voulu)
local NextInterventionId = 1
local lastStatusChange = {}
local lastWrite = {}

-- =========================================================================
-- OUTILS
-- =========================================================================
local function hasAccess(src)
    if not Config.UseAcePermission then return true end
    return IsPlayerAceAllowed(src, Config.AcePermission)
end

--- Identifiant stable du joueur (licence Rockstar) : sert à retrouver "ses"
--- créations dans le registre, même après une reconnexion ou un redémarrage.
local function getIdentifier(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return ('source:%d'):format(src)
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

local function findBy(storeName, field, value, exceptId)
    for index, record in ipairs(Store[storeName]) do
        if record[field] == value and record.id ~= exceptId then return record, index end
    end
    return nil
end

local function ensureUnit(src)
    if not Units[src] then
        Units[src] = { id = src, rpName = '', callsign = '', status = 'available', updatedAt = os.time() }
    end
    return Units[src]
end

--- Nom affiché de l'agent : son nom RP (jamais le pseudo Steam/FiveM).
local function agentName(src)
    local unit = ensureUnit(src)
    local name = unit.rpName ~= '' and unit.rpName or 'Agent sans nom RP'
    return unit.callsign ~= '' and ('%s (%s)'):format(name, unit.callsign) or name
end

local function unitsList()
    local list = {}
    for _, unit in pairs(Units) do list[#list + 1] = unit end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function pushToViewers(kind, payload)
    for src in pairs(Viewers) do
        TriggerClientEvent('mdc:client:push', src, kind, payload)
    end
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
-- UNITÉS : profil (nom RP / matricule) et statut
-- =========================================================================
RegisterNetEvent('mdc:server:setProfile', function(rpName, callsign)
    local src = source
    if not hasAccess(src) then return end

    local unit = ensureUnit(src)
    unit.rpName = clean(rpName, 40)
    unit.callsign = (clean(callsign, 12):upper():gsub('[^%w%-]', ''))
    pushToViewers('units', unitsList())
end)

RegisterNetEvent('mdc:server:setStatus', function(status)
    local src = source
    if not hasAccess(src) then return end
    if type(status) ~= 'string' or not Statuses[status] then return end

    local unit = ensureUnit(src)
    local oldStatus = unit.status
    if status == oldStatus then return end

    local now = GetGameTimer()
    if lastStatusChange[src] and now - lastStatusChange[src] < Config.StatusCooldown then return end
    lastStatusChange[src] = now

    unit.status = status
    unit.updatedAt = os.time()

    -- Notification console (le pseudo FiveM y figure pour les cadres)
    print(('^5[MDC]^0 %s [%s] (ID %d) : ^3%s^0 -> ^2%s^0'):format(
        agentName(src), GetPlayerName(src) or '?', src, Statuses[oldStatus] or oldStatus, Statuses[status]))

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
    Units[src], Viewers[src], lastStatusChange[src], lastWrite[src] = nil, nil, nil, nil

    local key, changed = tostring(src), false
    for _, intervention in ipairs(Interventions) do
        if intervention.units[key] then
            intervention.units[key] = nil
            changed = true
        end
    end

    if wasUnit then pushToViewers('units', unitsList()) end
    if changed then pushToViewers('interventions', Interventions) end
end)

-- =========================================================================
-- LIENS IDENTITÉS <-> VÉHICULES
-- Un véhicule pointe vers l'identité de son propriétaire par son numéro (ownerId).
-- Les véhicules d'anciennes versions (propriétaire en texte libre) sont reliés par le nom.
-- =========================================================================
local function identityNames(identity)
    local first, middle, last = normalizeName(identity.firstname), normalizeName(identity.middlename), normalizeName(identity.lastname)
    local names = { [first .. ' ' .. last] = true, [last .. ' ' .. first] = true }
    if middle ~= '' then
        names[first .. ' ' .. middle .. ' ' .. last] = true
        names[last .. ' ' .. first .. ' ' .. middle] = true
    end
    return names
end

local function isOwner(identity, vehicle)
    if vehicle.ownerId ~= nil then return vehicle.ownerId == identity.id end
    local legacy = normalizeName(vehicle.ownerName)
    return legacy ~= '' and identityNames(identity)[legacy] == true
end

local function vehiclesOf(identity)
    local list = {}
    for _, vehicle in ipairs(Store.vehicles) do
        if isOwner(identity, vehicle) then list[#list + 1] = publicView(vehicle, 'vehicle') end
    end
    return list
end

local function ownerOf(vehicle)
    for _, identity in ipairs(Store.identities) do
        if isOwner(identity, vehicle) then return publicView(identity, 'identity') end
    end
    return nil
end

local function identityView(identity)
    local view = publicView(identity, 'identity')
    view.vehicles = vehiclesOf(identity)
    return view
end

local function vehicleView(vehicle)
    local view = publicView(vehicle, 'vehicle')
    view.ownerIdentity = ownerOf(vehicle)
    return view
end

local function identityLabel(identity)
    local names = { (identity.lastname or ''):upper(), identity.firstname or '' }
    if (identity.middlename or '') ~= '' then names[#names + 1] = identity.middlename end
    return ('%s (%s)'):format(table.concat(names, ' '), identity.dob or '?')
end

-- =========================================================================
-- VALIDATION : dates, heures, générateurs de numéros
-- =========================================================================

--- 'JJ/MM/AAAA' -> nombre comparable AAAAMMJJ (ou nil si invalide)
local function dateKey(date)
    if type(date) ~= 'string' then return nil end
    local d, m, y = date:match('^(%d%d)/(%d%d)/(%d%d%d%d)$')
    d, m, y = tonumber(d), tonumber(m), tonumber(y)
    if not d or d < 1 or d > 31 or m < 1 or m > 12 or y < 1900 or y > 2100 then return nil end
    return y * 10000 + m * 100 + d
end

local function todayKey()
    local t = os.date('*t')
    return t.year * 10000 + t.month * 100 + t.day
end

local function validTime(time)
    if type(time) ~= 'string' then return false end
    local h, m = time:match('^(%d%d):(%d%d)$')
    h, m = tonumber(h), tonumber(m)
    return h ~= nil and h <= 23 and m <= 59
end

local function uniqueValue(storeName, field, generator)
    while true do
        local value = generator()
        if not findBy(storeName, field, value) then return value end
    end
end

-- SSN : XXX-XX-XXXX (zone 001-899 hors 666)
local function genSSN()
    local area
    repeat area = math.random(1, 899) until area ~= 666
    return ('%03d-%02d-%04d'):format(area, math.random(1, 99), math.random(1, 9999))
end

-- N° de licence de conduite : 1 lettre + 7 chiffres
local function genLicenseNumber()
    return string.char(math.random(65, 90)) .. ('%07d'):format(math.random(0, 9999999))
end

-- VIN : 17 caractères (sans I, O ni Q, comme les vrais VIN)
local VIN_CHARS = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789'
local function genVIN()
    local chars = {}
    for i = 1, 17 do
        local k = math.random(1, #VIN_CHARS)
        chars[i] = VIN_CHARS:sub(k, k)
    end
    return table.concat(chars)
end

-- N° de police d'assurance : 2 lettres + 8 chiffres
local function genPolicyNumber()
    return string.char(math.random(65, 90), math.random(65, 90)) .. ('%08d'):format(math.random(0, 99999999))
end

--- Valide une liste d'antécédents (identité) ou d'historique (véhicule).
--- Chaque entrée exige : date d'émission, horaire, adresse, explication
--- (+ l'infraction pour une identité, le type d'infraction pour un véhicule).
local function buildEntries(list, label, types)
    local out = {}
    if type(list) ~= 'table' then return out end
    if #list > Config.MaxEntries then
        return nil, ('%s : %d entrées maximum.'):format(label, Config.MaxEntries)
    end

    for i, e in ipairs(list) do
        if type(e) ~= 'table' then return nil, ('%s n°%d invalide.'):format(label, i) end
        local name = ('%s n°%d'):format(label, i)
        local entry = {
            date    = clean(e.date, 10),
            time    = clean(e.time, 5),
            address = clean(e.address, 80),
            details = cleanMultiline(e.details, 1000),
        }

        if types then
            if not types[e.type] then return nil, name .. ' : choisissez le type d\'infraction.' end
            entry.type = e.type
        else
            entry.offense = clean(e.offense, 80)
            if entry.offense == '' then return nil, name .. ' : l\'infraction est obligatoire.' end
        end

        local key = dateKey(entry.date)
        if not key then return nil, name .. ' : date d\'émission invalide (JJ/MM/AAAA).' end
        if key > todayKey() then return nil, name .. ' : la date d\'émission ne peut pas être dans le futur.' end
        if not validTime(entry.time) then return nil, name .. ' : horaire invalide (HH:MM).' end
        if entry.address == '' then return nil, name .. ' : l\'adresse est obligatoire.' end
        if entry.details == '' then return nil, name .. ' : l\'explication est obligatoire.' end

        out[#out + 1] = entry
    end
    return out
end

-- =========================================================================
-- LISTES (doivent correspondre aux <option> de index.html)
-- =========================================================================
local LICENSE_CLASSES = {
    ['N/A'] = true,
    ['Class C - Standard'] = true,
    ['Class F - Lourd'] = true,
    ['Class E - Combiné'] = true,
    ['Class M - Moto'] = true,
    ['CDL A'] = true,
    ['CDL B'] = true,
    ['CDL C'] = true,
    ['Probatoire - Class CP'] = true,
    ['Probatoire - Class D'] = true,
    ['Probatoire - Class MP'] = true,
}
-- Condition de la licence ("disqualified" uniquement pour les licences CDL)
local LICENSE_STATUSES = { valid = true, suspended = true, revoked = true, cancelled = true, disqualified = true }
local RESTRICTIONS = { weapon = true }  -- weapon = Port d'arme (liste vide = N/A)
local CONDITIONS = { none = true, wanted = true, missing = true, deceased = true }

local REG_STATUSES = { valid = true, invalid = true, suspended = true }
local INSURANCE_STATUSES = { valid = true, invalid = true, cancelled = true, none = true }
local INSURERS = {
    ['State Farm'] = true, ['GEICO'] = true, ['Progressive'] = true, ['Allstate'] = true,
    ['USAA'] = true, ['Auto-Owners Assurance'] = true, ['Liberty Mutual'] = true, ['Farmers'] = true,
}
local HISTORY_TYPES = { administrative = true, parking = true }
local PRIORITIES = { low = true, medium = true, high = true }

-- =========================================================================
-- CONSTRUCTION / VALIDATION DES FICHES
-- Chaque builder retourne (fiche) ou (nil, message d'erreur).
--   p      : données reçues du formulaire
--   selfId : numéro de la fiche modifiée (nil pour une création)
--   me     : identifiant du joueur (licence)
-- =========================================================================
local Builders = {}

Builders.identities = function(p, selfId)
    local r = {
        firstname     = clean(p.firstname, 40),
        middlename    = clean(p.middlename, 40),
        lastname      = clean(p.lastname, 40),
        dob           = clean(p.dob, 10),
        address       = clean(p.address, 80),
        ssn           = clean(p.ssn, 11),
        job           = clean(p.job, 40),
        licenseClass  = LICENSE_CLASSES[p.licenseClass] and p.licenseClass or 'N/A',
        licenseStatus = 'valid',
        licenseNumber = '',
        licenseState  = '',
        restrictions  = {},
        condition     = CONDITIONS[p.condition] and p.condition or 'none',
        wantedReason  = '',
        wantedSince   = '',
    }

    -- Obligatoires : Prénom, Nom de famille, DoB, Adresse, SSN (généré si vide)
    if r.firstname == '' or r.lastname == '' then return nil, 'Le prénom et le nom de famille sont obligatoires.' end
    local dob = dateKey(r.dob)
    if not dob then return nil, 'Date de naissance invalide (format JJ/MM/AAAA).' end
    if dob > todayKey() then return nil, 'La date de naissance ne peut pas être dans le futur.' end
    if r.address == '' then return nil, 'L\'adresse est obligatoire.' end

    if r.ssn == '' then
        r.ssn = uniqueValue('identities', 'ssn', genSSN)
    elseif not r.ssn:match('^%d%d%d%-%d%d%-%d%d%d%d$') then
        return nil, 'SSN invalide (format XXX-XX-XXXX).'
    else
        local other = findBy('identities', 'ssn', r.ssn, selfId)
        if other then return nil, ('Ce SSN est déjà attribué (fiche n°%d).'):format(other.id) end
    end

    -- Licence de conduite (numéro, État et condition uniquement si une licence est choisie)
    if r.licenseClass ~= 'N/A' then
        r.licenseState = clean(p.licenseState, 40)
        r.licenseStatus = LICENSE_STATUSES[p.licenseStatus] and p.licenseStatus or 'valid'
        if r.licenseStatus == 'disqualified' and not r.licenseClass:match('^CDL') then
            return nil, 'La disqualification ne concerne que les licences CDL.'
        end

        r.licenseNumber = (clean(p.licenseNumber, 20):upper():gsub('[^%w%-]', ''))
        if r.licenseNumber == '' then
            r.licenseNumber = uniqueValue('identities', 'licenseNumber', genLicenseNumber)
        else
            local other = findBy('identities', 'licenseNumber', r.licenseNumber, selfId)
            if other then return nil, ('Ce numéro de licence est déjà attribué (fiche n°%d).'):format(other.id) end
        end
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
        if r.wantedSince ~= '' and not dateKey(r.wantedSince) then
            return nil, 'Date de début de recherche invalide (format JJ/MM/AAAA).'
        end
    end

    -- Antécédents
    local records, err = buildEntries(p.records, 'Antécédent')
    if not records then return nil, err end
    r.records = records

    local fullName = normalizeName(r.firstname .. ' ' .. r.lastname)
    for _, identity in ipairs(Store.identities) do
        if identity.id ~= selfId and identity.dob == r.dob and identityNames(identity)[fullName] then
            return nil, ('Cette identité existe déjà (fiche n°%d).'):format(identity.id)
        end
    end

    return r
end

Builders.vehicles = function(p, selfId, me)
    local r = {
        plate            = normalizePlate(p.plate),
        regStatus        = REG_STATUSES[p.regStatus] and p.regStatus or nil,
        model            = clean(p.model, 40),
        make             = clean(p.make, 40),
        color            = clean(p.color, 40),
        ownerName        = '',
        vin              = (clean(p.vin, 17):upper():gsub('[^%w]', '')),
        inspectionDate   = clean(p.inspectionDate, 10),
        insuranceStatus  = INSURANCE_STATUSES[p.insuranceStatus] and p.insuranceStatus or nil,
        insurancePolicy  = '',
        insuranceCompany = '',
        stolen           = p.stolen == true,
        abandoned        = p.abandoned == true,
        commercial       = p.commercial == true,
    }

    -- Obligatoires : immatriculation, statut, modèle, marque, couleur, VIN (généré), contrôle technique, assurance
    if r.plate == '' then return nil, 'L\'immatriculation est obligatoire (lettres et chiffres, 8 max).' end
    if not r.regStatus then return nil, 'Choisissez le statut de l\'immatriculation.' end
    if r.model == '' then return nil, 'Le modèle est obligatoire.' end
    if r.make == '' then return nil, 'La marque est obligatoire.' end
    if r.color == '' then return nil, 'La couleur est obligatoire.' end

    local year = clean(p.year, 4)
    if year ~= '' then
        local maxYear = os.date('*t').year + 1
        r.year = tonumber(year)
        if not year:match('^%d%d%d%d$') or r.year < 1900 or r.year > maxYear then
            return nil, ('Année invalide (1900 à %d).'):format(maxYear)
        end
    end

    -- Propriétaire : uniquement une identité créée par ce joueur
    local ownerId = tonumber(p.ownerId)
    if ownerId then
        local owner = findBy('identities', 'id', ownerId)
        if not owner or owner.createdBy ~= me then
            return nil, 'Propriétaire invalide : choisissez une identité que vous avez créée.'
        end
        r.ownerId = ownerId
        r.ownerName = identityLabel(owner)
    end

    if r.vin == '' then
        r.vin = uniqueValue('vehicles', 'vin', genVIN)
    elseif #r.vin ~= 17 or not r.vin:match('^[A-HJ-NPR-Z0-9]+$') then
        return nil, 'VIN invalide (17 caractères, sans I, O ni Q).'
    else
        local other = findBy('vehicles', 'vin', r.vin, selfId)
        if other then return nil, ('Ce VIN est déjà enregistré (fiche n°%d).'):format(other.id) end
    end

    -- Contrôle technique : obligatoire et jamais après la date du jour
    local inspection = dateKey(r.inspectionDate)
    if not inspection then return nil, 'Date du dernier contrôle technique invalide (JJ/MM/AAAA).' end
    if inspection > todayKey() then
        return nil, 'La date du dernier contrôle technique ne peut pas être postérieure à aujourd\'hui.'
    end

    -- Assurance : statut obligatoire ; police + compagnie obligatoires sauf "Non-Assuré"
    if not r.insuranceStatus then return nil, 'Choisissez le statut de l\'assurance.' end
    if r.insuranceStatus ~= 'none' then
        r.insurancePolicy = (clean(p.insurancePolicy, 20):upper():gsub('[^%w%-]', ''))
        if r.insurancePolicy == '' then r.insurancePolicy = genPolicyNumber() end
        if not INSURERS[p.insuranceCompany] then return nil, 'Choisissez la compagnie d\'assurance.' end
        r.insuranceCompany = p.insuranceCompany
    end

    local history, err = buildEntries(p.history, 'Historique', HISTORY_TYPES)
    if not history then return nil, err end
    r.history = history

    local other = findBy('vehicles', 'plate', r.plate, selfId)
    if other then return nil, ('L\'immatriculation %s est déjà enregistrée (fiche n°%d).'):format(r.plate, other.id) end

    return r
end

local KIND_TO_STORE = { identity = 'identities', vehicle = 'vehicles' }

local function checkWriteCooldown(src)
    local now = GetGameTimer()
    if lastWrite[src] and now - lastWrite[src] < Config.CreateCooldown then return false end
    lastWrite[src] = now
    return true
end

-- =========================================================================
-- CRÉATIONS
-- =========================================================================
RegisterMDCCallback('create', function(src, payload)
    if payload.kind == 'intervention' then
        local title = clean(payload.title, 80)
        if title == '' then return { ok = false, error = 'Le titre est obligatoire.' } end
        if not checkWriteCooldown(src) then return { ok = false, error = 'Patientez un instant.' } end

        local intervention = {
            id            = NextInterventionId,
            title         = title,
            location      = clean(payload.location, 80),
            priority      = PRIORITIES[payload.priority] and payload.priority or 'medium',
            description   = cleanMultiline(payload.description, 2000),
            units         = {},
            createdAt     = os.time(),
            createdByName = agentName(src),
        }
        NextInterventionId = NextInterventionId + 1
        Interventions[#Interventions + 1] = intervention
        pushToViewers('interventions', Interventions)
        return { ok = true, id = intervention.id }
    end

    local storeName = KIND_TO_STORE[payload.kind]
    if not storeName then return { ok = false, error = 'Type de création invalide.' } end
    if Locked[storeName] then
        return { ok = false, error = 'Enregistrement bloqué : fichier de données corrompu (voir console serveur).' }
    end

    local me = getIdentifier(src)
    local record, err = Builders[storeName](payload, nil, me)
    if not record then return { ok = false, error = err } end
    if not checkWriteCooldown(src) then return { ok = false, error = 'Patientez un instant avant une nouvelle création.' } end

    record.id = NextId[storeName]
    record.createdAt = os.time()
    record.createdByName = agentName(src)
    record.createdBy = me -- privé : jamais envoyé aux clients (voir publicView)

    Store[storeName][#Store[storeName] + 1] = record
    if not saveStore(storeName) then
        table.remove(Store[storeName]) -- non sauvegardé : on annule
        return { ok = false, error = 'Erreur d\'écriture sur le serveur : rien n\'a été enregistré (voir console).' }
    end
    NextId[storeName] = NextId[storeName] + 1

    print(('^5[MDC]^0 Nouvelle fiche [%s n°%d] par %s [%s]'):format(payload.kind, record.id, record.createdByName, GetPlayerName(src) or '?'))
    return { ok = true, id = record.id }
end)

-- =========================================================================
-- MODIFICATION (uniquement ses propres identités / véhicules)
-- =========================================================================
RegisterMDCCallback('update', function(src, payload)
    local storeName = KIND_TO_STORE[payload.kind]
    local id = tonumber(payload.id)
    if not storeName or not id then return { ok = false, error = 'Fiche invalide.' } end
    if Locked[storeName] then
        return { ok = false, error = 'Modification bloquée : fichier de données corrompu (voir console serveur).' }
    end

    local me = getIdentifier(src)
    local old, index = findBy(storeName, 'id', id)
    if not old then return { ok = false, error = 'Fiche introuvable.' } end
    if old.createdBy ~= me then return { ok = false, error = 'Vous ne pouvez modifier que vos propres créations.' } end

    local record, err = Builders[storeName](payload, id, me)
    if not record then return { ok = false, error = err } end
    if not checkWriteCooldown(src) then return { ok = false, error = 'Patientez un instant.' } end

    -- On conserve les informations de création
    record.id = old.id
    record.createdAt = old.createdAt
    record.createdBy = old.createdBy
    record.createdByName = old.createdByName
    record.updatedAt = os.time()
    record.updatedByName = agentName(src)

    Store[storeName][index] = record
    if not saveStore(storeName) then
        Store[storeName][index] = old
        return { ok = false, error = 'Erreur d\'écriture sur le serveur : modification annulée (voir console).' }
    end

    print(('^5[MDC]^0 Fiche modifiée [%s n°%d] par %s [%s]'):format(payload.kind, id, record.updatedByName, GetPlayerName(src) or '?'))
    return { ok = true, id = id }
end)

-- =========================================================================
-- REGISTRE : identités et véhicules créés par le joueur (permanents)
-- =========================================================================
RegisterMDCCallback('getRegistry', function(src)
    local me = getIdentifier(src)
    local records = {}

    for _, identity in ipairs(Store.identities) do
        if identity.createdBy == me then records[#records + 1] = identityView(identity) end
    end
    for _, vehicle in ipairs(Store.vehicles) do
        if vehicle.createdBy == me then records[#records + 1] = vehicleView(vehicle) end
    end

    table.sort(records, function(a, b) return (a.createdAt or 0) > (b.createdAt or 0) end)
    return { ok = true, records = records }
end)

-- Propriétaires possibles d'un véhicule : les identités créées par le joueur
RegisterMDCCallback('getMyIdentities', function(src)
    local me = getIdentifier(src)
    local list = {}
    for _, identity in ipairs(Store.identities) do
        if identity.createdBy == me then
            list[#list + 1] = { id = identity.id, label = identityLabel(identity) }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return { ok = true, identities = list }
end)

-- =========================================================================
-- RECHERCHES
--   Identité : nom de famille + date de naissance obligatoires,
--              prénom et SSN facultatifs pour affiner.
--   Véhicule : immatriculation ou VIN.
-- =========================================================================
RegisterMDCCallback('search', function(_, payload)
    local results = {}

    if payload.type == 'identity' then
        local lastname = normalizeName(payload.lastname)
        local dob = clean(payload.dob, 10)
        if lastname == '' or not dateKey(dob) then
            return { ok = false, error = 'Le nom de famille et la date de naissance (JJ/MM/AAAA) sont obligatoires.' }
        end
        local firstname = normalizeName(payload.firstname)
        local ssnDigits = clean(payload.ssn, 11):gsub('%D', '')

        for _, identity in ipairs(Store.identities) do
            if normalizeName(identity.lastname) == lastname and identity.dob == dob
                and (firstname == '' or normalizeName(identity.firstname):sub(1, #firstname) == firstname)
                and (ssnDigits == '' or (identity.ssn or ''):gsub('%D', '') == ssnDigits) then
                results[#results + 1] = identityView(identity)
                if #results >= Config.MaxSearchResults then break end
            end
        end

    elseif payload.type == 'vehicle' then
        local query = clean(payload.query, 20):upper():gsub('[^%w]', '')
        if #query < 2 then return { ok = false, error = 'Saisissez au moins 2 caractères.' } end

        for _, vehicle in ipairs(Store.vehicles) do
            if (vehicle.plate or ''):find(query, 1, true) or (vehicle.vin or ''):find(query, 1, true) then
                results[#results + 1] = vehicleView(vehicle)
                if #results >= Config.MaxSearchResults then break end
            end
        end
    else
        return { ok = false, error = 'Type de recherche invalide.' }
    end

    return { ok = true, results = results }
end)

-- =========================================================================
-- INTERVENTIONS (en mémoire : effacées au redémarrage du serveur)
-- =========================================================================
RegisterMDCCallback('getInterventions', function()
    return { ok = true, interventions = Interventions }
end)

RegisterMDCCallback('updateIntervention', function(src, payload)
    local id = tonumber(payload.id)
    local action = payload.action

    for index, intervention in ipairs(Interventions) do
        if intervention.id == id then
            local unit = ensureUnit(src)
            local key = tostring(src)

            if action == 'attach' then
                intervention.units[key] = unit.callsign ~= '' and unit.callsign or agentName(src)
            elseif action == 'detach' then
                intervention.units[key] = nil
            elseif action == 'close' then
                table.remove(Interventions, index)
                print(('^5[MDC]^0 Intervention #%d clôturée par %s'):format(id, agentName(src)))
            else
                return { ok = false, error = 'Action invalide.' }
            end

            pushToViewers('interventions', Interventions)
            return { ok = true }
        end
    end

    return { ok = false, error = 'Intervention introuvable ou déjà clôturée.' }
end)
