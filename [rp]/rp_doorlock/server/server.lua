--[[
    RP Doorlock - serveur : tous les verrous, décidés ici
    ------------------------------------------------------
    - Verrouiller : joueurs EN MODE CIVIL seulement (état rpiCivilMode de rp_interact ; jamais un policier en service),
      à côté de la porte (et de son second battant), dans la limite MaxPerPlayer ; la porte appartient alors à ce
      joueur (sa licence : il la retrouve après une reconnexion).
    - Déverrouiller : son propriétaire, en mode civil (ou un admin, permission AdminAce).
    - Enfoncer (policiers en service, unité du MDC) : un coup de pied à la fois (Cooldown) ; Kick.Steps coups réussis
      (barre de réussite du client) : le verrou saute, la porte s'ouvre en grand chez tout le monde.
    - Frapper : le bruit est relayé aux joueurs proches.
    Les joueurs ne reçoivent jamais la licence du propriétaire, seulement une empreinte (tag) pour savoir « c'est la
    mienne ». Verrous gardés dans data/locks.json (Save). Aucune boucle.
]]

local Config = DoorlockConfig
local RES = GetCurrentResourceName()

local locks = {}  -- [id] = { id, model, x, y, z, owner, tag, group }
local kicks = {}  -- [groupe] = coups reçus
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

--- Mode civil de rp_interact (Menu F1 > Civil : état répliqué "rpiCivilMode") ; sans rp_interact : tout le monde
local function isCivil(src)
    if GetResourceState(Config.InteractResource or 'rp_interact') ~= 'started' then return true end
    return Player(src).state.rpiCivilMode == true
end
local CIVIL_ONLY = 'Réservé au mode civil (Menu Interaction > Civil > Mode civil).'

local function number(v)
    v = tonumber(v)
    if not v or v ~= v or math.abs(v) > 100000 then return nil end
    return v
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
    TriggerClientEvent('rp_doorlock:all', src, list, tagOf(licenseOf(src)), isAdmin(src))
end)

RegisterNetEvent('rp_doorlock:lock', function(doors)
    local src = source
    if type(doors) ~= 'table' or #doors == 0 or #doors > 2 or not throttle(src, 'lock', 800) then return end
    if not isCivil(src) or isPolice(src) then return notify(src, CIVIL_ONLY) end
    local license = licenseOf(src)
    local entries = {}
    for i, d in ipairs(doors) do
        local model, x, y, z = number(type(d) == 'table' and d.model), number(type(d) == 'table' and d.x),
            number(type(d) == 'table' and d.y), number(type(d) == 'table' and d.z)
        if not (model and x and y and z) then return end
        -- le second battant peut être un peu plus loin
        if not near(src, x, y, z, i == 1 and 1.0 or (Config.PairDistance or 2.6) + 1.0) then return end
        local id = DoorlockId(model, x, y, z)
        if locks[id] then return notify(src, 'Cette porte est déjà verrouillée.') end
        entries[#entries + 1] = { id = id, model = math.floor(model), x = x, y = y, z = z }
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
    kicks[group] = nil
    save()
    TriggerClientEvent('rp_doorlock:set', -1, out)
    notify(src, #out > 1 and 'Portes verrouillées.' or 'Porte verrouillée.')
end)

RegisterNetEvent('rp_doorlock:unlock', function(id)
    local src = source
    local l = type(id) == 'string' and locks[id] or nil
    if not l or not throttle(src, 'unlock', 800) then return end
    if not near(src, l.x, l.y, l.z, 1.0) then return end
    if not isAdmin(src) then
        if not isCivil(src) or isPolice(src) then return notify(src, CIVIL_ONLY) end
        if l.owner ~= licenseOf(src) then return notify(src, 'Vous n\'avez pas la clé de cette porte.') end
    end
    local ids = removeGroup(id)
    kicks[l.group] = nil
    save()
    TriggerClientEvent('rp_doorlock:unset', -1, ids)
    notify(src, #ids > 1 and 'Portes déverrouillées.' or 'Porte déverrouillée.')
end)

--- Début de la barre de réussite : les coups d'avant ne comptent plus
RegisterNetEvent('rp_doorlock:breachStart', function(id)
    local src = source
    local l = type(id) == 'string' and locks[id] or nil
    if l and isPolice(src) and near(src, l.x, l.y, l.z, 1.0) then kicks[l.group] = 0 end
end)

--- Un coup de pied : réussi (curseur dans la zone verte) ou raté ; Steps coups réussis -> la porte cède
RegisterNetEvent('rp_doorlock:kick', function(id, hit)
    local src = source
    local K = Config.Kick or {}
    local l = type(id) == 'string' and locks[id] or nil
    if K.Enabled == false or not l then return end
    if not isPolice(src) then return notify(src, 'Seuls les policiers en service peuvent enfoncer une porte.') end
    if not near(src, l.x, l.y, l.z, 1.0) or not throttle(src, 'kick', K.Cooldown or 700) then return end
    if hit ~= true then return end
    local n = (kicks[l.group] or 0) + 1
    kicks[l.group] = n
    if n < (K.Steps or 3) then return end
    local ped = GetPlayerPed(src)
    local from = GetEntityCoords(ped)
    local doors = {}
    for _, d in ipairs(groupOf(id)) do doors[#doors + 1] = public(d) end
    removeGroup(id)
    kicks[l.group] = nil
    save()
    TriggerClientEvent('rp_doorlock:breach', -1, doors, { x = from.x, y = from.y, z = from.z })
    notify(src, 'La porte cède !')
end)

RegisterNetEvent('rp_doorlock:knock', function(x, y, z)
    local src = source
    local K = Config.Knock or {}
    x, y, z = number(x), number(y), number(z)
    if K.Enabled == false or not (x and y and z) or not near(src, x, y, z, 1.0) or not throttle(src, 'knock', 2000) then return end
    TriggerClientEvent('rp_doorlock:knock', -1, { x = x, y = y, z = z })
end)

AddEventHandler('playerDropped', function() lastAct[source] = nil end)
