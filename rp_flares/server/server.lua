--[[
    RP Flares - serveur
    -------------------
    - Pose : vérifiée (fusée en main, à côté du joueur, modèle prévu, pas trop vite, limite par joueur), puis l'objet est
      créé ICI : il reste même si le joueur se déconnecte, figé, marqué "rpFlare" (sommet de la fusée, poseur).
    - Pose confirmée : une fusée retirée au joueur ("rp_flares:placed"). Retrait (œil de rp_interact,
      "rp_flares:remove") : joueur à côté de la fusée, qui la récupère ("rp_flares:pickedUp").
    - Combustion limitée (BurnMinutes > 0) : la fusée disparaît toute seule.
    Aucune boucle.
]]

local Config = FlareConfig
local WEAPON = GetHashKey(Config.Weapon)
local MODELS = { [Config.Model] = true, [Config.FallbackModel] = true }

local flares = {}    -- [objet] = id serveur du poseur
local lastPlace = {} -- [joueur] = heure de la dernière pose

local function notify(src, text) TriggerClientEvent('rp_flares:notify', src, text) end

local function number(value)
    value = tonumber(value)
    if not value or value ~= value or math.abs(value) > 100000 then return nil end
    return value
end

local function countOf(src)
    local n = 0
    for _, by in pairs(flares) do if by == src then n = n + 1 end end
    return n
end

local function removeFlare(object)
    flares[object] = nil
    if not DoesEntityExist(object) then return end
    Entity(object).state:set('rpFlare', nil, true) -- éteinte tout de suite chez tout le monde
    DeleteEntity(object)
end

RegisterNetEvent('rp_flares:place', function(data)
    local src = source
    if type(data) ~= 'table' or not MODELS[data.model] then return end
    local x, y, z = number(data.x), number(data.y), number(data.z)
    local top = type(data.top) == 'table' and vector3(number(data.top.x) or 0.0, number(data.top.y) or 0.0, number(data.top.z) or 0.0) or nil
    if not x or not y or not z or not top then return end
    local pos = vector3(x, y, z)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - pos) > 3.0 or #(top - pos) > 2.0 then return end
    local now = GetGameTimer()
    if lastPlace[src] and now - lastPlace[src] < 500 then return end
    lastPlace[src] = now
    local current = GetSelectedPedWeapon(ped) -- arme en main (synchronisée) ; 0 / nil : non disponible
    if current and current ~= 0 and (current & 0xFFFFFFFF) ~= (WEAPON & 0xFFFFFFFF) then return end
    if (Config.MaxPerPlayer or 0) > 0 and countOf(src) >= Config.MaxPerPlayer then
        return notify(src, ('%d fusées posées au maximum : retirez-en une.'):format(Config.MaxPerPlayer))
    end

    local object = CreateObjectNoOffset(GetHashKey(data.model), x, y, z, true, true, false)
    local timeout = GetGameTimer() + 2000
    while not DoesEntityExist(object) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(object) then return end
    SetEntityRotation(object, number(data.rx) or 0.0, number(data.ry) or 0.0, 0.0, 2, true)
    FreezeEntityPosition(object, true)
    Entity(object).state:set('rpFlare', { by = src, top = { x = top.x, y = top.y, z = top.z }, at = os.time() }, true)
    flares[object] = src
    TriggerClientEvent('rp_flares:placed', src) -- une fusée de moins chez le joueur
    if (Config.BurnMinutes or 0) > 0 then
        SetTimeout(Config.BurnMinutes * 60000, function()
            if flares[object] then removeFlare(object) end
        end)
    end
end)

RegisterNetEvent('rp_flares:remove', function(netId)
    local src = source
    local object = NetworkGetEntityFromNetworkId(tonumber(netId) or -1)
    if not object or object == 0 or not DoesEntityExist(object) or type(Entity(object).state.rpFlare) ~= 'table' then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(object)) > (Config.RemoveDistance or 3.0) + 1.0 then return end
    removeFlare(object)
    TriggerClientEvent('rp_flares:pickedUp', src) -- reprise : une fusée de plus pour celui qui la ramasse
end)

AddEventHandler('entityRemoved', function(entity) flares[entity] = nil end)
AddEventHandler('playerDropped', function() lastPlace[source] = nil end)

-- Ressource arrêtée : fusées retirées
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for object in pairs(flares) do
        if DoesEntityExist(object) then DeleteEntity(object) end
    end
end)
