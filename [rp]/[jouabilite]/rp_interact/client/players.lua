--[[
    RP Interact - Menu Interaction > Joueurs (client) : relais entre le menu (NUI) et le serveur (server/players.lua)
]]

RegisterNUICallback('playersList', function(_, cb)
    RPI.request('playersList', {}, function(res) cb(res or { ok = false }) end)
end)

RegisterNUICallback('playerAction', function(data, cb)
    if type(data) ~= 'table' then return cb({ ok = false }) end
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
