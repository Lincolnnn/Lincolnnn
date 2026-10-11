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

--- Unité MDC du joueur (table) ou nil : seul un joueur en unité est "policier"
local function policeUnit(src)
    if GetResourceState(Config.MdcResource) ~= 'started' then return nil end
    local ok, unit = pcall(function() return exports[Config.MdcResource]:getPlayerUnit(src) end)
    return ok and type(unit) == 'table' and unit or nil
end

local function announce(src, text)
    if not Config.AnnounceWithMe or not text or GetResourceState(Config.ChatResource) ~= 'started' then return end
    pcall(function() exports[Config.ChatResource]:sendMe(src, text) end)
end

-- =========================================================================
-- INSPECTIONS (œil)
-- =========================================================================
-- police = réservé aux joueurs dans une unité du MDC ; me = annonce RP dans le chat
local PERSON_FIELDS = {
    visual    = { title = 'Inspection visuelle', defaults = 'visual', me = 'observe attentivement l\'individu' },
    olfactory = { title = 'Inspection olfactive', defaults = 'olfactory', me = 'sent l\'odeur qui se dégage de l\'individu' },
    upper     = { title = 'Fouille de la partie supérieure du corps', defaults = 'search', police = true,
                  me = 'fouille la partie supérieure du corps de l\'individu' },
    lower     = { title = 'Fouille de la partie inférieure du corps', defaults = 'search', police = true,
                  me = 'fouille la partie inférieure du corps de l\'individu' },
    notable   = { title = 'Détail notoire', defaults = 'notable', police = true },
}
local VEHICLE_FIELDS = {
    visualInterior = { title = 'Inspection visuelle intérieure', defaults = 'vehicleVisual', me = 'inspecte visuellement l\'intérieur du véhicule' },
    visualExterior = { title = 'Inspection visuelle extérieure', defaults = 'vehicleVisual', me = 'fait le tour du véhicule pour l\'inspecter' },
    olfactory      = { title = 'Inspection olfactive', defaults = 'vehicleOlfactory', me = 'sent l\'odeur qui se dégage du véhicule' },
    notable        = { title = 'Détail notoire', defaults = 'notable', police = true },
    cabin          = { title = 'Fouille de l\'habitacle', defaults = 'vehicleSearch', police = true, me = 'fouille l\'habitacle du véhicule' },
    rear           = { title = 'Fouille de la banquette arrière', defaults = 'vehicleSearch', police = true, me = 'fouille la banquette arrière du véhicule' },
    trunk          = { title = 'Fouille du coffre', defaults = 'vehicleSearch', police = true, me = 'fouille le coffre du véhicule' },
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
on('inspect', function(src, p)
    local fields = (p.kind == 'vehicle') and VEHICLE_FIELDS or PERSON_FIELDS
    local spec = fields[p.field]
    if not spec or (p.kind ~= 'player' and p.kind ~= 'npc' and p.kind ~= 'vehicle') then
        return { ok = false, error = 'Action impossible.' }
    end
    if spec.police and not policeUnit(src) then
        return { ok = false, error = 'Réservé à la police : rejoignez une unité dans le MDC.' }
    end
    local now = GetGameTimer()
    if lastInspect[src] and now - lastInspect[src] < Config.InspectCooldown then
        return { ok = false, error = 'Patientez un instant.' }
    end
    lastInspect[src] = now

    local target = tonumber(p.target)
    local text, subject
    if p.kind == 'player' then
        if not target or not GetPlayerName(target) then return { ok = false, error = 'Cette personne n\'est plus là.' } end
        if target == src and not Config.AllowSelfTarget then return { ok = false, error = 'Action impossible.' } end
        if tooFar(playerCoords(src), playerCoords(target), Config.InspectDistance) then
            return { ok = false, error = 'Rapprochez-vous de la personne.' }
        end
        local profile = activeProfileOf(getIdentifier(target))
        text = personValue(profile, p.field, 'player:' .. getIdentifier(target) .. ':' .. tostring(profile and profile.id or 0))
        subject = target == src and 'Vous-même (test)' or 'Individu'
    elseif p.kind == 'npc' then
        -- Personnage non joueur : pas de profil, réponses par défaut
        text = personValue(nil, p.field, 'npc:' .. tostring(target or p.label or ''))
        subject = 'Individu (PNJ)'
    else
        local profile = target and vehicleProfile(target) or nil
        if target and ONESYNC then
            local entity = vehicleEntity(target)
            if entity and tooFar(playerCoords(src), coordsOfEntity(entity), Config.InspectDistance) then
                return { ok = false, error = 'Rapprochez-vous du véhicule.' }
            end
        end
        text = vehicleValue(profile, p.field, 'vehicle:' .. tostring(target or p.label or ''))
        subject = clean(p.label, 60)
        if subject == '' then subject = 'Véhicule' end
    end

    announce(src, spec.me)
    return { ok = true, title = spec.title, subject = subject, text = text }
end)

AddEventHandler('playerDropped', function()
    lastWrite[source], lastInspect[source] = nil, nil
end)
