--[[
    RP Teleport - serveur
    ---------------------
    Avec OneSync, le serveur connaît la position de TOUS les joueurs ; un client ne voit que ceux de son rayon (~424 m) :
    toute la logique de position passe donc par ici, le client ne fait que se déplacer (chargement de la zone) et
    afficher les blips. Messages : privés, dans le chat du joueur (rp_chat). Aucune boucle sans blip suivi.
]]

local C = TeleportConfig
local RES = GetCurrentResourceName()

-- ---- Permissions : ACE, ou rang Discord de rp_permissions (état « rpRank ») ----
local RANK_LEVEL = { nonofficiel = 1, membre = 2, admin = 3 }
local function allowed(src, ace)
    if src == 0 or not ace then return true end
    if IsPlayerAceAllowed(src, ace) then return true end
    local need = RANK_LEVEL[type(ace) == 'string' and ace:match('^rp%.(%w+)$') or '']
    if not need then return false end
    local p = Player(src)
    local rank = p and p.state and p.state.rpRank
    return (RANK_LEVEL[rank] or 0) >= need
end
local function can(src, command) return allowed(src, (C.Permissions or {})[command]) end
local function isAdmin(src) return allowed(src, 'rp.admin') end

local function notify(src, text, kind)
    if src == 0 then return print(('[%s] %s'):format(RES, text)) end
    TriggerClientEvent('rp_teleport:notify', src, text, kind)
end

local function nameOf(id)
    local name = GetPlayerName(id) or '?'
    local p = Player(id)
    local rp = p and p.state and p.state.rpName
    if type(rp) == 'string' and rp ~= '' and rp ~= name then return ('%s (%s)'):format(rp, name) end
    return name
end

--- Joueur connecté (numéro) ou nil
local function playerId(value)
    local id = tonumber(value)
    if not id or id ~= math.floor(id) or not GetPlayerName(id) then return nil end
    return id
end

--- Position d'un joueur, même très loin : coords, heading, véhicule (0 à pied)
local function getPlayerPosition(id)
    id = playerId(id)
    if not id then return nil end
    local ped = GetPlayerPed(id)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return GetEntityCoords(ped), GetEntityHeading(ped), GetVehiclePedIsIn(ped, false)
end
exports('GetPlayerPosition', function(id)
    local coords, heading = getPlayerPosition(id)
    return coords, heading
end)

--- Point d'arrivée À CÔTÉ d'un joueur (à gauche de lui ; à côté de son véhicule s'il est dedans)
local function besidePlayer(id)
    local coords, heading, vehicle = getPlayerPosition(id)
    if not coords then return nil end
    local distance = C.SideDistance or 1.5
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        heading = GetEntityHeading(vehicle)
        coords = GetEntityCoords(vehicle)
        distance = C.VehicleSideDistance or 3.0
    end
    local r = math.rad((heading or 0.0) + 90.0) -- à gauche
    return vector3(coords.x - math.sin(r) * distance, coords.y + math.cos(r) * distance, coords.z), heading
end

local function teleportPlayer(id, coords, heading)
    TriggerClientEvent('rp_teleport:teleport', id, { x = coords.x, y = coords.y, z = coords.z }, heading)
end
exports('TeleportPlayer', teleportPlayer)

local lastTeleport = {}
local function onCooldown(src)
    if isAdmin(src) then return false end
    local now = GetGameTimer()
    if lastTeleport[src] and now - lastTeleport[src] < (C.Cooldown or 0) then return true end
    lastTeleport[src] = now
    return false
end

local function sameBucket(a, b) return GetPlayerRoutingBucket(a) == GetPlayerRoutingBucket(b) end

AddEventHandler('onResourceStart', function(res)
    if res ~= RES then return end
    if GetConvar('onesync', 'off') == 'off' then
        print('^1[rp_teleport] OneSync est désactivé : les joueurs éloignés ne seront pas trouvés.^0')
    end
end)

-- =========================================================================
-- COMMANDES (tapées dans le chat : rp_chat les propose en tapant « / »)
-- =========================================================================
RegisterCommand('goto', function(src, args)
    if src == 0 then return notify(src, 'Commande utilisable en jeu uniquement.') end
    if not can(src, 'goto') then return notify(src, 'Permission refusée.', 'error') end
    local target = playerId(args[1])
    if not target then return notify(src, ('Joueur %s introuvable : /goto [ID] (/players pour la liste).'):format(args[1] or '?'), 'error') end
    if target == src then return notify(src, 'Vous ne pouvez pas vous téléporter à vous-même.', 'error') end
    if not sameBucket(src, target) then return notify(src, 'Ce joueur est dans une autre instance.', 'error') end
    local coords, heading = besidePlayer(target)
    if not coords then return notify(src, 'Position du joueur introuvable (en chargement ?).', 'error') end
    if onCooldown(src) then return notify(src, 'Patientez quelques secondes avant de vous retéléporter.', 'error') end
    teleportPlayer(src, coords, heading)
    notify(src, ('Téléporté vers %s [%d].'):format(nameOf(target), target), 'success')
    if C.NotifyTarget ~= false then notify(target, ('%s [%d] s\'est téléporté à vous.'):format(nameOf(src), src)) end
end, false)

RegisterCommand('bring', function(src, args)
    if src == 0 then return notify(src, 'Commande utilisable en jeu uniquement.') end
    if not can(src, 'bring') then return notify(src, 'Permission refusée.', 'error') end
    local target = playerId(args[1])
    if not target then return notify(src, ('Joueur %s introuvable : /bring [ID].'):format(args[1] or '?'), 'error') end
    if target == src then return notify(src, 'Vous ne pouvez pas vous amener vous-même.', 'error') end
    if not sameBucket(src, target) then return notify(src, 'Ce joueur est dans une autre instance.', 'error') end
    local coords, heading = besidePlayer(src)
    if not coords then return notify(src, 'Impossible de lire votre position.', 'error') end
    teleportPlayer(target, coords, heading)
    notify(src, ('%s [%d] a été amené à vous.'):format(nameOf(target), target), 'success')
    notify(target, ('Vous avez été téléporté par %s [%d] (/back pour revenir).'):format(nameOf(src), src))
end, false)

RegisterCommand('back', function(src)
    if src == 0 then return end
    if not can(src, 'back') then return notify(src, 'Permission refusée.', 'error') end
    if onCooldown(src) then return notify(src, 'Patientez quelques secondes avant de vous retéléporter.', 'error') end
    TriggerClientEvent('rp_teleport:back', src)
end, false)

RegisterCommand('players', function(src)
    if not can(src, 'players') then return notify(src, 'Permission refusée.', 'error') end
    local mine = src ~= 0 and getPlayerPosition(src) or nil
    local list = GetPlayers()
    table.sort(list, function(a, b) return tonumber(a) < tonumber(b) end)
    local lines = { ('%d joueur(s) connecté(s) :'):format(#list) }
    for _, id in ipairs(list) do
        local coords = getPlayerPosition(id)
        local distance = (mine and coords) and ('%.0f m'):format(#(mine - coords)) or '-'
        lines[#lines + 1] = ('[%s] %s — %s'):format(id, nameOf(tonumber(id)), tonumber(id) == src and 'vous' or distance)
    end
    notify(src, table.concat(lines, '\n'))
end, false)

-- =========================================================================
-- BLIPS : suivre un joueur sur la carte, à toute distance. Le serveur envoie les positions des joueurs suivis toutes
-- les Blip.Interval ms, et seulement tant que quelqu'un suit quelqu'un (aucune boucle sinon).
-- =========================================================================
local watching = {} -- [viewer] = { [target] = true }
local loopRunning = false

local function watchCount(viewer)
    local n = 0
    for _ in pairs(watching[viewer] or {}) do n = n + 1 end
    return n
end

local function sendBlips()
    for viewer, targets in pairs(watching) do
        local data = {}
        for target in pairs(targets) do
            local coords = getPlayerPosition(target)
            if not GetPlayerName(target) then
                targets[target] = nil
                data[#data + 1] = { id = target, gone = true }
            elseif coords and sameBucket(viewer, target) then
                data[#data + 1] = { id = target, x = coords.x, y = coords.y, z = coords.z, name = nameOf(target) }
            end
        end
        if #data > 0 then TriggerClientEvent('rp_teleport:blips', viewer, data) end
        if next(targets) == nil then watching[viewer] = nil end
    end
end

local function startLoop()
    if loopRunning then return end
    loopRunning = true
    CreateThread(function()
        while next(watching) do
            sendBlips()
            Wait((C.Blip or {}).Interval or 1500)
        end
        loopRunning = false
    end)
end
RPTeleport = { sendBlips = sendBlips, watching = watching } -- pour les tests

RegisterCommand('blip', function(src, args)
    if src == 0 then return end
    if not can(src, 'blip') then return notify(src, 'Permission refusée.', 'error') end
    local arg = tostring(args[1] or ''):lower()
    if arg == '' or arg == 'off' then
        local had = watchCount(src)
        watching[src] = nil
        TriggerClientEvent('rp_teleport:clearBlips', src)
        return notify(src, had > 0 and 'Blips des joueurs retirés.' or 'Usage : /blip [ID] (encore une fois pour le retirer), /blip off.')
    end
    local target = playerId(arg)
    if not target then return notify(src, ('Joueur %s introuvable.'):format(args[1]), 'error') end
    if target == src then return notify(src, 'Vous êtes déjà sur votre carte.', 'error') end
    watching[src] = watching[src] or {}
    if watching[src][target] then
        watching[src][target] = nil
        TriggerClientEvent('rp_teleport:blips', src, { { id = target, gone = true } })
        if next(watching[src]) == nil then watching[src] = nil end
        return notify(src, ('Blip de %s [%d] retiré.'):format(nameOf(target), target))
    end
    if watchCount(src) >= ((C.Blip or {}).Max or 10) then
        return notify(src, ('%d blips au plus : /blip off pour tout retirer.'):format((C.Blip or {}).Max or 10), 'error')
    end
    watching[src][target] = true
    notify(src, ('Blip de %s [%d] affiché sur la carte (/blip %d pour le retirer).'):format(nameOf(target), target, target), 'success')
    sendBlips()
    startLoop()
end, false)

AddEventHandler('playerDropped', function()
    local src = source
    watching[src], lastTeleport[src] = nil, nil
    for viewer, targets in pairs(watching) do
        if targets[src] then
            targets[src] = nil
            TriggerClientEvent('rp_teleport:blips', viewer, { { id = src, gone = true } })
            if next(targets) == nil then watching[viewer] = nil end
        end
    end
end)

-- =========================================================================
-- CHAT : commandes autorisées pour ce joueur, proposées par rp_chat en tapant « / » (sans nom RP : utilitaires)
-- =========================================================================
local COMMANDS = {
    { name = 'goto', usage = '/goto [ID]', desc = 'Se téléporter à un joueur (toute la carte)' },
    { name = 'back', usage = '/back', desc = 'Revenir à sa position d\'avant la téléportation' },
    { name = 'blip', usage = '/blip [ID]', desc = 'Suivre un joueur sur la carte (encore une fois : retirer ; /blip off)' },
    { name = 'players', usage = '/players', desc = 'Joueurs connectés : ID, nom, distance' },
    { name = 'bring', usage = '/bring [ID]', desc = 'Amener un joueur à soi (admin)' },
}
local function sendCommands(src)
    local list = {}
    for _, c in ipairs(COMMANDS) do
        if can(src, c.name) then list[#list + 1] = { name = c.name, usage = c.usage, desc = c.desc, noName = true } end
    end
    TriggerClientEvent('rp_teleport:commands', src, list)
end
RegisterNetEvent('rp_teleport:ready', function() sendCommands(source) end)
-- Rang Discord reçu / changé (rp_permissions) : liste mise à jour
AddStateBagChangeHandler('rpRank', nil, function(bagName)
    local src = tonumber(bagName:match('^player:(%d+)$'))
    if src then SetTimeout(500, function() if GetPlayerName(src) then sendCommands(src) end end) end
end)
