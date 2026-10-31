--[[
    RP Permissions - serveur
    ========================
    À la connexion : rôles Discord du joueur (API de Discord, bot du serveur) -> son rang (le rôle le plus haut de
    PermsConfig.Roles) -> groupe ACE donné à son identifiant Discord (add_principal identifier.discord:… group.…) :
    vMenu et tous les scripts lisent ensuite les permissions de ce groupe (permissions.cfg). Liste blanche : sans rôle
    d'accès, connexion refusée (PermsConfig.Whitelist).
    En jeu : rang revérifié toutes les RefreshMinutes (rôle donné / retiré sur Discord) ; état du joueur « rpRank »
    (visible par son client) ; exports getRank / isAdmin / isMember / hasRank / refresh.
    Le token du bot vient de la convar « rp_discord_token » (server.cfg) ou de BotToken (config.lua, lu seulement par
    le serveur) et n'est jamais affiché.
]]

local C = PermsConfig
local TOKEN = GetConvar('rp_discord_token', '')
if TOKEN == '' then TOKEN = tostring(C.BotToken or '') end
local GUILD = GetConvar('rp_discord_guild', '')
if GUILD == '' then GUILD = tostring(C.GuildId or '') end
local API = 'https://discord.com/api/v10'
local RES = GetCurrentResourceName()

local ROLES, LEVEL = {}, {} -- [clé] = rôle ; [clé] = niveau (1 = le plus haut)
for i, r in ipairs(C.Roles or {}) do
    ROLES[r.key] = r
    LEVEL[r.key] = i
end

local cache = {}      -- [discordId] = { status, roles, rank, at }
local applied = {}    -- [discordId] = groupe ACE donné par ce script
local ranks = {}      -- [joueur] = clé du rang (nil : aucun)
local working = TOKEN ~= '' and GUILD ~= ''

local function log(text, ...) print(('^5[rp_permissions]^0 ' .. text):format(...)) end
local function debug(text, ...) if C.Debug then log(text, ...) end end

--- Identifiant Discord d'un joueur (sans « discord: »), nil s'il n'en a pas
local function discordOf(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'discord:' then return id:sub(9) end
    end
    return nil
end

--- Rang d'après la liste des rôles Discord : le premier de PermsConfig.Roles que le joueur a
local function rankOf(roles)
    local has = {}
    for _, id in ipairs(roles or {}) do has[tostring(id)] = true end
    for _, r in ipairs(C.Roles or {}) do
        if has[tostring(r.role)] then return r.key end
    end
    return nil
end

local function blacklisted(roles)
    local banned = {}
    for _, id in ipairs(C.Whitelist and C.Whitelist.BlacklistRoles or {}) do banned[tostring(id)] = true end
    for _, id in ipairs(roles or {}) do if banned[tostring(id)] then return true end end
    return false
end

--- Rôles du membre sur le serveur Discord ; cb('ok', roles) / cb('notInGuild') / cb('error', nil, code)
local function fetchMember(discordId, cb)
    if not working then return cb('error', nil, 0) end
    PerformHttpRequest(('%s/guilds/%s/members/%s'):format(API, GUILD, discordId), function(code, body)
        if code == 200 then
            local ok, data = pcall(json.decode, body or '')
            if ok and type(data) == 'table' then return cb('ok', type(data.roles) == 'table' and data.roles or {}) end
            return cb('error', nil, code)
        elseif code == 404 then
            return cb('notInGuild')
        end
        return cb('error', nil, code)
    end, 'GET', '', { Authorization = 'Bot ' .. TOKEN, ['Content-Type'] = 'application/json' })
end

--- Comme fetchMember, en attendant la réponse (dans un thread), avec le cache
local function lookup(discordId, fresh)
    local entry = cache[discordId]
    local maxAge = (C.CacheMinutes or 10) * 60000
    if not fresh and entry and entry.status ~= 'error' and GetGameTimer() - entry.at < maxAge then return entry end
    local p = promise.new()
    fetchMember(discordId, function(status, roles, code) p:resolve({ status = status, roles = roles, code = code }) end)
    local res = Citizen.Await(p)
    entry = { status = res.status, roles = res.roles, rank = res.status == 'ok' and rankOf(res.roles) or nil,
        at = GetGameTimer(), code = res.code }
    if res.status ~= 'error' then cache[discordId] = entry end
    return entry
end

--- Groupe ACE de l'identifiant Discord : celui du rang (les autres groupes de rang retirés)
local function applyPrincipal(discordId, rank)
    local wanted = rank and ROLES[rank] and ROLES[rank].group or nil
    local principal = 'identifier.discord:' .. discordId
    if applied[discordId] == wanted and wanted ~= nil then return end
    for _, r in ipairs(C.Roles or {}) do
        -- première fois pour cet identifiant : tous les groupes de rang retirés (ancien rang d'un démarrage précédent)
        if r.group ~= wanted and (applied[discordId] == nil or applied[discordId] == r.group) then
            ExecuteCommand(('remove_principal %s %s'):format(principal, r.group))
        end
    end
    if wanted then ExecuteCommand(('add_principal %s %s'):format(principal, wanted)) end
    applied[discordId] = wanted or false
    debug('%s -> %s', principal, wanted or 'aucun groupe')
end

--- Rang d'un joueur connecté mis à jour (groupe ACE, état « rpRank »)
local function setRank(src, rank)
    ranks[src] = rank
    local p = Player(src)
    if p and p.state then p.state:set('rpRank', rank or 'aucun', true) end
end

local function refreshPlayer(src, fresh)
    local discordId = discordOf(src)
    if not discordId then return setRank(src, nil) end
    local entry = lookup(discordId, fresh)
    if entry.status == 'error' then return end -- Discord injoignable : rang actuel gardé
    local rank = entry.status == 'ok' and not blacklisted(entry.roles) and entry.rank or nil
    applyPrincipal(discordId, rank)
    if ranks[src] ~= rank then
        if ranks[src] ~= nil or rank ~= nil then
            log('%s (%d) : rang %s', GetPlayerName(src) or '?', src, rank and ROLES[rank].label or 'aucun')
        end
        setRank(src, rank)
    end
end

-- =========================================================================
-- CONNEXION : liste blanche et groupe ACE posé avant l'arrivée en jeu (vMenu lit les permissions à l'arrivée)
-- =========================================================================
AddEventHandler('playerConnecting', function(name, _, deferrals)
    local src = source
    local W = C.Whitelist or {}
    local M = W.Messages or {}
    deferrals.defer()
    Wait(0)
    deferrals.update((M.checking or 'Vérification Discord… (%s)'):format(name))

    local discordId = discordOf(src)
    if not discordId then
        if W.Enabled then return deferrals.done(M.noDiscord) end
        return deferrals.done()
    end
    local entry = lookup(discordId, false)
    if entry.status == 'error' then
        log('Discord injoignable pour %s (code %s) : %s', name, tostring(entry.code),
            W.OnApiError == 'deny' and 'connexion refusée' or 'connexion acceptée sans rôle')
        if W.Enabled and W.OnApiError == 'deny' then return deferrals.done(M.apiError) end
        applyPrincipal(discordId, nil)
        return deferrals.done()
    end
    if entry.status == 'notInGuild' then
        applyPrincipal(discordId, nil)
        if W.Enabled then return deferrals.done(M.notInGuild) end
        return deferrals.done()
    end
    if blacklisted(entry.roles) then
        applyPrincipal(discordId, nil)
        return deferrals.done(M.blacklisted)
    end
    if W.Enabled and not entry.rank then
        applyPrincipal(discordId, nil)
        return deferrals.done(M.notWhitelisted)
    end
    applyPrincipal(discordId, entry.rank)
    debug('%s : %s', name, entry.rank or 'aucun rang')
    deferrals.done()
end)

-- Arrivé en jeu (numéro de joueur définitif) : rang connu (cache de la connexion), sinon redemandé
AddEventHandler('playerJoining', function()
    local src = source
    local discordId = discordOf(src)
    local entry = discordId and cache[discordId]
    if entry and entry.status == 'ok' then
        setRank(src, not blacklisted(entry.roles) and entry.rank or nil)
    else
        CreateThread(function() refreshPlayer(src, false) end)
    end
end)

AddEventHandler('playerDropped', function() ranks[source] = nil end)

-- Démarrage (ou redémarrage du script) : vérification du bot, rang des joueurs déjà connectés
CreateThread(function()
    if TOKEN == '' then
        log('^1token du bot absent (BotToken dans config.lua, ou convar rp_discord_token) : rôles Discord désactivés '
            .. '(permissions de base pour tous).^0')
    elseif GUILD == '' then
        log('^1ID du serveur Discord absent (config.lua GuildId ou convar rp_discord_guild).^0')
    else
        local p = promise.new()
        PerformHttpRequest(('%s/guilds/%s'):format(API, GUILD), function(code) p:resolve(code) end, 'GET', '',
            { Authorization = 'Bot ' .. TOKEN })
        local code = Citizen.Await(p)
        if code == 200 then
            log('connecté au serveur Discord.')
        elseif code == 401 then
            working = false
            log('^1token du bot refusé par Discord (401) : régénérez-le et mettez à jour rp_discord_token.^0')
        else
            log('^1serveur Discord inaccessible (code %s) : bot absent du serveur ou mauvais ID.^0', tostring(code))
        end
    end
    if not IsPrincipalAceAllowed('resource.' .. RES, 'command.add_principal')
        or not IsPrincipalAceAllowed('resource.' .. RES, 'command.remove_principal') then
        log('^1il manque dans server.cfg : add_ace resource.%s command.add_principal allow ET '
            .. 'add_ace resource.%s command.remove_principal allow (sans elles, aucun groupe ne peut être donné).^0', RES, RES)
    end
    for _, id in ipairs(GetPlayers()) do refreshPlayer(tonumber(id), false) end
    -- Revérification régulière (rôle donné / retiré sur Discord pendant que le joueur joue)
    while true do
        Wait(math.max(1, C.RefreshMinutes or 15) * 60000)
        for _, id in ipairs(GetPlayers()) do
            refreshPlayer(tonumber(id), true)
            Wait(1500) -- ménage les limites de l'API de Discord
        end
    end
end)

-- =========================================================================
-- EXPORTS (serveur) : pour les scripts qui préfèrent demander le rang plutôt qu'une ACE
-- =========================================================================
local function getRank(src) return ranks[tonumber(src) or -1] end
--- Le joueur a au moins ce rang ('nonofficiel' < 'membre' < 'admin')
local function hasRank(src, key)
    local rank = getRank(src)
    if not rank or not LEVEL[key] then return false end
    return LEVEL[rank] <= LEVEL[key]
end
exports('getRank', getRank)
exports('hasRank', hasRank)
exports('isAdmin', function(src) return hasRank(src, 'admin') end)
exports('isMember', function(src) return hasRank(src, 'membre') end)
exports('refresh', function(src) CreateThread(function() refreshPlayer(tonumber(src), true) end) end)

-- =========================================================================
-- COMMANDES (console du serveur, ou admins) : liste des rangs, revérification
-- =========================================================================
local function canUse(src) return src == 0 or hasRank(src, 'admin') end
local function reply(src, text)
    if src == 0 then print(text) else TriggerClientEvent('chat:addMessage', src, { args = { 'Permissions', text } }) end
end

RegisterCommand('rpperms', function(src)
    if not canUse(src) then return end
    for _, id in ipairs(GetPlayers()) do
        local n = tonumber(id)
        local rank = ranks[n]
        reply(src, ('%d  %s  : %s'):format(n, GetPlayerName(n) or '?', rank and ROLES[rank].label or 'aucun rôle'))
    end
end, false)

RegisterCommand('rpperms_refresh', function(src, args)
    if not canUse(src) then return end
    local target = tonumber(args[1])
    CreateThread(function()
        for _, id in ipairs(GetPlayers()) do
            local n = tonumber(id)
            if not target or target == n then refreshPlayer(n, true) end
        end
        reply(src, 'Rangs revérifiés auprès de Discord.')
    end)
end, false)
