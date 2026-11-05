--[[
    RP Interact - serveur : Menu Interaction > Joueurs
    --------------------------------------------------
    Liste de tous les joueurs connectés : pseudo Discord (état « discordName », donné par rp_permissions ; sinon le nom
    FiveM) et, entre parenthèses, le nom RP (état « rpName », /nomrp). Pour chacun :
      - Se téléporter (TOUT LE MONDE) : à côté du joueur ;
      - Téléporter le joueur à soi, Expulser, Bannir (ADMINS : rang Admin de rp_permissions ou ACE rp.admin) ;
        Bannir : « Ban en jeu » ou « Ban en jeu et Discord » (rôles d'accès retirés sur Discord), par rp_permissions.
    Un admin ne peut ni expulser ni bannir un autre admin. Téléportation : rp_teleport (chargement du décor, sol sûr)
    s'il est démarré, sinon directement.
]]

local S = RPIServer
local P = (InteractConfig or {}).Players or {}

local function isAdmin(src) return S.rankAllowed(src, P.AdminAce or 'rp.admin') == true end

local function stateOf(id, key)
    local p = Player(id)
    local v = p and p.state and p.state[key]
    return type(v) == 'string' and v ~= '' and v or nil
end

local function displayOf(id)
    local discord = stateOf(id, 'discordName') or GetPlayerName(id) or ('Joueur %d'):format(id)
    local rp = stateOf(id, 'rpName')
    return discord, rp
end

S.on('playersList', function(src)
    local list = {}
    for _, s in ipairs(GetPlayers()) do
        local id = tonumber(s)
        local discord, rp = displayOf(id)
        list[#list + 1] = { id = id, discord = discord, rp = rp, self = id == src or nil, admin = isAdmin(id) or nil }
    end
    table.sort(list, function(a, b) return a.discord:lower() < b.discord:lower() end)
    return { ok = true, players = list, admin = isAdmin(src) }
end)

--- Point à côté du joueur (à sa gauche ; à côté de son véhicule s'il est dedans)
local function beside(id)
    local ped = GetPlayerPed(id)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local entity, distance = ped, 1.5
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle and vehicle ~= 0 then entity, distance = vehicle, 3.0 end
    local c, h = GetEntityCoords(entity), GetEntityHeading(entity)
    local r = math.rad(h + 90.0)
    return vector3(c.x - math.sin(r) * distance, c.y + math.cos(r) * distance, c.z), h
end

local function teleport(who, coords, heading)
    if GetResourceState('rp_teleport') == 'started' then
        local ok = pcall(function() exports.rp_teleport:TeleportPlayer(who, coords, heading) end)
        if ok then return end
    end
    TriggerClientEvent('rp_interact:client:teleport', who, { x = coords.x, y = coords.y, z = coords.z }, heading)
end

local lastTp = {}

S.on('playerAction', function(src, p)
    local target = tonumber(p.target)
    if not target or not GetPlayerName(target) then return { ok = false, error = 'Ce joueur n\'est plus connecté.' } end
    local action = p.action
    local admin = isAdmin(src)
    local discord, rp = displayOf(target)
    local who = rp and ('%s (%s)'):format(discord, rp) or discord
    local reason = type(p.reason) == 'string' and p.reason:gsub('[%c]', ' '):sub(1, 200) or ''

    if action == 'goto' then
        if target == src then return { ok = false, error = 'C\'est vous.' } end
        local now = GetGameTimer()
        if not admin and lastTp[src] and now - lastTp[src] < (P.TeleportCooldown or 5) * 1000 then
            return { ok = false, error = 'Patientez quelques secondes avant de vous téléporter à nouveau.' }
        end
        local coords, heading = beside(target)
        if not coords then return { ok = false, error = 'Position du joueur introuvable.' } end
        lastTp[src] = now
        teleport(src, coords, heading)
        return { ok = true, message = ('Téléporté à côté de %s.'):format(who) }
    end

    if not admin then return { ok = false, error = 'Réservé aux admins.' } end
    if target == src then return { ok = false, error = 'C\'est vous.' } end

    if action == 'bring' then
        local coords, heading = beside(src)
        if not coords then return { ok = false, error = 'Votre position est introuvable.' } end
        teleport(target, coords, heading)
        TriggerClientEvent('chat:addMessage', target, { args = { 'Admin', 'Vous avez été téléporté par un admin.' } })
        return { ok = true, message = ('%s a été téléporté à vous.'):format(who) }
    end

    if isAdmin(target) then return { ok = false, error = 'Impossible sur un autre admin.' } end

    if action == 'kick' then
        print(('[rp_interact] %s expulsé par %s (%s)'):format(GetPlayerName(target) or '?', GetPlayerName(src) or '?', reason ~= '' and reason or 'sans raison'))
        DropPlayer(target, (P.KickMessage or 'Expulsé par un admin. Raison : %s'):format(reason ~= '' and reason or 'aucune'))
        return { ok = true, message = ('%s a été expulsé.'):format(who) }
    end

    if action == 'ban' then
        if GetResourceState('rp_permissions') ~= 'started' then return { ok = false, error = 'rp_permissions n\'est pas démarré.' } end
        local wait = promise.new()
        local ok = pcall(function()
            exports.rp_permissions:ban(target, { reason = reason, by = src, discord = p.mode == 'discord' },
                function(done, text) wait:resolve({ ok = done == true, text = text }) end)
        end)
        if not ok then return { ok = false, error = 'Bannissement impossible.' } end
        local res = Citizen.Await(wait)
        return res.ok and { ok = true, message = res.text } or { ok = false, error = res.text or 'Bannissement impossible.' }
    end

    return { ok = false, error = 'Action inconnue.' }
end)

AddEventHandler('playerDropped', function() lastTp[source] = nil end)
