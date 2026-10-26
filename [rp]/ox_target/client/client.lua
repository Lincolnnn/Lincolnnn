--[[
    ox_target (pont) - client
    -------------------------
    Mêmes exports que le vrai ox_target, pour les scripts qui l'exigent : addGlobalVehicle / Ped / Player / Object /
    Option, addModel, addEntity, addLocalEntity (et leurs remove…), addSphereZone, addBoxZone, addPolyZone,
    removeZone, zoneExists, disableTargeting. Les options enregistrées s'affichent dans l'œil de rp_interact
    (exports targetOptions / targetSelect, rp_interact/config.lua : TargetProviders).
    Pris en charge dans une option : label, icon, distance, bones, canInteract, onSelect, event, serverEvent,
    command, export. Pas de groups / items (aucun framework) : ces conditions sont ignorées.
    Les options d'un script sont retirées quand il s'arrête.
    Performance : rien ne tourne ; le travail se fait seulement pendant que l'œil vise (rp_interact).
]]

local Config = BridgeConfig

local registry = {}          -- [uid] = option (avec .resource)
local nextUid = 0
local globals = { vehicle = {}, ped = {}, player = {}, object = {}, any = {} } -- listes d'uid
local models, netEntities, localEntities = {}, {}, {} -- [modèle / n° réseau / entité] = liste d'uid
local zones, nextZone = {}, 0 -- [id] = { kind, coords, radius | size, rotation | points, options = { uid }, resource, name }
local disabled = false

-- =========================================================================
-- ENREGISTREMENT
-- =========================================================================
local function caller() return GetInvokingResource() or GetCurrentResourceName() end

--- Une option seule ou une liste d'options -> liste
local function asList(options)
    if type(options) ~= 'table' then return {} end
    if options.label or options.name then return { options } end
    return options
end

local function register(list, options, resource)
    for _, option in ipairs(asList(options)) do
        if type(option) == 'table' then
            nextUid = nextUid + 1
            option.resource = option.resource or resource
            registry[nextUid] = option
            list[#list + 1] = nextUid
        end
    end
end

local function nameSet(names)
    if names == nil then return nil end
    local set = {}
    for _, n in ipairs(type(names) == 'table' and names or { names }) do set[n] = true end
    return set
end

--- Retire de `list` les options nommées `names` (toutes si nil) ; ressource : seulement les siennes
local function unregister(list, names, resource)
    local set = nameSet(names)
    for i = #list, 1, -1 do
        local option = registry[list[i]]
        if not option or ((not set or set[option.name]) and (not resource or option.resource == resource)) then
            registry[list[i]] = nil
            table.remove(list, i)
        end
    end
end

local function keyed(store, keys, options, resource)
    for _, key in ipairs(type(keys) == 'table' and keys or { keys }) do
        if type(key) == 'string' then key = joaat(key) end
        store[key] = store[key] or {}
        register(store[key], options, resource)
    end
end

local function unkeyed(store, keys, names)
    for _, key in ipairs(type(keys) == 'table' and keys or { keys }) do
        if type(key) == 'string' then key = joaat(key) end
        if store[key] then
            unregister(store[key], names)
            if #store[key] == 0 then store[key] = nil end
        end
    end
end

for kind, suffix in pairs({ vehicle = 'Vehicle', ped = 'Ped', player = 'Player', object = 'Object', any = 'Option' }) do
    exports('addGlobal' .. suffix, function(options) register(globals[kind], options, caller()) end)
    exports('removeGlobal' .. suffix, function(names) unregister(globals[kind], names) end)
end

exports('addModel', function(list, options) keyed(models, list, options, caller()) end)
exports('removeModel', function(list, names) unkeyed(models, list, names) end)
exports('addEntity', function(list, options) keyed(netEntities, list, options, caller()) end)
exports('removeEntity', function(list, names) unkeyed(netEntities, list, names) end)
exports('addLocalEntity', function(list, options) keyed(localEntities, list, options, caller()) end)
exports('removeLocalEntity', function(list, names) unkeyed(localEntities, list, names) end)

local function vec(v)
    if type(v) ~= 'table' and type(v) ~= 'vector3' and type(v) ~= 'userdata' then return nil end
    local x, y, z = tonumber(v.x or v[1]), tonumber(v.y or v[2]), tonumber(v.z or v[3])
    if not (x and y and z) then return nil end
    return vector3(x, y, z)
end

local function addZone(kind, data)
    if type(data) ~= 'table' then return nil end
    nextZone = nextZone + 1
    local zone = { kind = kind, name = data.name, resource = caller(), options = {} }
    if kind == 'poly' then
        zone.points = {}
        local minZ, maxZ = math.huge, -math.huge
        for _, p in ipairs(data.points or {}) do
            local point = vec(p)
            if point then
                zone.points[#zone.points + 1] = point
                minZ, maxZ = math.min(minZ, point.z), math.max(maxZ, point.z)
            end
        end
        local half = (tonumber(data.thickness) or 4.0) / 2.0
        zone.minZ, zone.maxZ = minZ - half, maxZ + half
    else
        zone.coords = vec(data.coords) or vector3(0.0, 0.0, 0.0)
        zone.radius = tonumber(data.radius) or 2.0
        zone.size = vec(data.size) or vector3(2.0, 2.0, 2.0)
        zone.rotation = math.rad(tonumber(data.rotation) or 0.0)
    end
    register(zone.options, data.options, zone.resource)
    zones[nextZone] = zone
    return nextZone
end

exports('addSphereZone', function(data) return addZone('sphere', data) end)
exports('addBoxZone', function(data) return addZone('box', data) end)
exports('addPolyZone', function(data) return addZone('poly', data) end)

local function dropZone(id)
    local zone = zones[id]
    if not zone then return end
    for _, uid in ipairs(zone.options) do registry[uid] = nil end
    zones[id] = nil
end

exports('removeZone', function(id)
    if zones[id] then return dropZone(id) end
    for zid, zone in pairs(zones) do if zone.name ~= nil and zone.name == id then dropZone(zid) end end
end)
exports('zoneExists', function(id) return zones[id] ~= nil end)
exports('disableTargeting', function(state) disabled = state == true end)
exports('isActive', function() return false end)

-- Script arrêté : ses options et ses zones disparaissent
AddEventHandler('onResourceStop', function(resource)
    for _, list in pairs(globals) do unregister(list, nil, resource) end
    for _, store in ipairs({ models, netEntities, localEntities }) do
        for key, list in pairs(store) do
            unregister(list, nil, resource)
            if #list == 0 then store[key] = nil end
        end
    end
    for id, zone in pairs(zones) do if zone.resource == resource then dropZone(id) end end
end)

-- =========================================================================
-- ŒIL (rp_interact) : options pour ce qui est visé
-- =========================================================================
local function inZone(zone, p)
    if zone.kind == 'sphere' then return #(p - zone.coords) <= zone.radius end
    if zone.kind == 'box' then
        local d = p - zone.coords
        local c, s = math.cos(-zone.rotation), math.sin(-zone.rotation)
        local lx, ly = d.x * c - d.y * s, d.x * s + d.y * c
        return math.abs(lx) <= zone.size.x / 2.0 and math.abs(ly) <= zone.size.y / 2.0 and math.abs(d.z) <= zone.size.z / 2.0
    end
    if p.z < zone.minZ or p.z > zone.maxZ then return false end
    local inside, pts = false, zone.points -- point dans le polygone (vu de dessus)
    local j = #pts
    for i = 1, #pts do
        local a, b = pts[i], pts[j]
        if (a.y > p.y) ~= (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x then inside = not inside end
        j = i
    end
    return inside
end

--- Partie du véhicule (bones) la plus proche du point visé, ou nil si aucune n'est assez proche
local function nearestBone(entity, bones, hit)
    local best, bestD
    for _, name in ipairs(type(bones) == 'table' and bones or { bones }) do
        local index = GetEntityBoneIndexByName(entity, name)
        if index ~= -1 then
            local d = #(GetWorldPositionOfEntityBone(entity, index) - hit)
            if d <= Config.BoneDistance and (not bestD or d < bestD) then best, bestD = index, d end
        end
    end
    return best
end

local function icon(name)
    if type(name) ~= 'string' then return 'hand' end
    for fa in name:gmatch('fa%-[%w%-]+') do
        if fa ~= 'fa-solid' and fa ~= 'fa-regular' and fa ~= 'fa-light' and Config.Icons[fa] then return Config.Icons[fa] end
    end
    return 'hand'
end

--- Option visible pour cette cible ? (distance, partie du véhicule, canInteract) -> contexte de l'option
local function evaluate(option, entity, hit, distance, zone)
    if (option.distance or Config.DefaultDistance) < distance then return nil end
    local bone
    if option.bones then
        if entity == 0 then return nil end
        bone = nearestBone(entity, option.bones, hit)
        if not bone then return nil end
    end
    if option.canInteract then
        local ok, allowed = pcall(option.canInteract, entity, distance, hit, option.name, bone)
        if not ok or not allowed then return nil end
    end
    return { entity = entity, coords = hit, distance = distance, zone = zone, bone = bone }
end

--- Options possibles pour ce qui est visé : liste de { uid, option, data }
local function candidates(info)
    local out = {}
    if disabled or type(info) ~= 'table' or type(info.hit) ~= 'table' then return out end
    local hit = vector3(info.hit.x, info.hit.y, info.hit.z)
    local ped = PlayerPedId()
    local distance = #(GetEntityCoords(ped) - hit)
    local entity = tonumber(info.entity) or 0
    local function consider(list, zoneId)
        for _, uid in ipairs(list or {}) do
            local option = registry[uid]
            if option and (Config.PoliceOnly or {})[option.resource] and not info.police then option = nil end
            local data = option and evaluate(option, entity, hit, distance, zoneId)
            if data then out[#out + 1] = { uid = uid, option = option, data = data } end
        end
    end
    if entity ~= 0 and DoesEntityExist(entity) then
        local kind = info.type
        if kind == 'ped' then kind = IsPedAPlayer(entity) and 'player' or 'ped' end
        consider(globals[kind])
        consider(globals.any)
        consider(models[GetEntityModel(entity)])
        if info.netId then consider(netEntities[info.netId]) end
        consider(localEntities[entity])
    end
    for id, zone in pairs(zones) do
        if inZone(zone, hit) then consider(zone.options, id) end
    end
    return out
end

exports('targetOptions', function(info)
    local list = candidates(info)
    if #list == 0 then return nil end
    local options, label = {}, nil
    for _, c in ipairs(list) do
        options[#options + 1] = { id = c.uid, label = tostring(c.option.label or c.option.name or '?'), icon = icon(c.option.icon) }
        label = label or Config.Labels[c.option.resource]
    end
    return { label = label, options = options }
end)

exports('targetSelect', function(id, info)
    for _, c in ipairs(candidates(info)) do
        if c.uid == tonumber(id) then
            local option, data = c.option, c.data
            data.name = option.name
            if option.onSelect then
                local ok, err = pcall(option.onSelect, option.qtarget and data.entity or data)
                if not ok then print(('^1[ox_target (pont)] %s : %s^7'):format(tostring(option.resource), tostring(err))) end
            elseif option.export then
                pcall(function() exports[option.resource][option.export](nil, data) end)
            elseif option.event then
                TriggerEvent(option.event, data)
            elseif option.serverEvent then
                data.entity = data.entity ~= 0 and NetworkGetEntityIsNetworked(data.entity) and NetworkGetNetworkIdFromEntity(data.entity) or 0
                TriggerServerEvent(option.serverEvent, data)
            elseif option.command then
                ExecuteCommand(option.command)
            end
            return
        end
    end
end)
