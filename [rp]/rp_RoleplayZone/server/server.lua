--[[
    RP RoleplayZone - serveur
    -------------------------
    Scènes préparées par les civils, vérifiées ici et publiées à tous les joueurs (GlobalState.rpScenes) :
      - 'zone'      : zone de recherche (cercle de 15 à 60 m) et sa description (affichée aux policiers dedans) ;
      - 'perimeter' : périmètre à fouiller (petit lieu, non lié à un objet) et ce qu'on y trouve ;
      - 'object'    : objet du décor à fouiller (modèle + position) et ce qu'on y trouve.
    Le contenu d'un périmètre / d'un objet n'est PAS publié : il est envoyé au policier qui le fouille, sur place.
    Armes lâchées : objet réseau créé ici (état "rpDroppedWeapon"), ramassé avec l'œil de rp_interact.
    Aucune boucle : une minuterie par scène / par arme.
]]

local Config = SceneConfig
local Scenes = {}   -- [id] = scène
local nextId = 1
local Weapons = {}  -- [objet] = { id, weapon, ammo, owner }
local nextWeapon = 1

local KINDS = { zone = true, perimeter = true, object = true }
local KIND_LABEL = { zone = 'zone de recherche', perimeter = 'périmètre à fouiller', object = 'objet à fouiller' }

-- =========================================================================
-- OUTILS
-- =========================================================================
local function num(value, min, max)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    if min and value < min then value = min end
    if max and value > max then value = max end
    return value
end

local function point(p)
    if type(p) ~= 'table' then return nil end
    local x, y, z = num(p.x, -20000, 20000), num(p.y, -20000, 20000), num(p.z, -500, 3000)
    if not x or not y or not z then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Texte propre : sans balises ni caractères de contrôle (sauf retours à la ligne), longueur limitée
local function cleanText(text, max, multiline)
    if type(text) ~= 'string' then return '' end
    text = text:gsub('\r', ''):gsub('[<>]', '')
    if multiline then
        text = text:gsub('[%z\1-\9\11-\31]', ''):gsub('\n\n\n+', '\n\n')
    else
        text = text:gsub('%c', ' '):gsub('%s+', ' ')
    end
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    if #text > max then
        text = text:sub(1, max)
        text = text:gsub('[\128-\191]+$', ''):gsub('[\192-\255]$', '') -- pas de caractère UTF-8 coupé
    end
    return text
end

local function pedPos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

local function ownerKey(src)
    return GetPlayerIdentifierByType(src, 'license') or ('src:' .. tostring(src))
end

local function rpName(src)
    local name = Player(src).state.rpName
    if type(name) == 'string' and name ~= '' then return name end
    return GetPlayerName(src) or ('Joueur %d'):format(src)
end

local function notify(src, text)
    if src and src > 0 then TriggerClientEvent('rp_scene:notify', src, text) end
end

-- =========================================================================
-- DROITS
-- =========================================================================
--- Unité MDC du joueur (policier en service) ou nil (le MDC publie son nom : GlobalState.mdcResource)
local function policeUnit(src)
    local resource = GlobalState.mdcResource or Config.MdcResource or 'rp_mdc'
    if GetResourceState(resource) == 'started' then
        local ok, unit = pcall(function() return exports[resource]:getPlayerUnit(src) end)
        if ok and type(unit) == 'table' then return unit end
    end
    local name = Player(src).state.mdcUnit
    if type(name) == 'string' and name ~= '' then return { name = name } end
    return nil
end

local function isAdmin(src)
    return src == 0 or IsPlayerAceAllowed(src, Config.AdminAce or 'rpscene.admin')
end

--- Créer une scène : civils (mode civil de rp_interact, hors unité du MDC), tout le monde, ou admin
local function canCreate(src, civil)
    if isAdmin(src) or Config.Creators == 'everyone' then return true end
    if policeUnit(src) then return false, 'Réservé aux civils : quittez votre unité du MDC.' end
    if GetResourceState('rp_interact') == 'started' and civil ~= true then
        return false, 'Activez le mode civil (Menu F1 > Civil) pour préparer une scène.'
    end
    return true
end

local function canSearch(src)
    if Config.Searchers == 'everyone' or isAdmin(src) then return true end
    return policeUnit(src) ~= nil
end

--- Véhicule à fouiller : entité serveur de son n° réseau (nil s'il n'existe plus)
local function vehicleOf(s)
    if not s.netId then return nil end
    local e = NetworkGetEntityFromNetworkId(s.netId)
    if e and e ~= 0 and DoesEntityExist(e) then return e end
    return nil
end

--- Position actuelle d'une scène (un véhicule a pu bouger)
local function scenePos(s)
    local e = vehicleOf(s)
    if e then
        local c = GetEntityCoords(e)
        return { x = c.x, y = c.y, z = c.z }
    end
    return s.pos
end

-- =========================================================================
-- PUBLICATION
-- =========================================================================
--- Ce que tous les joueurs reçoivent : la géométrie, la description des ZONES (affichée en y entrant), jamais le
--- contenu des périmètres / objets (envoyé à la fouille)
--- (description visuelle « look » : affichée au-dessus du lieu / de l'objet aux policiers proches qui le voient ;
--- src : joueur qui l'a créée, pour lui proposer « Modifier » à l'œil ; netId : véhicule à fouiller)
local function publicView(s)
    return { id = s.id, kind = s.kind, pos = s.pos, radius = s.radius, title = s.title, model = s.model, rot = s.rot,
        label = s.label, text = s.kind == 'zone' and s.text or nil, look = s.look ~= '' and s.look or nil,
        vehicle = s.vehicle, netId = s.netId, src = s.ownerSrc }
end

local function publish()
    local list = {}
    for _, s in pairs(Scenes) do list[#list + 1] = publicView(s) end
    table.sort(list, function(a, b) return a.id < b.id end)
    GlobalState.rpScenes = list
end

local function remaining(s)
    if (s.expires or 0) <= 0 then return 0 end
    return math.max(0, s.expires - os.time())
end

--- Liste pour le menu : ses scènes (toutes pour un admin), avec le contenu, le temps restant, les fouilles
local function menuList(src)
    local key, admin, list = ownerKey(src), isAdmin(src), {}
    for _, s in pairs(Scenes) do
        local mine = s.owner == key
        if mine or admin then
            list[#list + 1] = { id = s.id, kind = s.kind, pos = scenePos(s), radius = s.radius, title = s.title, text = s.text,
                look = s.look, vehicle = s.vehicle,
                label = s.label, by = s.by, mine = mine, remaining = remaining(s), permanent = (s.expires or 0) <= 0,
                duration = s.duration, searches = s.searches or 0, lastBy = s.lastBy }
        end
    end
    table.sort(list, function(a, b) return a.id > b.id end)
    return list
end

local function countBy(key)
    local n = 0
    for _, s in pairs(Scenes) do if s.owner == key then n = n + 1 end end
    return n
end

local function removeScene(id)
    if not Scenes[id] then return false end
    Scenes[id] = nil
    publish()
    return true
end

local function allowedDuration(value)
    local duration = math.floor(tonumber(value) or Config.DefaultDuration or 120)
    for _, d in ipairs(Config.Durations or {}) do if d == duration then return duration end end
    return Config.DefaultDuration or 120
end

local function schedule(s)
    s.timer = (s.timer or 0) + 1
    local token = s.timer
    if (s.expires or 0) > 0 then
        SetTimeout((s.expires - os.time()) * 1000, function()
            if Scenes[s.id] == s and s.timer == token then removeScene(s.id) end
        end)
    end
end

-- =========================================================================
-- DEMANDES DU CLIENT (réponse : rp_scene:response)
-- =========================================================================
local Handlers = {}

function Handlers.list(src, data)
    local allowed, reason = canCreate(src, type(data) == 'table' and data.civil)
    return { ok = true, allowed = allowed, reason = reason, admin = isAdmin(src), scenes = menuList(src),
        durations = Config.Durations, defaultDuration = Config.DefaultDuration,
        zone = Config.Zone, perimeter = Config.Perimeter,
        titleLength = Config.TitleLength, textLength = Config.TextLength, lookLength = Config.LookLength }
end

--- Champs communs à la création et à la modification : titre, contenu de la fouille (ou message de la zone),
--- description visuelle (périmètre / objet : au moins l'un des deux)
local function readTexts(data, kind)
    local title = cleanText(data.title, Config.TitleLength or 40, false)
    local text = cleanText(data.text, Config.TextLength or 500, true)
    local look = kind ~= 'zone' and cleanText(data.look, Config.LookLength or 160, true) or ''
    if text == '' and (kind == 'zone' or look == '') then
        return nil, nil, nil, kind == 'zone' and 'Écrivez une description.' or 'Écrivez ce qu\'on trouve en fouillant, ou ce qu\'on voit.'
    end
    return title, text, look
end


function Handlers.create(src, data)
    if type(data) ~= 'table' or not KINDS[data.kind] then return { ok = false, error = 'Type de scène inconnu.' } end
    local allowed, reason = canCreate(src, data.civil)
    if not allowed then return { ok = false, error = reason } end
    local key = ownerKey(src)
    local count = 0
    for _ in pairs(Scenes) do count = count + 1 end
    if count >= (Config.MaxScenes or 80) then return { ok = false, error = 'Trop de scènes actives sur le serveur.' } end
    if not isAdmin(src) and countBy(key) >= (Config.MaxPerPlayer or 12) then
        return { ok = false, error = ('%d scènes par personne au maximum : supprimez-en une.'):format(Config.MaxPerPlayer or 12) }
    end
    local pos, here = point(data.pos), pedPos(src)
    if not pos or not here then return { ok = false, error = 'Emplacement invalide.' } end
    local S = Config.Selector or {}
    -- portée de la visée, plus la caméra libre qui peut s'éloigner du personnage
    local reach = (data.kind == 'zone' and (S.Range or 60.0) or (S.ObjectRange or 30.0)) + (S.FreecamRange or 60.0) + 25.0
    if dist(pos, here) > reach then return { ok = false, error = 'Trop loin de vous : rapprochez-vous de l\'endroit.' } end
    local title, text, look, err = readTexts(data, data.kind)
    if err then return { ok = false, error = err } end

    local s = { kind = data.kind, pos = pos, title = title, text = text, look = look, owner = key, ownerSrc = src,
        by = rpName(src), label = cleanText(data.label, 80, false), searches = 0 }
    if data.kind == 'zone' then
        local Z = Config.Zone
        s.radius = num(data.radius, Z.MinRadius, Z.MaxRadius) or Z.DefaultRadius
    elseif data.kind == 'perimeter' then
        local P = Config.Perimeter
        s.radius = num(data.radius, P.MinRadius, P.MaxRadius) or P.DefaultRadius
    else
        local model = math.floor(num(data.model, -2147483648, 4294967295) or 0)
        if model == 0 then return { ok = false, error = 'Objet invalide.' } end
        s.model = model
        if data.vehicle then
            -- véhicule à fouiller : suivi par son n° réseau (il peut bouger)
            s.vehicle, s.netId = true, math.floor(tonumber(data.netId) or -1)
            local e = vehicleOf(s)
            if not e or GetEntityType(e) ~= 2 then return { ok = false, error = 'Véhicule introuvable.' } end
            s.pos = scenePos(s)
        end
        local r = type(data.rot) == 'table' and data.rot or {}
        s.rot = { x = num(r.x, -360, 360) or 0.0, y = num(r.y, -360, 360) or 0.0, z = num(r.z, -360, 360) or 0.0 }
        s.radius = num(data.radius, 0.3, 6.0) or 1.0 -- taille de l'objet (cercle sous l'objet, œil d'aigle)
    end
    s.duration = allowedDuration(data.duration)
    s.id = nextId
    nextId = nextId + 1
    s.created = os.time()
    s.expires = s.duration > 0 and (s.created + s.duration * 60) or 0
    Scenes[s.id] = s
    schedule(s)
    publish()
    print(('^5[rp_RoleplayZone]^0 %s : %s n°%d (%s) par %s'):format(os.date('%H:%M'), KIND_LABEL[s.kind], s.id,
        s.label ~= '' and s.label or '?', s.by))
    return { ok = true, id = s.id, scenes = menuList(src) }
end

local function ownedScene(src, data)
    local id = math.floor(tonumber(type(data) == 'table' and data.id) or -1)
    local s = Scenes[id]
    if not s then return nil, 'Scène déjà supprimée.' end
    if s.owner ~= ownerKey(src) and not isAdmin(src) then return nil, 'Ce n\'est pas votre scène.' end
    return s
end

--- Modifier le titre, la description et la durée (repart de maintenant)
function Handlers.update(src, data)
    local s, err = ownedScene(src, data)
    if not s then return { ok = false, error = err } end
    local title, text, look, terr = readTexts(data, s.kind)
    if terr then return { ok = false, error = terr } end
    s.title, s.text, s.look = title, text, look
    if data.duration ~= nil then
        s.duration = allowedDuration(data.duration)
        s.expires = s.duration > 0 and (os.time() + s.duration * 60) or 0
        schedule(s)
    end
    publish()
    return { ok = true, scenes = menuList(src) }
end

function Handlers.remove(src, data)
    local s, err = ownedScene(src, data)
    if not s then return { ok = false, error = err } end
    removeScene(s.id)
    return { ok = true, scenes = menuList(src) }
end

--- Supprimer ses scènes (mine = true) ou toutes (admin)
function Handlers.clear(src, data)
    local mine = not (type(data) == 'table' and data.mine == false and isAdmin(src))
    local key, n = ownerKey(src), 0
    for id, s in pairs(Scenes) do
        if not mine or s.owner == key then Scenes[id] = nil; n = n + 1 end
    end
    if n > 0 then publish() end
    return { ok = true, count = n, scenes = menuList(src) }
end

--- Fouille d'un périmètre / d'un objet (après la barre de chargement) : son contenu, sur place seulement
function Handlers.search(src, data)
    if not canSearch(src) then return { ok = false, error = 'Réservé aux policiers en service (unité du MDC).' } end
    local id = math.floor(tonumber(type(data) == 'table' and data.id) or -1)
    local s = Scenes[id]
    if not s or s.kind == 'zone' then return { ok = false, error = 'Il n\'y a plus rien à fouiller ici.' } end
    local here = pedPos(src)
    local reach = (s.kind == 'perimeter' and (s.radius + (Config.Search.Distance or 1.2))
        or ((Config.Object and Config.Object.Distance or 1.8) + s.radius)) + 2.5
    if s.vehicle and not vehicleOf(s) then return { ok = false, error = 'Le véhicule n\'est plus là.' } end
    if not here or dist(here, scenePos(s)) > reach then return { ok = false, error = 'Trop loin pour fouiller.' } end
    s.searches = (s.searches or 0) + 1
    local unit = policeUnit(src)
    s.lastBy = unit and tostring(unit.name or unit.id or rpName(src)) or rpName(src)
    if Config.Search.AutoMe then
        local chat = GlobalState.rpChatResource or 'rp_chat'
        if GetResourceState(chat) == 'started' then
            pcall(function() exports[chat]:sendMe(src, s.vehicle and 'fouille le véhicule'
                or (s.kind == 'object' and 'fouille l\'objet' or 'fouille les lieux')) end)
        end
    end
    if Config.Search.NotifyCreator and s.ownerSrc and s.ownerSrc ~= src and GetPlayerName(s.ownerSrc)
        and ownerKey(s.ownerSrc) == s.owner then
        notify(s.ownerSrc, ('Votre %s%s vient d\'être fouillé par %s.'):format(KIND_LABEL[s.kind],
            s.title ~= '' and (' « ' .. s.title .. ' »') or '', s.lastBy))
    end
    return { ok = true, kind = s.kind, vehicle = s.vehicle, title = s.title,
        text = s.text ~= '' and s.text or 'Rien de particulier.', label = s.label }
end

--- Point dans le secteur d'une scène (zone / lieu / objet + Protect.AreaMargin m) : rp_interact y refuse « Supprimer »
local function isProtectedArea(p)
    if type(p) ~= 'table' and type(p) ~= 'vector3' then return false end
    local margin = (Config.Protect and Config.Protect.AreaMargin) or 70.0
    for _, s in pairs(Scenes) do
        local c = scenePos(s)
        local dx, dy = c.x - p.x, c.y - p.y
        if math.sqrt(dx * dx + dy * dy) <= (s.radius or 0) + margin then return true end
    end
    return false
end
exports('isProtectedArea', isProtectedArea)

RegisterNetEvent('rp_scene:request', function(id, action, data)
    local src = source
    local handler = Handlers[action]
    local ok, result = pcall(function() return handler and handler(src, data) or { ok = false, error = 'Action inconnue.' } end)
    if not ok then
        print(('^1[rp_RoleplayZone] erreur (%s) : %s^7'):format(tostring(action), tostring(result)))
        result = { ok = false, error = 'Erreur du serveur.' }
    end
    TriggerClientEvent('rp_scene:response', src, id, result)
end)

-- =========================================================================
-- ARMES LÂCHÉES
-- =========================================================================
local W = Config.Weapons or {}
local BLACKLIST = {}
for _, name in ipairs(W.Blacklist or {}) do BLACKLIST[GetHashKey(name) & 0xFFFFFFFF] = true end
local lastDrop = {}
local UNARMED = GetHashKey('WEAPON_UNARMED') & 0xFFFFFFFF

local function weaponCount(src)
    local n = 0
    for _, w in pairs(Weapons) do if w.owner == src then n = n + 1 end end
    return n
end

local function removeWeapon(object)
    Weapons[object] = nil
    if DoesEntityExist(object) then
        Entity(object).state:set('rpDroppedWeapon', nil, true)
        DeleteEntity(object)
    end
end

--- Lâcher son arme : mode civil (rp_interact) et hors unité du MDC (W.CivilOnly), ou admin
local function canDrop(src, civil)
    if W.CivilOnly == false or isAdmin(src) then return true end
    if policeUnit(src) then return false end
    return GetResourceState('rp_interact') ~= 'started' or civil == true
end

-- Le joueur lâche l'arme qu'il a en main : { mode = 'place' | 'throw', weapon, model, ammo, x, y, z, rx, ry, rz,
-- velocity (jetée) } ; posée : figée au sol ; jetée : créée à sa main, l'élan est donné par son jeu (settled ensuite)
RegisterNetEvent('rp_scene:weapon:drop', function(data)
    local src = source
    -- l'arme a déjà quitté les mains du joueur : tout refus la lui rend (rp_scene:weapon:refused)
    local function refuse(message) TriggerClientEvent('rp_scene:weapon:refused', src, message) end
    if W.Enabled == false or type(data) ~= 'table' then return refuse() end
    if not canDrop(src, data.civil) then return refuse('Lâcher son arme : réservé au mode civil.') end
    local throw = data.mode == 'throw'
    local weapon = math.floor(num(data.weapon, -2147483648, 4294967295) or 0) & 0xFFFFFFFF
    local model = math.floor(num(data.model, -2147483648, 4294967295) or 0)
    local pos = point(data)
    if weapon == 0 or model == 0 or not pos or BLACKLIST[weapon] then return refuse() end
    local here = pedPos(src)
    if not here or dist(here, pos) > 3.0 then return refuse() end
    local now = GetGameTimer()
    if lastDrop[src] and now - lastDrop[src] < 1500 then return refuse() end
    lastDrop[src] = now
    local ped = GetPlayerPed(src)
    -- l'arme en main (copie du serveur), ou déjà les mains vides (elle vient de les quitter) : sinon refusé
    local current = GetSelectedPedWeapon(ped)
    if current and current ~= 0 and (current & 0xFFFFFFFF) ~= weapon and (current & 0xFFFFFFFF) ~= UNARMED then return refuse() end
    if (W.MaxPerPlayer or 0) > 0 and weaponCount(src) >= W.MaxPerPlayer then
        return refuse(('%d armes lâchées au maximum en même temps.'):format(W.MaxPerPlayer))
    end
    local object = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, true, true, false)
    local timeout = GetGameTimer() + 2000
    while not DoesEntityExist(object) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(object) then return refuse('Impossible de lâcher cette arme ici.') end
    SetEntityRotation(object, num(data.rx, -360, 360) or 0.0, num(data.ry, -360, 360) or 0.0, num(data.rz, -360, 360) or 0.0, 2, true)
    local w = { id = nextWeapon, weapon = weapon, ammo = math.floor(num(data.ammo, 0, 9999) or 0), owner = src, flying = throw }
    nextWeapon = nextWeapon + 1
    Weapons[object] = w
    Entity(object).state:set('rpDroppedWeapon', { id = w.id, weapon = weapon, at = os.time() }, true)
    local velocity
    if throw then
        local v = type(data.velocity) == 'table' and data.velocity or {}
        local max = (W.ThrowSpeed or 7.5) + 1.0
        velocity = { x = num(v.x, -max, max) or 0.0, y = num(v.y, -max, max) or 0.0, z = num(v.z, -2.0, (W.ThrowUp or 3.0) + 1.0) or 0.0 }
        -- le joueur qui l'a jetée ne répond pas (déconnecté…) : figée là où elle est au bout de 6 s
        SetTimeout(6000, function()
            if Weapons[object] == w and w.flying then w.flying = false; FreezeEntityPosition(object, true) end
        end)
    else
        FreezeEntityPosition(object, true)
    end
    TriggerClientEvent('rp_scene:weapon:dropped', src, weapon, NetworkGetNetworkIdFromEntity(object), throw and 'throw' or 'place', velocity)
    if (W.Expire or 0) > 0 then
        SetTimeout(W.Expire * 60000, function()
            if Weapons[object] == w then removeWeapon(object) end
        end)
    end
end)

-- Arme jetée retombée (jeu du joueur qui l'a jetée) : figée là, à plat sur le sol
RegisterNetEvent('rp_scene:weapon:settled', function(netId, pos, rot)
    local src = source
    local object = NetworkGetEntityFromNetworkId(tonumber(netId) or -1)
    local w = object and object ~= 0 and Weapons[object]
    if not w or w.owner ~= src or not w.flying then return end
    w.flying = false
    pos = point(pos)
    local here = pedPos(src)
    if pos and here and dist(pos, here) <= (W.ThrowSpeed or 7.5) * 2.5 + 3.0 then
        local c = GetEntityCoords(object)
        if dist(pos, { x = c.x, y = c.y, z = c.z }) > 0.3 then SetEntityCoords(object, pos.x, pos.y, pos.z, false, false, false, false) end
        if type(rot) == 'table' then
            SetEntityRotation(object, num(rot.x, -360, 360) or 0.0, num(rot.y, -360, 360) or 0.0, num(rot.z, -360, 360) or 0.0, 2, true)
        end
    end
    FreezeEntityPosition(object, true)
end)

-- Ramassée avec l'œil de rp_interact (seule façon de la récupérer) : le premier qui la prend
RegisterNetEvent('rp_scene:weapon:pickup', function(netId)
    local src = source
    local object = NetworkGetEntityFromNetworkId(tonumber(netId) or -1)
    if not object or object == 0 or not DoesEntityExist(object) then return end
    local w = Weapons[object]
    if not w then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(object)) > (W.PickupDistance or 2.0) + 1.5 then return end
    removeWeapon(object)
    TriggerClientEvent('rp_scene:weapon:pickedUp', src, w.weapon, w.ammo)
end)

AddEventHandler('entityRemoved', function(entity)
    Weapons[entity] = nil
    -- véhicule à fouiller supprimé : sa scène disparaît avec lui
    local ok, netId = pcall(NetworkGetNetworkIdFromEntity, entity)
    if not ok or not netId then return end
    for id, s in pairs(Scenes) do
        if s.vehicle and s.netId == netId then removeScene(id) end
    end
end)

-- =========================================================================
-- JOUEURS ET RESSOURCE
-- =========================================================================
AddEventHandler('playerDropped', function()
    local src = source
    lastDrop[src] = nil
    if not Config.RemoveOnDisconnect then return end
    local key, changed = ownerKey(src), false
    for id, s in pairs(Scenes) do
        if s.owner == key then Scenes[id] = nil; changed = true end
    end
    if changed then publish() end
end)

-- Retour d'un joueur : ses scènes le reconnaissent (prévenu quand elles sont fouillées)
RegisterNetEvent('rp_scene:hello', function()
    local src = source
    local key = ownerKey(src)
    for _, s in pairs(Scenes) do if s.owner == key then s.ownerSrc = src end end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for object in pairs(Weapons) do
        if DoesEntityExist(object) then DeleteEntity(object) end
    end
end)

-- Console : toutes les scènes supprimées
RegisterCommand('sceneclear', function(src)
    if not isAdmin(src) then return end
    Scenes = {}
    publish()
    print('^5[rp_RoleplayZone]^0 toutes les scènes sont supprimées.')
end, true)

GlobalState.rpScenes = {} -- démarrage : aucune scène

-- =========================================================================
-- SESSIONS : /sessionon, /sessionoff -> message pour TOUS les joueurs (en haut au milieu, son de message reçu)
-- =========================================================================
local SESSION = Config.Session or {}
local function sessionCommand(def, kind)
    if not def or not def.Command or def.Command == '' then return end
    RegisterCommand(def.Command, function(src)
        if src ~= 0 and not IsPlayerAceAllowed(src, SESSION.Ace or 'rpsession') and not isAdmin(src) then
            return TriggerClientEvent('rp_scene:session', src, { denied = true })
        end
        TriggerClientEvent('rp_scene:session', -1, { kind = kind, title = def.Title, text = def.Text,
            duration = SESSION.Duration or 12000 })
        print(('[RoleplayZone] %s : %s'):format(def.Command, def.Text or ''))
    end, false)
end
sessionCommand(SESSION.On, 'on')
sessionCommand(SESSION.Off, 'off')
