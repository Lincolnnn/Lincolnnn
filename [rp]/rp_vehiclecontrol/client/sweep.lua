--[[
    Vehicle Control - nettoyage des débris d'accident à l'œil (client)
    ------------------------------------------------------------------
    Œil (rp_interact, Config.TargetProviders) sur le sol près des débris > « Nettoyer les débris » : le personnage
    balaie (RPEMOTES « /e broom2 », sinon le balayeur du jeu) ; le serveur compte les joueurs qui balaient la même
    zone (plus ils sont, plus c'est rapide) puis fait disparaître les débris de la zone (DebrisCleanup.Radius m autour
    du premier) chez TOUS les joueurs, et chez ceux qui arrivent ensuite (Riven leur renverrait l'accident).
    Débris reconnus : modèles de la config de Riven Impact Dynamics (lue dans sa ressource), ceux de ce script
    (Debris / Glass) et DebrisCleanup.ExtraModels ; uniquement des objets posés par un script (jamais un objet de la
    carte) et jamais un objet accroché à un véhicule (airbags, pneus sur la jante).
    Performance : rien en dehors de l'œil ou d'un nettoyage ; près d'une zone nettoyée depuis moins de
    RememberSeconds s : une vérification toutes les 2 s.
]]

local C = VCConfig.DebrisCleanup or {}
if C.Enabled == false then return end

local RADIUS = C.Radius or 6.0

-- =========================================================================
-- MODÈLES DES DÉBRIS
-- =========================================================================
local models = nil -- [hash] = nom

local SKIP = { Footsteps = true, Sounds = true, Airbags = true, GtaParts = true, Appearance = true, Sync = true,
    Palette = true, Puddles = true, Absorbent = true }

local function prefixed(name)
    for _, p in ipairs(C.RivenPrefixes or { 'k3_', 'riven_crash_', 'prop_rub_carpart_' }) do
        if name:sub(1, #p) == p then return true end
    end
    return false
end

--- Config de Riven (son fichier, lu dans sa ressource) exécutée à part : ses tables Debris et CrashProps
local function rivenConfig()
    if not VC.riven or not VC.rivenResource then return nil end
    local raw = LoadResourceFile(VC.rivenResource, C.RivenConfigFile or 'riven_impact_config.lua')
    if not raw then return nil end
    local vec = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
    local env = setmetatable({ Config = {}, vector2 = vec, vector3 = vec, vector4 = vec, vec2 = vec, vec3 = vec, vec4 = vec,
        GetHashKey = GetHashKey, math = math, string = string, table = table, pairs = pairs, ipairs = ipairs,
        type = type, tonumber = tonumber, tostring = tostring, print = function() end },
        { __index = function() return function() end end })
    local chunk = load(raw, '@riven_config', 't', env)
    if not chunk or not pcall(chunk) then return nil end
    return env.Config
end

local function collect()
    local set = {}
    local function add(name)
        if type(name) == 'string' and name:match('^[%w_]+$') then set[GetHashKey(name)] = name end
    end
    local cfg = rivenConfig()
    if cfg then
        local palette = type(cfg.Debris) == 'table' and type(cfg.Debris.Palette) == 'table' and cfg.Debris.Palette or {}
        local function walk(t, depth)
            if depth > 6 then return end
            if t.painted == true and type(t.model) == 'string' then
                for paint in pairs(palette) do add(t.model .. '_' .. paint) end
            end
            for k, v in pairs(t) do
                if type(v) == 'string' and prefixed(v) then add(v)
                elseif type(v) == 'table' and not SKIP[k] then walk(v, depth + 1) end
            end
        end
        for _, key in ipairs({ 'Debris', 'CrashProps' }) do
            if type(cfg[key]) == 'table' then walk(cfg[key], 0) end
        end
    end
    local B = VCConfig.Bodywork or {}
    for _, list in ipairs({ (VCConfig.Debris or {}).Models, (B.Glass or {}).Models, C.ExtraModels }) do
        for _, name in ipairs(list or {}) do add(name) end
    end
    return set
end

local function modelSet()
    models = models or collect()
    return models
end
VC.sweepModels = modelSet -- pour les tests

--- Débris posés par un script (pas un objet de la carte), au sol (pas accroché à un véhicule)
local function isDebris(obj)
    return modelSet()[GetEntityModel(obj)] ~= nil and not IsEntityAttached(obj) and IsEntityAMissionEntity(obj)
end

local function flat(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

--- Débris à moins de radius m de at (au plus `limit`)
local function debrisAround(at, radius, limit)
    local out = {}
    for _, obj in ipairs(GetGamePool('CObject')) do
        local p = GetEntityCoords(obj)
        if math.abs(p.z - at.z) < 4.0 and flat(p, at) <= radius and isDebris(obj) then
            out[#out + 1] = obj
            if limit and #out >= limit then break end
        end
    end
    return out
end

--- Retire un débris posé par un autre script (Riven) : on en prend la propriété, puis il est supprimé
local function remove(obj)
    if not DoesEntityExist(obj) then return end
    SetEntityAsMissionEntity(obj, false, true)
    DeleteObject(obj)
    if DoesEntityExist(obj) then DeleteEntity(obj) end
end

local function clearZone(zone)
    local n = 0
    for _, obj in ipairs(debrisAround(zone, zone.r or RADIUS)) do remove(obj); n = n + 1 end
    return n
end

-- =========================================================================
-- ZONES NETTOYÉES : retirées ici, puis chez les joueurs qui arrivent ensuite (Riven leur renvoie l'accident)
-- =========================================================================
local zones = {} -- { x, y, z, r, untilAt }
local watching = false

local function watch()
    if watching then return end
    watching = true
    CreateThread(function()
        while #zones > 0 do
            local now, me = GetGameTimer(), GetEntityCoords(PlayerPedId())
            for i = #zones, 1, -1 do
                local z = zones[i]
                if now > z.untilAt then table.remove(zones, i)
                elseif flat(me, z) < 150.0 then clearZone(z) end
            end
            Wait(2000)
        end
        watching = false
    end)
end

local function addZones(list, ageMs)
    local keep = (C.RememberSeconds or 900) * 1000
    for _, z in ipairs(type(list) == 'table' and list or {}) do
        local x, y, zz = tonumber(z.x), tonumber(z.y), tonumber(z.z)
        if x and y and zz then
            local zone = { x = x, y = y, z = zz, r = tonumber(z.r) or RADIUS,
                untilAt = GetGameTimer() + keep - (tonumber(z.age) or ageMs or 0) }
            zones[#zones + 1] = zone
            clearZone(zone)
        end
    end
    if #zones > 0 then watch() end
end

RegisterNetEvent('rp_vehiclecontrol:debrisCleaned', function(list) addZones(list, 0) end)
CreateThread(function()
    Wait(3000)
    TriggerServerEvent('rp_vehiclecontrol:debrisZones') -- zones nettoyées avant notre arrivée
end)

-- =========================================================================
-- BALAYER
-- =========================================================================
local sweeping = nil -- { start = coords, res = ressource d'emotes ou nil }

local function emoteResource()
    local list = GlobalState.rpiEmotes
    local res = type(list) == 'table' and list.resource or nil
    for _, name in ipairs({ res, 'rpemotes', 'rpemotes-reborn', 'RPEMOTES', 'dpemotes' }) do
        if name and GetResourceState(name) == 'started' then return name end
    end
    return nil
end

local function progress(value, text)
    SendNUIMessage({ action = 'progress', data = value and { value = value, text = text } or false })
end

local function stopAnim(s)
    if s.res then
        pcall(function() exports[s.res]:EmoteCancel() end)
    else
        ClearPedTasks(PlayerPedId())
    end
end

local function stopSweep(tellServer, text)
    local s = sweeping
    if not s then return end
    sweeping = nil
    progress(false)
    stopAnim(s)
    if tellServer then TriggerServerEvent('rp_vehiclecontrol:sweepStop') end
    if text then VC.chat(text) end
end

local function animPlaying(s)
    if s.res then
        local ok, playing = pcall(function() return exports[s.res]:IsPlayerInAnim() end)
        return not ok or playing ~= false
    end
    return IsPedUsingAnyScenario(PlayerPedId())
end

local function startSweep()
    if sweeping then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, true) or IsEntityDead(ped) then return end
    local res = C.Emote and emoteResource()
    if res then
        ExecuteCommand(C.Emote)
    else
        TaskStartScenarioInPlace(ped, C.Scenario or 'WORLD_HUMAN_JANITOR', 0, true)
    end
    local s = { start = GetEntityCoords(ped), res = res, since = GetGameTimer() }
    sweeping = s
    progress(0.0, 'Nettoyage des débris')
    TriggerServerEvent('rp_vehiclecontrol:sweepStart')
    CreateThread(function()
        while sweeping == s do
            Wait(250)
            if sweeping ~= s then return end
            local p = PlayerPedId()
            local away = #(GetEntityCoords(p) - s.start) > (C.Leave or 2.5)
            -- l'emote met un instant à démarrer : son arrêt (X) ne compte qu'ensuite
            local stopped = GetGameTimer() - s.since > 1500 and not animPlaying(s)
            if away or stopped or IsPedInAnyVehicle(p, true) or IsEntityDead(p) then
                stopSweep(true, 'Nettoyage interrompu.')
            end
        end
    end)
end

-- Avancement envoyé par le serveur : part faite (0-1), nombre de joueurs qui balaient la zone
RegisterNetEvent('rp_vehiclecontrol:sweepProgress', function(value, count)
    if not sweeping then return end
    count = tonumber(count) or 1
    progress(tonumber(value) or 0.0, count > 1 and ('Nettoyage des débris (%d personnes)'):format(count) or 'Nettoyage des débris')
end)

RegisterNetEvent('rp_vehiclecontrol:sweepDone', function(removed)
    if not sweeping then return end
    stopSweep(false) -- (pas de message : les débris disparaissent)
end)

RegisterNetEvent('rp_vehiclecontrol:sweepRefused', function(text)
    if sweeping then stopSweep(false, text) end
end)

-- =========================================================================
-- ŒIL (rp_interact : Config.TargetProviders) : exports targetOptions / targetSelect
-- =========================================================================
local cache = { at = -math.huge, count = 0 }

local function nearbyCount()
    local now = GetGameTimer()
    if now - cache.at > 1000 then
        cache.at = now
        cache.count = #debrisAround(GetEntityCoords(PlayerPedId()), RADIUS, 1)
    end
    return cache.count
end

VC.addTarget({
    options = function(info)
        if sweeping or type(info) ~= 'table' or (info.type ~= 'world' and info.type ~= 'object') then return nil end
        if IsPedInAnyVehicle(PlayerPedId(), true) or nearbyCount() == 0 then return nil end
        return { label = 'Débris d\'accident', options = {
            { id = 'sweep', icon = 'trash', label = ('Nettoyer les débris (zone de %d m)'):format(math.floor(RADIUS)), primary = true },
        } }
    end,
    select = function(id)
        if id ~= 'sweep' then return false end
        startSweep()
        return true
    end,
})

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and sweeping then stopSweep(false) end
end)
