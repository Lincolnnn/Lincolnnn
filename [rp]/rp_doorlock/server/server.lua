--[[
    RP Doorlock - serveur : tous les verrous, décidés ici
    ------------------------------------------------------
    - Verrouiller : joueurs en mode civil ou sans rôle (jamais un policier en service, unité du MDC), à côté de la
      porte (et de son second battant), dans la limite MaxPerPlayer, sauf porte forcée ; la porte appartient alors à
      ce joueur (sa licence : il la retrouve après une reconnexion).
    - Déverrouiller : tout joueur en mode civil ou sans rôle (pas en service de police), ou un admin (AdminAce).
    - Enfoncer (TOUT LE MONDE, civil ou policier) : un coup de pied à la fois (Cooldown), bruit relayé aux joueurs
      proches (réussi ou raté) ; il faut entre Kick.Steps[1] et Kick.Steps[2] coups réussis (tiré au hasard pour la
      porte, la même pour ses deux battants) ; un coup raté ne compte pas, la tentative continue. La porte cède : le
      verrou saute, elle s'ouvre d'un coup sec chez tout le monde (bruit, secousse pour celui qui l'a enfoncée) et reste
      CASSÉE (Broken) : battante, elle ne se verrouille plus, sa description « Elle a été forcée. » s'affiche, jusqu'à
      sa réparation (admin, Broken.Duration minutes, ou redémarrage du serveur).
    Une porte double (deux battants) est verrouillée, déverrouillée et enfoncée EN ENTIER (même groupe).
    - Frapper : le bruit est relayé aux joueurs proches.
    Les joueurs ne reçoivent jamais la licence du propriétaire, seulement une empreinte (tag) pour savoir « c'est la
    mienne ». Verrous gardés dans data/locks.json (Save). Aucune boucle.
]]

local Config = DoorlockConfig
local RES = GetCurrentResourceName()

local locks = {}  -- [id] = { id, model, x, y, z, owner, tag, group }
local broken = {} -- [id] = { id, model, x, y, z, group } : portes enfoncées (jusqu'à réparation)
local kicks = {}  -- [groupe] = coups réussis de la tentative en cours
local needs = {}  -- [groupe] = coups réussis nécessaires (tirés au hasard une fois, gardés jusqu'à ce qu'elle cède)
local lastAct = {} -- [src] = { [action] = heure }

local function notify(src, text) TriggerClientEvent('rp_doorlock:notify', src, text) end

local function licenseOf(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return 'src:' .. tostring(src)
end

local function tagOf(license) return GetHashKey('rp_doorlock:' .. license) end

local function isAdmin(src) return Config.AdminAce and IsPlayerAceAllowed(src, Config.AdminAce) or false end

local function isPolice(src)
    local mdc = GlobalState.mdcResource or Config.MdcResource or 'rp_mdc'
    if GetResourceState(mdc) ~= 'started' then return false end
    local ok, unit = pcall(function() return exports[mdc]:getPlayerUnit(src) end)
    return ok and type(unit) == 'table'
end

local NOT_POLICE = 'Un policier en service ne verrouille ni ne déverrouille les portes : il peut frapper ou l\'enfoncer.'

--- Coups réussis nécessaires pour cette porte (groupe) : entre Kick.Steps[1] et Kick.Steps[2], tiré une fois
local function needOf(group)
    if not needs[group] then
        local steps = (Config.Kick or {}).Steps or { 3, 6 }
        if type(steps) == 'number' then steps = { steps, steps } end
        local lo, hi = math.floor(steps[1] or 3), math.floor(steps[2] or steps[1] or 6)
        needs[group] = hi > lo and math.random(lo, hi) or lo
    end
    return needs[group]
end

local function number(v)
    v = tonumber(v)
    if not v or v ~= v or math.abs(v) > 100000 then return nil end
    return v
end

--- Modèle d'une porte (empreinte du jeu, entier sur 32 bits : bien au-delà de 100000, refusé par number())
local function modelOf(v)
    v = tonumber(v)
    if not v or v ~= v or v ~= math.floor(v) or v < -2147483648 or v > 4294967295 then return nil end
    return math.floor(v)
end

local function near(src, x, y, z, extra)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(x, y, z)) <= (Config.Distance or 2.0) + (extra or 0.0)
end

local function throttle(src, action, ms)
    local now = GetGameTimer()
    lastAct[src] = lastAct[src] or {}
    if lastAct[src][action] and now - lastAct[src][action] < ms then return false end
    lastAct[src][action] = now
    return true
end

--- Ce que les joueurs voient d'un verrou (jamais la licence)
local function public(l) return { id = l.id, model = l.model, x = l.x, y = l.y, z = l.z, tag = l.tag, group = l.group } end

local function save()
    if Config.Save == false then return end
    local list = {}
    for _, l in pairs(locks) do list[#list + 1] = l end
    SaveResourceFile(RES, 'data/locks.json', json.encode(list), -1)
end

local function load()
    if Config.Save == false then return end
    local raw = LoadResourceFile(RES, 'data/locks.json')
    local ok, list = pcall(json.decode, raw or '[]')
    for _, l in ipairs(ok and type(list) == 'table' and list or {}) do
        if type(l) == 'table' and l.id and l.owner then
            l.tag = tagOf(l.owner)
            locks[l.id] = l
        end
    end
end
load()

local function countOf(license)
    local groups = {}
    for _, l in pairs(locks) do if l.owner == license then groups[l.group] = true end end
    local n = 0
    for _ in pairs(groups) do n = n + 1 end
    return n
end

local function groupOf(id)
    local l = locks[id]
    if not l then return {} end
    local list = {}
    for _, other in pairs(locks) do if other.group == l.group then list[#list + 1] = other end end
    return list
end

local function removeGroup(id)
    local ids = {}
    for _, l in ipairs(groupOf(id)) do
        locks[l.id] = nil
        ids[#ids + 1] = l.id
    end
    return ids
end

RegisterNetEvent('rp_doorlock:sync', function()
    local src = source
    local list = {}
    for _, l in pairs(locks) do list[#list + 1] = public(l) end
    local forced = {}
    for _, b in pairs(broken) do forced[#forced + 1] = b end
    TriggerClientEvent('rp_doorlock:all', src, list, tagOf(licenseOf(src)), isAdmin(src), forced)
end)

RegisterNetEvent('rp_doorlock:lock', function(doors)
    local src = source
    if type(doors) ~= 'table' or #doors == 0 or #doors > 2 or not throttle(src, 'lock', 800) then return end
    if isPolice(src) then return notify(src, NOT_POLICE) end
    local license = licenseOf(src)
    local entries = {}
    for i, d in ipairs(doors) do
        local model, x, y, z = modelOf(type(d) == 'table' and d.model), number(type(d) == 'table' and d.x),
            number(type(d) == 'table' and d.y), number(type(d) == 'table' and d.z)
        if not (model and x and y and z) then return end
        -- le second battant peut être un peu plus loin
        if not near(src, x, y, z, i == 1 and 1.0 or (Config.PairDistance or 2.6) + 1.0) then return end
        local id = DoorlockId(model, x, y, z)
        if locks[id] then return notify(src, 'Cette porte est déjà verrouillée.') end
        if broken[id] then return notify(src, 'Cette porte a été forcée : elle ne se verrouille plus.') end
        entries[#entries + 1] = { id = id, model = model, x = x, y = y, z = z }
    end
    if (Config.MaxPerPlayer or 0) > 0 and countOf(license) >= Config.MaxPerPlayer then
        return notify(src, ('Vous avez déjà verrouillé %d portes : déverrouillez-en une.'):format(Config.MaxPerPlayer))
    end
    local group = entries[1].id
    local out = {}
    for _, e in ipairs(entries) do
        e.owner, e.tag, e.group = license, tagOf(license), group
        locks[e.id] = e
        out[#out + 1] = public(e)
    end
    kicks[group], needs[group] = nil, nil
    save()
    TriggerClientEvent('rp_doorlock:set', -1, out)
    -- (pas de message : la porte se verrouille, son et animation)
end)

RegisterNetEvent('rp_doorlock:unlock', function(id)
    local src = source
    local l = type(id) == 'string' and locks[id] or nil
    if not l or not throttle(src, 'unlock', 800) then return end
    if not near(src, l.x, l.y, l.z, 1.0) then return end
    if not isAdmin(src) and isPolice(src) then return notify(src, NOT_POLICE) end
    local ids = removeGroup(id)
    kicks[l.group], needs[l.group] = nil, nil
    save()
    TriggerClientEvent('rp_doorlock:unset', -1, ids)
end)

--- Porte réparée : elle se verrouille de nouveau, sa description disparaît
local function repair(ids)
    local out = {}
    for _, id in ipairs(ids) do
        if broken[id] then
            broken[id] = nil
            out[#out + 1] = id
        end
    end
    if #out > 0 then TriggerClientEvent('rp_doorlock:repaired', -1, out) end
    return out
end

--- Début de la barre de réussite (tout le monde) : les coups réussis d'avant ne comptent plus ; le joueur apprend
--- combien de coups réussis il faut (même nombre pour toute la porte, tiré une fois)
RegisterNetEvent('rp_doorlock:breachStart', function(id)
    local src = source
    local l = type(id) == 'string' and locks[id] or nil
    if not l or (Config.Kick or {}).Enabled == false or not near(src, l.x, l.y, l.z, 1.0) then
        return TriggerClientEvent('rp_doorlock:breachInfo', src, id, nil)
    end
    kicks[l.group] = 0
    TriggerClientEvent('rp_doorlock:breachInfo', src, id, needOf(l.group))
end)

--- Un coup de pied (tout le monde) : bruit relayé aux joueurs proches ; réussi (curseur dans la zone verte) : compte ;
--- raté : ne compte pas (la tentative continue). Assez de coups réussis -> la porte (ses deux battants) cède
RegisterNetEvent('rp_doorlock:kick', function(id, hit)
    local src = source
    local K = Config.Kick or {}
    local l = type(id) == 'string' and locks[id] or nil
    if K.Enabled == false or not l then return end
    if not near(src, l.x, l.y, l.z, 1.0) or not throttle(src, 'kick', K.Cooldown or 700) then return end
    TriggerClientEvent('rp_doorlock:kickFx', -1, { x = l.x, y = l.y, z = l.z }, hit == true, src)
    if hit ~= true then return end
    local n = (kicks[l.group] or 0) + 1
    kicks[l.group] = n
    if n < needOf(l.group) then return end
    local ped = GetPlayerPed(src)
    local from = GetEntityCoords(ped)
    local doors, ids = {}, {}
    for _, d in ipairs(groupOf(id)) do
        doors[#doors + 1] = public(d)
        ids[#ids + 1] = d.id
        broken[d.id] = { id = d.id, model = d.model, x = d.x, y = d.y, z = d.z, group = d.group }
    end
    removeGroup(id)
    kicks[l.group], needs[l.group] = nil, nil
    save()
    TriggerClientEvent('rp_doorlock:breach', -1, doors, { x = from.x, y = from.y, z = from.z }, src)
    local minutes = tonumber((Config.Broken or {}).Duration) or 0
    if minutes > 0 then SetTimeout(math.floor(minutes * 60000), function() repair(ids) end) end
end)

--- Réparer une porte forcée (admin, avec l'œil) : la porte double en entier
RegisterNetEvent('rp_doorlock:repair', function(id)
    local src = source
    local b = type(id) == 'string' and broken[id] or nil
    if not b or not isAdmin(src) or not near(src, b.x, b.y, b.z, 1.0) then return end
    local ids = {}
    for otherId, other in pairs(broken) do if other.group == b.group then ids[#ids + 1] = otherId end end
    repair(ids)
end)

RegisterNetEvent('rp_doorlock:knock', function(x, y, z)
    local src = source
    local K = Config.Knock or {}
    x, y, z = number(x), number(y), number(z)
    if K.Enabled == false or not (x and y and z) or not near(src, x, y, z, 1.0) or not throttle(src, 'knock', 2000) then return end
    TriggerClientEvent('rp_doorlock:knock', -1, { x = x, y = y, z = z })
end)

AddEventHandler('playerDropped', function() lastAct[source] = nil end)
