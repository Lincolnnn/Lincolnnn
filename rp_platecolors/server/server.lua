--[[
    RP PlateColors - Serveur : réglages de l'éditeur (data/plates.json), envoyés à tous les joueurs
    positions[tostring(hash du modèle)] = { label, rear = { x, y, z, pitch, yaw, scale } | false, front = ... }
    colors[tostring(index de plaque)]   = { text = { r, g, b }, outline = { r, g, b } | false }
]]

local C = PlateConfig
local RESOURCE = GetCurrentResourceName()
local DATA_FILE = 'data/plates.json'
local Data = { positions = {}, colors = {} }

local function load()
    local raw = LoadResourceFile(RESOURCE, DATA_FILE)
    local ok, decoded = pcall(json.decode, raw or '')
    if ok and type(decoded) == 'table' then
        Data.positions = type(decoded.positions) == 'table' and decoded.positions or {}
        Data.colors = type(decoded.colors) == 'table' and decoded.colors or {}
    end
end

local function save()
    return SaveResourceFile(RESOURCE, DATA_FILE, json.encode(Data, { indent = true }), -1)
end

load()

local function allowed(src) return IsPlayerAceAllowed(src, C.EditAce) end

local function clamp(v, lo, hi, def)
    v = tonumber(v)
    if not v or v ~= v then return def end
    return math.max(lo, math.min(hi, v)) + 0.0
end

local function cleanSide(s)
    if type(s) ~= 'table' then return false end
    return {
        x = clamp(s.x, -10, 10, 0.0), y = clamp(s.y, -15, 15, 0.0), z = clamp(s.z, -5, 5, 0.0),
        pitch = clamp(s.pitch, -90, 90, 0.0), yaw = clamp(s.yaw, -180, 180, 0.0), scale = clamp(s.scale, 0.2, 4, 1.0),
    }
end

local function cleanRgb(c)
    if type(c) ~= 'table' or #c ~= 3 then return false end
    return { math.floor(clamp(c[1], 0, 255, 0)), math.floor(clamp(c[2], 0, 255, 0)), math.floor(clamp(c[3], 0, 255, 0)) }
end

RegisterNetEvent('rp_platecolors:request', function()
    TriggerClientEvent('rp_platecolors:data', source, Data)
end)

RegisterNetEvent('rp_platecolors:canEdit', function()
    TriggerClientEvent('rp_platecolors:editAllowed', source, allowed(source))
end)

RegisterNetEvent('rp_platecolors:savePosition', function(model, placement)
    local src = source
    model = tonumber(model)
    if not allowed(src) or not model then return end
    local key = tostring(math.floor(model))
    if type(placement) == 'table' then
        Data.positions[key] = {
            label = tostring(placement.label or ''):sub(1, 40),
            rear = cleanSide(placement.rear), front = cleanSide(placement.front),
        }
    else
        Data.positions[key] = nil
    end
    local ok = save()
    TriggerClientEvent('rp_platecolors:position', -1, key, Data.positions[key])
    TriggerClientEvent('rp_platecolors:saved', src,
        not ok and 'Erreur : data/plates.json n\'a pas pu être écrit.'
        or Data.positions[key] and 'Position enregistrée pour ce modèle.'
        or 'Réglage supprimé : placement automatique.', not ok)
end)

RegisterNetEvent('rp_platecolors:saveColors', function(colors)
    local src = source
    if not allowed(src) or type(colors) ~= 'table' then return end
    local clean = {}
    for k, c in pairs(colors) do
        local index = tonumber(k)
        local text = type(c) == 'table' and cleanRgb(c.text)
        if index and index >= 0 and index < 64 and text then
            clean[tostring(math.floor(index))] = { text = text, outline = cleanRgb(c.outline) }
        end
    end
    Data.colors = clean
    local ok = save()
    TriggerClientEvent('rp_platecolors:colors', -1, Data.colors)
    TriggerClientEvent('rp_platecolors:saved', src,
        not ok and 'Erreur : data/plates.json n\'a pas pu être écrit.'
        or next(clean) and 'Couleurs enregistrées.' or 'Couleurs de config.lua rétablies.', not ok)
end)
