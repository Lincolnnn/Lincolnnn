--[[
    Vehicle Control - verre brisé au sol après un gros accident (client, chez TOUS les joueurs proches)
    --------------------------------------------------------------------------------------------------
    Le conducteur signale les vitres qui viennent de casser (client/bodywork.lua) ; le serveur relaie à tout le
    monde. Chaque joueur à moins de Glass.Range m voit, sous chaque vitre : une gerbe d'éclats (effet du jeu), du verre
    brisé à plat sur le sol (décalques "verre" du jeu, comme les traces de pneus : épousent la route, aucun objet) qui
    disparaît après Glass.Lifetime, et entend le bruit du verre. Glass.Models (facultatif) : objets en plus.
    Performance : rien en dehors d'un accident ; un nettoyage toutes les 5 s seulement tant qu'il reste des objets.
]]

local Config = VCConfig.Bodywork and VCConfig.Bodywork.Glass or {}

local pieces = {}       -- { { object, expires } } : éclats posés, du plus ancien au plus récent
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

--- Tant qu'il reste du verre : retire les éclats trop anciens
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
    StartParticleFxNonLoopedAtCoord(fx[2], x, y, z + 0.6, 0.0, 0.0, 0.0, fx[3] or 1.0, false, false, false)
end

--- Éclats posés au sol autour d'un point
local function scatter(models, x, y, z)
    local count, spread = Config.Pieces or 6, Config.Spread or 0.6
    local lifetime = Config.Lifetime or 300000
    for _ = 1, count do
        local model = models[math.floor(math.random() * #models) + 1]
        local a, r = math.random() * 2.0 * math.pi, math.sqrt(math.random()) * spread
        local object = CreateObjectNoOffset(model, x + math.cos(a) * r, y + math.sin(a) * r, z, false, false, false)
        if object and object ~= 0 then
            SetEntityHeading(object, math.random() * 360.0)
            PlaceObjectOnGroundProperly(object)
            SetEntityCollision(object, false, false)
            FreezeEntityPosition(object, true)
            pieces[#pieces + 1] = { object = object, expires = GetGameTimer() + lifetime }
        end
    end
    -- trop d'éclats autour de soi : les plus anciens disparaissent
    while #pieces > (Config.MaxPieces or 150) do removePiece(table.remove(pieces, 1)) end
end

--- Verre brisé à plat sur le sol : quelques décalques "verre" du jeu, orientés au hasard, qui épousent la route
local function decals(x, y, z)
    local types = Config.Decals or { 5031, 5032 }
    if #types == 0 then return end
    local size = Config.DecalSize or { 0.7, 1.3 }
    local timeout = (Config.Lifetime or 300000) / 1000.0
    for _ = 1, Config.DecalCount or 3 do
        local a, r = math.random() * 2.0 * math.pi, math.sqrt(math.random()) * (Config.Spread or 0.6)
        local side = math.random() * 2.0 * math.pi
        local w = size[1] + math.random() * (size[2] - size[1])
        AddDecal(types[math.floor(math.random() * #types) + 1],
            x + math.cos(a) * r, y + math.sin(a) * r, z + 0.05,
            0.0, 0.0, -1.0, math.cos(side), math.sin(side), 0.0, -- vers le sol, rotation au hasard
            w, w, 1.0, 1.0, 1.0, 1.0, timeout, false, false, false)
    end
end

RegisterNetEvent('rp_vehiclecontrol:glass', function(points)
    if Config.Enabled == false or type(points) ~= 'table' or #points == 0 then return end
    local me = GetEntityCoords(PlayerPedId())
    local range = Config.Range or 120.0
    local near = {}
    for _, p in ipairs(points) do
        local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
        if x and y and z and #(me - vector3(x, y, z)) <= range then near[#near + 1] = { x = x, y = y, z = z } end
    end
    if #near == 0 then return end
    CreateThread(function()
        local snd = Config.Sound
        if snd then
            local p = near[1]
            PlaySoundFromCoord(-1, snd[1], p.x, p.y, p.z, snd[2], false, snd[3] or 25, false)
        end
        local models = {}
        for _, m in ipairs(Config.Models or {}) do
            local hash = loadModel(m)
            if hash then models[#models + 1] = hash end
        end
        for _, p in ipairs(near) do
            effect(p.x, p.y, p.z)
            decals(p.x, p.y, p.z)
            if #models > 0 then scatter(models, p.x, p.y, p.z) end
        end
        for _, hash in ipairs(models) do SetModelAsNoLongerNeeded(hash) end
        if #pieces > 0 then startCleaner() end
    end)
end)

--- /cleardebris : éclats posés autour de `center` retirés (tous si `range` est nil ; les décalques : debris.lua)
function VC.clearGlass(center, range)
    local kept = {}
    for _, entry in ipairs(pieces) do
        if range and DoesEntityExist(entry.object) and #(GetEntityCoords(entry.object) - center) > range then
            kept[#kept + 1] = entry
        else
            removePiece(entry)
        end
    end
    pieces = kept
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, entry in ipairs(pieces) do removePiece(entry) end
    pieces = {}
end)
