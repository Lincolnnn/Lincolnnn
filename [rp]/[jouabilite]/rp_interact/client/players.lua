--[[
    RP Interact - Menu Interaction > Joueurs (client) : relais entre le menu (NUI) et le serveur (server/players.lua)
]]

RegisterNUICallback('playersList', function(_, cb)
    RPI.request('playersList', {}, function(res) cb(res or { ok = false }) end)
end)

RegisterNUICallback('playerAction', function(data, cb)
    if type(data) ~= 'table' then return cb({ ok = false }) end
    if data.action == 'spectate' then return RPISpectate.toggle(tonumber(data.target), cb) end
    RPI.request('playerAction', { action = data.action, target = tonumber(data.target), reason = data.reason, mode = data.mode },
        function(res)
            res = res or { ok = false }
            if res.ok and res.message then RPI.notify(res.message, 'success')
            elseif not res.ok then RPI.notify(res.error or 'Action impossible.', 'error') end
            cb(res)
        end)
end)

-- Téléportation sans rp_teleport : décor chargé puis sol cherché
RegisterNetEvent('rp_interact:client:teleport', function(coords, heading)
    if type(coords) ~= 'table' or not tonumber(coords.x) then return end
    local ped = PlayerPedId()
    local x, y, z = coords.x + 0.0, coords.y + 0.0, coords.z + 0.0
    DoScreenFadeOut(250)
    Wait(250)
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    local deadline = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do Wait(0) end
    local ok, ground = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
    if ok then SetEntityCoordsNoOffset(ped, x, y, ground, false, false, false) end
    if heading then SetEntityHeading(ped, heading + 0.0) end
    DoScreenFadeIn(250)
end)

-- =========================================================================
-- SE TÉLÉPORTER AU POINT (point placé sur la carte), comme « Teleport to Waypoint » de vMenu : hauteur inconnue,
-- le sol est cherché en descendant (décor chargé à chaque palier)
-- =========================================================================
local tpBusy = false

local function waypointTeleport()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then return false, 'Placez d\'abord un point sur la carte.' end
    if tpBusy then return false, 'Téléportation déjà en cours.' end
    local pos = GetBlipInfoIdCoord(blip)
    tpBusy = true
    CreateThread(function()
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local entity = (vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped) and vehicle or ped
        if entity == ped and vehicle ~= 0 then TaskLeaveVehicle(ped, vehicle, 16) Wait(50) end
        DoScreenFadeOut(250)
        while not IsScreenFadedOut() do Wait(0) end
        FreezeEntityPosition(entity, true)
        local x, y = pos.x + 0.0, pos.y + 0.0
        local groundFound, groundZ = false, 0.0
        for z = 950.0, 0.0, -50.0 do
            SetEntityCoordsNoOffset(entity, x, y, z, false, false, false)
            RequestCollisionAtCoord(x, y, z)
            local deadline = GetGameTimer() + 600
            while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() < deadline do
                RequestCollisionAtCoord(x, y, z)
                Wait(0)
            end
            groundFound, groundZ = GetGroundZFor_3dCoord(x, y, z, false)
            if groundFound then break end
        end
        if not groundFound then
            groundZ = GetHeightmapTopZForPosition(x, y) -- (eau, zone non chargée)
        end
        SetEntityCoordsNoOffset(entity, x, y, groundZ + (entity == ped and 1.0 or 0.5), false, false, false)
        FreezeEntityPosition(entity, false)
        if entity ~= ped then SetVehicleOnGroundProperly(entity) end
        DoScreenFadeIn(250)
        tpBusy = false
    end)
    return true
end

RegisterNUICallback('playersWaypoint', function(_, cb)
    if not DoesBlipExist(GetFirstBlipInfoId(8)) then
        RPI.notify('Placez d\'abord un point sur la carte.', 'error')
        return cb({ ok = false })
    end
    RPI.request('waypoint', {}, function(res)
        res = res or { ok = false }
        if res.ok then
            local ok, err = waypointTeleport()
            if ok then RPI.notify('Téléporté au point de la carte.', 'success') else RPI.notify(err, 'error') end
            return cb({ ok = ok })
        end
        RPI.notify(res.error or 'Téléportation impossible.', 'error')
        cb(res)
    end)
end)

-- =========================================================================
-- BLIPS GPS des joueurs (positions envoyées par le serveur, sans limite de distance). Aucune boucle côté client.
-- =========================================================================
local playerBlips = {} -- [serverId] = blip

local function removePlayerBlip(id)
    if playerBlips[id] and DoesBlipExist(playerBlips[id]) then RemoveBlip(playerBlips[id]) end
    playerBlips[id] = nil
end

RegisterNetEvent('rp_interact:client:blips', function(list)
    if type(list) ~= 'table' then return end
    local seen = {}
    for _, p in ipairs(list) do
        local id = tonumber(p.id)
        if id and tonumber(p.x) then
            seen[id] = true
            local blip = playerBlips[id]
            if not blip or not DoesBlipExist(blip) then
                blip = AddBlipForCoord(p.x + 0.0, p.y + 0.0, p.z + 0.0)
                SetBlipCategory(blip, 7)               -- « Autres joueurs » dans la légende de la carte
                SetBlipAsShortRange(blip, false)       -- visible sur toute la carte
                ShowHeadingIndicatorOnBlip(blip, true)
                playerBlips[id] = blip
            else
                SetBlipCoords(blip, p.x + 0.0, p.y + 0.0, p.z + 0.0)
            end
            SetBlipSprite(blip, p.car and 225 or 1)    -- véhicule / à pied
            SetBlipColour(blip, p.tracked and 5 or 0)  -- jaune : joueur suivi un par un ; blanc : tous les joueurs
            SetBlipScale(blip, 0.85)
            SetBlipRotation(blip, math.floor(tonumber(p.h) or 0.0))
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(tostring(p.name or ('Joueur %d'):format(id)))
            EndTextCommandSetBlipName(blip)
        end
    end
    for id in pairs(playerBlips) do if not seen[id] then removePlayerBlip(id) end end
end)

RegisterNetEvent('rp_interact:client:blipsClear', function()
    for id in pairs(playerBlips) do removePlayerBlip(id) end
end)

RegisterNUICallback('playersBlipsAll', function(data, cb)
    RPI.request('blipsAll', { on = type(data) == 'table' and data.on == true }, function(res)
        res = res or { ok = false }
        if res.ok and res.message then RPI.notify(res.message, 'success')
        elseif not res.ok then RPI.notify(res.error or 'Action impossible.', 'error') end
        cb(res)
    end)
end)

-- =========================================================================
-- SPECTATE : voir le point de vue d'un joueur sans s'y téléporter. Avec OneSync, un joueur loin n'existe pas chez
-- ce client : le personnage du spectateur est caché (invisible, sans collision, figé) SOUS le joueur regardé pour le
-- garder à portée, puis revient exactement à sa place à la fin. Retour arrière (ou le menu) : arrêter.
-- Boucle seulement pendant le spectate.
-- =========================================================================
RPISpectate = { target = nil }
local S = RPISpectate

local function targetPed(id)
    local player = GetPlayerFromServerId(id)
    if player == -1 then return 0 end
    local ped = GetPlayerPed(player)
    return (ped ~= 0 and DoesEntityExist(ped)) and ped or 0
end

local function hideSelfNear(coords)
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, coords.x + 0.0, coords.y + 0.0, coords.z - 25.0, false, false, false)
end

function S.stop()
    if not S.target then return end
    S.target = nil -- la boucle s'arrête et remet tout en place
end

local function run(id, coords, name)
    S.target = id
    CreateThread(function()
        local ped = PlayerPedId()
        local origin, heading = GetEntityCoords(ped), GetEntityHeading(ped)
        DoScreenFadeOut(300)
        while not IsScreenFadedOut() do Wait(0) end
        SetEntityVisible(ped, false, false)
        SetEntityCollision(ped, false, false)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        hideSelfNear(coords)
        local deadline = GetGameTimer() + 6000
        local tped = targetPed(id)
        while tped == 0 and GetGameTimer() < deadline and S.target == id do
            RequestCollisionAtCoord(coords.x, coords.y, coords.z)
            Wait(100)
            tped = targetPed(id)
        end
        if tped == 0 then
            S.target = nil
            RPI.notify('Impossible de voir ce joueur (trop loin ou en chargement).', 'error')
        else
            NetworkSetInSpectatorMode(true, tped)
            DoScreenFadeIn(300)
        end
        local lastFollow, lastAsk = 0, 0
        while S.target == id do
            tped = targetPed(id)
            local now = GetGameTimer()
            if tped ~= 0 then
                if now - lastFollow > 1000 then -- rester à portée du joueur regardé
                    lastFollow = now
                    hideSelfNear(GetEntityCoords(tped))
                end
            elseif now - lastAsk > 1500 then -- il est sorti de la portée (téléporté) : sa position par le serveur
                lastAsk = now
                RPI.request('spectatePos', { target = id }, function(res)
                    if res and res.ok then hideSelfNear(res.coords) else S.target = nil end
                end)
            end
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(('Spectate : %s~n~~INPUT_FRONTEND_RRIGHT~ arrêter'):format(name or ''))
            EndTextCommandDisplayHelp(0, false, false, -1)
            if IsControlJustPressed(0, 194) or IsControlJustPressed(0, 177) then S.target = nil end
            Wait(0)
        end
        -- fin : retour exact à sa place
        DoScreenFadeOut(300)
        while not IsScreenFadedOut() do Wait(0) end
        NetworkSetInSpectatorMode(false, ped)
        RequestCollisionAtCoord(origin.x, origin.y, origin.z)
        SetEntityCoordsNoOffset(ped, origin.x, origin.y, origin.z, false, false, false)
        SetEntityHeading(ped, heading)
        local wait = GetGameTimer() + 3000
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < wait do Wait(0) end
        FreezeEntityPosition(ped, false)
        SetEntityCollision(ped, true, true)
        SetEntityInvincible(ped, false)
        SetEntityVisible(ped, true, false)
        DoScreenFadeIn(300)
    end)
end

--- Menu : lance / arrête le spectate de ce joueur
function S.toggle(id, cb)
    if not id then return cb({ ok = false }) end
    if S.target == id then
        S.stop()
        RPI.notify('Spectate arrêté.', 'success')
        return cb({ ok = true, on = false })
    end
    if S.target then S.stop() Wait(800) end
    RPI.request('playerAction', { action = 'spectate', target = id }, function(res)
        res = res or { ok = false }
        if not res.ok then
            RPI.notify(res.error or 'Spectate impossible.', 'error')
            return cb(res)
        end
        run(id, res.coords, res.name)
        cb({ ok = true, on = true })
    end)
end

RegisterNUICallback('playersSpectating', function(_, cb) cb({ ok = true, target = S.target }) end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(playerBlips) do removePlayerBlip(id) end
    if S.target then -- arrêt de la ressource pendant un spectate : le personnage redevient normal sur place
        local ped = PlayerPedId()
        NetworkSetInSpectatorMode(false, ped)
        FreezeEntityPosition(ped, false)
        SetEntityCollision(ped, true, true)
        SetEntityInvincible(ped, false)
        SetEntityVisible(ped, true, false)
    end
end)
