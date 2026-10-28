--[[
    RP Revive - serveur : corps laissés sur place
    ---------------------------------------------
    Le client crée la copie de son personnage (réseau) et l'annonce ici : elle est vérifiée (un personnage, près du
    joueur), gardée même loin des joueurs, marquée « corps » (état rpCorpse, pour l'œil), retirée au bout de
    Corpse.Minutes ou quand le même joueur en laisse un autre (MaxPerPlayer). La description du profil civil actif est
    copiée sur le corps par rp_interact (export rememberCorpse), sans l'odeur détectée automatiquement.
    Aucune boucle.
]]

local R = ReviveConfig
local C = R.Corpse or {}
local corpses = {} -- [src] = { entity, ... } (plus ancien en premier)

local function remove(entity)
    if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
end

RegisterNetEvent('rp_revive:corpse', function(netId)
    local src = source
    if C.Enabled == false then return end
    netId = tonumber(netId)
    local entity = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 1 then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(entity)) > 30.0 then return remove(entity) end
    pcall(SetEntityOrphanMode, entity, 2) -- gardé même si son créateur s'en va loin ou se déconnecte
    Entity(entity).state:set('rpCorpse', true, true)
    local list = corpses[src] or {}
    corpses[src] = list
    list[#list + 1] = entity
    while #list > math.max(1, C.MaxPerPlayer or 1) do remove(table.remove(list, 1)) end
    local interact = R.InteractResource or 'rp_interact'
    if GetResourceState(interact) == 'started' then
        pcall(function() exports[interact]:rememberCorpse(src, netId) end)
    end
    local minutes = tonumber(C.Minutes) or 0
    if minutes > 0 then
        SetTimeout(math.floor(minutes * 60000), function()
            remove(entity)
            for i, e in ipairs(corpses[src] or {}) do if e == entity then table.remove(corpses[src], i) break end end
        end)
    end
end)

RegisterNetEvent('rp_revive:revived', function(where)
    local src = source
    print(('^5[RP Revive]^0 %s réanimé %s.'):format(GetPlayerName(src) or src, where == 'hospital' and 'à l\'hôpital' or 'sur place'))
end)

-- Corps gardés après la déconnexion de leur joueur (retirés à la fin de leur durée) ; ressource arrêtée : retirés
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, list in pairs(corpses) do for _, e in ipairs(list) do remove(e) end end
end)
