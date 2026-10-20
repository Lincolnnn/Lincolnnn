--[[
    RP DLS - serveur
    ----------------
    Seul à écrire l'état "dls" des véhicules (state bag répliqué à tous les clients), après vérification :
      - l'auteur conduit le véhicule, ou vient d'en descendre (stage de descente, sirène coupée : 15 s, 20 m) ;
      - chaque valeur est possible pour ce modèle (stages présents dans son XML, Traffic Advisor et Steady Burn
        seulement s'il en a, tons 0 à 5…). Véhicule sans fichier DLS : gyrophares d'origine (stage 3) seulement.
    Un changement refusé est signalé au client (son état revient à celui du serveur). Aucune boucle.
]]

local MAX_PER_SECOND = 25
local LEFT_MS = 15000
local LEFT_RANGE = 20.0

local lastDriver = {} -- [véhicule] = { src, time } : dernier conducteur (descente du véhicule)
local rate = {}       -- [src] = { second, count }

CreateThread(function()
    DLS.load()
end)

local function vehicleFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
    return entity
end

local function isDriver(src, vehicle)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
end

local function justLeft(src, vehicle)
    local last = lastDriver[vehicle]
    if not last or last.src ~= src or GetGameTimer() - last.time > LEFT_MS then return false end
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= LEFT_RANGE
end

local function limited(src)
    local now = os.time()
    local r = rate[src]
    if not r or r.second ~= now then r = { second = now, count = 0 }; rate[src] = r end
    r.count = r.count + 1
    return r.count > MAX_PER_SECOND
end

local function int(v, min, max)
    v = type(v) == 'number' and math.tointeger(v)
    return v and v >= min and v <= max and v or nil
end

--- État reçu -> état propre pour ce modèle, ou nil s'il est impossible
local function clean(model, st)
    if type(st) ~= 'table' then return nil end
    local s, ta, tap, tone = int(st.s, 0, 5), int(st.ta or 0, 0, 4), int(st.tap or 0, 0, 64), int(st.tone or 0, 0, 5)
    if not s or not DLS.hasStage(model, s) then return nil end
    if not ta or (ta ~= 0 and not model.ta) then return nil end
    if not tap or tap > DLS.taPatternCount(model) then return nil end
    if not tone or (tone ~= 0 and not model.tones[tone]) then return nil end
    for _, key in ipairs({ 'sb', 'int', 'bo', 'aux', 'horn' }) do
        if st[key] ~= nil and type(st[key]) ~= 'boolean' then return nil end
    end
    if st.sb and not model.steady then return nil end
    if ta ~= 0 and model.v2 and not model.ta.modes[ta] then return nil end
    -- Cruise, takedown, alley : modes du fichier en DLS v2 ; sinon takedown / alley dessinés par le script
    local cr, td, al = int(st.cr or 0, 0, 9), int(st.td or 0, 0, 9), int(st.al or 0, 0, 3)
    if not cr or not td or not al then return nil end
    if model.v2 then
        if cr > model.cruise or td > model.takedown then return nil end
        if (al & 1 ~= 0 and not model.alley.left) or (al & 2 ~= 0 and not model.alley.right) then return nil end
    elseif cr ~= 0 or td > 1 then
        return nil
    end
    return {
        s = s, ta = ta, tap = tap, sb = st.sb == true, int = st.int == true, bo = st.bo == true,
        tone = tone, aux = st.aux == true, horn = st.horn == true, cr = cr, td = td, al = al,
    }
end

RegisterNetEvent('rp_dls:driver', function(netId)
    local src = source
    local vehicle = vehicleFromNet(netId)
    if vehicle and isDriver(src, vehicle) then lastDriver[vehicle] = { src = src, time = GetGameTimer() } end
end)

RegisterNetEvent('rp_dls:set', function(netId, st)
    local src = source
    if limited(src) then return end
    local vehicle = vehicleFromNet(netId)
    if not vehicle then return end
    local driver = isDriver(src, vehicle)
    if driver then
        lastDriver[vehicle] = { src = src, time = GetGameTimer() }
    elseif not justLeft(src, vehicle) then
        TriggerClientEvent('rp_dls:refused', src, netId)
        return
    end
    local model = DLS.models[GetEntityModel(vehicle)] or DLS.generic
    local value = clean(model, st)
    if not value then
        TriggerClientEvent('rp_dls:refused', src, netId)
        return
    end
    Entity(vehicle).state:set('dls', value, true)
end)

AddEventHandler('entityRemoved', function(entity) lastDriver[entity] = nil end)
AddEventHandler('playerDropped', function() rate[source] = nil end)
