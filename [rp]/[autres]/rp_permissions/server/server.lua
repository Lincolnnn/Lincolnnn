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

-- SESSION WHITELIST (/whiteliston, /whitelistoff) : connexion réservée aux Membres et Admins ; gardée au redémarrage
local WS = (C.Whitelist or {}).Session or {}
local KVP_MEMBERS = 'rp_whitelist_members_only'
local membersOnly = GetResourceKvpString(KVP_MEMBERS) == '1'
GlobalState.rpWhitelistMembersOnly = membersOnly
--- Ce rang peut-il se connecter pendant une session whitelist ? (Membre ou au-dessus)
local function sessionAllows(rank)
    if not membersOnly then return true end
    local need = LEVEL[WS.MinRank or 'membre'] or 2
    return rank ~= nil and LEVEL[rank] ~= nil and LEVEL[rank] <= need
end

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
            if ok and type(data) == 'table' then
                local user = type(data.user) == 'table' and data.user or {}
                local name = type(user.global_name) == 'string' and user.global_name ~= '' and user.global_name or user.username
                return cb('ok', type(data.roles) == 'table' and data.roles or {}, nil, type(name) == 'string' and name or nil)
            end
            return cb('error', nil, code)
        elseif code == 404 then
            return cb('notInGuild')
        end
        return cb('error', nil, code)
    end, 'GET', '', { Authorization = 'Bot ' .. TOKEN, ['Content-Type'] = 'application/json' })
end

--- Comme fetchMember, en attendant la réponse (dans un thread), avec le cache.
--- `fresh` : toujours redemandé à Discord ; si Discord ne répond pas, le dernier résultat connu (moins de
--- CacheMinutes) sert de secours.
local function lookup(discordId, fresh)
    local cached = cache[discordId]
    local maxAge = (C.CacheMinutes or 10) * 60000
    local recent = cached and cached.status ~= 'error' and GetGameTimer() - cached.at < maxAge
    if not fresh and recent then return cached end
    local p = promise.new()
    fetchMember(discordId, function(status, roles, code, name) p:resolve({ status = status, roles = roles, code = code, name = name }) end)
    local res = Citizen.Await(p)
    if res.status == 'error' and recent then
        debug('Discord injoignable (code %s) : dernier résultat connu utilisé', tostring(res.code))
        return cached
    end
    local entry = { status = res.status, roles = res.roles, rank = res.status == 'ok' and rankOf(res.roles) or nil,
        at = GetGameTimer(), code = res.code, name = res.name }
    if res.status ~= 'error' then cache[discordId] = entry end
    return entry
end

local applyMembersOnly -- plus bas (refus « réservé aux membres »)
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
    if applyMembersOnly then applyMembersOnly(discordId, rank) end
    debug('%s -> %s', principal, wanted or 'aucun groupe')
end

-- =========================================================================
-- RÉSERVÉ AUX MEMBRES (C.MembersOnly : loadouts d'armes enregistrés de vMenu…) : refus posé sur l'identifiant Discord
-- de chaque joueur qui n'est ni Membre ni Admin. Un refus l'emporte sur un « allow » donné ailleurs (autre .cfg,
-- builtin.everyone) ; posé sur l'identifiant (pas sur group.nonofficiel, dont héritent les membres), il ne touche
-- que ce joueur, et il est retiré dès qu'il devient Membre / Admin. Posé AVANT l'arrivée en jeu (vMenu lit les
-- permissions à l'arrivée). Demande : add_ace resource.rp_permissions command.add_ace / command.remove_ace allow.
-- =========================================================================
local denied = {}      -- [discordId] = true : refus posés
local denyWarned = false
local MEMBER_LEVEL = { admin = true, membre = true }
applyMembersOnly = function(discordId, rank)
    local list = C.MembersOnly or {}
    if #list == 0 then return end
    local want = not MEMBER_LEVEL[rank or '']
    -- première fois pour cet identifiant (ou script redémarré) : toujours appliqué (un ancien refus est retiré)
    if denied[discordId] ~= nil and denied[discordId] == want then return end
    local command = want and 'add_ace' or 'remove_ace'
    if not IsPrincipalAceAllowed('resource.' .. RES, 'command.' .. command) then
        if not denyWarned then
            denyWarned = true
            log('^3MembersOnly (loadouts vMenu…) : ajoutez dans server.cfg  add_ace resource.%s command.add_ace allow  et'
                .. '  add_ace resource.%s command.remove_ace allow  (sinon seul permissions.cfg les réserve aux membres).^0', RES, RES)
        end
        return
    end
    local principal = 'identifier.discord:' .. discordId
    for _, ace in ipairs(list) do ExecuteCommand(('%s %s %s deny'):format(command, principal, ace)) end
    denied[discordId] = want
    debug('%s : %s refusé(s) %s', principal, #list, want and 'posé(s)' or 'retiré(s)')
end
RPPerms = { applyMembersOnly = applyMembersOnly } -- pour les tests

--- Rang d'un joueur connecté mis à jour (groupe ACE, état « rpRank »)
local function setRank(src, rank)
    ranks[src] = rank
    local p = Player(src)
    if p and p.state then p.state:set('rpRank', rank or 'aucun', true) end
end

--- Pseudo Discord du joueur (nom affiché, sinon nom d'utilisateur) : état « discordName » (liste des joueurs du Menu
--- Interaction) ; sans Discord : son nom FiveM
local function setDiscordName(src, name)
    local p = Player(src)
    if p and p.state then p.state:set('discordName', name or GetPlayerName(src) or '?', true) end
end

local function refreshPlayer(src, fresh)
    local discordId = discordOf(src)
    if not discordId then setDiscordName(src, nil) return setRank(src, nil) end
    local entry = lookup(discordId, fresh)
    if entry.name then setDiscordName(src, entry.name) end
    if entry.status == 'error' then return ranks[src] end -- Discord injoignable : rang actuel gardé
    local rank = entry.status == 'ok' and not blacklisted(entry.roles) and entry.rank or nil
    applyPrincipal(discordId, rank)
    if ranks[src] ~= rank then
        local before = ranks[src]
        if before ~= nil or rank ~= nil then
            log('%s (%d) : rang %s', GetPlayerName(src) or '?', src, rank and ROLES[rank].label or 'aucun')
        end
        setRank(src, rank)
        -- en jeu (pas à l'arrivée) : le joueur est prévenu ; les scripts rp_ suivent tout de suite, vMenu lit ses
        -- permissions à l'arrivée seulement
        if before ~= nil and GetPlayerName(src) then
            TriggerClientEvent('chat:addMessage', src, { args = { 'Permissions', ('Rôle Discord mis à jour : %s. '
                .. 'Reconnecte-toi pour que vMenu prenne aussi tes nouvelles permissions.'):format(rank and ROLES[rank].label or 'aucun') } })
        end
    end
    return rank
end

-- =========================================================================
-- BANNISSEMENTS (Menu Interaction > Joueurs, admins) : gardés dans la mémoire du serveur (KVP « rp_bans »), vérifiés à
-- la connexion sur tous les identifiants du joueur (licence, Discord, FiveM, Steam, Xbox…) et ses jetons matériels.
-- « Ban en jeu et Discord » : en plus, rôles d'accès retirés sur Discord, du plus haut au plus bas (Membre puis Joueur
-- non-officiel) ; le bot doit avoir la permission « Gérer les rôles » et un rôle plus haut que ceux-là.
-- /bans : liste ; /unban <n°> : lever un ban (admins ou console).
-- =========================================================================
local KVP_BANS = 'rp_bans'
local B = C.Bans or {}
local bans = {}
do
    local ok, data = pcall(json.decode, GetResourceKvpString(KVP_BANS) or '[]')
    if ok and type(data) == 'table' then bans = data end
end
local function saveBans() SetResourceKvp(KVP_BANS, json.encode(bans)) end

--- Identifiants et jetons d'un joueur (connecté ou en connexion)
local function idsOf(src)
    local out = {}
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if not id:find('^ip:') then out[#out + 1] = id end -- jamais l'adresse IP
    end
    for i = 0, math.min(10, (GetNumPlayerTokens(src) or 0)) - 1 do
        local t = GetPlayerToken(src, i)
        if t then out[#out + 1] = 'token:' .. t end
    end
    return out
end

local function findBan(src)
    local mine = {}
    for _, id in ipairs(idsOf(src)) do mine[id] = true end
    for _, ban in ipairs(bans) do
        for _, id in ipairs(ban.ids or {}) do if mine[id] then return ban end end
    end
    return nil
end

local function banMessage(ban)
    return (B.Message or 'Tu es banni du serveur. Raison : %s'):format(ban.reason ~= '' and ban.reason or 'aucune')
end

--- Rôles d'accès retirés sur Discord, du plus haut au plus bas (Membre, puis Joueur non-officiel) ; cb(retirés, échecs)
local function removeDiscordRoles(discordId, cb)
    if not working or not discordId then return cb({}, { 'Discord indisponible' }) end
    CreateThread(function()
        local entry = lookup(discordId, true)
        local has = {}
        for _, id in ipairs(entry.roles or {}) do has[tostring(id)] = true end
        local removed, failed = {}, {}
        for _, key in ipairs(B.DiscordRemoveRoles or { 'membre', 'nonofficiel' }) do
            local r = ROLES[key]
            if r and has[tostring(r.role)] then
                local p = promise.new()
                PerformHttpRequest(('%s/guilds/%s/members/%s/roles/%s'):format(API, GUILD, discordId, r.role),
                    function(code) p:resolve(code) end, 'DELETE', '',
                    { Authorization = 'Bot ' .. TOKEN, ['X-Audit-Log-Reason'] = 'Ban en jeu' })
                local code = Citizen.Await(p)
                if code == 204 or code == 200 then removed[#removed + 1] = r.label else failed[#failed + 1] = ('%s (code %s)'):format(r.label, tostring(code)) end
                Wait(300) -- limites de l'API de Discord
            end
        end
        cache[discordId] = nil
        cb(removed, failed)
    end)
end

--- Bannir un joueur connecté : opts = { reason, by (joueur ou 0), discord (rôles retirés aussi) } ; cb(ok, texte)
local function banPlayer(target, opts, cb)
    cb = cb or function() end
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return cb(false, 'Joueur introuvable.') end
    opts = type(opts) == 'table' and opts or {}
    local reason = type(opts.reason) == 'string' and opts.reason:sub(1, 200) or ''
    local by = tonumber(opts.by) or 0
    local discordId = discordOf(target)
    local ban = {
        n = (bans[#bans] and tonumber(bans[#bans].n) or 0) + 1, name = GetPlayerName(target), discord = discordId,
        reason = reason, by = by == 0 and 'console' or (GetPlayerName(by) or '?'), at = os.time(), discordBan = opts.discord == true,
        ids = idsOf(target),
    }
    bans[#bans + 1] = ban
    saveBans()
    log('%s banni par %s%s (raison : %s)', ban.name, ban.by, ban.discordBan and ' (en jeu et Discord)' or '', reason ~= '' and reason or 'aucune')
    local function finish(extra)
        DropPlayer(target, banMessage(ban))
        cb(true, ('%s est banni%s.%s'):format(ban.name, ban.discordBan and ' (en jeu et Discord)' or ' (en jeu)', extra or ''))
    end
    if not ban.discordBan then return finish() end
    removeDiscordRoles(discordId, function(removed, failed)
        local extra = #removed > 0 and (' Rôles retirés : %s.'):format(table.concat(removed, ', ')) or ' Aucun rôle d\'accès à retirer.'
        if #failed > 0 then extra = extra .. (' Échec : %s.'):format(table.concat(failed, ', ')) end
        finish(extra)
    end)
end

exports('ban', banPlayer)
exports('isBanned', function(src) return findBan(tonumber(src)) ~= nil end)
exports('discordName', function(src)
    local p = Player(tonumber(src) or -1)
    return p and p.state and p.state.discordName or GetPlayerName(src)
end)

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
    local ban = findBan(src)
    if ban then
        log('%s refusé : banni (n° %s, %s)', name, tostring(ban.n), ban.reason ~= '' and ban.reason or 'sans raison')
        return deferrals.done(banMessage(ban))
    end

    local discordId = discordOf(src)
    if not discordId then
        if W.Enabled then return deferrals.done(M.noDiscord) end
        return deferrals.done()
    end
    -- Toujours redemandé à Discord à la connexion : un rôle donné (ou un membre arrivé sur le serveur Discord) compte
    -- tout de suite. Avant : un refus restait en cache CacheMinutes (10 min) et il fallait redémarrer le serveur.
    local entry = lookup(discordId, true)
    if entry.status == 'error' then
        log('Discord injoignable pour %s (code %s) : %s', name, tostring(entry.code),
            W.OnApiError == 'deny' and 'connexion refusée' or 'connexion acceptée sans rôle')
        if W.Enabled and W.OnApiError == 'deny' then return deferrals.done(M.apiError) end
        if membersOnly then return deferrals.done(M.apiError) end -- session whitelist : jamais sans rang vérifié
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
    if not sessionAllows(entry.rank) then
        applyPrincipal(discordId, entry.rank)
        log('%s refusé : session whitelist (rang %s)', name, entry.rank and ROLES[entry.rank].label or 'aucun')
        return deferrals.done(WS.DeniedMessage or 'Session whitelist en cours : le serveur est réservé aux membres recrutés.')
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
        setDiscordName(src, entry.name)
    else
        CreateThread(function() refreshPlayer(src, false) end)
    end
end)

AddEventHandler('playerDropped', function() ranks[source] = nil end)

local ensureHierarchy
--- Hiérarchie des rangs, posée ici (même si permissions.cfg l'oublie) : chaque groupe hérite du groupe du rang en
--- dessous (admin > membre > joueur non-officiel : un admin a tout ce qu'a un membre, qui a tout ce qu'a un joueur
--- non-officiel), et chaque groupe a son repère « rp.<rang> » (lu par les scripts du serveur)
ensureHierarchy = function()
    local roles = C.Roles or {}
    for i = 1, #roles - 1 do
        ExecuteCommand(('add_principal %s %s'):format(roles[i].group, roles[i + 1].group))
    end
    if IsPrincipalAceAllowed('resource.' .. RES, 'command.add_ace') then
        for _, r in ipairs(roles) do ExecuteCommand(('add_ace %s rp.%s allow'):format(r.group, r.key)) end
    else
        log('^3repères rp.admin / rp.membre posés par permissions.cfg seulement (pour les poser ici aussi : '
            .. 'add_ace resource.%s command.add_ace allow). Les scripts lisent de toute façon le rang du joueur.^0', RES)
    end
end

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
    ensureHierarchy()
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

-- /roles (C.SelfRefresh) : un joueur revérifie SES rôles Discord tout de suite (rôle reçu en jeu), sans attendre la
-- revérification régulière ni redémarrer le serveur
local selfRefreshAt = {}
local SR = C.SelfRefresh or {}
if SR.Enabled ~= false then
    RegisterCommand(SR.Command or 'roles', function(src)
        if src == 0 then return end
        local now = GetGameTimer()
        local wait = (SR.Cooldown or 30) * 1000
        if selfRefreshAt[src] and now - selfRefreshAt[src] < wait then
            return reply(src, ('Patiente %d s avant de revérifier tes rôles.'):format(math.ceil((wait - (now - selfRefreshAt[src])) / 1000)))
        end
        selfRefreshAt[src] = now
        local before = ranks[src]
        CreateThread(function()
            local rank = refreshPlayer(src, true)
            if rank == before then
                reply(src, ('Rôles revérifiés auprès de Discord : %s (inchangé).'):format(rank and ROLES[rank].label or 'aucun rôle'))
            end
        end)
    end, false)
    AddEventHandler('playerDropped', function() selfRefreshAt[source] = nil end)
end

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

-- =========================================================================
-- SESSION WHITELIST : /whiteliston (admins) -> accès réservé aux membres recrutés, annoncé à tous, puis REDÉMARRAGE du
-- serveur RestartSeconds s après (joueurs prévenus puis déconnectés, commande RestartCommand : « quit » -> txAdmin
-- relance le serveur). Au retour, les joueurs non-officiels ne peuvent plus se connecter (refusé dès la commande).
-- /whitelistoff -> accès rétabli tout de suite pour tous les membres du Discord (Joueur non-officiel et plus),
-- sans redémarrage ; annule un redémarrage en cours.
-- =========================================================================
local restartToken = 0
local function announce(kind, title, text)
    if GetResourceState('rp_RoleplayZone') == 'started' then
        -- bannière des sessions (en haut au milieu, son), comme /sessionon et /sessionoff
        TriggerClientEvent('rp_scene:session', -1, { kind = kind, title = title, text = text, duration = 12000 })
    end
    TriggerClientEvent('chat:addMessage', -1, { args = { title, text }, color = { 230, 120, 90 } })
    log('%s : %s', title, text)
end

local function setMembersOnly(on)
    membersOnly = on == true
    SetResourceKvp(KVP_MEMBERS, membersOnly and '1' or '0')
    GlobalState.rpWhitelistMembersOnly = membersOnly
end
exports('isMembersOnly', function() return membersOnly end)

local function restartServer()
    for _, id in ipairs(GetPlayers()) do
        DropPlayer(id, WS.RestartKickMessage or 'Redémarrage du serveur : session whitelist (membres recrutés). Reconnectez-vous dans une minute.')
    end
    local command = WS.RestartCommand == nil and 'quit' or WS.RestartCommand
    if command == '' then return log('session whitelist active : redémarrez le serveur vous-même (RestartCommand vide).') end
    if not IsPrincipalAceAllowed('resource.' .. RES, 'command.' .. command:match('^(%S+)')) then
        return log('^1redémarrage impossible : ajoutez  add_ace resource.%s command.%s allow  dans server.cfg '
            .. '(session whitelist active quand même : redémarrez depuis txAdmin).^0', RES, command:match('^(%S+)'))
    end
    SetTimeout(1500, function() ExecuteCommand(command) end)
end

local function sessionAdmin(src) return src == 0 or hasRank(src, 'admin') or IsPlayerAceAllowed(src, 'rp.admin') end

RegisterCommand(WS.CommandOn or 'whiteliston', function(src)
    if not sessionAdmin(src) then return reply(src, 'Commande réservée aux administrateurs.') end
    if restartToken > 0 and membersOnly then return reply(src, 'Redémarrage déjà prévu (session whitelist).') end
    setMembersOnly(true)
    local seconds = math.max(5, math.floor(tonumber(WS.RestartSeconds) or 30))
    restartToken = restartToken + 1
    local token = restartToken
    announce('off', WS.OnTitle or 'SESSION WHITELIST', (WS.OnText or 'Accès réservé aux membres recrutés : redémarrage du serveur dans %d secondes.'):format(seconds))
    log('session whitelist demandée par %s', src == 0 and 'la console' or (GetPlayerName(src) or tostring(src)))
    CreateThread(function()
        local left = seconds
        while left > 0 do
            Wait(1000)
            if restartToken ~= token then return end -- annulé (/whitelistoff)
            left = left - 1
            if left == 20 or left == 10 or left == 5 then
                TriggerClientEvent('chat:addMessage', -1, { args = { WS.OnTitle or 'SESSION WHITELIST',
                    ('Redémarrage du serveur dans %d secondes.'):format(left) }, color = { 230, 120, 90 } })
            end
        end
        if restartToken ~= token then return end
        restartToken = 0
        restartServer()
    end)
end, false)

RegisterCommand(WS.CommandOff or 'whitelistoff', function(src)
    if not sessionAdmin(src) then return reply(src, 'Commande réservée aux administrateurs.') end
    local cancelled = restartToken > 0
    restartToken = 0
    if not membersOnly and not cancelled then return reply(src, 'Le serveur est déjà ouvert à tous les membres du Discord.') end
    setMembersOnly(false)
    announce('on', WS.OffTitle or 'SESSION OUVERTE', (WS.OffText
        or 'Accès rétabli pour tous les membres du Discord (à partir du rôle Joueur non-officiel).')
        .. (cancelled and ' Redémarrage annulé.' or ''))
end, false)

if membersOnly then log('^3session whitelist active : connexion réservée aux membres recrutés (/whitelistoff pour rouvrir).^0') end
RPPermsSession = { allows = sessionAllows, isOn = function() return membersOnly end } -- pour les tests

-- /bans (liste) et /unban <n°> : admins ou console du serveur
RegisterCommand(B.ListCommand or 'bans', function(src)
    if not canUse(src) then return end
    if #bans == 0 then return reply(src, 'Aucun joueur banni.') end
    for _, ban in ipairs(bans) do
        reply(src, ('n° %s : %s — %s (par %s, %s%s)'):format(tostring(ban.n), ban.name or '?', ban.reason ~= '' and ban.reason or 'sans raison',
            ban.by or '?', os.date('%d/%m/%Y %H:%M', ban.at or 0), ban.discordBan and ', Discord' or ''))
    end
end, false)

RegisterCommand(B.UnbanCommand or 'unban', function(src, args)
    if not canUse(src) then return end
    local n = tonumber(args[1])
    for i, ban in ipairs(bans) do
        if tonumber(ban.n) == n then
            table.remove(bans, i)
            saveBans()
            log('ban n° %s (%s) levé', tostring(n), ban.name or '?')
            return reply(src, ('Ban n° %s levé (%s).%s'):format(tostring(n), ban.name or '?',
                ban.discordBan and ' Ses rôles Discord ne sont pas rendus automatiquement.' or ''))
        end
    end
    reply(src, 'Usage : /unban <n°> (voir /bans).')
end, false)


-- =========================================================================
-- rpnettest (CONSOLE du serveur seulement) : le serveur joint-il Internet en HTTPS ? Diagnostic quand un script payant
-- dit « License check failed: Could not reach license server (HTTP 0) » (HTTP 0 = aucune réponse : DNS, pare-feu de
-- l'hébergeur, panne du site). Aucune clé, aucun jeton n'est envoyé : une simple requête GET sur chaque adresse.
-- =========================================================================
local NET_TEST = {
    { 'Riven Systems (licences riven-impact / riven_spikes)', 'https://rivensystems.harvestiq.life/' },
    { 'Discord (rôles, rp_permissions)', 'https://discord.com/api/v10/gateway' },
    { 'Google (Internet en général)', 'https://www.google.com/' },
}
RegisterCommand('rpnettest', function(src)
    if src ~= 0 then return end
    print('^5[rp_permissions]^7 test réseau du serveur (HTTPS, sans clé) :')
    for _, t in ipairs(NET_TEST) do
        local started = GetGameTimer()
        PerformHttpRequest(t[2], function(code)
            local ms = GetGameTimer() - started
            if tonumber(code) and code > 0 then
                print(('^2  OK^7  %s : HTTP %d (%d ms) — le serveur joint ce site'):format(t[1], code, ms))
            else
                print(('^1  ÉCHEC^7  %s : HTTP %s (%d ms) — aucune réponse : DNS, pare-feu de l\'hébergeur ou site en panne'):format(t[1], tostring(code), ms))
            end
        end, 'GET', '', { ['User-Agent'] = 'FiveM-server-nettest' })
    end
end, true)
