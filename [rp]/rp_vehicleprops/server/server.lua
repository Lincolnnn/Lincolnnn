--[[
    RP VehicleProps - serveur
    -------------------------
    Les objets d'un véhicule sont écrits dans l'état du véhicule "rpProps" (lu par tous les clients, qui posent chacun
    leurs objets) : ils vivent et disparaissent avec le véhicule, rien à nettoyer. Vérifié ici : véhicule réel, joueur à
    côté, objet de la liste (config.lua), position et rotation bornées, nombre maximal, permission éventuelle.
    Aucune boucle.
]]

local Config = VPConfig
local E = Config.Editor or {}
local RANGE = E.Range or 3.0

local byId = {}
for _, p in ipairs(Config.Props or {}) do byId[p.id] = p end

local lastAt = {} -- [src] = dernier changement (ms)
local counter = 0

local function vehicleFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
    return entity
end

local function allowed(src, vehicle)
    if Config.Restricted and not IsPlayerAceAllowed(src, 'rp_vehicleprops.use') then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > (Config.ServerDistance or 8.0) then return false end
    local now = GetGameTimer()
    if lastAt[src] and now - lastAt[src] < 250 then return false end
    lastAt[src] = now
    return true
end

local function num(v, min, max)
    v = tonumber(v)
    if not v or v ~= v then return 0.0 end
    return math.max(min, math.min(max, v)) + 0.0
end

--- Position / rotation reçues -> valeurs bornées
local function cleanOffsets(o)
    o = type(o) == 'table' and o or {}
    return {
        x = num(o.x, -RANGE, RANGE), y = num(o.y, -RANGE, RANGE), z = num(o.z, -RANGE, RANGE),
        rx = num(o.rx, -180.0, 180.0), ry = num(o.ry, -180.0, 180.0), rz = num(o.rz, -180.0, 180.0),
    }
end

local function current(vehicle)
    local list = Entity(vehicle).state.rpProps
    local out = {}
    if type(list) == 'table' then
        for _, p in ipairs(list) do if type(p) == 'table' and byId[p.key] then out[#out + 1] = p end end
    end
    return out
end

local function publish(vehicle, list)
    Entity(vehicle).state:set('rpProps', #list > 0 and list or nil, true)
end

local function reply(src, ok, text)
    TriggerClientEvent('rp_vehicleprops:result', src, ok, text)
end

-- Ajouter (id absent) ou déplacer (id d'un objet déjà posé)
RegisterNetEvent('rp_vehicleprops:save', function(netId, data)
    local src = source
    local vehicle = vehicleFromNet(netId)
    if not vehicle or type(data) ~= 'table' or not allowed(src, vehicle) then return reply(src, false, 'Action impossible.') end
    local list = current(vehicle)
    local offsets = cleanOffsets(data.offsets)
    if type(data.id) == 'string' then
        for _, p in ipairs(list) do
            if p.id == data.id then
                p.x, p.y, p.z, p.rx, p.ry, p.rz = offsets.x, offsets.y, offsets.z, offsets.rx, offsets.ry, offsets.rz
                publish(vehicle, list)
                return reply(src, true, 'Objet déplacé.')
            end
        end
        return reply(src, false, 'Cet objet n\'est plus sur le véhicule.')
    end
    local prop = byId[data.key]
    if not prop then return reply(src, false, 'Objet inconnu.') end
    if #list >= (Config.MaxPerVehicle or 12) then
        return reply(src, false, ('Pas plus de %d objets par véhicule.'):format(Config.MaxPerVehicle or 12))
    end
    counter = counter + 1
    list[#list + 1] = { id = ('%d_%d'):format(os.time() % 100000, counter), key = prop.id,
        x = offsets.x, y = offsets.y, z = offsets.z, rx = offsets.rx, ry = offsets.ry, rz = offsets.rz }
    publish(vehicle, list)
    reply(src, true, ('%s posé sur le véhicule.'):format(prop.label))
end)

RegisterNetEvent('rp_vehicleprops:remove', function(netId, id)
    local src = source
    local vehicle = vehicleFromNet(netId)
    if not vehicle or type(id) ~= 'string' or not allowed(src, vehicle) then return reply(src, false, 'Action impossible.') end
    local list, kept, removed = current(vehicle), {}, nil
    for _, p in ipairs(list) do
        if p.id == id then removed = p else kept[#kept + 1] = p end
    end
    if not removed then return reply(src, false, 'Cet objet n\'est plus sur le véhicule.') end
    publish(vehicle, kept)
    reply(src, true, ('%s retiré du véhicule.'):format(byId[removed.key].label))
end)

AddEventHandler('playerDropped', function() lastAt[source] = nil end)
