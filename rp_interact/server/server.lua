--[[
    RP Interact - Serveur
    ---------------------
    PROFILS CIVILS (permanents) : data/profiles.json
      Chaque joueur crée ses profils (retrouvés grâce à sa licence Rockstar), en choisit un
      "actif" : c'est lui que la police découvre en l'inspectant / le fouillant avec l'œil.
      Ils survivent aux déconnexions et aux redémarrages du serveur.
      >>> BASE DE DONNÉES : remplacez uniquement loadProfiles() / saveProfiles().

    PROFILS DE VÉHICULE (temporaires) : en mémoire uniquement
      Liés au véhicule physique (entité réseau) : supprimés dès que le véhicule disparaît
      (OneSync : événement "entityRemoved" + vérification à chaque lecture) ou au redémarrage.

    POLICIER : joueur dans une unité du MDC (export mdc_standalone:getPlayerUnit). Lui seul
    accède aux fouilles et aux détails notoires ; tout le monde peut faire les inspections
    visuelles et olfactives.
]]

local Config = InteractConfig
local RESOURCE = GetCurrentResourceName()
local DATA_FILE = 'data/profiles.json'
local ONESYNC = GetConvar('onesync', 'off') ~= 'off'

-- =========================================================================
-- OUTILS TEXTE
-- =========================================================================
local function truncate(str, maxLen)
    local length = utf8.len(str)
    if length and length > maxLen then
        return str:sub(1, utf8.offset(str, maxLen + 1) - 1)
    end
    return length and str or str:sub(1, maxLen)
end

local function clean(str, maxLen)
    if type(str) ~= 'string' then return '' end
    str = str:gsub('%c', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return truncate(str, maxLen)
end

-- Comme clean() mais conserve les retours à la ligne (zones de texte)
local function cleanMultiline(str, maxLen)
    if type(str) ~= 'string' then return '' end
    str = str:gsub('\r', ''):gsub('[\1-\9\11-\31]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return truncate(str, maxLen)
end

local function getIdentifier(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return ('source:%d'):format(src)
end

-- =========================================================================
-- STOCKAGE DES PROFILS CIVILS (fichier JSON)
-- =========================================================================
local Profiles = {}
local NextProfileId = 1
local Locked = false -- fichier illisible : on refuse d'écrire pour ne rien perdre

local function loadProfiles()
    -- >>> BASE DE DONNÉES : SELECT * FROM rp_profiles
    local raw = LoadResourceFile(RESOURCE, DATA_FILE)
    Profiles, NextProfileId, Locked = {}, 1, false
    if raw and raw:match('%S') then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            for _, profile in ipairs(decoded) do
                if type(profile) == 'table' and type(profile.id) == 'number' then
                    Profiles[#Profiles + 1] = profile
                    if profile.id >= NextProfileId then NextProfileId = profile.id + 1 end
                end
            end
        else
            Locked = true
            print(('^1[RP Interact] ERREUR : %s est illisible (JSON invalide). Les profils ne seront pas ' ..
                'enregistrés tant que le fichier n\'est pas corrigé (puis "rpi_reload").^0'):format(DATA_FILE))
        end
    end
    print(('^5[RP Interact]^0 %d profil(s) civil(s) chargé(s).'):format(#Profiles))
    return raw ~= nil
end

local function saveProfiles()
    if Locked then return false end
    -- >>> BASE DE DONNÉES : INSERT / UPDATE / DELETE ciblé
    local ok = SaveResourceFile(RESOURCE, DATA_FILE, json.encode(Profiles, { indent = true }), -1)
    if not ok then
        print(('^1[RP Interact] ERREUR : impossible d\'écrire %s (le dossier "data" existe-t-il ?).^0'):format(DATA_FILE))
    end
    return ok
end

if not loadProfiles() and not Locked then saveProfiles() end

RegisterCommand('rpi_reload', function(source)
    if source ~= 0 then return end
    loadProfiles()
end, true)

local function findProfile(id)
    for index, profile in ipairs(Profiles) do
        if profile.id == id then return profile, index end
    end
    return nil
end

local function profilesOf(owner)
    local list = {}
    for _, profile in ipairs(Profiles) do
        if profile.owner == owner then list[#list + 1] = profile end
    end
    return list
end

local function activeProfileOf(owner)
    for _, profile in ipairs(Profiles) do
        if profile.owner == owner and profile.active then return profile end
    end
    return nil
end

local function profileView(profile)
    local view = {}
    for k, v in pairs(profile) do
        if k ~= 'owner' then view[k] = v end
    end
    return view
end

-- Parties d'un profil civil : case cochée (known) + texte
local PROFILE_PARTS = {
    { key = 'visual', label = 'Inspection > Visuel' },
    { key = 'olfactory', label = 'Inspection > Olfactif' },
    { key = 'upper', label = 'Fouille > Partie supérieure du corps' },
    { key = 'lower', label = 'Fouille > Partie inférieure du corps' },
}

--- Valide un profil reçu de l'interface. Retourne (profil) ou (nil, erreur).
local function buildProfile(p)
    local r = { name = clean(p.name, 40), notable = cleanMultiline(p.notable, Config.TextMax) }
    if r.name == '' then return nil, 'Donnez un nom au profil.' end
    for _, part in ipairs(PROFILE_PARTS) do
        local known = p[part.key .. 'Known'] == true
        r[part.key .. 'Known'] = known
        r[part.key] = known and cleanMultiline(p[part.key], Config.TextMax) or ''
        if known and r[part.key] == '' then
            return nil, ('%s : décrivez ce qu\'il y a (ou décochez la case).'):format(part.label)
        end
    end
    return r
end

-- =========================================================================
-- PROFILS DE VÉHICULE (mémoire, liés à l'entité)
-- =========================================================================
local VehicleProfiles = {} -- [netId] = profil

local function vehicleEntity(netId)
    if not ONESYNC then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    return entity
end

--- Profil du véhicule, ou nil s'il n'existe plus (véhicule supprimé, n° réseau réutilisé)
local function vehicleProfile(netId)
    local profile = VehicleProfiles[netId]
    if profile and ONESYNC then
        local entity = vehicleEntity(netId)
        if entity ~= profile.entity then
            VehicleProfiles[netId] = nil
            return nil
        end
    end
    return profile
end

-- OneSync : véhicule supprimé -> profil supprimé
AddEventHandler('entityRemoved', function(entity)
    for netId, profile in pairs(VehicleProfiles) do
        if profile.entity == entity then VehicleProfiles[netId] = nil end
    end
end)

local VEHICLE_TEXTS = { 'olfactory', 'notable', 'cabin', 'rear', 'trunk' }

local function buildVehicleProfile(p)
    local r = { visualKnown = p.visualKnown == true }
    r.interior = r.visualKnown and cleanMultiline(p.interior, Config.TextMax) or ''
    r.exterior = r.visualKnown and cleanMultiline(p.exterior, Config.TextMax) or ''
    if r.visualKnown and r.interior == '' and r.exterior == '' then
        return nil, 'Inspection visuelle : remplissez l\'intérieur et / ou l\'extérieur (ou décochez la case).'
    end
    for _, key in ipairs(VEHICLE_TEXTS) do r[key] = cleanMultiline(p[key], Config.TextMax) end
    return r
end

-- =========================================================================
-- POSITION ET POLICE
-- =========================================================================
local function coordsOfEntity(entity)
    if not entity or entity == 0 then return nil end
    local c = GetEntityCoords(entity)
    if not c or (c.x == 0 and c.y == 0 and c.z == 0) then return nil end
    return c
end

local function playerCoords(src)
    if not ONESYNC then return nil end
    return coordsOfEntity(GetPlayerPed(src))
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- true si les deux positions sont connues et trop éloignées (sinon on ne bloque pas)
local function tooFar(a, b, maxDistance)
    return a ~= nil and b ~= nil and distance(a, b) > maxDistance
end

-- Noms réels du MDC et du chat : publiés par ces ressources elles-mêmes (GlobalState, modifiable
-- uniquement par le serveur), donc corrects même si leurs dossiers ont été renommés.
local function mdcResource() return GlobalState.mdcResource or Config.MdcResource end
local function chatResource() return GlobalState.rpChatResource or Config.ChatResource end

local mdcWarned = false
local function warnMdc(reason)
    if mdcWarned then return end
    mdcWarned = true
    print(('^3[RP Interact] Statut "policier" indisponible : %s. Personne ne peut fouiller tant que le MDC ' ..
        '(v1.18 ou plus récent) n\'est pas démarré. Vérifiez "ensure" du MDC dans server.cfg.^0'):format(reason))
end

--- Unité MDC du joueur (table) ou nil : seul un joueur dans une unité du MDC est "policier".
--- Lu en direct à chaque demande : en service dès qu'il rejoint une unité, plus en service dès qu'il la quitte.
local function policeUnit(src)
    local resource = mdcResource()
    if GetResourceState(resource) ~= 'started' then
        warnMdc(('ressource "%s" non démarrée'):format(resource))
        return nil
    end
    local ok, unit = pcall(function() return exports[resource]:getPlayerUnit(src) end)
    if not ok then
        warnMdc(('le MDC "%s" ne fournit pas l\'export getPlayerUnit (version trop ancienne ?)'):format(resource))
        return nil
    end
    mdcWarned = false
    return type(unit) == 'table' and unit or nil
end

local function announce(src, text)
    local resource = chatResource()
    if not Config.AnnounceWithMe or not text or GetResourceState(resource) ~= 'started' then return end
    pcall(function() exports[resource]:sendMe(src, text) end)
end

-- Vérification au démarrage : le MDC est-il là et à jour ?
SetTimeout(5000, function() policeUnit(0) end)

-- =========================================================================
-- INSPECTIONS (œil)
-- =========================================================================
-- police = réservé aux joueurs dans une unité du MDC ; me = annonce RP dans le chat
local PERSON_FIELDS = {
    visual    = { title = 'Inspection visuelle', defaults = 'visual', me = 'observe attentivement l\'individu' },
    olfactory = { title = 'Inspection olfactive', defaults = 'olfactory', me = 'sent l\'odeur qui se dégage de l\'individu' },
    upper     = { title = 'Fouille de la partie supérieure du corps', defaults = 'search', police = true, search = 'person',
                  me = 'fouille la partie supérieure du corps de l\'individu' },
    lower     = { title = 'Fouille de la partie inférieure du corps', defaults = 'search', police = true, search = 'person',
                  me = 'fouille la partie inférieure du corps de l\'individu' },
    notable   = { title = 'Détail notoire', defaults = 'notable', police = true },
}
local VEHICLE_FIELDS = {
    visualInterior = { title = 'Inspection visuelle intérieure', defaults = 'vehicleVisual', me = 'inspecte visuellement l\'intérieur du véhicule' },
    visualExterior = { title = 'Inspection visuelle extérieure', defaults = 'vehicleVisual', me = 'fait le tour du véhicule pour l\'inspecter' },
    olfactory      = { title = 'Inspection olfactive', defaults = 'vehicleOlfactory', me = 'sent l\'odeur qui se dégage du véhicule' },
    notable        = { title = 'Détail notoire', defaults = 'notable', police = true },
    cabin          = { title = 'Fouille de l\'habitacle', defaults = 'vehicleSearch', police = true, search = 'vehicle', me = 'fouille l\'habitacle du véhicule' },
    rear           = { title = 'Fouille de la banquette arrière', defaults = 'vehicleSearch', police = true, search = 'vehicle', me = 'fouille la banquette arrière du véhicule' },
    trunk          = { title = 'Fouille du coffre', defaults = 'vehicleSearch', police = true, search = 'vehicle', me = 'fouille le coffre du véhicule' },
}

--- Réponse par défaut : toujours la même pour une même cible et une même case
local function defaultText(listName, key)
    local list = Config.Defaults[listName] or { 'Rien à signaler' }
    local hash = 0
    for i = 1, #key do hash = (hash * 31 + key:byte(i)) % 1000003 end
    return list[hash % #list + 1]
end

local function personValue(profile, field, key)
    local spec = PERSON_FIELDS[field]
    if profile then
        if field == 'notable' then
            if profile.notable ~= '' then return profile.notable end
        elseif profile[field .. 'Known'] and profile[field] ~= '' then
            return profile[field]
        end
    end
    return defaultText(spec.defaults, key .. ':' .. field)
end

local VEHICLE_TEXT_OF = { visualInterior = 'interior', visualExterior = 'exterior' }

local function vehicleValue(profile, field, key)
    local spec = VEHICLE_FIELDS[field]
    if profile then
        local textKey = VEHICLE_TEXT_OF[field] or field
        local visual = VEHICLE_TEXT_OF[field] ~= nil
        if (not visual or profile.visualKnown) and profile[textKey] ~= '' then return profile[textKey] end
    end
    return defaultText(spec.defaults, key .. ':' .. field)
end

-- =========================================================================
-- SYSTÈME DE CALLBACKS (requête client -> réponse serveur)
-- =========================================================================
local Handlers = {}
local lastWrite, lastInspect = {}, {}

local function on(name, fn) Handlers[name] = fn end

RegisterNetEvent('rp_interact:server:request', function(name, id, payload)
    local src = source
    if type(name) ~= 'string' or type(id) ~= 'number' then return end
    local handler = Handlers[name]
    local result
    if not handler then
        result = { ok = false, error = 'Action inconnue.' }
    else
        local ok, res = pcall(handler, src, type(payload) == 'table' and payload or {})
        if ok then
            result = res or { ok = true }
        else
            print(('^1[RP Interact] Erreur dans "%s" : %s^0'):format(name, res))
            result = { ok = false, error = 'Erreur serveur.' }
        end
    end
    TriggerClientEvent('rp_interact:client:response', src, id, result)
end)

local function writeCooldown(src)
    local now = GetGameTimer()
    if lastWrite[src] and now - lastWrite[src] < 1000 then return false end
    lastWrite[src] = now
    return true
end

-- ---- Menu d'interactions : profil actif et service de police ----
on('getMenuState', function(src)
    local active = activeProfileOf(getIdentifier(src))
    local unit = policeUnit(src)
    return { ok = true, activeName = active and active.name or nil, police = unit and unit.name or nil }
end)

-- ---- Profils civils (uniquement ceux du joueur) ----
on('getProfiles', function(src)
    local list = {}
    for _, profile in ipairs(profilesOf(getIdentifier(src))) do list[#list + 1] = profileView(profile) end
    -- Les plus récemment modifiés d'abord (à égalité : le plus récent créé)
    table.sort(list, function(a, b)
        local ta, tb = a.updatedAt or a.createdAt or 0, b.updatedAt or b.createdAt or 0
        if ta ~= tb then return ta > tb end
        return a.id > b.id
    end)
    return { ok = true, profiles = list, max = Config.MaxProfiles }
end)

on('saveProfile', function(src, p)
    if Locked then return { ok = false, error = 'Enregistrement bloqué : fichier de données illisible (voir console serveur).' } end
    local owner = getIdentifier(src)
    local id = tonumber(p.id)
    local old, index
    if id then
        old, index = findProfile(id)
        if not old or old.owner ~= owner then return { ok = false, error = 'Profil introuvable.' } end
    elseif #profilesOf(owner) >= Config.MaxProfiles then
        return { ok = false, error = ('%d profils maximum : supprimez-en un.'):format(Config.MaxProfiles) }
    end

    local record, err = buildProfile(p)
    if not record then return { ok = false, error = err } end
    if not writeCooldown(src) then return { ok = false, error = 'Patientez un instant.' } end

    record.owner = owner
    if old then
        record.id, record.createdAt, record.active = old.id, old.createdAt, old.active
        record.updatedAt = os.time()
        Profiles[index] = record
        if not saveProfiles() then
            Profiles[index] = old
            return { ok = false, error = 'Erreur d\'écriture sur le serveur (voir console).' }
        end
    else
        record.id = NextProfileId
        record.createdAt = os.time()
        record.active = activeProfileOf(owner) == nil -- premier profil : actif d'office
        Profiles[#Profiles + 1] = record
        if not saveProfiles() then
            table.remove(Profiles)
            return { ok = false, error = 'Erreur d\'écriture sur le serveur (voir console).' }
        end
        NextProfileId = NextProfileId + 1
    end
    return { ok = true, id = record.id, active = record.active }
end)

on('deleteProfile', function(src, p)
    if Locked then return { ok = false, error = 'Suppression bloquée : fichier de données illisible.' } end
    local profile, index = findProfile(tonumber(p.id))
    if not profile or profile.owner ~= getIdentifier(src) then return { ok = false, error = 'Profil introuvable.' } end
    table.remove(Profiles, index)
    if not saveProfiles() then
        table.insert(Profiles, index, profile)
        return { ok = false, error = 'Erreur d\'écriture sur le serveur (voir console).' }
    end
    return { ok = true }
end)

-- Profil actif (id = nil : aucun)
on('setActive', function(src, p)
    if Locked then return { ok = false, error = 'Modification bloquée : fichier de données illisible.' } end
    local owner = getIdentifier(src)
    local id = tonumber(p.id)
    if id then
        local profile = findProfile(id)
        if not profile or profile.owner ~= owner then return { ok = false, error = 'Profil introuvable.' } end
    end
    for _, profile in ipairs(Profiles) do
        if profile.owner == owner then profile.active = profile.id == id end
    end
    saveProfiles()
    return { ok = true }
end)

-- ---- Profil du véhicule (temporaire) ----
local function checkVehicle(src, netId)
    netId = tonumber(netId)
    if not netId then return nil, 'Véhicule introuvable.' end
    local entity = vehicleEntity(netId)
    if ONESYNC then
        if not entity or GetEntityType(entity) ~= 2 then return nil, 'Véhicule introuvable.' end
        if tooFar(playerCoords(src), coordsOfEntity(entity), 10.0) then
            return nil, 'Placez-vous dans le véhicule ou juste à côté.'
        end
    end
    return netId, entity
end

on('getVehicleProfile', function(src, p)
    local netId, entity = checkVehicle(src, p.netId)
    if not netId then return { ok = false, error = entity } end
    local profile = vehicleProfile(netId)
    if not profile then return { ok = true, profile = nil } end
    local mine = profile.owner == getIdentifier(src)
    return { ok = true, profile = mine and profileView(profile) or nil, taken = not mine }
end)

on('saveVehicleProfile', function(src, p)
    local netId, entity = checkVehicle(src, p.netId)
    if not netId then return { ok = false, error = entity } end
    local owner = getIdentifier(src)
    local old = vehicleProfile(netId)
    if old and old.owner ~= owner then
        return { ok = false, error = 'Ce véhicule a déjà un profil créé par un autre joueur.' }
    end
    local record, err = buildVehicleProfile(p)
    if not record then return { ok = false, error = err } end
    if not writeCooldown(src) then return { ok = false, error = 'Patientez un instant.' } end

    record.owner, record.netId, record.entity = owner, netId, entity
    record.label, record.plate = clean(p.label, 40), clean(p.plate, 10)
    record.createdAt = old and old.createdAt or os.time()
    record.updatedAt = old and os.time() or nil
    VehicleProfiles[netId] = record
    return { ok = true }
end)

on('deleteVehicleProfile', function(src, p)
    local netId = tonumber(p.netId)
    local profile = netId and vehicleProfile(netId)
    if not profile or profile.owner ~= getIdentifier(src) then return { ok = false, error = 'Aucun profil à supprimer.' } end
    VehicleProfiles[netId] = nil
    return { ok = true }
end)

-- ---- Inspection d'une personne ou d'un véhicule (œil) ----
-- p = { kind = 'player' | 'npc' | 'vehicle', target = id serveur (player) / n° réseau, field, label }
-- Observations (visuel, olfactif, détail notoire) : jusqu'à ObserveDistance (10 m), immédiates.
-- Fouilles : jusqu'à SearchDistance (3 m), après une barre de chargement (15 s personne, 35 s véhicule) :
--   "startSearch" la démarre (annonce /me), "inspect" donne le résultat une fois le temps écoulé.
-- Une personne est toujours désignée "Individu" (ni nom, ni profil, ni PNJ).
local OBSERVE_RANGE = Config.ObserveDistance + 2.0  -- tolérance (décalage réseau)
local SEARCH_RANGE = Config.SearchDistance + 1.5
local SEARCH_EARLY = 1500                           -- ms de tolérance sur la durée d'une fouille
local Searches = {}                                 -- [joueur] = { key, ready (GetGameTimer) }

local function fieldSpec(p)
    local fields = (p.kind == 'vehicle') and VEHICLE_FIELDS or PERSON_FIELDS
    local spec = fields[p.field]
    if not spec or (p.kind ~= 'player' and p.kind ~= 'npc' and p.kind ~= 'vehicle') then return nil end
    return spec
end

local function searchKey(p)
    return table.concat({ p.kind, tostring(p.target or p.label or ''), p.field }, ':')
end

--- Cible encore présente et assez proche ? Retourne un message d'erreur, sinon nil.
local function checkTarget(src, p, range)
    local target = tonumber(p.target)
    if p.kind == 'player' then
        if not target or not GetPlayerName(target) then return 'Cette personne n\'est plus là.' end
        if target == src and not Config.AllowSelfTarget then return 'Action impossible.' end
        if tooFar(playerCoords(src), playerCoords(target), range) then return 'Rapprochez-vous de la personne.' end
    elseif p.kind == 'vehicle' and target and ONESYNC then
        local entity = vehicleEntity(target)
        if entity and tooFar(playerCoords(src), coordsOfEntity(entity), range + 2.5) then -- + taille du véhicule
            return 'Rapprochez-vous du véhicule.'
        end
    end
    return nil
end

on('startSearch', function(src, p)
    local spec = fieldSpec(p)
    if not spec or not spec.search then return { ok = false, error = 'Action impossible.' } end
    if not policeUnit(src) then return { ok = false, error = 'Réservé à la police : rejoignez une unité dans le MDC.' } end
    local err = checkTarget(src, p, SEARCH_RANGE)
    if err then return { ok = false, error = err } end
    local duration = Config.SearchDurations[spec.search] or 15000
    Searches[src] = { key = searchKey(p), ready = GetGameTimer() + duration - SEARCH_EARLY }
    announce(src, spec.me) -- la fouille commence : visible par les joueurs autour
    return { ok = true, duration = duration }
end)

on('inspect', function(src, p)
    local spec = fieldSpec(p)
    if not spec then return { ok = false, error = 'Action impossible.' } end
    if spec.police and not policeUnit(src) then
        return { ok = false, error = 'Réservé à la police : rejoignez une unité dans le MDC.' }
    end
    local now = GetGameTimer()
    if spec.search then
        local search = Searches[src]
        if not search or search.key ~= searchKey(p) or now < search.ready then
            return { ok = false, error = 'Fouille non terminée.' }
        end
        Searches[src] = nil
    else
        if lastInspect[src] and now - lastInspect[src] < Config.InspectCooldown then
            return { ok = false, error = 'Patientez un instant.' }
        end
        lastInspect[src] = now
    end
    local err = checkTarget(src, p, spec.search and SEARCH_RANGE or OBSERVE_RANGE)
    if err then return { ok = false, error = err } end

    local target = tonumber(p.target)
    local text, subject
    if p.kind == 'player' then
        local profile = activeProfileOf(getIdentifier(target))
        text = personValue(profile, p.field, 'player:' .. getIdentifier(target) .. ':' .. tostring(profile and profile.id or 0))
        subject = 'Individu'
    elseif p.kind == 'npc' then
        -- Personnage non joueur : pas de profil, réponses par défaut (présenté comme un individu)
        text = personValue(nil, p.field, 'npc:' .. tostring(target or p.label or ''))
        subject = 'Individu'
    else
        local profile = target and vehicleProfile(target) or nil
        text = vehicleValue(profile, p.field, 'vehicle:' .. tostring(target or p.label or ''))
        subject = clean(p.label, 60)
        if subject == '' then subject = 'Véhicule' end
    end

    if not spec.search then announce(src, spec.me) end
    return { ok = true, title = spec.title, subject = subject, text = text }
end)

-- =========================================================================
-- MODE CIVIL : un policier met en joue un civil (tips d'arrestation chez le civil)
-- Le client du policier (dans une unité du MDC) envoie, pendant qu'il vise avec une arme, la liste
-- des joueurs visés (visée directe ou à moins de AimRadius mètres de la ligne de visée).
-- Le serveur vérifie, puis prévient chaque civil visé (début / fin). Sans nouvelle du policier
-- (déconnexion, plantage), la mise en joue expire seule.
-- =========================================================================
local Aimed = {}     -- [civil] = { [policier] = expiration (GetGameTimer) }
local AimingAt = {}  -- [policier] = { [civil] = true }
local lastAimEvent = {}
local AIM_TTL = (Config.AimRefresh or 1500) * 2 + 500

local function aimEnded(civil)
    Aimed[civil] = nil
    TriggerClientEvent('rp_interact:client:aimed', civil, false)
end

local function releaseAim(police, civil)
    local set = Aimed[civil]
    if not set then return end
    set[police] = nil
    if next(set) == nil then aimEnded(civil) end
end

local function expireAim(civil)
    local set = Aimed[civil]
    if not set then return end
    local now = GetGameTimer()
    for police, expires in pairs(set) do
        if expires <= now then
            set[police] = nil
            if AimingAt[police] then AimingAt[police][civil] = nil end
        end
    end
    if next(set) == nil then aimEnded(civil) end
end

RegisterNetEvent('rp_interact:server:aiming', function(list)
    local src = source
    if type(list) ~= 'table' then return end
    local now = GetGameTimer()
    if lastAimEvent[src] and now - lastAimEvent[src] < 150 then return end
    lastAimEvent[src] = now

    local targets = {}
    if #list > 0 and policeUnit(src) then
        local origin = playerCoords(src)
        for i = 1, math.min(#list, 16) do
            local civil = tonumber(list[i])
            if civil and civil ~= src and GetPlayerName(civil)
                and not tooFar(origin, playerCoords(civil), (Config.AimRange or 60.0) + 10.0) then
                targets[civil] = true
            end
        end
    end

    for civil in pairs(AimingAt[src] or {}) do
        if not targets[civil] then releaseAim(src, civil) end
    end
    AimingAt[src] = next(targets) and targets or nil

    for civil in pairs(targets) do
        local wasAimed = Aimed[civil] ~= nil
        Aimed[civil] = Aimed[civil] or {}
        Aimed[civil][src] = now + AIM_TTL
        if not wasAimed then TriggerClientEvent('rp_interact:client:aimed', civil, true) end
        SetTimeout(AIM_TTL + 100, function() expireAim(civil) end)
    end
end)

-- =========================================================================
-- POLICE : MENOTTES, PRENDRE PAR LE BRAS, PLACER / SORTIR D'UN VÉHICULE (joueurs)
-- (sur les PNJ, le client du policier agit directement : rien à vérifier ici)
-- Le serveur vérifie la police (unité du MDC) et les distances, puis prévient le civil, dont le
-- client joue l'emote, s'attache au policier ou monte dans le véhicule.
-- =========================================================================
local ACTION_RANGE = Config.ActionDistance + 1.5
local Drags = {} -- [civil] = policier qui le tient par le bras

local function policeTarget(src, p, range)
    if not policeUnit(src) then return nil, 'Réservé à la police : rejoignez une unité dans le MDC.' end
    local target = tonumber(p.target)
    if not target or target == src or not GetPlayerName(target) then return nil, 'Cette personne n\'est plus là.' end
    if tooFar(playerCoords(src), playerCoords(target), range) then return nil, 'Rapprochez-vous de la personne.' end
    return target
end

local function stopDrag(civil)
    if not Drags[civil] then return end
    Drags[civil] = nil
    Player(civil).state:set('rpiDraggedBy', false, true)
    TriggerClientEvent('rp_interact:client:drag', civil, false)
end

on('cuff', function(src, p)
    local target, err = policeTarget(src, p, ACTION_RANGE)
    if not target then return { ok = false, error = err } end
    local cuffed = p.cuffed == true
    Player(target).state:set('rpiCuffed', cuffed, true)
    TriggerClientEvent('rp_interact:client:setCuffed', target, cuffed)
    if not cuffed then stopDrag(target) end
    return { ok = true }
end)

on('drag', function(src, p)
    if p.drag ~= true then
        local target = tonumber(p.target)
        if target and Drags[target] == src then stopDrag(target) end
        return { ok = true }
    end
    local target, err = policeTarget(src, p, ACTION_RANGE)
    if not target then return { ok = false, error = err } end
    if Drags[target] and Drags[target] ~= src then return { ok = false, error = 'Un autre policier tient déjà cette personne.' } end
    Drags[target] = src
    Player(target).state:set('rpiDraggedBy', src, true)
    TriggerClientEvent('rp_interact:client:drag', target, src)
    return { ok = true }
end)

-- Placer à l'arrière : le policier a ouvert la portière ; le civil y monte lui-même (sans téléportation)
on('putInVehicle', function(src, p)
    local target, err = policeTarget(src, p, Config.PlaceVehicleDistance + 3.0)
    if not target then return { ok = false, error = err } end
    local seat, netId = tonumber(p.seat), tonumber(p.netId)
    if (seat ~= 1 and seat ~= 2) or not netId then return { ok = false, error = 'Place arrière invalide.' } end
    if ONESYNC then
        local entity = vehicleEntity(netId)
        if not entity or tooFar(playerCoords(src), coordsOfEntity(entity), Config.PlaceVehicleDistance + 3.0) then
            return { ok = false, error = 'Rapprochez-vous du véhicule.' }
        end
    end
    stopDrag(target)
    TriggerClientEvent('rp_interact:client:enterVehicle', target, netId, seat)
    return { ok = true }
end)

on('takeOut', function(src, p)
    local target, err = policeTarget(src, p, Config.PlaceVehicleDistance + 3.0)
    if not target then return { ok = false, error = err } end
    TriggerClientEvent('rp_interact:client:leaveVehicle', target)
    return { ok = true }
end)

-- =========================================================================
-- SUPPRIMER DES ÉLÉMENTS AMBIANTS (PNJ, véhicules sans joueur, objets)
-- Réservé à DeleteAccess ('police' / 'everyone') ou à la permission ACE DeleteAce.
-- Les entités créées par des scripts (véhicules / objets "mission") ne sont pas supprimées.
-- Les objets de la carte sont masqués chez tous les joueurs (y compris ceux qui se connectent ensuite).
-- =========================================================================
local POPULATION_MISSION = 7
local HiddenProps = {} -- { model, x, y, z }

local function canDelete(src)
    if IsPlayerAceAllowed(src, Config.DeleteAce) then return true end
    if Config.DeleteAccess == 'everyone' then return true end
    return Config.DeleteAccess == 'police' and policeUnit(src) ~= nil
end

-- Droit ACE publié pour l'affichage de l'option (le serveur revérifie)
local function publishDeleteRight(src)
    Player(src).state:set('rpiCanDelete', IsPlayerAceAllowed(src, Config.DeleteAce) == true, true)
end
AddEventHandler('playerJoining', function() publishDeleteRight(source) end)
for _, id in ipairs(GetPlayers()) do publishDeleteRight(tonumber(id)) end

local function playerInVehicle(entity)
    for _, id in ipairs(GetPlayers()) do
        if GetVehiclePedIsIn(GetPlayerPed(id), false) == entity then return true end
    end
    return false
end

on('deleteEntity', function(src, p)
    if not canDelete(src) then return { ok = false, error = 'Vous ne pouvez pas supprimer d\'éléments.' } end
    if not ONESYNC then return { ok = false, fallback = true } end -- sans OneSync : suppression par le client
    local entity = NetworkGetEntityFromNetworkId(tonumber(p.netId) or -1)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return { ok = false, error = 'Élément introuvable.' } end
    if tooFar(playerCoords(src), coordsOfEntity(entity), OBSERVE_RANGE + 2.5) then return { ok = false, error = 'Rapprochez-vous.' } end
    local kind = GetEntityType(entity)
    if kind == 1 then
        if IsPedAPlayer(entity) then return { ok = false, error = 'Impossible de supprimer un joueur.' } end
    elseif kind == 2 then
        if playerInVehicle(entity) then return { ok = false, error = 'Un joueur est dans ce véhicule.' } end
        if GetEntityPopulationType(entity) == POPULATION_MISSION then
            return { ok = false, error = 'Véhicule non ambiant (créé par un joueur ou un script).' }
        end
    elseif kind == 3 then
        if GetEntityPopulationType(entity) == POPULATION_MISSION then
            return { ok = false, error = 'Objet créé par un script : non supprimé.' }
        end
    else
        return { ok = false, error = 'Élément introuvable.' }
    end
    DeleteEntity(entity)
    return { ok = true }
end)

on('hideProp', function(src, p)
    if not canDelete(src) then return { ok = false, error = 'Vous ne pouvez pas supprimer d\'éléments.' } end
    local model, x, y, z = tonumber(p.model), tonumber(p.x), tonumber(p.y), tonumber(p.z)
    if not model or not x or not y or not z then return { ok = false, error = 'Élément introuvable.' } end
    if tooFar(playerCoords(src), { x = x, y = y, z = z }, OBSERVE_RANGE + 5.0) then return { ok = false, error = 'Rapprochez-vous.' } end
    if #HiddenProps >= 1000 then table.remove(HiddenProps, 1) end
    local prop = { model = model, x = x, y = y, z = z }
    HiddenProps[#HiddenProps + 1] = prop
    TriggerClientEvent('rp_interact:client:hideProp', -1, prop)
    return { ok = true }
end)

on('getHiddenProps', function()
    return { ok = true, props = HiddenProps }
end)

-- Console / ACE : réaffiche tous les objets masqués
RegisterCommand('rpi_showprops', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.DeleteAce) then return end
    TriggerClientEvent('rp_interact:client:showProps', -1, HiddenProps)
    print(('^5[RP Interact]^0 %d objet(s) masqué(s) réaffiché(s).'):format(#HiddenProps))
    HiddenProps = {}
end, false)

-- =========================================================================
-- VÉHICULES D'URGENCE : /policeon et /policeoff (sans annonce ni notification)
-- Activé : seuls les policiers (unité du MDC) montent dans un véhicule de classe 18, sauf
-- portière déjà ouverte. Vérifié par chaque client (voir client/police.lua).
-- =========================================================================
local function canTogglePoliceVehicles(src)
    return src == 0 or IsPlayerAceAllowed(src, Config.PoliceVehiclesAce) or policeUnit(src) ~= nil
end

local function setPoliceVehicles(src, enabled)
    if not canTogglePoliceVehicles(src) then return end
    GlobalState.rpiPoliceVehicles = enabled
    print(('^5[RP Interact]^0 Véhicules d\'urgence réservés à la police : %s (par %s)'):format(
        enabled and 'ACTIVÉ' or 'désactivé', src == 0 and 'console' or (GetPlayerName(src) or tostring(src))))
end
RegisterCommand('policeon', function(src) setPoliceVehicles(src, true) end, false)
RegisterCommand('policeoff', function(src) setPoliceVehicles(src, false) end, false)

AddEventHandler('playerDropped', function()
    local src = source
    lastWrite[src], lastInspect[src], lastAimEvent[src], Searches[src] = nil, nil, nil, nil
    for civil in pairs(AimingAt[src] or {}) do releaseAim(src, civil) end
    AimingAt[src], Aimed[src] = nil, nil
    -- Policier parti : les civils qu'il tenait sont lâchés
    for civil, police in pairs(Drags) do
        if police == src then stopDrag(civil) end
    end
    Drags[src] = nil
end)
