--[[
    MDC Standalone - Serveur
    ------------------------
    STOCKAGE PERMANENT (sans base de données) :
      Les IDENTITÉS, les VÉHICULES et les RAPPORTS sont sauvegardés dans des
      fichiers JSON à l'intérieur de la ressource, à chaque création / modification :
          data/identities.json
          data/vehicles.json
          data/reports.json
          data/bolos.json      (BOLOs actifs)
      Ils survivent aux déconnexions et aux redémarrages du serveur. Identités et
      véhicules restent accessibles via les recherches et dans le registre de leur
      créateur ; les rapports dans l'onglet "Rapports".

      Le script ne SUPPRIME JAMAIS une identité, un véhicule ou un rapport (seuls les BOLOs
      peuvent être supprimés depuis le MDC, quand ils ne sont plus d'actualité). Seuls les cadres
      du serveur peuvent retirer une entrée, manuellement :
          1. Ouvrez le fichier JSON voulu et supprimez l'objet { ... } concerné
             (attention aux virgules : le fichier doit rester un JSON valide).
          2. Tapez "mdc_reload" dans la console serveur (ou redémarrez la ressource).
      Si un fichier est illisible (JSON invalide), le script refuse de l'écraser
      pour ne rien perdre, et affiche une erreur dans la console.

    Les UNITÉS, INTERVENTIONS et INCIDENTS sont gardés en mémoire uniquement :
    ils disparaissent au redémarrage du serveur.

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
    MaxReportResults = 200, -- nombre max de rapports affichés dans la liste
    MaxUnitMembers = 4,     -- nombre max de joueurs dans une unité
    MaxSharedHistory = 100, -- historique de recherches partagé par une unité
    MaxBolos = 200,         -- nombre max de BOLOs actifs

    -- Débit (octets/s) des réponses "latentes" (modèles et contenu des rapports,
    -- qui peuvent dépasser la taille d'un événement classique)
    LatentBps = 200000,
}

local RESOURCE = GetCurrentResourceName()

-- Statuts d'une unité : clé technique -> libellé (doit correspondre à index.html)
local Statuses = {
    available   = 'Disponible',
    en_route    = 'En route',
    on_scene    = 'Sur place',
    unavailable = 'Indisponible',
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
    reports    = 'data/reports.json',
    bolos      = 'data/bolos.json',
}

local Store  = { identities = {}, vehicles = {}, reports = {}, bolos = {} }
local NextId = { identities = 1, vehicles = 1, reports = 1, bolos = 1 }
local Locked = {} -- [kind] = true si le fichier est corrompu (on ne l'écrase pas)

-- Mise à niveau des fiches créées avec une version précédente du MDC
local Migrations = {}

-- Anciennes fiches (État écrit en toutes lettres) -> code de l'État
local STATE_NAMES = {
    georgia = 'GA', florida = 'FL', floride = 'FL', tennessee = 'TN',
    ['south carolina'] = 'SC', ['north carolina'] = 'NC', alabama = 'AL',
}

Migrations.identities = function(r)
    if type(r.licenseClass) == 'string' then
        r.licenseClass = r.licenseClass:gsub('^Prob %- ', 'Probatoire - ')
    end
    r.licenseClass = r.licenseClass or 'N/A'
    r.licenseStatus = r.licenseStatus or 'valid'
    -- v1.13 : État d'émission sous forme de code (GA, FL…)
    if type(r.licenseState) == 'string' then
        r.licenseState = STATE_NAMES[r.licenseState:lower():gsub('^%s+', ''):gsub('%s+$', '')] or r.licenseState
    end
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

Migrations.reports = function(r)
    if type(r.data) ~= 'table' then r.data = {} end
    -- v1.12 : le Warning commence par le type d'infraction (routière si un véhicule était renseigné)
    if r.type == 'warning' and r.data.category == nil then
        r.data.category = (type(r.data.plate) == 'string' and r.data.plate ~= '') and 'road' or 'other'
    end
end

Migrations.bolos = function(r)
    if type(r.vehicles) ~= 'table' then r.vehicles = {} end
    if type(r.origins) ~= 'table' then r.origins = {} end
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
-- ÉTAT EN MÉMOIRE (non persistant : remis à zéro au redémarrage du serveur)
-- =========================================================================
local Viewers = {}          -- [source] = true (joueurs ayant le MDC ouvert)
local Units = {}            -- unités créées par les joueurs (section UNITÉS)
local PlayerUnit = {}       -- [source] = id de l'unité rejointe par le joueur
local Interventions = {}    -- interventions (civils) et incidents (police)
local lastWrite = {}
local createIntervention    -- défini dans la section INTERVENTIONS
local reportLinks           -- défini dans la section RAPPORTS
local shareUnitSearch       -- défini dans la section ESPACE PARTAGÉ D'UNITÉ
local pushHud               -- défini dans la section HUD
local bolosFor              -- défini dans la section BOLOs

-- Identifiant de cette session du serveur : un rapport n'est relié "en direct" à une
-- intervention que si le lien date de la session en cours (les interventions sont
-- effacées au redémarrage, leurs numéros internes repartent de 1).
local SessionId = ('%d-%d'):format(os.time(), math.random(1000, 9999))

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

--- Nom RP du joueur ('' s'il n'en a pas encore défini).
--- Gardé dans l'état du joueur (state bag "rpName"), partagé avec le chat (ressource rp_chat,
--- commande /nomrp) : il n'est enregistré nulle part et disparaît à la déconnexion.
local function rpNameOf(src)
    -- Re-nettoyé à chaque lecture : un client modifié peut écrire lui-même dans son état
    return clean(Player(src).state.rpName, 40)
end

--- Nom affiché d'un joueur : son nom RP (jamais le pseudo Steam/FiveM).
local function agentName(src)
    local name = rpNameOf(src)
    return name ~= '' and name or 'Agent sans nom RP'
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
local LatentHandlers = {} -- réponses volumineuses : envoyées en événement "latent"

local function RegisterMDCCallback(name, fn, latent)
    Handlers[name] = fn
    LatentHandlers[name] = latent or nil
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

    if LatentHandlers[name] then
        TriggerLatentClientEvent('mdc:client:response', src, Config.LatentBps, id, result)
    else
        TriggerClientEvent('mdc:client:response', src, id, result)
    end
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
    view.bolos = bolosFor('identity', identity) -- BOLOs actifs visant cette personne
    return view
end

local function vehicleView(vehicle)
    local view = publicView(vehicle, 'vehicle')
    view.ownerIdentity = ownerOf(vehicle)
    view.bolos = bolosFor('vehicle', vehicle)
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
-- Licences de conduite par État d'émission. Doit correspondre à LICENSE_STATES dans script.js.
--   GA : toutes les licences du MDC (standard, lourd, combiné, moto, CDL, probatoires)
--   autres États : licences standard, moto et CDL de chaque État
local LICENSE_STATES = {
    GA = {
        ['Class C - Standard'] = true, ['Class F - Lourd'] = true, ['Class E - Combiné'] = true, ['Class M - Moto'] = true,
        ['CDL A'] = true, ['CDL B'] = true, ['CDL C'] = true,
        ['Probatoire - Class CP'] = true, ['Probatoire - Class D'] = true, ['Probatoire - Class MP'] = true,
    },
    FL = { ['Class E - Standard'] = true, ['CDL A'] = true, ['CDL B'] = true, ['CDL C'] = true, ['Class M - Moto'] = true },
    TN = { ['Class D - Standard'] = true, ['CDL A'] = true, ['CDL B'] = true, ['CDL C'] = true, ['Class M - Moto'] = true },
    SC = { ['Class D - Standard'] = true, ['CDL A'] = true, ['CDL B'] = true, ['CDL C'] = true, ['Class M - Moto'] = true, ['Class G - Cyclomoteur'] = true },
    NC = { ['Class C - Standard'] = true, ['CDL A'] = true, ['CDL B'] = true, ['CDL C'] = true, ['Class M - Moto'] = true },
    AL = { ['Class D - Standard'] = true, ['CDL A'] = true, ['CDL B'] = true, ['CDL C'] = true, ['Class M - Moto'] = true },
}
-- Condition de la licence ("disqualified" uniquement pour les licences CDL)
local LICENSE_STATUSES = { valid = true, suspended = true, revoked = true, cancelled = true, disqualified = true }
-- Interdictions (cumulables ; liste vide = N/A) : port d'arme, conduite de jour uniquement,
-- interdiction de rouler sur Interstate
local RESTRICTIONS = { weapon = true, daylight = true, nointerstate = true }
local CONDITIONS = { none = true, wanted = true, missing = true, deceased = true }

local REG_STATUSES = { valid = true, invalid = true, suspended = true }
local INSURANCE_STATUSES = { valid = true, invalid = true, cancelled = true, none = true }
local INSURERS = {
    ['State Farm'] = true, ['GEICO'] = true, ['Progressive'] = true, ['Allstate'] = true,
    ['USAA'] = true, ['Auto-Owners Assurance'] = true, ['Liberty Mutual'] = true, ['Farmers'] = true,
}
local HISTORY_TYPES = { administrative = true, parking = true }

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
        licenseClass  = 'N/A',
        licenseStatus = 'valid',
        licenseNumber = '',
        licenseState  = '',
        restrictions  = {},
        condition     = CONDITIONS[p.condition] and p.condition or 'none',
        sex           = (p.sex == 'M' or p.sex == 'F') and p.sex or '', -- (M) Male / (F) Female
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

    -- Licence de conduite (case "licence de conduite" cochée) : État d'émission, type de licence
    -- de cet État, n° (généré si vide) et condition
    if p.hasLicense == true then
        local classes = LICENSE_STATES[p.licenseState]
        if not classes then return nil, 'Choisissez l\'État d\'émission de la licence de conduite.' end
        if not classes[p.licenseClass] then return nil, 'Choisissez un type de licence délivré par cet État.' end
        r.licenseState = p.licenseState
        r.licenseClass = p.licenseClass
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
    if payload.kind == 'intervention' then return createIntervention(src, payload) end

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
RegisterMDCCallback('search', function(src, payload)
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

    shareUnitSearch(src, results) -- historique et résultat partagés avec l'unité du joueur
    return { ok = true, results = results }
end)

-- =========================================================================
-- UNITÉS
-- Une unité n'est liée à aucun joueur : n'importe qui peut la créer, la
-- rejoindre, la quitter, la modifier ou la supprimer. Un joueur fait partie
-- d'une seule unité à la fois. Le statut (barre latérale) est celui de l'unité.
-- =========================================================================
local TAG_COLORS = { green = true, purple = true, blue = true, orange = true, red = true, yellow = true, pink = true, gray = true }

-- Services de police (toujours présents ; doivent correspondre à index.html / script.js)
local DEPARTMENTS = {
    apd = 'Atlanta Police Department',
    gsp = 'Georgia State Patrol',
}

local NextUnitId = 1
local lastStatusChange = {}
local pushInterventions -- défini dans la section INTERVENTIONS

local function findUnit(id)
    id = tonumber(id)
    for index, unit in ipairs(Units) do
        if unit.id == id then return unit, index end
    end
    return nil
end

-- Nom affiché dans la console : "[TAG] Nom" (ou "Nom" si l'unité n'a pas de tag)
local function unitLabel(unit)
    return unit.tag ~= '' and ('[%s] %s'):format(unit.tag, unit.name) or unit.name
end

local function unitView(unit)
    local members = {}
    for key in pairs(unit.members) do
        local member = tonumber(key)
        members[#members + 1] = { id = member, name = agentName(member) }
    end
    table.sort(members, function(a, b) return a.name < b.name end)
    return {
        id = unit.id, name = unit.name, tag = unit.tag, color = unit.color, dept = unit.dept,
        status = unit.status, updatedAt = unit.updatedAt, members = members,
    }
end

local function unitsList()
    local list = {}
    for _, unit in ipairs(Units) do list[#list + 1] = unitView(unit) end
    return list
end

local function pushUnits()
    pushToViewers('units', unitsList())
    pushHud()
end

local function leaveCurrentUnit(src)
    local unit = findUnit(PlayerUnit[src])
    if unit then unit.members[tostring(src)] = nil end
    PlayerUnit[src] = nil
end

local function buildUnit(p)
    local name = clean(p.name, 30)
    local tag = clean(p.tag, 10):upper() -- facultatif
    if name == '' then return nil, 'Le nom de l\'unité est obligatoire.' end
    if not TAG_COLORS[p.color] then return nil, 'Choisissez la couleur du tag.' end
    if not DEPARTMENTS[p.dept] then return nil, 'Choisissez le service de police de l\'unité.' end
    return { name = name, tag = tag, color = p.color, dept = p.dept }
end

RegisterMDCCallback('getUnits', function()
    return { ok = true, units = unitsList() }
end)

RegisterMDCCallback('createUnit', function(src, payload)
    local unit, err = buildUnit(payload)
    if not unit then return { ok = false, error = err } end
    if not checkWriteCooldown(src) then return { ok = false, error = 'Patientez un instant.' } end

    unit.id = NextUnitId
    unit.status = 'available'
    unit.members = {}
    unit.createdAt = os.time()
    unit.updatedAt = os.time()
    NextUnitId = NextUnitId + 1
    Units[#Units + 1] = unit

    print(('^5[MDC]^0 Unité créée : %s (%s) par %s [%s]'):format(unitLabel(unit), DEPARTMENTS[unit.dept], agentName(src), GetPlayerName(src) or '?'))
    pushUnits()
    return { ok = true, id = unit.id }
end)

RegisterMDCCallback('updateUnit', function(_, payload)
    local unit = findUnit(payload.id)
    if not unit then return { ok = false, error = 'Unité introuvable.' } end
    local data, err = buildUnit(payload)
    if not data then return { ok = false, error = err } end

    unit.name, unit.tag, unit.color, unit.dept = data.name, data.tag, data.color, data.dept
    unit.updatedAt = os.time()
    pushUnits()
    pushInterventions()
    return { ok = true }
end)

RegisterMDCCallback('joinUnit', function(src, payload)
    local unit = findUnit(payload.id)
    if not unit then return { ok = false, error = 'Unité introuvable.' } end
    if rpNameOf(src) == '' then
        return { ok = false, error = 'Définissez d\'abord votre nom RP (en haut à gauche, ou /nomrp dans le chat) pour rejoindre une unité.' }
    end
    if PlayerUnit[src] == unit.id then return { ok = true } end
    local count = 0
    for _ in pairs(unit.members) do count = count + 1 end
    if count >= Config.MaxUnitMembers then return { ok = false, error = 'Cette unité est complète.' } end
    leaveCurrentUnit(src) -- une seule unité à la fois
    unit.members[tostring(src)] = true
    PlayerUnit[src] = unit.id
    pushUnits()
    return { ok = true }
end)

RegisterMDCCallback('leaveUnit', function(src)
    leaveCurrentUnit(src)
    pushUnits()
    return { ok = true }
end)

RegisterMDCCallback('deleteUnit', function(src, payload)
    local unit, index = findUnit(payload.id)
    if not unit then return { ok = false, error = 'Unité introuvable.' } end

    for key in pairs(unit.members) do PlayerUnit[tonumber(key)] = nil end
    for _, intervention in ipairs(Interventions) do intervention.units[tostring(unit.id)] = nil end
    table.remove(Units, index)

    print(('^5[MDC]^0 Unité supprimée : %s par %s'):format(unitLabel(unit), agentName(src)))
    pushUnits()
    pushInterventions()
    return { ok = true }
end)

-- Notification "statut de l'unité" (en haut à droite) envoyée à chaque membre de l'unité
local function notifyUnitStatus(unit)
    local data = { name = unit.name, tag = unit.tag, color = unit.color, status = unit.status }
    for key in pairs(unit.members) do
        TriggerClientEvent('mdc:client:statusNotify', tonumber(key), data)
    end
end

-- Statut de l'unité du joueur (barre latérale)
RegisterMDCCallback('setStatus', function(src, payload)
    local unit = findUnit(PlayerUnit[src])
    if not unit then return { ok = false, error = 'Rejoignez une unité (onglet Unités) pour définir son statut.' } end
    if not Statuses[payload.status] then return { ok = false, error = 'Statut invalide.' } end
    if unit.status == payload.status then return { ok = true } end

    local now = GetGameTimer()
    if lastStatusChange[src] and now - lastStatusChange[src] < Config.StatusCooldown then
        return { ok = false, error = 'Patientez un instant.' }
    end
    lastStatusChange[src] = now

    -- Notification console
    print(('^5[MDC]^0 %s : ^3%s^0 -> ^2%s^0 (par %s [%s])'):format(unitLabel(unit),
        Statuses[unit.status] or unit.status, Statuses[payload.status], agentName(src), GetPlayerName(src) or '?'))

    unit.status = payload.status
    unit.updatedAt = os.time()
    pushUnits()
    notifyUnitStatus(unit)
    return { ok = true }
end)

-- =========================================================================
-- PROFIL (nom RP) ET OUVERTURE DU MDC
-- Le nom RP est l'état "rpName" du joueur, répliqué à tous les clients : le chat
-- (/nomrp) et le MDC lisent et modifient la même valeur. Il n'est pas sauvegardé :
-- remis à zéro à chaque connexion.
-- =========================================================================
local RP_NAME_MIN, RP_NAME_MAX = 2, 40 -- identiques à ChatConfig.NameMin / NameMax (rp_chat)

RegisterNetEvent('mdc:server:setProfile', function(rpName)
    local src = source
    if not hasAccess(src) then return end
    local name = clean(rpName, RP_NAME_MAX):gsub('%s+', ' ')
    if (utf8.len(name) or 0) < RP_NAME_MIN then return end
    Player(src).state:set('rpName', name, true)
end)

-- Nom RP modifié (MDC ou /nomrp du chat) : listes des unités et HUD à jour.
-- Le gestionnaire est appelé AVANT que la nouvelle valeur soit enregistrée : mise à jour au tick suivant.
AddStateBagChangeHandler('rpName', nil, function(bagName)
    local src = GetPlayerFromStateBagName(bagName)
    if not src or src == 0 then return end
    SetTimeout(0, function()
        if PlayerUnit[src] then pushUnits() end
    end)
end)

RegisterNetEvent('mdc:server:viewer', function(isViewing)
    local src = source
    Viewers[src] = (isViewing and hasAccess(src)) or nil
end)

-- =========================================================================
-- INTERVENTIONS (créées par les civils dans "Créations") et
-- INCIDENTS (créés par les unités dans "Interventions").
-- En mémoire uniquement : effacés au redémarrage du serveur.
-- Déroulé : "En attente" (aucune unité), "En cours" (au moins une unité),
-- "Terminée" (bouton "Intervention terminée", grisée dans la liste).
-- =========================================================================
local PRIORITIES = { nonurgent = true, p1 = true, p2 = true, p3 = true }
local NextInterventionId = 1

-- Les notes sont toujours écrites en MAJUSCULES (accents compris)
local ACCENTS = {
    ['à'] = 'À', ['â'] = 'Â', ['ä'] = 'Ä', ['é'] = 'É', ['è'] = 'È', ['ê'] = 'Ê', ['ë'] = 'Ë',
    ['î'] = 'Î', ['ï'] = 'Ï', ['ô'] = 'Ô', ['ö'] = 'Ö', ['ù'] = 'Ù', ['û'] = 'Û', ['ü'] = 'Ü',
    ['ç'] = 'Ç', ['ÿ'] = 'Ÿ', ['œ'] = 'Œ', ['æ'] = 'Æ',
}
local function upperFr(str)
    return (str:upper():gsub('[\195\197][\128-\191]', ACCENTS))
end

-- N° de téléphone du requérant : AAA-XXX-XXXX, où AAA est un indicatif régional de
-- Géorgie compris entre 470 et 678 (doit correspondre à script.js, Random.phone)
local GEORGIA_AREA_CODES = { 470, 478, 678 }
local function genPhone()
    local area = GEORGIA_AREA_CODES[math.random(1, #GEORGIA_AREA_CODES)]
    return ('%d-%03d-%04d'):format(area, math.random(200, 999), math.random(0, 9999))
end

-- N° d'incident : XX-XXXX (chiffres aléatoires, sans lien avec la date)
local function genCaseNumber()
    return ('%02d-%04d'):format(math.random(0, 99), math.random(0, 9999))
end

local function newInterventionNumber()
    while true do
        local number, used = genCaseNumber(), false
        for _, intervention in ipairs(Interventions) do
            if intervention.number == number then used = true break end
        end
        if not used then return number end
    end
end

local function findIntervention(id)
    id = tonumber(id)
    for _, intervention in ipairs(Interventions) do
        if intervention.id == id then return intervention end
    end
    return nil
end

local function interventionStatus(intervention)
    if intervention.closed then return 'closed' end
    return next(intervention.units) and 'ongoing' or 'pending'
end

local function interventionView(intervention)
    local view = {}
    for k, v in pairs(intervention) do view[k] = v end

    local units = {}
    for key in pairs(intervention.units) do
        local unit = findUnit(key)
        if unit then units[#units + 1] = { id = unit.id, name = unit.name, tag = unit.tag, color = unit.color } end
    end
    table.sort(units, function(a, b) return a.name < b.name end)

    view.units = units
    view.status = interventionStatus(intervention)
    view.reports = reportLinks(intervention) -- affichés avec les notes, dans le déroulé

    -- Identités / véhicules liés : informations à jour lues dans les fiches
    local links = {}
    for _, link in ipairs(intervention.links or {}) do
        local record = findBy(link.kind == 'vehicle' and 'vehicles' or 'identities', 'id', link.recordId)
        if record then
            local item = { kind = link.kind, recordId = link.recordId, addedBy = link.addedBy, addedAt = link.addedAt }
            if link.kind == 'vehicle' then
                local owner = ownerOf(record)
                item.plate, item.make, item.model, item.color = record.plate, record.make, record.model, record.color
                item.stolen, item.regStatus = record.stolen, record.regStatus
                item.owner = owner and identityLabel(owner) or (record.ownerName ~= '' and record.ownerName or nil)
            else
                item.firstname, item.middlename, item.lastname = record.firstname, record.middlename, record.lastname
                item.dob, item.condition = record.dob, record.condition
            end
            links[#links + 1] = item
        end
    end
    view.links = links
    return view
end

-- En cours / en attente en haut (les plus récentes d'abord), terminées en bas
local function interventionsList()
    local list = {}
    for _, intervention in ipairs(Interventions) do list[#list + 1] = interventionView(intervention) end
    table.sort(list, function(a, b)
        if a.closed ~= b.closed then return not a.closed end
        return a.id > b.id
    end)
    return list
end

pushInterventions = function()
    pushToViewers('interventions', interventionsList())
    pushHud()
end

--- Valide les champs d'une intervention ('intervention') ou d'un incident ('incident').
local function buildCall(p, kind)
    local r = {
        title       = clean(p.title, 60),
        address     = clean(p.address, 80),
        crossStreet = clean(p.crossStreet, 80), -- croisement (facultatif)
        block       = clean(p.block, 40),
        description = cleanMultiline(p.description, 2000),
    }

    if r.title == '' then
        return nil, kind == 'incident' and 'Le type d\'incident est obligatoire.' or 'Le type d\'intervention est obligatoire.'
    end

    if kind == 'intervention' then
        r.caller = clean(p.caller, 60)
        if r.caller == '' then return nil, 'Le requérant est obligatoire.' end

        r.phone = clean(p.phone, 20)
        if r.phone == '' then r.phone = genPhone() end
        if not r.phone:match('^[%d%s%-%+%(%)%.]+$') then return nil, 'Numéro de téléphone invalide.' end

        if not PRIORITIES[p.priority] then return nil, 'Choisissez la priorité de l\'urgence.' end
        r.priority = p.priority
    end

    if r.address == '' then return nil, 'L\'adresse est obligatoire.' end
    if r.block == '' then return nil, 'Le bloc est obligatoire.' end
    if r.description == '' then return nil, 'La description est obligatoire.' end
    return r
end

-- Notification "nouvelle intervention / nouvel incident" (en haut à droite de l'écran) :
-- envoyée à TOUS les joueurs en jeu (son auteur, les unités, les civils).
local function notifyNewCall(call)
    TriggerClientEvent('mdc:client:callNotify', -1, {
        number = call.number, kind = call.kind, title = call.title, priority = call.priority,
        address = call.address, crossStreet = call.crossStreet, block = call.block, unitName = call.unitName,
    })
end

local function addCall(src, call, kind, unit)
    call.id = NextInterventionId
    call.number = newInterventionNumber()
    call.kind = kind
    call.units = {}
    call.notes = {}
    call.reports = {} -- [id du rapport] = true (rapports liés, section RAPPORTS)
    call.links = {}   -- identités / véhicules liés : { kind, recordId, addedBy, addedAt }
    call.nextNoteId = 1
    call.closed = false
    call.createdAt = os.time()
    call.createdByName = agentName(src)
    if unit then call.units[tostring(unit.id)] = true end -- l'unité qui déclare un incident est sur l'appel

    NextInterventionId = NextInterventionId + 1
    Interventions[#Interventions + 1] = call

    print(('^5[MDC]^0 Nouvel(le) %s %s "%s" par %s [%s]'):format(kind, call.number, call.title, agentName(src), GetPlayerName(src) or '?'))
    pushInterventions()
    notifyNewCall(call)
    return { ok = true, id = call.id, number = call.number }
end

-- Intervention créée par un civil (onglet "Créations")
createIntervention = function(src, payload)
    local call, err = buildCall(payload, 'intervention')
    if not call then return { ok = false, error = err } end
    if not checkWriteCooldown(src) then return { ok = false, error = 'Patientez un instant.' } end
    return addCall(src, call, 'intervention')
end

-- Incident déclaré par une unité (onglet "Interventions")
RegisterMDCCallback('createIncident', function(src, payload)
    local unit = findUnit(PlayerUnit[src])
    if not unit then return { ok = false, error = 'Vous devez faire partie d\'une unité pour déclarer un incident.' } end

    local call, err = buildCall(payload, 'incident')
    if not call then return { ok = false, error = err } end
    if not checkWriteCooldown(src) then return { ok = false, error = 'Patientez un instant.' } end

    call.unitName = unit.name -- nom de l'unité déclarante (automatique)
    return addCall(src, call, 'incident', unit)
end)

RegisterMDCCallback('getInterventions', function()
    return { ok = true, interventions = interventionsList() }
end)

-- Rejoindre / quitter l'appel, y mettre fin (réservé aux unités)
RegisterMDCCallback('interventionAction', function(src, payload)
    local call = findIntervention(payload.id)
    if not call then return { ok = false, error = 'Intervention introuvable.' } end
    if call.closed then return { ok = false, error = 'Cette intervention est terminée.' } end

    local unit = findUnit(PlayerUnit[src])
    if not unit then
        return { ok = false, error = 'Seules les unités peuvent agir sur un appel : rejoignez d\'abord une unité (onglet Unités).' }
    end
    local key = tostring(unit.id)

    if payload.action == 'join' then
        call.units[key] = true
        local changed = unit.status ~= 'en_route'
        unit.status = 'en_route' -- rejoindre un appel passe l'unité "En route"
        unit.updatedAt = os.time()
        pushUnits()
        if changed then notifyUnitStatus(unit) end
    elseif payload.action == 'leave' then
        call.units[key] = nil
    elseif payload.action == 'end' then
        if not call.units[key] then return { ok = false, error = 'Seules les unités sur l\'appel peuvent y mettre fin.' } end
        call.closed = true
        call.closedAt = os.time()
        call.closedByName = unit.name
        print(('^5[MDC]^0 %s terminé(e) par %s'):format(call.number, unitLabel(unit)))
    else
        return { ok = false, error = 'Action invalide.' }
    end

    pushInterventions()
    return { ok = true }
end)

-- Modification des informations d'une intervention / d'un incident
RegisterMDCCallback('editIntervention', function(src, payload)
    local call = findIntervention(payload.id)
    if not call then return { ok = false, error = 'Intervention introuvable.' } end
    if call.closed then return { ok = false, error = 'Une intervention terminée ne peut plus être modifiée.' } end

    local data, err = buildCall(payload, call.kind)
    if not data then return { ok = false, error = err } end

    for k, v in pairs(data) do call[k] = v end
    call.updatedAt = os.time()
    call.updatedByName = agentName(src)
    pushInterventions()
    return { ok = true }
end)

-- Notes : écrites en majuscules par les unités présentes sur l'appel, modifiables par leur unité
RegisterMDCCallback('addNote', function(src, payload)
    local call = findIntervention(payload.id)
    if not call then return { ok = false, error = 'Intervention introuvable.' } end
    if call.closed then return { ok = false, error = 'Cette intervention est terminée.' } end

    local unit = findUnit(PlayerUnit[src])
    if not unit or not call.units[tostring(unit.id)] then
        return { ok = false, error = 'Seules les unités sur l\'appel peuvent ajouter une note.' }
    end

    local text = upperFr(cleanMultiline(payload.text, 500))
    if text == '' then return { ok = false, error = 'La note est vide.' } end

    call.notes[#call.notes + 1] = {
        id = call.nextNoteId,
        unitId = unit.id,
        unitTag = unit.tag,
        unitName = unit.name,
        unitColor = unit.color,
        authorName = agentName(src),
        text = text,
        createdAt = os.time(),
    }
    call.nextNoteId = call.nextNoteId + 1
    pushInterventions()
    return { ok = true }
end)

-- Identités / véhicules (historique des recherches) liés à l'appel par une unité présente
local LINK_STORES = { identity = 'identities', vehicle = 'vehicles' }

RegisterMDCCallback('linkRecord', function(src, payload)
    local call = findIntervention(payload.id)
    if not call then return { ok = false, error = 'Intervention introuvable.' } end
    if call.closed then return { ok = false, error = 'Cette intervention est terminée.' } end

    local unit = findUnit(PlayerUnit[src])
    if not unit or not call.units[tostring(unit.id)] then
        return { ok = false, error = 'Seules les unités sur l\'appel peuvent y ajouter des fiches.' }
    end

    local storeName = LINK_STORES[payload.kind]
    local record = storeName and findBy(storeName, 'id', tonumber(payload.recordId))
    if not record then return { ok = false, error = 'Fiche introuvable.' } end

    for _, link in ipairs(call.links) do
        if link.kind == payload.kind and link.recordId == record.id then
            return { ok = false, error = 'Cette fiche est déjà liée à l\'appel.' }
        end
    end
    if #call.links >= 30 then return { ok = false, error = '30 fiches maximum par appel.' } end

    call.links[#call.links + 1] = { kind = payload.kind, recordId = record.id, addedBy = unit.name, addedAt = os.time() }
    pushInterventions()
    return { ok = true }
end)

RegisterMDCCallback('unlinkRecord', function(src, payload)
    local call = findIntervention(payload.id)
    if not call then return { ok = false, error = 'Intervention introuvable.' } end
    if call.closed then return { ok = false, error = 'Cette intervention est terminée.' } end

    local unit = findUnit(PlayerUnit[src])
    if not unit or not call.units[tostring(unit.id)] then
        return { ok = false, error = 'Seules les unités sur l\'appel peuvent retirer une fiche.' }
    end

    local recordId = tonumber(payload.recordId)
    for index, link in ipairs(call.links) do
        if link.kind == payload.kind and link.recordId == recordId then
            table.remove(call.links, index)
            pushInterventions()
            return { ok = true }
        end
    end
    return { ok = false, error = 'Fiche introuvable sur cet appel.' }
end)

-- Fiche complète (bouton "Fiche" d'une identité / d'un véhicule lié à un appel)
RegisterMDCCallback('getRecord', function(_, payload)
    local storeName = LINK_STORES[payload.kind]
    local record = storeName and findBy(storeName, 'id', tonumber(payload.id))
    if not record then return { ok = false, error = 'Fiche introuvable.' } end
    return { ok = true, record = payload.kind == 'vehicle' and vehicleView(record) or identityView(record) }
end)

RegisterMDCCallback('editNote', function(src, payload)
    local call = findIntervention(payload.id)
    if not call then return { ok = false, error = 'Intervention introuvable.' } end
    if call.closed then return { ok = false, error = 'Cette intervention est terminée.' } end

    local noteId = tonumber(payload.noteId)
    for _, note in ipairs(call.notes) do
        if note.id == noteId then
            if note.unitId ~= PlayerUnit[src] then
                return { ok = false, error = 'Seule l\'unité qui a écrit la note peut la modifier.' }
            end
            local text = upperFr(cleanMultiline(payload.text, 500))
            if text == '' then return { ok = false, error = 'La note est vide.' } end
            note.text = text
            note.updatedAt = os.time()
            pushInterventions()
            return { ok = true }
        end
    end
    return { ok = false, error = 'Note introuvable.' }
end)

-- =========================================================================
-- RAPPORTS (onglet "Rapports") : DOT-523, Arrest Report, Incident Report,
-- Citation, Traffic Ticket, Ticket, Warning.
-- Permanents (data/reports.json), comme les identités et les véhicules.
-- Les formulaires sont décrits dans server/reports.lua (MDC_REPORT_TYPES) :
-- le serveur valide chaque rapport avec ces mêmes règles.
-- Tout le monde peut lire les rapports ; seul l'auteur peut modifier le sien.
-- =========================================================================
local ReportTypes = {}   -- [id] = modèle
local ReportFields = {}  -- [id] = { [clé] = champ } (premier niveau : résumés, listes)
local OptionSets = {}    -- [liste d'options] = { [valeur] = libellé }

local function indexFields(fields, index)
    for _, f in ipairs(fields) do
        if f.t == 'group' then
            indexFields(f.f, index)
        elseif f.k then
            index[f.k] = f
        end
    end
end

-- Contrôle du modèle : deux champs d'un même niveau ne doivent pas partager une clé
-- (les groupes ne créent pas de niveau ; les listes, si).
local function checkDuplicateKeys(fields, seen, where)
    for _, f in ipairs(fields) do
        if f.t == 'group' then
            checkDuplicateKeys(f.f, seen, where)
        elseif f.k and f.t ~= 'matrix' then
            if seen[f.k] then
                print(('^1[MDC] ERREUR dans server/reports.lua : la clé "%s" est utilisée deux fois (%s).^0'):format(f.k, where))
            end
            seen[f.k] = true
            if f.t == 'list' then checkDuplicateKeys(f.f, {}, where .. ' > ' .. f.k) end
        end
    end
end

for _, reportType in ipairs(MDC_REPORT_TYPES or {}) do
    ReportTypes[reportType.id] = reportType
    ReportFields[reportType.id] = {}
    local seen = {}
    for _, section in ipairs(reportType.sections) do
        indexFields(section.f, ReportFields[reportType.id])
        checkDuplicateKeys(section.f, seen, reportType.id)
    end
end

if not MDC_REPORT_TYPES then
    print('^1[MDC] ERREUR : server/reports.lua n\'est pas chargé (vérifiez fxmanifest.lua). Onglet "Rapports" indisponible.^0')
end

local function optionSet(options)
    local set = OptionSets[options]
    if not set then
        set = {}
        for _, option in ipairs(options) do set[option[1]] = option[2] end
        OptionSets[options] = set
    end
    return set
end

-- Options d'un tableau "matrix" (toutes catégories confondues)
local function matrixSet(f)
    local set = OptionSets[f]
    if not set then
        set = {}
        for _, group in ipairs(f.groups) do
            for _, option in ipairs(group.o) do set[option[1]] = option[2] end
        end
        OptionSets[f] = set
    end
    return set
end

local function hasAny(list, values)
    if type(list) ~= 'table' then return false end
    for _, v in ipairs(list) do
        for _, w in ipairs(values) do
            if v == w then return true end
        end
    end
    return false
end

--- Condition "show" / "reqIf" d'un champ, évaluée sur les données déjà validées.
local function condMet(cond, obj)
    local value = obj[cond.k]
    if cond['in'] then
        for _, allowed in ipairs(cond['in']) do
            if value == allowed then return true end
        end
        return false
    end
    if cond.any then return hasAny(value, cond.any) end
    if cond.none then return not hasAny(value, cond.none) end
    return value == cond.eq
end

local function pickOptions(list, set)
    local out, seen = {}, {}
    if type(list) ~= 'table' then return out end
    for _, key in ipairs(list) do
        if type(key) == 'string' and set[key] and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    return out
end

local function fieldError(crumb, f, message)
    local where = #crumb > 0 and (table.concat(crumb, ' › ') .. ' › ') or ''
    return ('%s%s : %s'):format(where, f.l or f.k, message)
end

--- Valide une valeur simple et l'écrit dans `out`. Retourne un message d'erreur ou nil.
local function readValue(f, v, out, crumb)
    local required = f.req or (f.reqIf ~= nil and condMet(f.reqIf, out))
    local value

    if f.t == 'check' then
        value = v == true
        if required and not value then return fieldError(crumb, f, 'case obligatoire.') end
        out[f.k] = value
        return nil
    elseif f.t == 'checks' then
        value = pickOptions(v, optionSet(f.o))
        if required and #value == 0 then return fieldError(crumb, f, 'cochez au moins une case.') end
        out[f.k] = value
        return nil
    elseif f.t == 'text' then
        value = clean(v, f.max or 80)
        if f.upper then value = upperFr(value) end
    elseif f.t == 'area' then
        value = cleanMultiline(v, f.max or 2000)
    elseif f.t == 'date' then
        value = clean(v, 10)
        if value ~= '' then
            local key = dateKey(value)
            if not key then return fieldError(crumb, f, 'date invalide (JJ/MM/AAAA).') end
            if f.past and key > todayKey() then return fieldError(crumb, f, 'la date ne peut pas être dans le futur.') end
        end
    elseif f.t == 'time' then
        value = clean(v, 5)
        if value ~= '' and not validTime(value) then return fieldError(crumb, f, 'horaire invalide (HH:MM).') end
    elseif f.t == 'num' then
        local raw = type(v) == 'number' and v == math.floor(v) and ('%d'):format(v) or clean(v, 12)
        value = ''
        if raw ~= '' then
            local n = raw:match('^%d+$') and tonumber(raw)
            if not n or (f.min and n < f.min) or (f.max and n > f.max) then
                return fieldError(crumb, f, ('nombre entier attendu (%d à %d).'):format(f.min or 0, f.max or 999999999))
            end
            value = n
        end
    elseif f.t == 'select' then
        value = (type(v) == 'string' and optionSet(f.o)[v]) and v or ''
    else
        return nil
    end

    if required and value == '' then return fieldError(crumb, f, 'champ obligatoire.') end
    out[f.k] = value
    return nil
end

local sanitizeFields

local function sanitizeList(f, rawList, out, ctx, crumb)
    local items = {}
    if type(rawList) == 'table' then
        if #rawList > (f.max or 20) then return ('%s : %d maximum.'):format(f.l, f.max or 20) end
        for i, rawItem in ipairs(rawList) do
            local item = {}
            crumb[#crumb + 1] = ('%s %d'):format(f.item, i)
            local err = sanitizeFields(f.f, type(rawItem) == 'table' and rawItem or {}, item, ctx, crumb)
            crumb[#crumb] = nil
            if err then return err end
            items[#items + 1] = item
        end
    end
    if #items < (f.min or 0) then
        return ('%s : ajoutez au moins %d %s.'):format(f.l, f.min, f.item:lower())
    end
    out[f.k] = items
    return nil
end

--- Valide une liste de champs (récursif : groupes, listes, tableaux par "Unit").
--- Les champs masqués (condition "show" fausse) sont ignorés et non enregistrés.
sanitizeFields = function(fields, raw, out, ctx, crumb)
    for _, f in ipairs(fields) do
        if not f.show or condMet(f.show, out) then
            local err
            if f.t == 'group' then
                err = sanitizeFields(f.f, raw, out, ctx, crumb)
            elseif f.t == 'list' then
                err = sanitizeList(f, raw[f.k], out, ctx, crumb)
            elseif f.t == 'matrix' or f.t == 'perUnit' then
                -- Données rangées dans chaque élément de la liste source (ex : units[i].causes)
                local listSpec = ctx.fields[f.list]
                local rawList = type(ctx.raw[f.list]) == 'table' and ctx.raw[f.list] or {}
                for i, item in ipairs(ctx.out[f.list] or {}) do
                    local rawItem = type(rawList[i]) == 'table' and rawList[i] or {}
                    if f.t == 'matrix' then
                        item[f.k] = pickOptions(rawItem[f.k], matrixSet(f))
                    else
                        crumb[#crumb + 1] = ('%s %d'):format(listSpec and listSpec.item or '', i)
                        for _, sub in ipairs(f.f) do
                            if not sub.show or condMet(sub.show, item) then
                                err = err or readValue(sub, rawItem[sub.k], item, crumb)
                            end
                        end
                        crumb[#crumb] = nil
                    end
                    if err then break end
                end
            elseif f.k then
                err = readValue(f, raw[f.k], out, crumb)
            end
            if err then return err end
        end
    end
    return nil
end

local function buildReport(reportType, raw)
    local out = {}
    local ctx = { raw = raw, out = out, fields = ReportFields[reportType.id] }
    for _, section in ipairs(reportType.sections) do
        -- Section conditionnelle (ex : "Véhicule" du Warning, seulement pour une infraction routière)
        if not section.show or condMet(section.show, out) then
            local err = sanitizeFields(section.f, raw, out, ctx, { section.title })
            if err then return nil, err end
        end
    end
    return out
end

-- Retire les espaces et tirets "—" en trop au début / à la fin d'un résumé
local function trimSummary(text)
    text = text:gsub('%s+', ' ')
    local changed = true
    while changed do
        changed = false
        text = text:gsub('^%s+', ''):gsub('%s+$', '')
        if text:sub(1, 3) == '—' then text, changed = text:sub(4), true end
        if text:sub(-3) == '—' then text, changed = text:sub(1, -4), true end
    end
    return text
end

--- Résumé affiché dans la liste, d'après le modèle "summary" ({clé}, {#liste}).
local function reportSummary(reportType, data)
    local fields = ReportFields[reportType.id]
    local text = (reportType.summary or ''):gsub('{(#?)([%w_]+)}', function(count, key)
        local value = data[key]
        if count == '#' then return tostring(type(value) == 'table' and #value or 0) end
        local f = fields[key]
        if f and f.t == 'select' then return optionSet(f.o)[value] or '' end
        if type(value) == 'string' or type(value) == 'number' then return tostring(value) end
        return ''
    end)
    return truncate(trimSummary(text), 120)
end

-- Texte de recherche : toutes les valeurs saisies (noms, plaques, adresses…), en minuscules
local function reportSearchText(data)
    local parts = {}
    local function collect(value)
        if type(value) == 'string' and value ~= '' then
            parts[#parts + 1] = value
        elseif type(value) == 'table' then
            for _, v in pairs(value) do collect(v) end
        end
    end
    collect(data)
    local text = table.concat(parts, ' '):gsub('%c', ' '):lower():gsub('%s+', ' ')
    return truncate(text, 4000)
end

-- ---- Lien rapport <-> intervention / incident ----
-- Le rapport garde une copie du lien : report.call = { id, session, number, title, kind }.
-- L'intervention garde la liste de ses rapports : intervention.reports[id] = true.

--- Intervention encore présente à laquelle le rapport est relié (nil après un redémarrage).
local function liveCall(link)
    if type(link) ~= 'table' or link.session ~= SessionId then return nil end
    return findIntervention(link.id)
end

-- Rapports affichés dans le déroulé d'une intervention (avec les notes)
reportLinks = function(intervention)
    local list = {}
    for key in pairs(intervention.reports or {}) do
        local report = findBy('reports', 'id', tonumber(key))
        if report then
            local reportType = ReportTypes[report.type]
            list[#list + 1] = {
                id = report.id, number = report.number, type = report.type,
                label = reportType and reportType.label or report.type, summary = report.summary,
                createdByName = report.createdByName, unitName = report.unitName,
                createdAt = report.createdAt, updatedAt = report.updatedAt,
            }
        end
    end
    table.sort(list, function(a, b) return (a.createdAt or 0) < (b.createdAt or 0) end)
    return list
end

local function reportListItem(report, me)
    return {
        id = report.id, number = report.number, type = report.type, summary = report.summary,
        createdAt = report.createdAt, createdByName = report.createdByName, unitName = report.unitName,
        updatedAt = report.updatedAt, mine = report.createdBy == me,
        callNumber = type(report.call) == 'table' and report.call.number or nil,
    }
end

RegisterMDCCallback('getReportTypes', function()
    return { ok = true, types = MDC_REPORT_TYPES or {} }
end, true)

-- Liste : filtres par type, par texte (n°, résumé, auteur, contenu) et "mes rapports"
RegisterMDCCallback('getReports', function(src, payload)
    local me = getIdentifier(src)
    local typeFilter = ReportTypes[payload.type] and payload.type or nil
    local query = normalizeName(payload.query)
    local mineOnly = payload.mine == true
    local list = {}

    for i = #Store.reports, 1, -1 do -- les plus récents d'abord
        local report = Store.reports[i]
        if (not typeFilter or report.type == typeFilter) and (not mineOnly or report.createdBy == me)
            and (query == '' or (report.number or ''):find(query, 1, true)
                or normalizeName(report.summary):find(query, 1, true)
                or normalizeName(report.createdByName):find(query, 1, true)
                or (report.searchText or ''):find(query, 1, true)) then
            list[#list + 1] = reportListItem(report, me)
            if #list >= Config.MaxReportResults then break end
        end
    end
    return { ok = true, reports = list }
end)

RegisterMDCCallback('getReport', function(src, payload)
    local report = findBy('reports', 'id', tonumber(payload.id))
    if not report then return { ok = false, error = 'Rapport introuvable.' } end
    local view = publicView(report, 'report')
    view.searchText = nil
    view.mine = report.createdBy == getIdentifier(src)
    view.callLive = liveCall(report.call) ~= nil -- intervention liée encore présente
    if type(view.call) == 'table' then view.call = { id = view.call.id, number = view.call.number, title = view.call.title, kind = view.call.kind } end
    return { ok = true, report = view }
end, true)

-- Création (sans id) ou modification (id : uniquement par son auteur).
-- payload.callRef : numéro de l'intervention / de l'incident lié (obligatoire),
-- ou 'keep' lors d'une modification pour garder le lien actuel (même si l'intervention
-- a disparu après un redémarrage).
RegisterMDCCallback('saveReport', function(src, payload)
    if Locked.reports then
        return { ok = false, error = 'Enregistrement bloqué : fichier de données corrompu (voir console serveur).' }
    end

    local me = getIdentifier(src)
    local id = tonumber(payload.id)
    local old, index
    if id then
        old, index = findBy('reports', 'id', id)
        if not old then return { ok = false, error = 'Rapport introuvable.' } end
        if old.createdBy ~= me then
            -- Rapport rédigé à plusieurs : la modification a été ouverte par son auteur dans l'unité du joueur
            local unit = findUnit(PlayerUnit[src])
            local draft = unit and unit.shared and unit.shared.draft
            if not (draft and draft.id == id and draft.startedBy == old.createdBy) then
                return { ok = false, error = 'Vous ne pouvez modifier que vos propres rapports.' }
            end
        end
    end

    local reportType = ReportTypes[old and old.type or payload.type]
    if not reportType then return { ok = false, error = 'Type de rapport invalide.' } end
    if reportType.archived and not old then
        return { ok = false, error = 'Ce type de rapport n\'est plus utilisé.' }
    end

    -- Intervention / incident lié (en cours ou terminé)
    local link
    if old and payload.callRef == 'keep' then
        link = old.call
    else
        local call = findIntervention(payload.callRef)
        if not call then return { ok = false, error = 'Choisissez l\'intervention ou l\'incident lié au rapport (première ligne).' } end
        link = { id = call.id, session = SessionId, number = call.number, title = call.title, kind = call.kind }
    end

    local data, err = buildReport(reportType, type(payload.data) == 'table' and payload.data or {})
    if not data then return { ok = false, error = err } end
    if not checkWriteCooldown(src) then return { ok = false, error = 'Patientez un instant.' } end

    local record = {
        type = reportType.id, data = data, call = link,
        summary = reportSummary(reportType, data),
        searchText = reportSearchText(data),
    }

    if old then
        record.id, record.number = old.id, old.number
        record.createdAt, record.createdBy, record.createdByName, record.unitName = old.createdAt, old.createdBy, old.createdByName, old.unitName
        record.updatedAt = os.time()
        record.updatedByName = agentName(src)
        Store.reports[index] = record
        if not saveStore('reports') then
            Store.reports[index] = old
            return { ok = false, error = 'Erreur d\'écriture sur le serveur : modification annulée (voir console).' }
        end
    else
        local unit = findUnit(PlayerUnit[src])
        record.id = NextId.reports
        record.number = uniqueValue('reports', 'number', genCaseNumber)
        record.createdAt = os.time()
        record.createdByName = agentName(src)
        record.unitName = unit and unit.name or nil
        record.createdBy = me -- privé : jamais envoyé aux clients (voir publicView)
        Store.reports[#Store.reports + 1] = record
        if not saveStore('reports') then
            table.remove(Store.reports)
            return { ok = false, error = 'Erreur d\'écriture sur le serveur : rien n\'a été enregistré (voir console).' }
        end
        NextId.reports = NextId.reports + 1
    end

    -- Mise à jour du déroulé des interventions (ancien et nouveau lien)
    local key = tostring(record.id)
    local previous = old and liveCall(old.call)
    if previous then previous.reports[key] = nil end
    local current = liveCall(record.call)
    if current then current.reports[key] = true end
    pushInterventions()

    print(('^5[MDC]^0 Rapport %s n°%s %s par %s [%s] (intervention %s)'):format(reportType.short, record.number,
        old and 'modifié' or 'créé', agentName(src), GetPlayerName(src) or '?', link and link.number or '-'))
    return { ok = true, id = record.id, number = record.number }
end)

-- =========================================================================
-- BOLOs ("Be On the Look-Out") : avis de recherche d'un individu ou d'un véhicule
-- Permanents (data/bolos.json) jusqu'à leur suppression depuis le MDC.
-- N'importe quel agent peut créer, modifier ou supprimer un BOLO.
--   Individu : motif, identité (facultative, depuis l'historique des recherches),
--              description, lieu, détails et véhicule(s) utilisé(s)
--   Véhicule : motif, immatriculation PARTIELLE (complète = c'est le propriétaire
--              qui est recherché : BOLO individu), marque, modèle, couleur, type, détails
-- Une description non cochée / non renseignée est affichée "Inconnue".
-- =========================================================================
-- Doivent correspondre à BOLO_ORIGINS / BOLO_VEHICLE_TYPES dans script.js
local BOLO_ORIGINS = {
    white = true, hispanic = true, black = true, asian = true, native = true, mideast = true,
}
local BOLO_VEHICLE_TYPES = {
    ['Compact'] = true, ['Sedan'] = true, ['SUV'] = true, ['Coupé'] = true, ['Break'] = true,
    ['Muscle'] = true, ['Sport'] = true, ['Pick-up'] = true, ['Van'] = true, ['Moto'] = true,
    ['Camion'] = true, ['Autre'] = true,
}
local BOLO_MAX_VEHICLES = 5
local BOLO_WILDCARD = '*' -- caractère inconnu d'une immatriculation partielle

--- Immatriculation de BOLO : lettres, chiffres et * (caractère inconnu), 8 max
local function boloPlate(plate)
    return (clean(plate, 16):upper():gsub('[^%w%*]', ''):sub(1, 8))
end

--- Une immatriculation est complète si elle est enregistrée, ou si elle a 8 caractères
--- sans aucun caractère inconnu.
local function plateIsComplete(plate)
    if plate == '' or plate:find(BOLO_WILDCARD, 1, true) then return false end
    return #plate == 8 or findBy('vehicles', 'plate', plate) ~= nil
end

--- Immatriculation partielle d'un BOLO (ex. "AB*12") retrouvée dans une immatriculation
--- (au moins 3 caractères connus, sinon trop de correspondances).
local function plateMatches(pattern, plate)
    if type(pattern) ~= 'string' or #pattern:gsub('%*', '') < 3 or type(plate) ~= 'string' then return false end
    local luaPattern = pattern:gsub('%*', '.')
    return plate:find(luaPattern) ~= nil
end

local function boloVehicle(v, i)
    local name = ('Véhicule n°%d'):format(i)
    if type(v) ~= 'table' then return nil, name .. ' invalide.' end
    local out = {
        plate = boloPlate(v.plate),
        make  = clean(v.make, 40),
        model = clean(v.model, 40),
        color = clean(v.color, 40),
        vtype = BOLO_VEHICLE_TYPES[v.vtype] and v.vtype or '',
    }
    if out.plate == '' and out.make == '' and out.model == '' and out.color == '' and out.vtype == '' then
        return nil, name .. ' : renseignez au moins un élément (ou retirez-le).'
    end
    -- Immatriculation enregistrée : lien vers la fiche du véhicule
    local record = out.plate ~= '' and findBy('vehicles', 'plate', out.plate)
    if record then out.recordId = record.id end
    return out
end

--- Valide le formulaire d'un BOLO. Retourne (bolo) ou (nil, message d'erreur).
local function buildBolo(p)
    local kind = p.kind == 'person' and 'person' or p.kind == 'vehicle' and 'vehicle' or nil
    if not kind then return nil, 'Choisissez le type de BOLO (individu ou véhicule).' end

    local r = { kind = kind, reason = clean(p.reason, 120), details = cleanMultiline(p.details, 2000) }
    if r.reason == '' then return nil, 'Le motif est obligatoire.' end

    if kind == 'vehicle' then
        r.plate = boloPlate(p.plate)
        r.make, r.model, r.color = clean(p.make, 40), clean(p.model, 40), clean(p.color, 40)
        r.vtype = BOLO_VEHICLE_TYPES[p.vtype] and p.vtype or ''
        if plateIsComplete(r.plate) then
            return nil, 'Immatriculation complète : c\'est son propriétaire qui est recherché. Créez un BOLO ' ..
                '"Individu" (avec ce véhicule), ou remplacez les caractères inconnus par *.'
        end
        if r.plate == '' and r.make == '' and r.model == '' and r.color == '' and r.vtype == '' then
            return nil, 'Renseignez au moins un élément du véhicule (immatriculation partielle, marque, modèle, couleur ou type).'
        end
        return r
    end

    -- Individu : identité facultative (fiche existante)
    local identityId = tonumber(p.identityId)
    if identityId then
        local identity = findBy('identities', 'id', identityId)
        if not identity then return nil, 'Identité introuvable : refaites la recherche.' end
        r.identityId = identity.id
        r.identityLabel = identityLabel(identity)
    end

    -- Description : chaque case cochée exige sa précision (non cochée = "Inconnue")
    r.hairKnown = p.hairKnown == true
    r.hairColor = r.hairKnown and clean(p.hairColor, 40) or ''
    if r.hairKnown and r.hairColor == '' then return nil, 'Cheveux : précisez la couleur (ou décochez la case).' end

    r.facialKnown = p.facialKnown == true
    r.facialType = r.facialKnown and clean(p.facialType, 40) or ''
    r.facialColor = r.facialKnown and clean(p.facialColor, 40) or ''
    if r.facialKnown and r.facialType == '' then return nil, 'Pilosité faciale : précisez le type (ou décochez la case).' end

    r.tattooKnown = p.tattooKnown == true
    r.tattoos = r.tattooKnown and cleanMultiline(p.tattoos, 500) or ''
    if r.tattooKnown and r.tattoos == '' then return nil, 'Tatouages : précisez lesquels (ou décochez la case).' end

    r.skin = clean(p.skin, 40)
    r.clothing = cleanMultiline(p.clothing, 500)

    r.origins = {}
    if type(p.origins) == 'table' then
        local seen = {}
        for _, origin in ipairs(p.origins) do
            if BOLO_ORIGINS[origin] and not seen[origin] then
                seen[origin] = true
                r.origins[#r.origins + 1] = origin
            end
        end
    end

    local height = clean(p.height, 3)
    if height ~= '' then
        r.height = tonumber(height)
        if not height:match('^%d+$') or r.height < 50 or r.height > 250 then
            return nil, 'Taille invalide (en cm, de 50 à 250).'
        end
    end

    r.location = clean(p.location, 120)

    r.vehicles = {}
    if type(p.vehicles) == 'table' then
        if #p.vehicles > BOLO_MAX_VEHICLES then return nil, ('%d véhicules maximum.'):format(BOLO_MAX_VEHICLES) end
        for i, v in ipairs(p.vehicles) do
            local vehicle, err = boloVehicle(v, i)
            if not vehicle then return nil, err end
            r.vehicles[i] = vehicle
        end
    end
    return r
end

--- Résumé affiché dans la liste
local function boloSummary(bolo)
    if bolo.kind == 'vehicle' then
        local parts = { bolo.plate ~= '' and bolo.plate or nil }
        local name = table.concat({ bolo.make or '', bolo.model or '' }, ' '):gsub('^%s+', ''):gsub('%s+$', '')
        if name ~= '' then parts[#parts + 1] = name end
        if bolo.color ~= '' then parts[#parts + 1] = bolo.color end
        if bolo.vtype ~= '' then parts[#parts + 1] = bolo.vtype end
        return table.concat(parts, ' — ')
    end
    local parts = { bolo.identityLabel or 'Individu non identifié' }
    if bolo.height then parts[#parts + 1] = bolo.height .. ' cm' end
    if #bolo.vehicles > 0 then parts[#parts + 1] = ('%d véhicule(s)'):format(#bolo.vehicles) end
    return table.concat(parts, ' — ')
end

local function boloListItem(bolo)
    return {
        id = bolo.id, number = bolo.number, kind = bolo.kind, reason = bolo.reason,
        summary = boloSummary(bolo), location = bolo.location,
        createdAt = bolo.createdAt, updatedAt = bolo.updatedAt,
    }
end

local function bolosList()
    local list = {}
    for i = #Store.bolos, 1, -1 do -- les plus récents d'abord
        list[#list + 1] = boloListItem(Store.bolos[i])
    end
    return list
end

local function pushBolos()
    pushToViewers('bolos', bolosList())
end

--- BOLOs actifs visant une fiche (affichés en alerte dans les recherches) :
---   identité : BOLO individu lié à cette identité
---   véhicule : BOLO individu utilisant ce véhicule, ou BOLO véhicule dont
---              l'immatriculation partielle correspond (correspondance possible)
bolosFor = function(kind, record)
    local list = {}
    for _, bolo in ipairs(Store.bolos) do
        local match, possible = false, false
        if kind == 'identity' then
            match = bolo.kind == 'person' and bolo.identityId == record.id
        elseif bolo.kind == 'person' then
            for _, v in ipairs(bolo.vehicles or {}) do
                if v.recordId == record.id or (v.plate ~= '' and v.plate == record.plate) then match = true break end
            end
        else
            match = plateMatches(bolo.plate, record.plate)
            possible = match
        end
        if match then
            list[#list + 1] = { id = bolo.id, number = bolo.number, reason = bolo.reason, possible = possible or nil }
        end
    end
    return list
end

RegisterMDCCallback('getBolos', function()
    return { ok = true, bolos = bolosList() }
end)

RegisterMDCCallback('getBolo', function(_, payload)
    local bolo = findBy('bolos', 'id', tonumber(payload.id))
    if not bolo then return { ok = false, error = 'Ce BOLO n\'existe plus.' } end
    local view = publicView(bolo, bolo.kind) -- kind : 'person' ou 'vehicle'
    -- Nom à jour de l'identité liée (si la fiche existe encore)
    if bolo.identityId then
        local identity = findBy('identities', 'id', bolo.identityId)
        view.identityExists = identity ~= nil
        if identity then view.identityLabel = identityLabel(identity) end
    end
    return { ok = true, bolo = view }
end)

-- Création (sans id) ou modification (id) d'un BOLO
RegisterMDCCallback('saveBolo', function(src, payload)
    if Locked.bolos then
        return { ok = false, error = 'Enregistrement bloqué : fichier de données corrompu (voir console serveur).' }
    end
    local id = tonumber(payload.id)
    local old, index
    if id then
        old, index = findBy('bolos', 'id', id)
        if not old then return { ok = false, error = 'Ce BOLO n\'existe plus.' } end
        if payload.kind ~= old.kind then return { ok = false, error = 'Le type d\'un BOLO ne peut pas être modifié.' } end
    elseif #Store.bolos >= Config.MaxBolos then
        return { ok = false, error = ('%d BOLOs actifs maximum : supprimez ceux qui ne sont plus d\'actualité.'):format(Config.MaxBolos) }
    end

    local record, err = buildBolo(payload)
    if not record then return { ok = false, error = err } end
    if not checkWriteCooldown(src) then return { ok = false, error = 'Patientez un instant.' } end

    if old then
        record.id, record.number = old.id, old.number
        record.createdAt, record.createdBy, record.createdByName, record.unitName = old.createdAt, old.createdBy, old.createdByName, old.unitName
        record.updatedAt = os.time()
        record.updatedByName = agentName(src)
        Store.bolos[index] = record
        if not saveStore('bolos') then
            Store.bolos[index] = old
            return { ok = false, error = 'Erreur d\'écriture sur le serveur : modification annulée (voir console).' }
        end
    else
        local unit = findUnit(PlayerUnit[src])
        record.id = NextId.bolos
        record.number = uniqueValue('bolos', 'number', genCaseNumber)
        record.createdAt = os.time()
        record.createdByName = agentName(src)
        record.unitName = unit and unit.name or nil
        record.createdBy = getIdentifier(src) -- privé : jamais envoyé aux clients (voir publicView)
        Store.bolos[#Store.bolos + 1] = record
        if not saveStore('bolos') then
            table.remove(Store.bolos)
            return { ok = false, error = 'Erreur d\'écriture sur le serveur : rien n\'a été enregistré (voir console).' }
        end
        NextId.bolos = NextId.bolos + 1
    end

    pushBolos()
    print(('^5[MDC]^0 BOLO n°%s %s par %s [%s]'):format(record.number, old and 'modifié' or 'créé', agentName(src), GetPlayerName(src) or '?'))
    return { ok = true, id = record.id, number = record.number }
end)

-- Suppression définitive (BOLO levé)
RegisterMDCCallback('deleteBolo', function(src, payload)
    if Locked.bolos then
        return { ok = false, error = 'Suppression bloquée : fichier de données corrompu (voir console serveur).' }
    end
    local bolo, index = findBy('bolos', 'id', tonumber(payload.id))
    if not bolo then return { ok = false, error = 'Ce BOLO n\'existe plus.' } end

    table.remove(Store.bolos, index)
    if not saveStore('bolos') then
        table.insert(Store.bolos, index, bolo)
        return { ok = false, error = 'Erreur d\'écriture sur le serveur : suppression annulée (voir console).' }
    end

    pushBolos()
    print(('^5[MDC]^0 BOLO n°%s supprimé par %s [%s]'):format(bolo.number, agentName(src), GetPlayerName(src) or '?'))
    return { ok = true }
end)

-- Immatriculation complète saisie dans un BOLO : informations du véhicule enregistré
-- (remplissage automatique de la marque, du modèle et de la couleur)
RegisterMDCCallback('lookupPlate', function(_, payload)
    local plate = normalizePlate(payload.plate)
    local vehicle = plate ~= '' and findBy('vehicles', 'plate', plate)
    if not vehicle then return { ok = true, found = false } end
    local owner = ownerOf(vehicle)
    return { ok = true, found = true, vehicle = {
        id = vehicle.id, plate = vehicle.plate, make = vehicle.make, model = vehicle.model, color = vehicle.color,
        ownerId = owner and owner.id or nil, ownerLabel = owner and identityLabel(owner) or nil,
    } }
end)

-- =========================================================================
-- ESPACE PARTAGÉ D'UNITÉ
-- Les membres d'une même unité partagent :
--   - les recherches : saisie en direct, résultats, historique ;
--   - le rapport en cours de rédaction (chacun voit l'autre écrire et peut le compléter).
-- Gardé en mémoire avec l'unité (perdu au redémarrage, comme les unités).
-- =========================================================================
local SEARCH_FIELDS = { lastname = 40, firstname = 40, dob = 10, ssn = 11, query = 17 }
local MAX_DRAFT_SIZE = 60000 -- octets (JSON) d'un rapport en cours de rédaction

local function sharedOf(unit)
    unit.shared = unit.shared or { history = {} }
    return unit.shared
end

local function sendToMembers(unit, exceptSrc, scope, payload, latent)
    for key in pairs(unit.members) do
        local member = tonumber(key)
        if member ~= exceptSrc then
            if latent then
                TriggerLatentClientEvent('mdc:client:unitSync', member, Config.LatentBps, scope, payload)
            else
                TriggerClientEvent('mdc:client:unitSync', member, scope, payload)
            end
        end
    end
end

-- Résultats d'une recherche faite par un membre : en tête de l'historique commun,
-- et affichés chez les autres membres
shareUnitSearch = function(src, results)
    local unit = findUnit(PlayerUnit[src])
    if not unit or #results == 0 then return end
    local shared = sharedOf(unit)

    local list, seen = {}, {}
    local function add(kind, id)
        local key = kind .. ':' .. tostring(id)
        if not seen[key] and #list < Config.MaxSharedHistory then
            seen[key] = true
            list[#list + 1] = { kind = kind, id = id }
        end
    end
    for _, record in ipairs(results) do add(record.kind, record.id) end
    for _, entry in ipairs(shared.history) do add(entry.kind, entry.id) end
    shared.history = list

    sendToMembers(unit, src, 'searchResults', { results = results, by = agentName(src) }, true)
end

-- Historique commun avec les fiches à jour (les fiches supprimées par les cadres disparaissent)
local function historyRecords(shared)
    local out = {}
    for _, entry in ipairs(shared.history) do
        local record = findBy(entry.kind == 'vehicle' and 'vehicles' or 'identities', 'id', entry.id)
        if record then out[#out + 1] = entry.kind == 'vehicle' and vehicleView(record) or identityView(record) end
    end
    return out
end

local function draftView(draft)
    return {
        type = draft.type, id = draft.id, callRef = draft.callRef, call = draft.call,
        data = draft.data, startedName = draft.startedName,
    }
end

local function draftSize(data)
    local ok, encoded = pcall(json.encode, data)
    return ok and #encoded or math.huge
end

--- Chemin "units.0.lastname" (index JS à partir de 0) -> { 'units', 1, 'lastname' } (index Lua)
local function draftPath(path)
    if type(path) ~= 'string' or #path > 120 then return nil end
    local parts = {}
    for part in path:gmatch('[^%.]+') do
        if part:match('^%d+$') then
            parts[#parts + 1] = tonumber(part) + 1
        elseif part:match('^[%a_][%w_]*$') then
            parts[#parts + 1] = part
        else
            return nil
        end
    end
    if #parts == 0 or #parts > 8 then return nil end
    return parts
end

local function draftValue(value)
    local kind = type(value)
    if kind == 'string' then return truncate(value, 6000) end
    if kind == 'number' or kind == 'boolean' then return value end
    if kind == 'table' then -- cases multiples : liste de textes
        local out = {}
        for index, item in ipairs(value) do
            if type(item) == 'string' and index <= 40 then out[#out + 1] = truncate(item, 40) end
        end
        return out
    end
    return nil
end

local function draftCallRef(ref)
    if ref == 'keep' then return 'keep' end
    local id = tonumber(ref)
    return id and tostring(math.floor(id)) or ''
end

--- Applique une modification du rapport partagé. Retourne ce qu'il faut relayer aux autres membres.
local function applyDraftOp(shared, src, op)
    if op.op == 'start' then
        if not ReportTypes[op.type] or type(op.data) ~= 'table' or draftSize(op.data) > MAX_DRAFT_SIZE then return nil end
        local id = tonumber(op.id)
        if id then -- modification d'un rapport existant : commencée par son auteur uniquement
            local report = findBy('reports', 'id', id)
            if not report or report.createdBy ~= getIdentifier(src) then return nil end
        end
        local call = type(op.call) == 'table' and {
            number = clean(op.call.number, 7), title = clean(op.call.title, 60), kind = op.call.kind == 'incident' and 'incident' or 'intervention',
        } or nil
        shared.draft = {
            type = op.type, id = id, callRef = draftCallRef(op.callRef), call = call, data = op.data,
            startedBy = getIdentifier(src), startedName = agentName(src),
        }
        local view = draftView(shared.draft)
        view.op = 'start'
        return view, true
    end

    local draft = shared.draft
    if not draft then return nil end

    if op.op == 'set' then
        local parts, value = draftPath(op.path), draftValue(op.value)
        if not parts or value == nil then return nil end
        local target = draft.data
        for i = 1, #parts - 1 do target = type(target) == 'table' and target[parts[i]] or nil end
        if type(target) ~= 'table' then return nil end
        target[parts[#parts]] = value
        return { op = 'set', path = op.path, value = value }
    elseif op.op == 'replace' then
        if type(op.data) ~= 'table' or draftSize(op.data) > MAX_DRAFT_SIZE then return nil end
        draft.data = op.data
        return { op = 'replace', data = op.data }, true
    elseif op.op == 'call' then
        draft.callRef = draftCallRef(op.callRef)
        return { op = 'call', callRef = draft.callRef }
    elseif op.op == 'close' then
        shared.draft = nil
        return { op = 'close', saved = op.saved == true, number = clean(op.number, 7) }
    end
    return nil
end

-- État partagé à l'ouverture du MDC ou en rejoignant une unité
RegisterMDCCallback('getUnitShared', function(src)
    local unit = findUnit(PlayerUnit[src])
    if not unit then return { ok = true, inUnit = false } end
    local shared = sharedOf(unit)
    return {
        ok = true, inUnit = true, unitId = unit.id,
        searchForm = shared.form,
        history = historyRecords(shared),
        draft = shared.draft and draftView(shared.draft) or nil,
    }
end, true)

-- Modifications en direct d'un membre (saisie de recherche, historique, rapport)
RegisterNetEvent('mdc:server:unitSync', function(scope, payload)
    local src = source
    if not hasAccess(src) or type(payload) ~= 'table' then return end
    local unit = findUnit(PlayerUnit[src])
    if not unit then return end
    local shared = sharedOf(unit)
    local by = agentName(src)

    if scope == 'searchForm' then
        local form = { type = payload.type == 'vehicle' and 'vehicle' or 'identity' }
        for key, maxLen in pairs(SEARCH_FIELDS) do form[key] = clean(payload[key], maxLen) end
        shared.form = form
        sendToMembers(unit, src, 'searchForm', { form = form, by = by })
    elseif scope == 'searchClear' then
        shared.history = {}
        sendToMembers(unit, src, 'searchClear', { by = by })
    elseif scope == 'draft' then
        local relay, large = applyDraftOp(shared, src, payload)
        if relay then
            relay.by = by
            sendToMembers(unit, src, 'draft', relay, large)
        end
    end
end)

-- =========================================================================
-- HUD : display MDC (nom de l'unité, tag, statut, n° d'incident de l'appel)
-- Envoyé à chaque membre d'une unité, uniquement quand ses informations changent
-- (aucune boucle). Le client (client/hud.lua) n'affiche le HUD que dans une unité.
-- =========================================================================
local HudCache = {} -- [source] = clé des dernières informations envoyées

--- Informations du HUD pour un joueur (nil s'il ne fait partie d'aucune unité).
local function hudFor(src)
    local unit = findUnit(PlayerUnit[src])
    if not unit then return nil end

    -- Appel en cours de l'unité : le plus récent non terminé
    local call
    for _, intervention in ipairs(Interventions) do
        if not intervention.closed and intervention.units[tostring(unit.id)]
            and (not call or intervention.id > call.id) then
            call = intervention
        end
    end

    return {
        name = unit.name, tag = unit.tag, color = unit.color, dept = unit.dept, status = unit.status,
        callNumber = call and call.number or nil,
        callTitle = call and call.title or nil,
    }
end

local function hudKey(info)
    if not info then return '' end
    return table.concat({ info.name, info.tag, info.color, info.dept or '', info.status, info.callNumber or '', info.callTitle or '' }, '|')
end

local function sendHud(src, force)
    local info = hudFor(src)
    local key = hudKey(info)
    if force or HudCache[src] ~= key then
        HudCache[src] = key ~= '' and key or nil
        TriggerClientEvent('mdc:client:hud', src, hasAccess(src), info)
    end
end

pushHud = function()
    local done = {}
    for src in pairs(PlayerUnit) do
        done[src] = true
        sendHud(src)
    end
    -- Joueurs sortis d'une unité : HUD vidé
    for src in pairs(HudCache) do
        if not done[src] then sendHud(src) end
    end
end

-- Demande du client au démarrage (accès au MDC + unité actuelle)
RegisterNetEvent('mdc:server:hudSync', function()
    sendHud(source, true)
end)

-- =========================================================================
-- DÉCONNEXION
-- =========================================================================
AddEventHandler('playerDropped', function()
    local src = source
    local hadUnit = PlayerUnit[src] ~= nil
    leaveCurrentUnit(src)
    Viewers[src], lastStatusChange[src], lastWrite[src], HudCache[src] = nil, nil, nil, nil
    if hadUnit then pushUnits() end
end)
