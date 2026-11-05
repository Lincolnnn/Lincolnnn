--[[
    Vehicle Control - débris de carrosserie sur la route après un gros choc (client, chez TOUS les joueurs proches)
    ------------------------------------------------------------------------------------------------------------
    Le CONDUCTEUR reconnaît le gros choc (violence d'au moins Debris.Min, pas un piéton ni un plot) et le côté touché ;
    le serveur relaie à tout le monde. Chaque joueur à moins de Debris.Range m voit, du côté touché : une gerbe
    d'étincelles (Effect) et des morceaux de carrosserie posés à plat sur la route (Models, sans collision : rien à
    synchroniser, personne ne bute dessus), retirés après Debris.Lifetime.
    /cleardebris : retire débris et verre autour de soi (chez soi) ; /cleardebrisall : chez tous (permission ACE).
    Performance : rien en dehors d'un accident ; un nettoyage toutes les 5 s seulement tant qu'il reste des débris.
]]

-- Riven Impact Dynamics installé : c'est lui qui gère les débris (config.lua : Riven)
if VC.riven then return end

local Config = VCConfig.Debris or {}
local Bodywork = VCConfig.Bodywork or {}

local pieces = {}       -- { { object, expires } } : débris posés, du plus ancien au plus récent
local cleaning = false

local function loadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local untilTime = GetGameTimer() + 1500
    while not HasModelLoaded(hash) and GetGameTimer() < untilTime do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function removePiece(entry)
    if entry and DoesEntityExist(entry.object) then DeleteObject(entry.object) end
end

local function startCleaner()
    if cleaning then return end
    cleaning = true
    CreateThread(function()
        while #pieces > 0 do
            Wait(5000)
            local now = GetGameTimer()
            while pieces[1] and pieces[1].expires <= now do removePiece(table.remove(pieces, 1)) end
        end
        cleaning = false
    end)
end

local function effect(x, y, z)
    local fx = Config.Effect
    if not fx then return end
    RequestNamedPtfxAsset(fx[1])
    local untilTime = GetGameTimer() + 1000
    while not HasNamedPtfxAssetLoaded(fx[1]) and GetGameTimer() < untilTime do Wait(0) end
    if not HasNamedPtfxAssetLoaded(fx[1]) then return end
    UseParticleFxAsset(fx[1])
    StartParticleFxNonLoopedAtCoord(fx[2], x, y, z + 0.4, 0.0, 0.0, 0.0, fx[3] or 1.0, false, false, false)
end

--- Nombre de morceaux selon la violence du choc
function VC.debrisCount(sev)
    if sev < (Config.Min or 32.0) then return 0 end
    return math.min(Config.Max or 7, (Config.Base or 2) + math.floor((sev - (Config.Min or 32.0)) / (Config.Step or 12.0)))
end

--- Point au ras du sol, juste à l'extérieur du côté touché
local function sidePoint(vehicle, side)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local off = ({
        front = vector3(0.0, max.y + 0.4, 0.0), rear = vector3(0.0, min.y - 0.4, 0.0),
        left = vector3(min.x - 0.4, 0.0, 0.0), right = vector3(max.x + 0.4, 0.0, 0.0),
    })[side] or vector3(0.0, 0.0, 0.0)
    local p = GetOffsetFromEntityInWorldCoords(vehicle, off.x, off.y, off.z)
    return { x = p.x, y = p.y, z = p.z }
end

-- Gros choc (conducteur) : débris signalés au serveur
VC.on('impact', function(vehicle, _, drop, velocity, hit, jolt, after)
    if Config.Enabled == false or VC.seat ~= -1 or (Config.SkipClasses or {})[GetVehicleClass(vehicle)] then return end
    if hit and hit.severity == 'light' then return end
    local sev = math.max(drop or 0.0, (jolt or 0.0) * (Bodywork.JoltFactor or 1.0))
    local count = VC.debrisCount(sev)
    if count <= 0 then return end
    local side = VC.impactSide and VC.impactSide(vehicle, velocity, after or GetEntityVelocity(vehicle)) or 'front'
    local p = sidePoint(vehicle, side)
    TriggerServerEvent('rp_vehiclecontrol:debris', { x = p.x, y = p.y, z = p.z, count = count })
end)

RegisterNetEvent('rp_vehiclecontrol:debris', function(point)
    if Config.Enabled == false or type(point) ~= 'table' then return end
    local x, y, z, count = tonumber(point.x), tonumber(point.y), tonumber(point.z), tonumber(point.count)
    if not (x and y and z and count) then return end
    if #(GetEntityCoords(PlayerPedId()) - vector3(x, y, z)) > (Config.Range or 150.0) then return end
    CreateThread(function()
        effect(x, y, z)
        local models = {}
        for _, m in ipairs(Config.Models or {}) do
            local hash = loadModel(m)
            if hash then models[#models + 1] = hash end
        end
        if #models == 0 then return end
        local spread, lifetime = Config.Spread or 1.4, Config.Lifetime or 600000
        for _ = 1, math.min(count, Config.Max or 7) do
            local a, r = math.random() * 2.0 * math.pi, math.sqrt(math.random()) * spread
            local object = CreateObjectNoOffset(models[math.floor(math.random() * #models) + 1],
                x + math.cos(a) * r, y + math.sin(a) * r, z, false, false, false)
            if object and object ~= 0 then
                SetEntityHeading(object, math.random() * 360.0)
                PlaceObjectOnGroundProperly(object)
                SetEntityCollision(object, false, false)
                FreezeEntityPosition(object, true)
                pieces[#pieces + 1] = { object = object, expires = GetGameTimer() + lifetime }
            end
        end
        for _, hash in ipairs(models) do SetModelAsNoLongerNeeded(hash) end
        while #pieces > (Config.MaxPieces or 120) do removePiece(table.remove(pieces, 1)) end
        if #pieces > 0 then startCleaner() end
    end)
end)

--- Retire les débris (et le verre au sol) autour de `center` (tous si `range` est nil)
local function clearDebris(center, range)
    local kept = {}
    for _, entry in ipairs(pieces) do
        if range and DoesEntityExist(entry.object) and #(GetEntityCoords(entry.object) - center) > range then
            kept[#kept + 1] = entry
        else
            removePiece(entry)
        end
    end
    local removed = #pieces - #kept
    pieces = kept
    if VC.clearGlass then VC.clearGlass(center, range) end
    RemoveDecalsInRange(center.x, center.y, center.z, range or 5000.0)
    return removed
end
VC.clearDebris = clearDebris -- pour les tests

if Config.Command then
    RegisterCommand(Config.Command, function()
        local n = clearDebris(GetEntityCoords(PlayerPedId()), Config.ClearRange or 60.0)
        VC.chat(('Débris retirés autour de vous (%d morceau%s, verre compris).'):format(n, n > 1 and 'x' or ''))
    end, false)
end

if Config.CommandAll then
    RegisterCommand(Config.CommandAll, function()
        TriggerServerEvent('rp_vehiclecontrol:clearDebrisAll')
    end, false)
end

RegisterNetEvent('rp_vehiclecontrol:clearDebrisAll', function()
    clearDebris(GetEntityCoords(PlayerPedId()), nil)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, entry in ipairs(pieces) do removePiece(entry) end
    pieces = {}
end)
