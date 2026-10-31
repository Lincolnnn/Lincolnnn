--[[
    RP Teleport - client
    --------------------
    Téléportation qui attend le décor et les collisions (sinon on passe sous la map quand la zone est loin), posée sur
    le sol trouvé ; blips des joueurs suivis (positions envoyées par le serveur) ; messages privés dans rp_chat.
    Performance : aucune boucle ; rien ne tourne sans téléportation en cours.
]]

local C = TeleportConfig
local RES = GetCurrentResourceName()
local lastPosition = nil
local busy, pending = false, nil

-- ---- Messages privés : chat du serveur (rp_chat, nom publié dans GlobalState.rpChatResource), sinon chat d'origine
local function chatResource()
    local name = GlobalState.rpChatResource
    if type(name) == 'string' and GetResourceState(name) == 'started' then return name end
    return nil
end

local function notify(text, kind)
    local chat = chatResource()
    if chat then
        local ok = pcall(function() exports[chat]:addPrivate({ title = C.ChatTitle or 'Téléportation', text = text }) end)
        if ok then return end
    end
    TriggerEvent('chat:addMessage', { args = { C.ChatTitle or 'Téléportation', text },
        color = kind == 'error' and { 230, 90, 90 } or { 120, 190, 255 } })
end
RegisterNetEvent('rp_teleport:notify', notify)

-- =========================================================================
-- TÉLÉPORTATION
-- =========================================================================
--- Sol sous / près du point d'arrivée (une fois le décor chargé) : évite d'arriver en l'air ou dans le sol
local function groundZ(x, y, z)
    for _, from in ipairs({ z + 1.5, z + 10.0, z + 50.0 }) do
        local found, ground = GetGroundZFor_3dCoord(x, y, from, false)
        if found and ground > z - 5.0 and ground < z + 3.0 then return ground end
    end
    return nil
end

local function safeTeleport(coords, heading, saveLast)
    if busy then pending = { coords = coords, heading = heading, save = saveLast } return end -- gardée pour après
    busy = true
    CreateThread(function()
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local driver = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
        local entity = driver and vehicle or ped

        if saveLast then
            lastPosition = { coords = GetEntityCoords(entity), heading = GetEntityHeading(entity) }
        end
        -- Passager : il sort du véhicule (celui du conducteur ne bouge pas)
        if vehicle ~= 0 and not driver then
            TaskLeaveVehicle(ped, vehicle, 16)
            Wait(50)
        end

        if C.ScreenFade ~= false then
            DoScreenFadeOut(250)
            local fadeLimit = GetGameTimer() + 1000
            while not IsScreenFadedOut() and GetGameTimer() < fadeLimit do Wait(0) end
        end

        local x, y, z = coords.x + 0.0, coords.y + 0.0, coords.z + 0.0
        FreezeEntityPosition(entity, true)
        RequestCollisionAtCoord(x, y, z)
        NewLoadSceneStartSphere(x, y, z, 50.0, 0)
        SetEntityCoordsNoOffset(entity, x, y, z, false, false, false)
        if heading then SetEntityHeading(entity, heading + 0.0) end

        local deadline = GetGameTimer() + (C.LoadTimeout or 8000)
        while GetGameTimer() < deadline do
            RequestCollisionAtCoord(x, y, z)
            if HasCollisionLoadedAroundEntity(entity) and IsNewLoadSceneLoaded() then break end
            Wait(0)
        end
        NewLoadSceneStop()

        local ground = groundZ(x, y, z)
        if ground then
            SetEntityCoordsNoOffset(entity, x, y, ground + (driver and 0.5 or 1.0), false, false, false)
        end
        FreezeEntityPosition(entity, false)
        if driver then SetVehicleOnGroundProperly(vehicle) end

        if C.ScreenFade ~= false then DoScreenFadeIn(250) end
        busy = false
        if pending then
            local p = pending
            pending = nil
            safeTeleport(p.coords, p.heading, p.save)
        end
    end)
end
RPTeleportClient = { teleport = safeTeleport } -- pour les tests

RegisterNetEvent('rp_teleport:teleport', function(coords, heading)
    if type(coords) ~= 'table' or not tonumber(coords.x) then return end
    safeTeleport(vector3(coords.x, coords.y, coords.z), heading, true)
end)

RegisterNetEvent('rp_teleport:back', function()
    if not lastPosition then return notify('Aucune position précédente.', 'error') end
    safeTeleport(lastPosition.coords, lastPosition.heading, true) -- /back deux fois = aller-retour
    notify('Retour à votre position précédente.')
end)

exports('teleport', function(coords, heading) safeTeleport(coords, heading, true) end)

-- =========================================================================
-- BLIPS des joueurs suivis (/blip) : positions du serveur, à toute distance
-- =========================================================================
local blips = {} -- [serverId] = blip
local B = C.Blip or {}

local function removeBlip(id)
    if blips[id] and DoesBlipExist(blips[id]) then RemoveBlip(blips[id]) end
    blips[id] = nil
end

RegisterNetEvent('rp_teleport:blips', function(list)
    if type(list) ~= 'table' then return end
    for _, data in ipairs(list) do
        local id = tonumber(data.id)
        if id then
            if data.gone then
                removeBlip(id)
            else
                local blip = blips[id]
                if not blip or not DoesBlipExist(blip) then
                    blip = AddBlipForCoord(data.x + 0.0, data.y + 0.0, data.z + 0.0)
                    SetBlipSprite(blip, B.Sprite or 1)
                    SetBlipColour(blip, B.Colour or 3)
                    SetBlipScale(blip, (B.Scale or 0.9) + 0.0)
                    SetBlipAsShortRange(blip, B.ShortRange == true)
                    ShowNumberOnBlip(blip, id % 100)
                    blips[id] = blip
                else
                    SetBlipCoords(blip, data.x + 0.0, data.y + 0.0, data.z + 0.0)
                end
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(('[%d] %s'):format(id, tostring(data.name or '')))
                EndTextCommandSetBlipName(blip)
            end
        end
    end
end)

RegisterNetEvent('rp_teleport:clearBlips', function()
    for id in pairs(blips) do removeBlip(id) end
end)
RPTeleportClient.blips = blips

-- =========================================================================
-- CHAT : commandes proposées par rp_chat en tapant « / » (celles que ce joueur a le droit d'utiliser)
-- =========================================================================
RegisterNetEvent('rp_teleport:commands', function(list)
    TriggerEvent('rp_chat:client:addCommands', RES, type(list) == 'table' and list or {})
end)
CreateThread(function()
    Wait(2000)
    TriggerServerEvent('rp_teleport:ready')
end)
-- rp_chat (re)démarré après nous : la liste lui est renvoyée
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= RES and resource == GlobalState.rpChatResource then
        SetTimeout(1000, function() TriggerServerEvent('rp_teleport:ready') end)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RES then return end
    for id in pairs(blips) do removeBlip(id) end
    if busy then
        FreezeEntityPosition(PlayerPedId(), false)
        DoScreenFadeIn(0)
    end
end)
