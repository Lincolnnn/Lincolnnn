--[[
    RP TrafficControl - serveur
    ---------------------------
    Mesures de trafic (route barrée, limitation de vitesse, arrêt du trafic) : vérifiées ici, publiées à tous les
    joueurs (GlobalState.rpTraffic) ; chaque joueur les applique au réseau routier de SON jeu (client/network.lua).
    Durée limitée (levée automatique) ou jusqu'à ce qu'on la lève. Aucune boucle : une minuterie par mesure.
]]

local Config = TrafficConfig
local Measures = {} -- [id] = mesure
local nextId = 1

local KINDS = { close = true, speed = true, stop = true }

-- =========================================================================
-- PUBLICATION
-- =========================================================================
--- Ce que les joueurs reçoivent (géométrie et réglages, pas de données privées)
local function publicView(m)
    return { id = m.id, kind = m.kind, a = m.a, b = m.b, width = m.width, center = m.center, radius = m.radius,
        speed = m.speed, label = m.label }
end

local function publish()
    local list = {}
    for _, m in pairs(Measures) do list[#list + 1] = publicView(m) end
    table.sort(list, function(x, y) return x.id < y.id end)
    GlobalState.rpTraffic = list
end

-- =========================================================================
-- DROITS
-- =========================================================================
--- Unité MDC du joueur (policier en service) ou nil (le MDC publie son nom : GlobalState.mdcResource)
local function policeUnit(src)
    local resource = GlobalState.mdcResource or Config.MdcResource or 'mdc_standalone'
    if GetResourceState(resource) == 'started' then
        local ok, unit = pcall(function() return exports[resource]:getPlayerUnit(src) end)
        if ok and type(unit) == 'table' then return unit end
    end
    local name = Player(src).state.mdcUnit
    if type(name) == 'string' and name ~= '' then return { name = name } end
    return nil
end

--- Nom affiché de l'auteur (unité MDC, sinon nom du joueur), ou nil si non autorisé
local function author(src)
    if src == 0 then return 'Console' end
    local unit = policeUnit(src)
    if unit then return tostring(unit.name or unit.id or GetPlayerName(src)) end
    if IsPlayerAceAllowed(src, Config.AdminAce or 'rptraffic.admin') or Config.PoliceOnly == false then
        return GetPlayerName(src) or ('Joueur %d'):format(src)
    end
    return nil
end

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

local function cleanLabel(text)
    text = type(text) == 'string' and text:gsub('[%c<>]', ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '') or ''
    return text:sub(1, 70)
end

local function countBy(src)
    local n = 0
    for _, m in pairs(Measures) do if m.owner == src then n = n + 1 end end
    return n
end

local function remaining(m)
    if (m.expires or 0) <= 0 then return 0 end
    return math.max(0, m.expires - os.time())
end

--- Liste pour le menu (avec l'auteur et le temps restant)
local function menuList(src)
    local list = {}
    for _, m in pairs(Measures) do
        local v = publicView(m)
        v.by, v.mine, v.remaining, v.permanent = m.by, m.owner == src, remaining(m), (m.expires or 0) <= 0
        list[#list + 1] = v
    end
    table.sort(list, function(x, y) return x.id > y.id end)
    return list
end

local function removeMeasure(id)
    if not Measures[id] then return false end
    Measures[id] = nil
    publish()
    return true
end

-- =========================================================================
-- DEMANDES DU CLIENT (réponse : rp_traffic:response)
-- =========================================================================
local Handlers = {}

function Handlers.list(src)
    return { ok = true, allowed = author(src) ~= nil, measures = menuList(src),
        durations = Config.Durations, defaultDuration = Config.DefaultDuration,
        speed = Config.Speed, max = Config.MaxMeasures, maxMine = Config.MaxPerPlayer }
end

function Handlers.create(src, data)
    local by = author(src)
    if not by then return { ok = false, error = 'Réservé aux policiers en service (unité du MDC).' } end
    if type(data) ~= 'table' or not KINDS[data.kind] then return { ok = false, error = 'Mesure inconnue.' } end
    local count = 0
    for _ in pairs(Measures) do count = count + 1 end
    if count >= (Config.MaxMeasures or 30) then return { ok = false, error = 'Trop de mesures actives : levez-en une.' } end
    if countBy(src) >= (Config.MaxPerPlayer or 8) then
        return { ok = false, error = ('%d mesures par personne au maximum : levez-en une.'):format(Config.MaxPerPlayer or 8) }
    end
    local here = GetEntityCoords(GetPlayerPed(src))
    here = { x = here.x, y = here.y, z = here.z }
    local reach = ((Config.Editor and Config.Editor.Range) or 150.0) + 60.0

    local m = { kind = data.kind, owner = src, by = by, label = cleanLabel(data.label) }
    if data.kind == 'close' then
        local C = Config.Closure
        local a, b = point(data.a), point(data.b)
        if not a or not b then return { ok = false, error = 'Tronçon invalide.' } end
        if dist(a, here) > reach and dist(b, here) > reach then return { ok = false, error = 'Trop loin de vous.' } end
        local length = dist(a, b)
        if length < (C.MinLength or 6.0) then return { ok = false, error = 'Tronçon trop court.' } end
        if length > (C.MaxLength or 250.0) then return { ok = false, error = 'Tronçon trop long.' } end
        m.a, m.b = a, b
        m.width = num(data.width, C.MinWidth or 4.0, C.MaxWidth or 40.0) or C.DefaultWidth or 14.0
    else
        local S = Config.Speed
        local center = point(data.center)
        if not center then return { ok = false, error = 'Zone invalide.' } end
        if dist(center, here) > reach then return { ok = false, error = 'Trop loin de vous.' } end
        m.center = center
        m.radius = num(data.radius, S.MinRadius or 10.0, S.MaxRadius or 200.0) or S.DefaultRadius or 40.0
        if data.kind == 'speed' then
            m.speed = math.floor(num(data.speed, S.MinLimit or 5, S.MaxLimit or 80) or S.DefaultLimit or 25)
        else
            m.speed = 0
        end
    end

    -- Durée : une des durées proposées (0 = jusqu'à ce qu'on la lève)
    local duration = math.floor(tonumber(data.duration) or Config.DefaultDuration or 30)
    local allowedDuration = false
    for _, d in ipairs(Config.Durations or {}) do if d == duration then allowedDuration = true end end
    if not allowedDuration then duration = Config.DefaultDuration or 30 end

    m.id = nextId
    nextId = nextId + 1
    m.created = os.time()
    m.expires = duration > 0 and (m.created + duration * 60) or 0
    Measures[m.id] = m
    publish()
    if duration > 0 then
        SetTimeout(duration * 60000, function()
            if Measures[m.id] == m then removeMeasure(m.id) end
        end)
    end
    print(('^5[rp_TrafficControl]^0 %s : %s n°%d (%s) par %s'):format(
        os.date('%H:%M'), m.kind, m.id, m.label ~= '' and m.label or '?', by))
    return { ok = true, id = m.id, measures = menuList(src) }
end

function Handlers.remove(src, data)
    if not author(src) then return { ok = false, error = 'Réservé aux policiers en service (unité du MDC).' } end
    local id = math.floor(tonumber(type(data) == 'table' and data.id) or -1)
    if not removeMeasure(id) then return { ok = false, error = 'Mesure déjà levée.' } end
    return { ok = true, measures = menuList(src) }
end

--- Lever ses mesures (mine = true) ou toutes
function Handlers.clear(src, data)
    if not author(src) then return { ok = false, error = 'Réservé aux policiers en service (unité du MDC).' } end
    local mine = type(data) == 'table' and data.mine == true
    local n = 0
    for id, m in pairs(Measures) do
        if not mine or m.owner == src then Measures[id] = nil; n = n + 1 end
    end
    if n > 0 then publish() end
    return { ok = true, count = n, measures = menuList(src) }
end

RegisterNetEvent('rp_traffic:request', function(id, action, data)
    local src = source
    local handler = Handlers[action]
    local ok, result = pcall(function() return handler and handler(src, data) or { ok = false, error = 'Action inconnue.' } end)
    if not ok then
        print(('^1[rp_TrafficControl] erreur (%s) : %s^7'):format(tostring(action), tostring(result)))
        result = { ok = false, error = 'Erreur du serveur.' }
    end
    TriggerClientEvent('rp_traffic:response', src, id, result)
end)

AddEventHandler('playerDropped', function()
    if not Config.RemoveOnDisconnect then return end
    local src, changed = source, false
    for id, m in pairs(Measures) do
        if m.owner == src then Measures[id] = nil; changed = true end
    end
    if changed then publish() end
end)

-- Console : toutes les mesures levées
RegisterCommand('trafficclear', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.AdminAce or 'rptraffic.admin') then return end
    Measures = {}
    publish()
    print('^5[rp_TrafficControl]^0 toutes les mesures de trafic sont levées.')
end, true)

GlobalState.rpTraffic = {} -- démarrage : aucune mesure (le réseau routier de chaque joueur revient à l'original)
