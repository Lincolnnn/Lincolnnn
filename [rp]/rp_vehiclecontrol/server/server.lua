--[[
    Vehicle Control - serveur
    -------------------------
    Écrit l'état des véhicules (lu par tous les clients) après vérification :
      - "fuel" (essence en %) : un joueur proche du véhicule ; la valeur ne monte qu'en faisant le plein,
        au rythme d'une pompe (Fuel.RefuelPerSecond) ou d'un jerrican (Fuel.JerrycanPerSecond) ;
      - "vcEngine" (moteur toujours allumé), "vcBroken" (moteur détruit), "vcDamaged" (moteur très abîmé :
        fumée), "vcSignal" (clignotants / warnings),
        "vcStopLights" (feux stop à l'arrêt), "vcSteer" (angle des roues gardé à la descente) : le
        conducteur (extinction des feux stop / angle des roues : aussi juste après sa descente) ;
      - "vcPushed" (véhicule poussé : par qui, sens, poussée en cours) : un joueur à côté du véhicule ;
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
        local rate = reason == 'jerrycan' and (Config.Fuel.JerrycanPerSecond or 4.0) or Config.Fuel.RefuelPerSecond
        value = math.min(value, current + rate * elapsed * 1.5 + 2.0)
    end
    state:set('fuel', math.floor(value * 100 + 0.5) / 100, true)
end)

-- ---- Moteur, véhicule cassé, clignotants (conducteur) ; poussée (joueur à côté) ----
local SIGNALS = { left = true, right = true, hazard = true }
local STATE_KEYS = {
    vcEngine = function(v) return type(v) == 'boolean' end,
    vcBroken = function(v) return type(v) == 'boolean' end,
    vcDamaged = function(v) return type(v) == 'boolean' end,
    vcSignal = function(v) return v == false or SIGNALS[v] == true end,
    vcStopLights = function(v) return type(v) == 'boolean' end,
    vcSteer = function(v) return v == false or (type(v) == 'number' and v == v and math.abs(v) <= 90.0) end,
}
-- Envoyés aussi juste après la descente du conducteur (il est alors à côté du véhicule)
-- Clés modifiables par un joueur à côté du véhicule (pas à bord) : feux stop éteints, angle des roues,
-- véhicule réparé (/repair depuis l'extérieur)
local AFTER_LEAVING = {
    vcStopLights = function(v) return v == false end,
    vcSteer = function(v) return type(v) == 'number' end,
    vcBroken = function(v) return v == false end,
    vcDamaged = function(v) return v == false end,
}
-- Coupés par son DERNIER conducteur passé directement dans un autre véhicule (nouveau véhicule apparu) :
-- moteur éteint, clignotants / warnings coupés sur l'ancien
local LAST_DRIVER = {
    vcEngine = function(v) return v == false end,
    vcSignal = function(v) return v == false end,
}
local lastDriver = {} -- [véhicule] = id serveur de son dernier conducteur

--- Conducteur (siège -1) ; à défaut (siège pas encore à jour côté serveur), joueur à bord du véhicule
local function isDriver(src, vehicle)
    if seatOf(src, vehicle) == -1 then return true end
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetVehiclePedIsIn(ped, false) == vehicle
end

RegisterNetEvent('rp_vehiclecontrol:state', function(netId, key, value)
    local src = source
    local vehicle = vehicleFromNet(netId)
    if not vehicle then return end
    if key == 'vcPushed' then
        -- Joueur qui pousse (à côté du véhicule) : sens (+1 / -1) et poussée en cours
        if not near(src, vehicle, 7.0) then return end
        if value == false then
            local current = Entity(vehicle).state.vcPushed
            if type(current) == 'table' and current.by ~= src then return end
            Entity(vehicle).state:set('vcPushed', false, true)
        elseif type(value) == 'table' and (value.dir == 1 or value.dir == -1) then
            Entity(vehicle).state:set('vcPushed', { by = src, dir = value.dir, active = value.active == true }, true)
        end
        return
    end
    local valid = STATE_KEYS[key]
    if not valid or not valid(value) then return end
    local driver = isDriver(src, vehicle)
    if driver then
        lastDriver[vehicle] = src
    elseif not (AFTER_LEAVING[key] and AFTER_LEAVING[key](value) and near(src, vehicle, 10.0))
        and not (LAST_DRIVER[key] and LAST_DRIVER[key](value) and lastDriver[vehicle] == src) then
        return
    end
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

-- Balle bien placée (moteur / réservoir), vue par le tireur : transmise au joueur qui contrôle le véhicule
local G = Config.Gunshots or {}
local shots = {} -- [src] = { second, count }
RegisterNetEvent('rp_vehiclecontrol:bulletHit', function(netId, part, amount)
    local src = source
    if G.Enabled == false or (part ~= 'engine' and part ~= 'tank') then return end
    local vehicle = vehicleFromNet(netId)
    amount = tonumber(amount)
    if not vehicle or not amount or amount ~= amount or amount <= 0 then return end
    amount = math.min(amount, 600.0)
    local now = os.time()
    local s = shots[src]
    if not s or s.second ~= now then s = { second = now, count = 0 }; shots[src] = s end
    s.count = s.count + 1
    if s.count > (G.MaxPerSecond or 20) then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > (G.MaxDistance or 300.0) then return end
    local owner = NetworkGetEntityOwner(vehicle)
    if owner and owner > 0 then TriggerClientEvent('rp_vehiclecontrol:bulletHit', owner, netId, part, amount) end
end)

AddEventHandler('entityRemoved', function(entity) lastDriver[entity] = nil end)

AddEventHandler('playerDropped', function()
    shots[source] = nil
    local src = source
    refuelClock[src] = nil
    -- Pistolet de pompe encore sorti : retiré
    local hose = Player(src).state.vcHose
    if type(hose) == 'table' and hose.net then
        local prop = NetworkGetEntityFromNetworkId(hose.net)
        if prop and prop ~= 0 and DoesEntityExist(prop) then DeleteEntity(prop) end
    end
end)
