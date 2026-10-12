--[[
    Vehicle Control - serveur
    -------------------------
    Écrit l'état des véhicules (lu par tous les clients) après vérification :
      - "fuel" (essence en %) : un joueur proche du véhicule ; la valeur ne monte qu'en faisant le plein,
        au rythme d'une pompe (Fuel.RefuelPerSecond) ;
      - "vcEngine" (moteur toujours allumé), "vcBrake" (frein de parcage), "vcBroken" (cassé) : le
        conducteur uniquement ;
      - "vcDoors" (qui a ouvert chaque portière avant) : conducteur (portières 0 et 1) ou passager avant
        (portière 1) ; le propriétaire réseau du véhicule applique l'ouverture / la fermeture.
    Aucune boucle.
]]

local Config = VCConfig

local function vehicleFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
    return entity
end

local function seatOf(src, vehicle)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    for seat = -1, 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then return seat end
    end
    return nil
end

local function near(src, vehicle, range)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= range
end

-- ---- Essence ----
local refuelClock = {} -- [src] = dernière mise à jour d'un plein (ms)

RegisterNetEvent('rp_vehiclecontrol:fuel', function(netId, value, reason)
    local src = source
    local vehicle = vehicleFromNet(netId)
    value = tonumber(value)
    if not vehicle or not value or value ~= value or not near(src, vehicle, 15.0) then return end
    value = math.max(0.0, math.min(100.0, value))
    local state = Entity(vehicle).state
    local current = state.fuel
    if type(current) == 'number' and value > current + 0.01 then
        -- Hausse : seulement en faisant le plein, au rythme d'une pompe
        if reason ~= 'pump' and reason ~= 'jerrycan' then return end
        local now = GetGameTimer()
        local elapsed = math.min((now - (refuelClock[src] or now - 1000)) / 1000, 10.0)
        refuelClock[src] = now
        value = math.min(value, current + Config.Fuel.RefuelPerSecond * elapsed * 1.5 + 2.0)
    end
    state:set('fuel', math.floor(value * 100 + 0.5) / 100, true)
end)

-- ---- Moteur, frein de parcage, véhicule cassé (conducteur uniquement) ----
local STATE_KEYS = { vcEngine = true, vcBrake = true, vcBroken = true }

RegisterNetEvent('rp_vehiclecontrol:state', function(netId, key, value)
    local src = source
    local vehicle = vehicleFromNet(netId)
    if not vehicle or not STATE_KEYS[key] or type(value) ~= 'boolean' then return end
    if seatOf(src, vehicle) ~= -1 then return end
    Entity(vehicle).state:set(key, value, true)
end)

-- ---- Portières avant ----
--- Le joueur est-il encore dans ce véhicule ? (sinon, ses portières ne sont plus prioritaires)
local function inside(src, vehicle)
    local ped = GetPlayerPed(src)
    return ped ~= nil and ped ~= 0 and GetVehiclePedIsIn(ped, false) == vehicle
end

local DOORS_ALLOWED = { [-1] = { [0] = true, [1] = true }, [0] = { [1] = true } }

RegisterNetEvent('rp_vehiclecontrol:doors', function(netId, actions)
    local src = source
    local vehicle = vehicleFromNet(netId)
    if not vehicle or type(actions) ~= 'table' or #actions > 2 then return end
    local allowed = DOORS_ALLOWED[seatOf(src, vehicle)]
    if not allowed then return end
    local state = Entity(vehicle).state
    local owners = type(state.vcDoors) == 'table' and state.vcDoors or {}
    local copy, valid = {}, {}
    for k, v in pairs(owners) do copy[k] = v end
    for _, a in ipairs(actions) do
        local door = tonumber(type(a) == 'table' and a.door)
        if door and allowed[door] then
            local open = a.open == true
            -- Priorité à celui qui a ouvert : la portière ouverte par un autre n'est pas refermée
            local owner = copy[tostring(door)]
            if open or not owner or owner == src or not inside(owner, vehicle) then
                copy[tostring(door)] = open and src or nil
                valid[#valid + 1] = { door = door, open = open }
            end
        end
    end
    if #valid == 0 then return end
    state:set('vcDoors', copy, true)
    local owner = NetworkGetEntityOwner(vehicle)
    if owner and owner > 0 then TriggerClientEvent('rp_vehiclecontrol:applyDoors', owner, netId, valid) end
end)

AddEventHandler('playerDropped', function()
    refuelClock[source] = nil
end)
