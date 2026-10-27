--[[
    RP Interact - odeurs détectées automatiquement (commun client / serveur)
    Liste : config.lua (Smells). Une odeur est désignée par son id (gardé dans les profils).
]]

local byId = {}
for _, smell in ipairs(InteractConfig.Smells or {}) do byId[smell.id] = smell end

RPISmells = {}

function RPISmells.get(id) return byId[id] end

--- Liste d'odeurs reçue (fiche civile) -> ids valides, sans doublon, Smell.Max au plus
function RPISmells.clean(list)
    local out, seen = {}, {}
    local max = (InteractConfig.Smell or {}).Max or 2
    if type(list) ~= 'table' then return out end
    for _, id in ipairs(list) do
        if type(id) == 'string' and byId[id] and not seen[id] and #out < max then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

--- « une odeur d'essence et une odeur de brûlé » (nil sans odeur)
function RPISmells.text(list)
    local parts = {}
    for _, id in ipairs(type(list) == 'table' and list or {}) do
        if byId[id] then parts[#parts + 1] = byId[id].text end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ' et ')
end

--- Première lettre en majuscule (UTF-8 : lettres accentuées de début de phrase laissées telles quelles)
function RPISmells.sentence(text)
    if not text or text == '' then return text end
    return text:sub(1, 1):upper() .. text:sub(2)
end
