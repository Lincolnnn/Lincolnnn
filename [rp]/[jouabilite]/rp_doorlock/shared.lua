--[[
    RP Doorlock - commun (client et serveur) : identifiant d'une porte = son modèle et sa position (au décimètre),
    identique chez tous les joueurs (la porte est posée par la map, au même endroit pour tout le monde).
]]

function DoorlockId(model, x, y, z)
    local function r(v) return math.floor(v * 10.0 + 0.5) end
    return ('%d:%d:%d:%d'):format(math.floor(tonumber(model) or 0), r(x), r(y), r(z))
end
