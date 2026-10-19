--[[
    RP Ganghunt - serveur : nettoyage
    ---------------------------------
    Les ennemis et leurs véhicules appartiennent au joueur qui a lancé la chasse (son client les crée et les retire).
    Le serveur garde seulement leur liste : si ce joueur se déconnecte (ou plante) en pleine chasse, tout est retiré
    pour qu'aucun ennemi ne reste sur la carte.
]]

local tracked = {} -- [source] = { [netId] = true }
local MAX_TRACKED = 200 -- par joueur (10 vagues de 10 + véhicules : largement assez)

RegisterNetEvent('rp_ganghunt:track', function(netId)
    local src = source
    netId = tonumber(netId)
    if not netId then return end
    local list = tracked[src] or {}
    tracked[src] = list
    local count = 0
    for _ in pairs(list) do count = count + 1 end
    if count < MAX_TRACKED then list[netId] = true end
end)

local function clear(src, delete)
    local list = tracked[src]
    tracked[src] = nil
    if not list or not delete then return end
    for netId in pairs(list) do
        local entity = NetworkGetEntityFromNetworkId(netId)
        if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
    end
end

-- Fin de chasse normale : le client a déjà tout retiré (il en est le propriétaire)
RegisterNetEvent('rp_ganghunt:clear', function() clear(source, false) end)

AddEventHandler('playerDropped', function() clear(source, true) end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(tracked) do clear(src, true) end
end)
