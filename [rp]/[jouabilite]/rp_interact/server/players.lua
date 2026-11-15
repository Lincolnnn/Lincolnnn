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
    En plus (permissions de Config.Players.Permissions : false = tous, 'rp.membre' = Whitelist et au-dessus, 'rp.admin') :
      - Se téléporter au point (point placé sur la carte, comme « Teleport to Waypoint » de vMenu) : tout le monde ;
      - Activer les blips (TOUS les joueurs) et Activer le blip (UN joueur) : Whitelist et au-dessus. Positions envoyées
        par le serveur (OneSync : il connaît tous les joueurs), donc SANS LIMITE DE DISTANCE ; boucle seulement tant
        qu'au moins un joueur a des blips ;
      - Spectate Player : voir le point de vue d'un joueur sans s'y téléporter (Whitelist et au-dessus).
]]

local S = RPIServer
local P = (InteractConfig or {}).Players or {}

local function isAdmin(src) return S.rankAllowed(src, P.AdminAce or 'rp.admin') == true end

-- Permission d'une option (Config.Players.Permissions) ; options d'admin par défaut si absentes
local DEFAULT_PERMS = { teleport = false, waypoint = false, blips = 'rp.membre', spectate = 'rp.membre',
    bring = 'rp.admin', kick = 'rp.admin', ban = 'rp.admin' }
local function can(src, option)
    local perms = P.Permissions or {}
    local ace = perms[option]
    if ace == nil then ace = DEFAULT_PERMS[option] end
    if ace == true then ace = P.AdminAce or 'rp.admin' end
    return S.rankAllowed(src, ace or nil) == true
end
local function permsOf(src)
    local out = {}
    for option in pairs(DEFAULT_PERMS) do out[option] = can(src, option) end
    return out
end

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
    local sub = BlipSubs and BlipSubs[src]
    local tracked = {}
    for id in pairs(sub and sub.ids or {}) do tracked[#tracked + 1] = id end
    return { ok = true, players = list, admin = isAdmin(src), perms = permsOf(src),
        blipsAll = sub and sub.all or false, blipIds = tracked }
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
        if not can(src, 'teleport') then return { ok = false, error = 'Vous n\'avez pas la permission.' } end
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

    if action == 'blip' then
        if not can(src, 'blips') then return { ok = false, error = 'Blips réservés aux membres Whitelist et au-dessus.' } end
        if target == src then return { ok = false, error = 'C\'est vous.' } end
        local on = BlipsSet(src, target)
        return { ok = true, on = on, message = on and ('Blip de %s activé.'):format(who) or ('Blip de %s désactivé.'):format(who) }
    end

    if action == 'spectate' then
        if not can(src, 'spectate') then return { ok = false, error = 'Spectate réservé aux membres Whitelist et au-dessus.' } end
        if target == src then return { ok = false, error = 'C\'est vous.' } end
        local ped = GetPlayerPed(target)
        if not ped or ped == 0 or not DoesEntityExist(ped) then return { ok = false, error = 'Position du joueur introuvable.' } end
        local c = GetEntityCoords(ped)
        print(('[rp_interact] %s regarde le point de vue de %s (spectate)'):format(GetPlayerName(src) or '?', GetPlayerName(target) or '?'))
        return { ok = true, coords = { x = c.x, y = c.y, z = c.z }, name = who }
    end

    if not can(src, action) then return { ok = false, error = 'Réservé aux admins.' } end
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

-- Position du joueur regardé (spectate) quand il n'est plus dans le rayon du client (téléporté, loin)
S.on('spectatePos', function(src, p)
    if not can(src, 'spectate') then return { ok = false } end
    local target = tonumber(p.target)
    local ped = target and GetPlayerName(target) and GetPlayerPed(target)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return { ok = false, error = 'Le joueur n\'est plus connecté.' } end
    local c = GetEntityCoords(ped)
    return { ok = true, coords = { x = c.x, y = c.y, z = c.z } }
end)

-- Se téléporter au point placé sur la carte : le client cherche le sol, le serveur vérifie la permission et le délai
S.on('waypoint', function(src)
    if not can(src, 'waypoint') then return { ok = false, error = 'Vous n\'avez pas la permission.' } end
    local now = GetGameTimer()
    if not isAdmin(src) and lastTp[src] and now - lastTp[src] < (P.TeleportCooldown or 5) * 1000 then
        return { ok = false, error = 'Patientez quelques secondes avant de vous téléporter à nouveau.' }
    end
    lastTp[src] = now
    return { ok = true }
end)

-- =========================================================================
-- BLIPS GPS (tous les joueurs ou certains), sans limite de distance
-- =========================================================================
BlipSubs = {} -- [src] = { all = bool, ids = { [id] = true } }
local blipLoop = false

local function hasSubs()
    for _, sub in pairs(BlipSubs) do
        if sub.all or next(sub.ids) then return true end
    end
    return false
end

local function blipName(id)
    local discord, rp = displayOf(id)
    return rp and ('%s (%s)'):format(discord, rp) or discord
end

local function startBlipLoop()
    if blipLoop then return end
    blipLoop = true
    CreateThread(function()
        while hasSubs() do
            -- positions de tous les joueurs (une seule fois par tour)
            local all = {}
            for _, s in ipairs(GetPlayers()) do
                local id = tonumber(s)
                local ped = GetPlayerPed(id)
                if ped and ped ~= 0 and DoesEntityExist(ped) then
                    local c = GetEntityCoords(ped)
                    local vehicle = GetVehiclePedIsIn(ped, false)
                    all[#all + 1] = { id = id, x = c.x, y = c.y, z = c.z,
                        h = GetEntityHeading(vehicle ~= 0 and vehicle or ped), car = vehicle ~= 0 or nil, name = blipName(id) }
                end
            end
            for src, sub in pairs(BlipSubs) do
                if not GetPlayerName(src) then
                    BlipSubs[src] = nil
                elseif not can(src, 'blips') then -- rang perdu : blips retirés
                    BlipSubs[src] = nil
                    TriggerClientEvent('rp_interact:client:blipsClear', src)
                elseif sub.all or next(sub.ids) then
                    local list = {}
                    for _, pl in ipairs(all) do
                        if pl.id ~= src and (sub.all or sub.ids[pl.id]) then
                            list[#list + 1] = { id = pl.id, x = pl.x, y = pl.y, z = pl.z, h = pl.h, car = pl.car, name = pl.name,
                                tracked = sub.ids[pl.id] or nil }
                        end
                    end
                    TriggerClientEvent('rp_interact:client:blips', src, list)
                end
            end
            Wait(math.max(500, P.BlipInterval or 2000))
        end
        blipLoop = false
    end)
end

--- Blip d'UN joueur : bascule ; retourne true s'il est maintenant affiché
function BlipsSet(src, target)
    local sub = BlipSubs[src] or { all = false, ids = {} }
    BlipSubs[src] = sub
    if sub.ids[target] then sub.ids[target] = nil else sub.ids[target] = true end
    if not sub.all and not next(sub.ids) then TriggerClientEvent('rp_interact:client:blipsClear', src) end
    startBlipLoop()
    return sub.ids[target] == true
end

-- Blips de TOUS les joueurs : bascule
S.on('blipsAll', function(src, p)
    if not can(src, 'blips') then return { ok = false, error = 'Blips réservés aux membres Whitelist et au-dessus.' } end
    local sub = BlipSubs[src] or { all = false, ids = {} }
    BlipSubs[src] = sub
    sub.all = p.on == true
    if not sub.all and not next(sub.ids) then TriggerClientEvent('rp_interact:client:blipsClear', src) end
    startBlipLoop()
    return { ok = true, on = sub.all, message = sub.all and 'Blips de tous les joueurs activés (sans limite de distance).'
        or 'Blips de tous les joueurs désactivés.' }
end)

AddEventHandler('playerDropped', function()
    lastTp[source] = nil
    BlipSubs[source] = nil
    for _, sub in pairs(BlipSubs) do sub.ids[source] = nil end
end)
