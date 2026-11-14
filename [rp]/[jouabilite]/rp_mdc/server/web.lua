--[[
    MDC - PONT AVEC LE MDC WEB DU DISPATCH (site Node.js, dossier mdc-web)
    ---------------------------------------------------------------------
    Deux sens, sur HTTP, protégés par une clé partagée (jamais envoyée aux joueurs) :
      - site -> serveur FiveM : API de la ressource (SetHttpHandler) : http://IP:PORT/rp_mdc/api/<action>
        (en-tête X-MDC-Key = convar mdc_web_key ; facultatif : convar mdc_web_allow_ip). Le site y fait TOUTES ses
        modifications (valider / refuser une intervention, affecter une unité, changer un statut, écrire…) : le serveur
        FiveM reste le seul à écrire dans MySQL et prévient tout de suite les joueurs.
      - serveur FiveM -> site : événements (appels, unités, messages, mode Dispatch) envoyés à <mdc_web_url>/bridge/events,
        APRÈS l'écriture dans MySQL (le site relit la base, puis prévient les dispatchers en temps réel).
    Le site envoie un « battement » toutes les 15 s (dispatchers connectés) : sans nouvelles depuis
    Config.Dispatch.HeartbeatTimeout s, le dispatch est considéré hors ligne et les appels partent directement aux unités.
    Sans convar mdc_web_key : pont désactivé, le MDC en jeu fonctionne seul.
]]

MDCServer = MDCServer or {} -- fonctions du dispatch (définies dans server.lua)
MDCWeb = {}

local URL = (GetConvar('mdc_web_url', '')):gsub('/+$', '')
local KEY = GetConvar('mdc_web_key', '')
local ALLOW = {}
for ip in (GetConvar('mdc_web_allow_ip', '')):gmatch('[^,%s]+') do ALLOW[ip] = true end

function MDCWeb.enabled() return KEY ~= '' end

-- =========================================================================
-- ÉVÉNEMENTS VERS LE SITE (regroupés, envoyés une fois MySQL à jour)
-- =========================================================================
local pending, scheduled, lastError = {}, false, 0
local COALESCE = { calls = true, units = true, reads = true } -- un seul « liste à jour » par envoi

local function flush()
    if MDCDB.busy() then return end -- MDCDB.onIdle relancera l'envoi
    if #pending == 0 then return end
    local events = pending
    pending = {}
    PerformHttpRequest(URL .. '/bridge/events', function(code)
        if code ~= 200 and os.time() - lastError > 60 then
            lastError = os.time()
            print(('^3[MDC] MDC Web injoignable (%s/bridge/events, code %s) : le MDC en jeu continue sans lui.^0'):format(URL, tostring(code)))
        end
    end, 'POST', json.encode({ events = events }), { ['Content-Type'] = 'application/json', ['X-MDC-Key'] = KEY })
end

local function schedule()
    if scheduled then return end
    scheduled = true
    SetTimeout(50, function()
        scheduled = false
        flush()
    end)
end

--- Prévient le site d'un changement (`topic` : calls, units, message, dispatch, call:awaiting, call:new…)
function MDCWeb.notify(topic, data)
    if URL == '' or KEY == '' then return end
    if COALESCE[topic] then
        for _, e in ipairs(pending) do if e.topic == topic then return schedule() end end
    end
    pending[#pending + 1] = { topic = topic, data = data, at = os.time() }
    if #pending > 200 then table.remove(pending, 1) end
    schedule()
end

MDCDB.onIdle(function() if #pending > 0 then schedule() end end)

-- =========================================================================
-- API APPELÉE PAR LE SITE
-- =========================================================================
--- Comparaison en temps constant (la clé ne se devine pas caractère par caractère)
local function sameKey(a, b)
    if type(a) ~= 'string' or #a ~= #b or #b == 0 then return false end
    local diff = 0
    for i = 1, #b do diff = diff | (a:byte(i) ~ b:byte(i)) end
    return diff == 0
end

local function header(req, name)
    for k, v in pairs(req.headers or {}) do
        if type(k) == 'string' and k:lower() == name then return v end
    end
    return nil
end

local function actorOf(body)
    local a = type(body.actor) == 'table' and body.actor or {}
    local id = tostring(a.id or ''):gsub('[^%d]', ''):sub(1, 32)
    local name = tostring(a.name or ''):gsub('[%c<>]', ''):sub(1, 60)
    return { id = id, name = name ~= '' and name or 'Dispatch' }
end

local ACTIONS = {
    ['heartbeat']      = function(b) return MDCServer.heartbeat(b.dispatchers) end,
    ['state']          = function() return { ok = true, dispatch = MDCServer.dispatchState(), ready = MDCDB.ready } end,
    ['dispatch.mode']  = function(b, actor) return MDCServer.setMode(b.enabled == true, actor) end,
    ['call.validate']  = function(b, actor) return MDCServer.validate(b.id, actor, b.units) end,
    ['call.refuse']    = function(b, actor) return MDCServer.refuse(b.id, b.reason, actor) end,
    ['call.cancel']    = function(b, actor) return MDCServer.cancel(b.id, b.reason, actor) end,
    ['call.close']     = function(b, actor) return MDCServer.close(b.id, actor, b.clear) end,
    ['call.assign']    = function(b, actor) return MDCServer.assign(b.id, b.unitId, actor) end,
    ['call.unassign']  = function(b, actor) return MDCServer.unassign(b.id, b.unitId, actor) end,
    ['call.note']      = function(b, actor) return MDCServer.note(b.id, b.text, actor) end,
    ['unit.status']    = function(b, actor) return MDCServer.unitStatus(b.unitId, b.status, actor) end,
    ['message.send']   = function(b, actor) return MDCServer.sendMessage(b.channel, b.text, actor) end,
    ['message.read']   = function(b) return MDCServer.markRead(b.channel) end,
}

local function reply(res, code, data)
    res.writeHead(code, { ['Content-Type'] = 'application/json' })
    res.send(json.encode(data))
end

if KEY ~= '' then
    SetHttpHandler(function(req, res)
        local action = (req.path or ''):match('^/api/([%w%.]+)$')
        if req.method ~= 'POST' or not action then return reply(res, 404, { ok = false, error = 'not found' }) end
        local ip = tostring(req.address or ''):gsub(':%d+$', '')
        if next(ALLOW) and not ALLOW[ip] then return reply(res, 403, { ok = false, error = 'forbidden' }) end
        if not sameKey(header(req, 'x-mdc-key'), KEY) then return reply(res, 401, { ok = false, error = 'unauthorized' }) end
        req.setDataHandler(function(raw)
            local ok, body = pcall(json.decode, raw or '')
            if not ok or type(body) ~= 'table' then return reply(res, 400, { ok = false, error = 'JSON invalide' }) end
            local fn = ACTIONS[action]
            if not fn then return reply(res, 404, { ok = false, error = 'action inconnue' }) end
            if not MDCDB.ready then return reply(res, 503, { ok = false, error = 'MDC en cours de chargement' }) end
            local okRun, result = pcall(fn, body, actorOf(body))
            if not okRun then
                print(('^1[MDC] API dispatch "%s" : %s^0'):format(action, tostring(result)))
                return reply(res, 500, { ok = false, error = 'Erreur serveur FiveM.' })
            end
            reply(res, 200, result or { ok = true })
        end)
    end)
    print(('^5[MDC]^0 API du MDC Web active (%s).'):format(URL ~= '' and ('événements vers ' .. URL) or 'mdc_web_url absent : aucun événement envoyé'))
else
    print('^3[MDC] MDC Web désactivé : ajoutez « set mdc_web_key » (et mdc_web_url) dans server.cfg pour le relier.^0')
end
