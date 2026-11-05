--[[
    RP VehicleProps - serveur : chapeaux / lunettes (tenue, EUP compris) au sol ou posés sur un véhicule
    -----------------------------------------------------------------------------------------------------
    Visibles et repris par TOUS les joueurs (aucune permission) :
      - au sol : liste GlobalState "rpWearGround" (tombés d'un joueur bousculé, blessé, en chute…) ;
      - sur un véhicule : liste dans l'état du véhicule "rpWear" (chapeaux posés avec l'œil), qui vit et disparaît avec lui.
    Chaque élément : { id, anchor (0 chapeau, 1 lunettes), drawable, texture, pedModel, x, y, z, rx, ry, rz, at }.
    Le reprendre : seulement par un personnage du même modèle (homme / femme : les modèles EUP diffèrent).
    Vérifié : distance, nombres, valeurs bornées ; au sol, les plus anciens disparaissent (Expire, GroundTotal).
    Aucune boucle.
]]

local Config = VPConfig
local LP = Config.LostProps or {}
if LP.Enabled == false then return end

local RANGE = (Config.Editor or {}).Range or 3.0
local function u32(v) return (math.tointeger(tonumber(v) or 0) or 0) & 0xFFFFFFFF end
local ANCHORS = { [0] = 'chapeau', [1] = 'lunettes' }

local lastAt, counter = {}, 0
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

local function near(src, coords, max)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and #(GetEntityCoords(ped) - coords) <= max
end

local function vehicleFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
    return entity
end

local function reply(src, ok, text) TriggerClientEvent('rp_vehicleprops:wearResult', src, ok, text) end

--- Pièce reçue -> valeurs propres (nil si invalide) ; le modèle du personnage est lu par le serveur
local function cleanPiece(src, d)
    if type(d) ~= 'table' then return nil end
    local anchor = math.tointeger(tonumber(d.anchor))
    if not anchor or not ANCHORS[anchor] then return nil end
    local drawable = math.tointeger(tonumber(d.drawable))
    if not drawable or drawable < 0 or drawable > 4000 then return nil end
    local texture = math.tointeger(tonumber(d.texture)) or 0
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    counter = counter + 1
    return {
        id = ('h%d_%d'):format(os.time() % 100000, counter), anchor = anchor, drawable = drawable,
        texture = math.max(0, math.min(texture, 255)), pedModel = u32(GetEntityModel(ped)), at = os.time(),
    }
end

local function groundList()
    local list, out, now = GlobalState.rpWearGround, {}, os.time()
    if type(list) == 'table' then
        for _, item in ipairs(list) do
            if type(item) == 'table' and now - (tonumber(item.at) or now) <= (LP.Expire or 900) then out[#out + 1] = item end
        end
    end
    return out
end

local function vehicleList(vehicle)
    local list, out = Entity(vehicle).state.rpWear, {}
    if type(list) == 'table' then for _, item in ipairs(list) do if type(item) == 'table' then out[#out + 1] = item end end end
    return out
end

-- Tombé au sol (le client du joueur l'a vu tomber et donne l'endroit où il s'est arrêté)
RegisterNetEvent('rp_vehicleprops:wearDrop', function(data)
    local src = source
    if throttled(src) or type(data) ~= 'table' then return end
    local item = cleanPiece(src, data)
    if not item then return end
    local pos = vector3(num(data.x, -20000, 20000), num(data.y, -20000, 20000), num(data.z, -500, 3000))
    if not near(src, pos, 12.0) then return end
    item.x, item.y, item.z = pos.x, pos.y, pos.z
    item.rx, item.ry, item.rz = num(data.rx, -180, 180), num(data.ry, -180, 180), num(data.rz, -360, 360)
    local list = groundList()
    while #list >= (LP.GroundTotal or 60) do table.remove(list, 1) end -- le plus ancien disparaît
    list[#list + 1] = item
    GlobalState.rpWearGround = list
end)

-- Posé sur un véhicule (retiré de la tête par le joueur : tout refus le lui rend)
RegisterNetEvent('rp_vehicleprops:wearPlaceVehicle', function(netId, data)
    local src = source
    local vehicle = vehicleFromNet(netId)
    if not vehicle or throttled(src) or not near(src, GetEntityCoords(vehicle), Config.ServerDistance or 8.0) then
        return reply(src, false, 'Action impossible.')
    end
    local item = cleanPiece(src, data)
    if not item or item.anchor ~= 0 then return reply(src, false, 'Action impossible.') end -- le chapeau seulement
    local list = vehicleList(vehicle)
    if #list >= (LP.MaxPerVehicle or 6) then return reply(src, false, 'Plus de place sur ce véhicule.') end
    local o = type(data.offsets) == 'table' and data.offsets or {}
    item.x, item.y, item.z = num(o.x, -RANGE, RANGE), num(o.y, -RANGE, RANGE), num(o.z, -RANGE, RANGE)
    item.rx, item.ry, item.rz = num(o.rx, -180, 180), num(o.ry, -180, 180), num(o.rz, -180, 180)
    list[#list + 1] = item
    Entity(vehicle).state:set('rpWear', list, true)
    reply(src, true)
end)

--- Reprise : même modèle de personnage (homme / femme) ; n'importe quel joueur à côté
local function give(src, item)
    local ped = GetPlayerPed(src)
    if u32(GetEntityModel(ped)) ~= u32(item.pedModel) then
        reply(src, false, ('Ce %s ne va pas à votre personnage.'):format(ANCHORS[item.anchor] or 'objet'))
        return false
    end
    TriggerClientEvent('rp_vehicleprops:wearGive', src, item)
    return true
end

RegisterNetEvent('rp_vehicleprops:wearPickup', function(id)
    local src = source
    if type(id) ~= 'string' or throttled(src) then return end
    local list, kept, taken = groundList(), {}, nil
    for _, item in ipairs(list) do
        if item.id == id and not taken and near(src, vector3(item.x, item.y, item.z), (LP.Distance or 2.5) + 1.5) then
            taken = item
        else
            kept[#kept + 1] = item
        end
    end
    if not taken then return reply(src, false, 'Il n\'est plus là.') end
    if give(src, taken) then GlobalState.rpWearGround = kept end
end)

RegisterNetEvent('rp_vehicleprops:wearTake', function(netId, id)
    local src = source
    local vehicle = vehicleFromNet(netId)
    if not vehicle or type(id) ~= 'string' or throttled(src) or not near(src, GetEntityCoords(vehicle), Config.ServerDistance or 8.0) then return end
    local list, kept, taken = vehicleList(vehicle), {}, nil
    for _, item in ipairs(list) do if item.id == id and not taken then taken = item else kept[#kept + 1] = item end end
    if not taken then return reply(src, false, 'Il n\'est plus sur le véhicule.') end
    if give(src, taken) then Entity(vehicle).state:set('rpWear', #kept > 0 and kept or nil, true) end
end)

AddEventHandler('playerDropped', function() lastAt[source] = nil end)
