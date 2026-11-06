--[[
    RP Spotlight - serveur
    ----------------------
    Seul le joueur à la bonne place change un projecteur : conducteur -> côté conducteur ; passager avant -> côté
    passager ; conducteur seul (place passager vide) -> les deux. L'état est publié sur le véhicule (état « rpSpot »,
    vu par tous) : { d = projecteur conducteur, p = projecteur passager }, chacun
    { on, yaw, pitch, mode (0 manuel, 1 verrouillé), tx, ty, tz (point verrouillé) }.
    Valeurs bornées ; au plus une mise à jour toutes les 60 ms par joueur. Aucune boucle.
]]

local C = SpotlightConfig or {}
local MODELS = {} -- [hachage] = { d = true, p = true }
for name, def in pairs(C.Vehicles or {}) do
    if type(def) == 'table' then
        MODELS[GetHashKey(name:lower()) & 0xFFFFFFFF] = { d = def.driver ~= nil, p = def.passenger ~= nil }
    end
end

local last = {}

local function num(v, min, max)
    v = tonumber(v)
    if not v or v ~= v then return 0.0 end
    return math.max(min, math.min(max, v)) + 0.0
end

--- Ce joueur peut-il tenir ce projecteur ? ('d' conducteur, 'p' passager)
local function allowed(src, vehicle, side)
    local sides = MODELS[GetEntityModel(vehicle) & 0xFFFFFFFF]
    if not sides or not sides[side] then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetVehiclePedIsIn(ped, false) ~= vehicle then return false end
    local driver, passenger = GetPedInVehicleSeat(vehicle, -1), GetPedInVehicleSeat(vehicle, 0)
    if side == 'd' then return driver == ped end
    if passenger == ped then return true end
    return driver == ped and (passenger == 0 or not passenger) -- conducteur seul : l'autre projecteur aussi
end

RegisterNetEvent('rp_spotlight:set', function(netId, side, data)
    local src = source
    if (side ~= 'd' and side ~= 'p') or type(data) ~= 'table' then return end
    local now = GetGameTimer()
    if last[src] and now - last[src] < 60 then return end
    last[src] = now
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or -1)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return end
    if not allowed(src, vehicle, side) then return end
    local mode = math.tointeger(tonumber(data.mode)) or 0
    if mode ~= 1 then mode = 0 end
    local spot = {
        on = data.on == true,
        yaw = num(data.yaw, -180, 180), pitch = num(data.pitch, -90, 90),
        mode = mode,
    }
    if mode == 1 then spot.tx, spot.ty, spot.tz = num(data.tx, -20000, 20000), num(data.ty, -20000, 20000), num(data.tz, -500, 3000) end
    local state = Entity(vehicle).state
    local all = type(state.rpSpot) == 'table' and state.rpSpot or {}
    local copy = { d = all.d, p = all.p }
    copy[side] = spot
    if not (copy.d and copy.d.on) and not (copy.p and copy.p.on) then copy = nil end -- tout éteint : état retiré
    state:set('rpSpot', copy, true)
end)

AddEventHandler('playerDropped', function() last[source] = nil end)
