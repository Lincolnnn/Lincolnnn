--[[
    RP Interact - Voiture (spawn, radio) et Équipements (serveur)
    -------------------------------------------------------------
    - Fichiers JSON du dossier data/ (remplis à la main, relus avec la commande console "rpi_vehicles") :
      vehicles.json (véhicules du menu Voiture > Spawn), loadouts.json (armes du menu Équipements),
      outfits.json (tenues du menu /eup). Seuls les véhicules de vehicles.json peuvent être demandés ;
      véhicules de police réservés aux policiers en service si SpawnPoliceOnly.
    - Radio : état du véhicule "rpiRadio" = { url, start (heure UTC de lancement, s), volume (0-100),
      queue (file "Écouter ensuite", 5 liens max), history (5 morceaux précédents), seq (n° du morceau),
      paused (position en pause, s) }, lu par tous les clients (chacun joue le son, plus ou moins fort
      selon sa distance et les vitres / portières). Réglable par les places AVANT, ou par un joueur collé
      au véhicule (œil, portière avant ouverte) : lancer, ajouter à la file, pause / reprise, début du
      morceau (deux fois : morceau précédent), suivant, arrêter, volume. À la fin d'un morceau (signalée
      par un joueur qui l'entend), le suivant de la file démarre.
    - Équipements : armes de loadouts.json ; tenues de outfits.json (menu /eup, vérification de l'accès).
    Aucune boucle.
]]

local Config = InteractConfig
local S = RPIServer
local SERVICES = {
    ['atlanta police department'] = 'apd',
    ['georgia state patrol'] = 'gsp',
    ['fayette county sheriff office'] = 'fcso',
}

-- =========================================================================
-- FICHIERS JSON (data/*.json) : remplis à la main, relus avec "rpi_vehicles" (console)
-- =========================================================================
local function trim(text) return (tostring(text or '')):gsub('^%s+', ''):gsub('%s+$', '') end

--- Champ d'un objet JSON, quelle que soit la casse de la clé ("Name", "name", "NAME")
local function field(object, name)
    if type(object) ~= 'table' then return nil end
    if object[name] ~= nil then return object[name] end
    local lower = name:lower()
    for k, v in pairs(object) do
        if type(k) == 'string' and k:lower() == lower then return v end
    end
    return nil
end

--- Liste lue dans un fichier JSON (nil + message dans la console si absent / invalide)
local function readJsonList(path)
    local raw = LoadResourceFile(GetCurrentResourceName(), path)
    if not raw then
        print(('^3[RP Interact] %s introuvable.^0'):format(path))
        return nil
    end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        print(('^1[RP Interact] %s : JSON invalide (virgule en trop, guillemet manquant…). Fichier ignoré.^0'):format(path))
        return nil
    end
    return data
end

-- =========================================================================
-- VÉHICULES (data/vehicles.json)
--   [ { "Code": "police3", "Service": "Atlanta Police Department", "Name": "…", "Livery": 0, "Extras": [1, 2] } ]
-- =========================================================================
local Vehicles, byCode = {}, {}

local function loadVehicles()
    Vehicles, byCode = {}, {}
    local list = readJsonList('data/vehicles.json')
    if not list then return end
    for i, v in ipairs(list) do
        local code, label = trim(field(v, 'Code')), trim(field(v, 'Name'))
        if code == '' or label == '' then
            print(('^3[RP Interact] vehicles.json : véhicule n°%d ignoré (Code ou Name manquant).^0'):format(i))
        else
            local extras
            local rawExtras = field(v, 'Extras')
            if type(rawExtras) == 'table' and #rawExtras > 0 then
                extras = {}
                for _, n in ipairs(rawExtras) do if tonumber(n) then extras[#extras + 1] = math.floor(tonumber(n)) end end
            end
            local entry = {
                code = code:lower(), label = label:sub(1, 80),
                service = SERVICES[trim(field(v, 'Service')):lower()] or 'other',
                livery = tonumber(field(v, 'Livery')), extras = extras,
            }
            local existing = byCode[entry.code]
            if existing then
                -- Même code deux fois : le dernier l'emporte (à la même place dans la liste)
                existing.label, existing.service = entry.label, entry.service
                existing.livery, existing.extras = entry.livery, entry.extras
            else
                Vehicles[#Vehicles + 1] = entry
                byCode[entry.code] = entry
            end
        end
    end
    print(('^5[RP Interact]^0 %d véhicule(s) lu(s) dans data/vehicles.json'):format(#Vehicles))
end

-- =========================================================================
-- ARMES (data/loadouts.json) et TENUES (data/outfits.json, menu /eup)
-- =========================================================================
local Loadouts, Outfits = {}, {}

local function loadLoadouts()
    Loadouts = {}
    for _, l in ipairs(readJsonList('data/loadouts.json') or {}) do
        local name = trim(field(l, 'Name'))
        if name ~= '' then
            local weapons = {}
            for _, w in ipairs(type(field(l, 'Weapons')) == 'table' and field(l, 'Weapons') or {}) do
                local weapon = trim(field(w, 'Weapon')):upper()
                if weapon ~= '' then
                    local components = {}
                    for _, c in ipairs(type(field(w, 'Components')) == 'table' and field(w, 'Components') or {}) do
                        components[#components + 1] = trim(c):upper()
                    end
                    weapons[#weapons + 1] = { weapon = weapon, ammo = math.floor(tonumber(field(w, 'Ammo')) or 0), components = components }
                end
            end
            Loadouts[#Loadouts + 1] = { name = name:sub(1, 80), replace = field(l, 'Replace') == true, weapons = weapons }
        end
    end
end

-- Pièces d'une tenue : nom dans le fichier -> composant (component) ou accessoire (prop) du personnage
local OUTFIT_PARTS = {
    Hat = { prop = 0 }, Glasses = { prop = 1 }, Ear = { prop = 2 }, Watch = { prop = 6 }, Bracelet = { prop = 7 },
    Mask = { component = 1 }, UpperSkin = { component = 3 }, Pants = { component = 4 }, Parachute = { component = 5 },
    Shoes = { component = 6 }, Accessories = { component = 7 }, UnderCoat = { component = 8 }, Armor = { component = 9 },
    Decal = { component = 10 }, Top = { component = 11 },
}
local POLICE_GROUPS = {
    apd = 'APD', ['atlanta police department'] = 'APD',
    fcso = 'FCSO', ['fayette county sheriff office'] = 'FCSO',
    gsp = 'GSP', ['georgia state patrol'] = 'GSP',
}

local function loadOutfits()
    Outfits = {}
    local oneBased = not (Config.Eup and Config.Eup.OneBased == false)
    for i, o in ipairs(readJsonList('data/outfits.json') or {}) do
        local name = trim(field(o, 'Name'))
        if name == '' then
            print(('^3[RP Interact] outfits.json : tenue n°%d ignorée (Name manquant).^0'):format(i))
        else
            local gender = trim(field(o, 'Gender')):lower()
            gender = (gender == 'female' or gender == 'femme' or gender == 'f') and 'female'
                or ((gender == 'male' or gender == 'homme' or gender == 'm') and 'male' or nil)
            local cate = trim(field(o, 'Cate')):lower()
            local group = trim(field(o, 'Category2'))
            local isPolice = cate == 'police'
            if isPolice then group = POLICE_GROUPS[group:lower()] or (group ~= '' and group:upper() or 'Autres') end
            local components, props = {}, {}
            for part, target in pairs(OUTFIT_PARTS) do
                local value = field(o, part)
                local d, t = tostring(value or ''):match('^%s*(%-?%d+)%s*:%s*(%-?%d+)%s*$')
                d, t = tonumber(d), tonumber(t)
                if d then
                    if oneBased then d, t = d - 1, math.max((t or 1) - 1, 0) end
                    if target.prop then
                        props[#props + 1] = { target.prop, d, t or 0 } -- -1 : accessoire retiré
                    else
                        components[#components + 1] = { target.component, math.max(d, 0), t or 0 }
                    end
                end
            end
            Outfits[#Outfits + 1] = {
                index = #Outfits + 1, name = name:sub(1, 80), gender = gender,
                cate = isPolice and 'police' or 'civil', group = group ~= '' and group:sub(1, 40) or nil,
                components = components, props = props,
            }
        end
    end
end

local function loadAll()
    loadVehicles()
    loadLoadouts()
    loadOutfits()
    print(('^5[RP Interact]^0 %d tenue(s) (data/outfits.json), %d lot(s) d\'armes (data/loadouts.json)'):format(#Outfits, #Loadouts))
end

loadAll()
RegisterCommand('rpi_vehicles', function(src)
    if src == 0 or IsPlayerAceAllowed(src, Config.PoliceVehiclesAce) then loadAll() end
end, false)

local function isPolice(src) return S.policeUnit(src) ~= nil end

-- Permissions (config.lua : Permissions) : catégories réservées à certains joueurs
local DENIED = { ok = false, error = 'Accès réservé : vous n\'avez pas la permission.' }
local function allowed(src, section) return not S.hasPermission or S.hasPermission(src, section) end

S.on('vehicleList', function(src)
    if not allowed(src, 'car') then return DENIED end
    return { ok = true, vehicles = Vehicles, police = isPolice(src), policeOnly = Config.SpawnPoliceOnly ~= false }
end)

S.on('spawnVehicle', function(src, p)
    if not allowed(src, 'car') then return DENIED end
    local entry = byCode[type(p.code) == 'string' and p.code:lower() or '']
    if not entry then return { ok = false, error = 'Véhicule inconnu.' } end
    if entry.service ~= 'other' and Config.SpawnPoliceOnly ~= false and not isPolice(src) then
        return { ok = false, error = 'Véhicule de police : rejoignez une unité dans le MDC.' }
    end
    return { ok = true, vehicle = entry }
end)

-- =========================================================================
-- RADIO DU VÉHICULE
-- =========================================================================
local function vehicleFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
    return entity
end

--- Places avant (conducteur, passager avant) ou joueur collé au véhicule (œil, portière avant ouverte)
local function canUseRadio(src, vehicle)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    if GetPedInVehicleSeat(vehicle, -1) == ped or GetPedInVehicleSeat(vehicle, 0) == ped then return true end
    if GetVehiclePedIsIn(ped, false) == vehicle then return false end -- à l'arrière
    return #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= 4.0
end

local function validUrl(url)
    if type(url) ~= 'string' then return nil end
    url = trim(url)
    if #url > 400 or not url:match('^https?://[%w%-%.]+') or url:find('[%s<>"\']') then return nil end
    return url
end

local MAX_QUEUE = 5
local MAX_HISTORY = 5 -- morceaux précédents gardés (bouton "revenir au début" appuyé deux fois)
local trackSeq = 0 -- n° unique de chaque morceau lancé (deux morceaux peuvent démarrer dans la même seconde)

local function copyList(list, max)
    local out = {}
    for i, url in ipairs(type(list) == 'table' and list or {}) do
        if i > max then break end
        out[#out + 1] = url
    end
    return out
end
local function copyQueue(current) return copyList(current and current.queue, MAX_QUEUE) end
local function copyHistory(current) return copyList(current and current.history, MAX_HISTORY) end

--- État de la radio (champs absents : repris de `base`, l'état actuel) ; `seq = nil` dans `fields`
--- avec `new = true` : nouveau morceau. `paused` : position (s) du morceau en pause, sinon nil.
local function radioState(base, fields)
    base = base or {}
    local r = {
        url = fields.url or base.url, start = fields.start or base.start,
        volume = fields.volume or base.volume or 60, by = fields.by or base.by,
        queue = fields.queue or copyQueue(base), history = fields.history or copyHistory(base),
        seq = base.seq, paused = base.paused,
    }
    if fields.new then
        trackSeq = trackSeq + 1
        r.seq, r.paused = trackSeq, nil
    end
    if fields.paused ~= nil then r.paused = fields.paused or nil end
    return r
end

--- Lance `url` ; le morceau en cours passe dans l'historique (s'il y en a un)
local function playTrack(state, current, url, fields)
    fields = fields or {}
    local history = copyHistory(current)
    if current and current.url and not fields.noHistory then
        table.insert(history, current.url)
        while #history > MAX_HISTORY do table.remove(history, 1) end
    end
    state:set('rpiRadio', radioState(current, {
        url = url, start = os.time(), volume = fields.volume, by = fields.by,
        queue = fields.queue, history = history, new = true,
    }), true)
end

--- Morceau suivant de la file "Écouter ensuite" (ou radio coupée si la file est vide)
local function playNext(state, current)
    local queue = copyQueue(current)
    local nextUrl = table.remove(queue, 1)
    if nextUrl then
        playTrack(state, current, nextUrl, { queue = queue })
    else
        state:set('rpiRadio', false, true)
    end
end

S.on('radio', function(src, p)
    if not allowed(src, 'car') then return DENIED end
    local vehicle = vehicleFromNet(p.netId)
    if not vehicle then return { ok = false, error = 'Véhicule introuvable.' } end
    local state = Entity(vehicle).state
    local current = type(state.rpiRadio) == 'table' and state.rpiRadio or nil

    -- Fin d'un morceau (signalée par un joueur qui l'entend) : morceau suivant de la file
    if p.action == 'ended' then
        if not current or current.seq ~= tonumber(p.seq) or current.paused then return { ok = true } end -- déjà passé
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 40.0 then return { ok = false } end
        playNext(state, current)
        return { ok = true }
    end

    if not canUseRadio(src, vehicle) then
        return { ok = false, error = 'Seules les places avant peuvent régler la radio.' }
    end
    local function needOn() return not current and { ok = false, error = 'La radio est éteinte.' } or nil end
    if p.action == 'play' then
        local url = validUrl(p.url)
        if not url then return { ok = false, error = 'Lien invalide (adresse http:// ou https://).' } end
        local volume = math.floor(math.max(0, math.min(100, tonumber(p.volume) or (current and current.volume) or 60)))
        playTrack(state, current, url, { volume = volume, by = src })
    elseif p.action == 'queue' then
        -- "+" : ajouté à la file "Écouter ensuite" (radio éteinte : lancé tout de suite)
        local url = validUrl(p.url)
        if not url then return { ok = false, error = 'Lien invalide (adresse http:// ou https://).' } end
        if not current then
            local volume = math.floor(math.max(0, math.min(100, tonumber(p.volume) or 60)))
            playTrack(state, nil, url, { volume = volume, by = src })
        else
            local queue = copyQueue(current)
            if #queue >= MAX_QUEUE then return { ok = false, error = ('File pleine (%d morceaux au maximum).'):format(MAX_QUEUE) } end
            queue[#queue + 1] = url
            state:set('rpiRadio', radioState(current, { queue = queue }), true)
        end
    elseif p.action == 'unqueue' then
        if needOn() then return needOn() end
        local queue = copyQueue(current)
        local index = math.tointeger(tonumber(p.index))
        if not index or not queue[index] then return { ok = false, error = 'Morceau introuvable.' } end
        table.remove(queue, index)
        state:set('rpiRadio', radioState(current, { queue = queue }), true)
    elseif p.action == 'next' then
        if needOn() then return needOn() end
        playNext(state, current)
    elseif p.action == 'pause' then
        -- Pause / reprise : même morceau, repris là où il était (pour tout le monde)
        if needOn() then return needOn() end
        if current.paused then
            state:set('rpiRadio', radioState(current, { start = os.time() - current.paused, paused = false }), true)
        else
            local position = math.max(0, os.time() - (tonumber(current.start) or os.time()))
            state:set('rpiRadio', radioState(current, { paused = position }), true)
        end
    elseif p.action == 'restart' then
        -- Retour au début du morceau (relancé pour tout le monde, pas d'entrée dans l'historique)
        if needOn() then return needOn() end
        playTrack(state, current, current.url, { queue = copyQueue(current), noHistory = true })
    elseif p.action == 'previous' then
        -- Morceau précédent (bouton "début" appuyé deux fois) : le morceau en cours revient en tête de file
        if needOn() then return needOn() end
        local history = copyHistory(current)
        local previous = table.remove(history)
        if not previous then return { ok = false, error = 'Aucun morceau précédent.' } end
        local queue = copyQueue(current)
        table.insert(queue, 1, current.url)
        while #queue > MAX_QUEUE do table.remove(queue) end
        state:set('rpiRadio', radioState(current, {
            url = previous, start = os.time(), queue = queue, history = history, new = true,
        }), true)
    elseif p.action == 'stop' then
        state:set('rpiRadio', false, true)
    elseif p.action == 'volume' then
        if needOn() then return needOn() end
        local volume = math.floor(math.max(0, math.min(100, tonumber(p.volume) or current.volume)))
        state:set('rpiRadio', radioState(current, { volume = volume }), true)
    else
        return { ok = false, error = 'Action inconnue.' }
    end
    return { ok = true, radio = state.rpiRadio or false }
end)

-- =========================================================================
-- ÉQUIPEMENTS : armes (data/loadouts.json) et tenues (data/outfits.json, menu /eup)
-- =========================================================================
S.on('loadoutList', function(src)
    local list = {}
    for i, l in ipairs(Loadouts) do list[#list + 1] = { index = i, name = l.name } end
    return { ok = true, loadouts = list, police = isPolice(src), policeOnly = Config.EquipmentPoliceOnly ~= false }
end)

S.on('equipment', function(src, p)
    if not allowed(src, 'equipment') then return DENIED end
    if Config.EquipmentPoliceOnly ~= false and not isPolice(src) then
        return { ok = false, error = 'Réservé à la police : rejoignez une unité dans le MDC.' }
    end
    local loadout = p.kind == 'loadout' and Loadouts[tonumber(p.index) or 0] or nil
    if not loadout then return { ok = false, error = 'Équipement inconnu.' } end
    return { ok = true, loadout = loadout }
end)

--- Menu /eup : toutes les tenues (le client garde celles de son personnage homme / femme)
S.on('eupList', function(src)
    local policeOnly = Config.Eup and Config.Eup.PoliceOnly == true
    return { ok = true, outfits = Outfits, policeLocked = policeOnly and not isPolice(src) or false }
end)

S.on('eupWear', function(src, p)
    local outfit = Outfits[tonumber(p.index) or 0]
    if not outfit then return { ok = false, error = 'Tenue inconnue.' } end
    if outfit.cate == 'police' and Config.Eup and Config.Eup.PoliceOnly == true and not isPolice(src) then
        return { ok = false, error = 'Tenues de police réservées aux policiers en service (unité du MDC).' }
    end
    return { ok = true, outfit = outfit }
end)
