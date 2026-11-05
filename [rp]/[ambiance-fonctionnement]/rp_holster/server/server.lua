--[[
    RP Holster - serveur : sons du holster (sortie / rangement) relayés aux joueurs proches (Sound.Range),
    une fois par geste au plus
]]

local C = HolsterConfig or {}
local SND = C.Sound or {}
local KINDS = { draw = true, holster = true }
local last = {}

RegisterNetEvent('rp_holster:sound', function(kind)
    local src = source
    if SND.Enabled == false then return end
    kind = KINDS[kind] and kind or 'holster'
    local now = GetGameTimer()
    if last[src] and now - last[src] < 250 then return end
    last[src] = now
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pos = GetEntityCoords(ped)
    local range = (SND.Range or 8.0) + 2.0
    for _, id in ipairs(GetPlayers()) do
        local p = tonumber(id)
        if p ~= src then
            local other = GetPlayerPed(p)
            if other and other ~= 0 and #(GetEntityCoords(other) - pos) <= range then
                TriggerClientEvent('rp_holster:play', p, { x = pos.x, y = pos.y, z = pos.z }, kind)
            end
        end
    end
end)

AddEventHandler('playerDropped', function() last[source] = nil end)
