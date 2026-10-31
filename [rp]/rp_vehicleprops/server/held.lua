--[[
    RP VehicleProps - serveur : arme / lampe tenue posée sur un véhicule ou une lampe au sol
    ---------------------------------------------------------------------------------------
    Véhicule : liste dans l'état du véhicule "rpWeapons" (chaque joueur pose ses objets, collés au véhicule) ; elle
    vit et disparaît avec lui. Lampe au sol : objet réseau créé ici, figé, marqué "rpPlacedTorch" (ramassé avec l'œil
    de rp_interact, ExternalObjects). Vérifié : arme en main (ou mains déjà vides), distance, nombre, valeurs bornées.
    Aucune boucle.
]]

local Config = VPConfig
local H = Config.Held or {}
local RANGE = (Config.Editor or {}).Range or 3.0

local function u32(v) return (math.tointeger(tonumber(v) or 0) or 0) & 0xFFFFFFFF end
local UNARMED = u32(GetHashKey('WEAPON_UNARMED'))
local TORCHES = {}
for name, model in pairs(H.Torches or {}) do TORCHES[u32(GetHashKey(name))] = model end

local lastAt, counter = {}, 0
local Torches = {} -- [objet] = { owner, w }

local function throttled(src)
    local now = GetGameTimer()
    if lastAt[src] and now - lastAt[src] < 400 then return true end
    lastAt[src] = now
    return false
end

local function num(v, min, max)
    v = tonumber(v)
    if not v or v ~= v then return 0.0 end
    return math.max(min, math.min(max, v)) + 0.0
end

local function vehicleFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
    return entity
end

local function near(src, coords, max)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and #(GetEntityCoords(ped) - coords) <= max
end

--- Arme reçue -> valeurs propres ; nil si ce n'est pas l'arme en main (ou les mains déjà vides : elle vient de partir)
local function cleanWeapon(src, d)
    if type(d) ~= 'table' then return nil end
    local hash = u32(d.hash)
    if hash == 0 or hash == UNARMED then return nil end
    local current = u32(GetSelectedPedWeapon(GetPlayerPed(src)))
    if current ~= 0 and current ~= hash and current ~= UNARMED then return nil end
    local components, tints = {}, {}
    for _, name in ipairs(type(d.components) == 'table' and d.components or {}) do
        if type(name) == 'string' and #name <= 64 and name:match('^COMPONENT_[%w_]+$') and #components < 16 then
            components[#components + 1] = name
            local t = type(d.componentTints) == 'table' and tonumber(d.componentTints[name])
            if t then tints[name] = math.floor(num(t, 0, 31)) end
        end
    end
    local label = type(d.label) == 'string' and d.label:sub(1, 40) or 'Arme'
    return { hash = hash, label = label, ammo = math.floor(num(d.ammo, 0, 9999)), tint = math.floor(num(d.tint, -1, 31)),
        components = components, componentTints = tints, light = d.light == true, torch = TORCHES[hash] ~= nil }
end

local function weaponsOf(vehicle)
    local list, out = Entity(vehicle).state.rpWeapons, {}
    if type(list) == 'table' then
        for _, w in ipairs(list) do if type(w) == 'table' and type(w.id) == 'string' then out[#out + 1] = w end end
    end
    return out
end

local function reply(src, ok, text) TriggerClientEvent('rp_vehicleprops:held', src, ok, text) end

-- Arme / lampe posée sur le véhicule (déjà partie des mains du joueur : tout refus la lui rend)
RegisterNetEvent('rp_vehicleprops:placeWeapon', function(netId, data)
    local src = source
    if H.Enabled == false then return reply(src, false) end
    local vehicle = vehicleFromNet(netId)
    if not vehicle or throttled(src) or not near(src, GetEntityCoords(vehicle), Config.ServerDistance or 8.0) then
        return reply(src, false, 'Action impossible.')
    end
    local w = cleanWeapon(src, data)
    if not w then return reply(src, false, 'Action impossible.') end
    local list = weaponsOf(vehicle)
    if #list >= (H.MaxWeaponsPerVehicle or 4) then
        return reply(src, false, ('Pas plus de %d armes sur un véhicule.'):format(H.MaxWeaponsPerVehicle or 4))
    end
    local o = type(data.offsets) == 'table' and data.offsets or {}
    counter = counter + 1
    w.id = ('w%d_%d'):format(os.time() % 100000, counter)
    w.x, w.y, w.z = num(o.x, -RANGE, RANGE), num(o.y, -RANGE, RANGE), num(o.z, -RANGE, RANGE)
    w.rx, w.ry, w.rz = num(o.rx, -180.0, 180.0), num(o.ry, -180.0, 180.0), num(o.rz, -180.0, 180.0)
    list[#list + 1] = w
    Entity(vehicle).state:set('rpWeapons', list, true)
    reply(src, true)
end)

-- Reprendre une arme posée (n'importe qui à côté du véhicule) : rendue telle quelle
RegisterNetEvent('rp_vehicleprops:takeWeapon', function(netId, id)
    local src = source
    local vehicle = vehicleFromNet(netId)
    if not vehicle or type(id) ~= 'string' or throttled(src) or not near(src, GetEntityCoords(vehicle), Config.ServerDistance or 8.0) then return end
    local list, kept, taken = weaponsOf(vehicle), {}, nil
    for _, w in ipairs(list) do if w.id == id and not taken then taken = w else kept[#kept + 1] = w end end
    if not taken then return TriggerClientEvent('rp_vehicleprops:held', src, false, 'Elle n\'est plus sur le véhicule.') end
    Entity(vehicle).state:set('rpWeapons', #kept > 0 and kept or nil, true)
    TriggerClientEvent('rp_vehicleprops:heldGive', src, taken)
end)

-- Lampe posée au sol : objet réseau figé là où elle s'est posée
RegisterNetEvent('rp_vehicleprops:placeTorch', function(data)
    local src = source
    if H.Enabled == false or type(data) ~= 'table' or throttled(src) then return reply(src, false) end
    local w = cleanWeapon(src, data)
    if not w or not w.torch then return reply(src, false, 'Action impossible.') end
    local pos = vector3(num(data.x, -20000, 20000), num(data.y, -20000, 20000), num(data.z, -500, 3000))
    if not near(src, pos, (H.GroundDistance or 3.0) + 2.0) then return reply(src, false, 'Trop loin.') end
    local count = 0
    for _, t in pairs(Torches) do if t.owner == src then count = count + 1 end end
    if count >= (H.GroundMax or 3) then return reply(src, false, ('Pas plus de %d lampes au sol.'):format(H.GroundMax or 3)) end
    local object = CreateObjectNoOffset(GetHashKey(TORCHES[w.hash]), pos.x, pos.y, pos.z, true, true, false)
    local timeout = GetGameTimer() + 2000
    while not DoesEntityExist(object) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(object) then return reply(src, false, 'Impossible de poser la lampe ici.') end
    SetEntityRotation(object, num(data.rx, -360, 360), num(data.ry, -360, 360), num(data.rz, -360, 360), 2, true)
    FreezeEntityPosition(object, true)
    Torches[object] = { owner = src, w = w }
    Entity(object).state:set('rpPlacedTorch', { light = w.light, label = w.label }, true)
    reply(src, true)
end)

-- Ramassée avec l'œil (rp_interact, ExternalObjects) : le premier à côté la prend
RegisterNetEvent('rp_vehicleprops:pickupTorch', function(netId)
    local src = source
    local object = NetworkGetEntityFromNetworkId(tonumber(netId) or -1)
    if not object or object == 0 or not DoesEntityExist(object) then return end
    local t = Torches[object]
    if not t or not near(src, GetEntityCoords(object), 3.5) then return end
    Torches[object] = nil
    DeleteEntity(object)
    TriggerClientEvent('rp_vehicleprops:heldGive', src, t.w)
end)

AddEventHandler('entityRemoved', function(entity) Torches[entity] = nil end)
AddEventHandler('playerDropped', function() lastAt[source] = nil end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for object in pairs(Torches) do if DoesEntityExist(object) then DeleteEntity(object) end end
end)
