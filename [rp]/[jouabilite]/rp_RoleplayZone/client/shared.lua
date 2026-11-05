--[[
    RP RoleplayZone - client : outils partagés
    ------------------------------------------
    Demandes au serveur, notifications, droits (policier / civil), lieu lisible (rues d'Atlanta du MDC), aide en
    haut à gauche, et le CERCLE QUI ÉPOUSE LE TERRAIN (comme l'indicateur de lancer de grenade de PUBG) : chaque
    point du cercle est posé sur ce qui se trouve dessous (sol, trottoir, mur, toit, objet), puis le cercle est
    dessiné comme une bande blanche lumineuse (DrawPoly) avec un halo. Utilisé par le mode sélection, l'œil
    d'aigle (onde radar, périmètres en surbrillance) et l'aperçu des scènes.
]]

RZ = RZ or {}
local Config = SceneConfig

-- =========================================================================
-- DEMANDES AU SERVEUR
-- =========================================================================
local pending, nextId = {}, 0

function RZ.request(action, data, cb)
    nextId = nextId + 1
    pending[nextId] = cb
    TriggerServerEvent('rp_scene:request', nextId, action, data or {})
end

RegisterNetEvent('rp_scene:response', function(id, result)
    local cb = pending[id]
    pending[id] = nil
    if cb then cb(result or {}) end
end)

--- Herse de Riven (riven_spikes) en main ou son cordon tenu : ses touches (E, G, X, Q, molette) ont la priorité
local SPIKE_MODES = { holding = true, cord = true, throwing = true, busy = true }
function RZ.spikesBusy()
    if LocalPlayer.state.rivenSpikeHand ~= nil then return true end
    if GetResourceState('riven_spikes') ~= 'started' then return false end
    local ok, mode = pcall(function() return exports.riven_spikes:getMode() end)
    return ok and SPIKE_MODES[mode] == true
end

function RZ.notify(text)
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started'
        and pcall(function() exports[chat]:addPrivate({ title = 'Scène', text = text }) end) then
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('rp_scene:notify', function(text) RZ.notify(text) end)

-- =========================================================================
-- DROITS (le serveur vérifie de son côté)
-- =========================================================================
function RZ.isPolice()
    local unit = LocalPlayer.state.mdcUnit
    return unit ~= nil and unit ~= false and unit ~= ''
end

--- Fouilles, zones et œil d'aigle : policiers en service (ou tout le monde selon Config.Searchers)
function RZ.isSearcher()
    return Config.Searchers == 'everyone' or RZ.isPolice()
end

--- Mode civil de rp_interact (Menu F1 > Civil) ; sans rp_interact : considéré comme civil
function RZ.civilMode()
    if GetResourceState('rp_interact') ~= 'started' then return true end
    return LocalPlayer.state.rpiCivilMode == true
end

--- Lieu lisible (noms du MDC si présent : rues d'Atlanta ; sinon ceux du jeu)
function RZ.locationText(p)
    local mdc = GlobalState.mdcResource
    if mdc and GetResourceState(mdc) == 'started' then
        local ok, text = pcall(function() return exports[mdc]:GetLocationText(vector3(p.x, p.y, p.z)) end)
        if ok and type(text) == 'string' and text ~= '' then return text end
    end
    return GetStreetNameFromHashKey((GetStreetNameAtCoord(p.x, p.y, p.z)))
end

function RZ.dist2D(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

function RZ.camDirection()
    local rot = GetGameplayCamRot(2)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vector3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

--- Direction d'une rotation de caméra (degrés)
function RZ.rotDirection(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vector3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

--- Ce que vise la caméra jusqu'à range m : point, entité (flags : 1 monde, 16 objets, 2 véhicules…) ;
--- origin / dir : une autre caméra (caméra libre de la sélection)
function RZ.aim(range, flags, origin, dir)
    local cam = origin or GetGameplayCamCoord()
    local to = cam + (dir or RZ.camDirection()) * range
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, flags or -1, PlayerPedId(), 7)
    local _, hit, coords, _, entity = GetShapeTestResult(ray)
    if hit ~= 1 and hit ~= true then return nil end
    return coords, entity
end

-- =========================================================================
-- AIDE EN HAUT À GAUCHE (morceaux de moins de 99 caractères : CELL_EMAIL_BCON)
-- =========================================================================
function RZ.help(lines)
    local parts, current = {}, ''
    for i, l in ipairs(lines) do
        local piece = (i > 1 and '~n~' or '') .. l
        if #current + #piece > 90 and current ~= '' then parts[#parts + 1] = current; current = '' end
        current = current .. piece
    end
    if current ~= '' then parts[#parts + 1] = current end
    BeginTextCommandDisplayHelp('CELL_EMAIL_BCON')
    for _, part in ipairs(parts) do AddTextComponentSubstringPlayerName(part) end
    EndTextCommandDisplayHelp(0, false, false, -1)
end

--- Échap : le menu pause du jeu ne s'ouvre pas tant que la touche n'est pas relâchée
function RZ.blockPause(stillOpen)
    CreateThread(function()
        local untilTime, extra = GetGameTimer() + 3000, 10
        while extra > 0 and GetGameTimer() < untilTime and not (stillOpen and stillOpen()) do
            for _, c in ipairs({ 199, 200, 322 }) do DisableControlAction(0, c, true) end
            if IsPauseMenuActive() then SetPauseMenuActive(false) end
            if not (IsDisabledControlPressed(0, 200) or IsDisabledControlPressed(0, 322)) then extra = extra - 1 end
            Wait(0)
        end
    end)
end

-- =========================================================================
-- CERCLE QUI ÉPOUSE LE TERRAIN
-- =========================================================================
local SURFACE_FLAGS = 1 + 16 -- monde (sols, murs, toits) + objets

--- Hauteur de ce qui se trouve sous (x, y), en partant de zRef + up vers le bas
local function surfaceZ(x, y, zRef, up, down, ignore)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(x, y, zRef + up, x, y, zRef - down, SURFACE_FLAGS, ignore or 0, 7)
    local _, hit, coords = GetShapeTestResult(ray)
    if hit == 1 or hit == true then return coords.z end
    return nil
end
RZ.surfaceZ = surfaceZ

--- Points du cercle (centre c, rayon r) posés sur le terrain ; n points
function RZ.ringPoints(c, r, n, opts)
    opts = opts or {}
    local up = opts.up or math.max(2.5, math.min(8.0, r * 0.35))
    local down = opts.down or (up + 6.0)
    local pts, last = {}, c.z
    local ignore = opts.ignore or PlayerPedId()
    for i = 0, n - 1 do
        local a = (i / n) * math.pi * 2
        local dx, dy = math.cos(a), math.sin(a)
        local x, y = c.x + dx * r, c.y + dy * r
        local z = surfaceZ(x, y, c.z, up, down, ignore)
        if not z then z = last end
        last = z
        pts[#pts + 1] = { x = x, y = y, z = z, dx = dx, dy = dy }
    end
    return pts
end

--- Nombre de points selon le rayon (cercles précis, sans excès)
function RZ.ringCount(r, max)
    return math.floor(math.max(20, math.min(max or 96, r * 5.0)))
end

local function quad(a, b, c, d, r, g, bl, al)
    -- deux triangles, dans les deux sens (visible de dessus comme de dessous)
    DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, r, g, bl, al)
    DrawPoly(c.x, c.y, c.z, b.x, b.y, b.z, a.x, a.y, a.z, r, g, bl, al)
    DrawPoly(a.x, a.y, a.z, c.x, c.y, c.z, d.x, d.y, d.z, r, g, bl, al)
    DrawPoly(d.x, d.y, d.z, c.x, c.y, c.z, a.x, a.y, a.z, r, g, bl, al)
end

--- Dessine le cercle (points de RZ.ringPoints) : bande lumineuse de largeur band, halo plus large et transparent
--- color = { r, g, b }, alpha 0-255
function RZ.drawRing(pts, band, color, alpha, glow)
    local n = #pts
    if n < 2 then return end
    local r, g, b = color[1], color[2], color[3]
    local half = band / 2
    local haloHalf = band * 2.2
    local haloAlpha = math.floor(alpha * 0.28)
    for i = 1, n do
        local p, q = pts[i], pts[i % n + 1]
        local zp, zq = p.z + 0.04, q.z + 0.04
        local pi = { x = p.x - p.dx * half, y = p.y - p.dy * half, z = zp }
        local po = { x = p.x + p.dx * half, y = p.y + p.dy * half, z = zp }
        local qi = { x = q.x - q.dx * half, y = q.y - q.dy * half, z = zq }
        local qo = { x = q.x + q.dx * half, y = q.y + q.dy * half, z = zq }
        quad(pi, po, qo, qi, r, g, b, alpha)
        if glow ~= false then
            local hpi = { x = p.x - p.dx * haloHalf, y = p.y - p.dy * haloHalf, z = zp + 0.01 }
            local hpo = { x = p.x + p.dx * haloHalf, y = p.y + p.dy * haloHalf, z = zp + 0.01 }
            local hqi = { x = q.x - q.dx * haloHalf, y = q.y - q.dy * haloHalf, z = zq + 0.01 }
            local hqo = { x = q.x + q.dx * haloHalf, y = q.y + q.dy * haloHalf, z = zq + 0.01 }
            quad(hpi, hpo, hqo, hqi, r, g, b, haloAlpha)
        end
        DrawLine(po.x, po.y, po.z + 0.02, qo.x, qo.y, qo.z + 0.02, r, g, b, math.min(255, alpha + 40))
    end
end

--- Point central lumineux (repère de la sélection)
function RZ.drawCenter(c, color, alpha, size)
    size = size or 0.35
    DrawMarker(28, c.x, c.y, c.z + 0.05, 0, 0, 0, 0, 0, 0, size, size, size, color[1], color[2], color[3], alpha,
        false, false, 2, false, nil, nil, false)
end

--- Dimensions d'un modèle : rayon horizontal (cercle sous l'objet)
function RZ.modelRadius(model)
    local min, max = GetModelDimensions(model)
    local sx, sy = max.x - min.x, max.y - min.y
    return math.max(0.4, math.min(6.0, math.sqrt(sx * sx + sy * sy) / 2 + 0.25))
end

function RZ.vec(p) return { x = p.x + 0.0, y = p.y + 0.0, z = p.z + 0.0 } end

--- Scènes publiées (GlobalState.rpScenes)
function RZ.scenes()
    local list = GlobalState.rpScenes
    return type(list) == 'table' and list or {}
end

--- Boîte filaire autour d'une entité (ses dimensions), couleur { r, g, b }
local EDGES = { { 1, 2 }, { 2, 4 }, { 4, 3 }, { 3, 1 }, { 5, 6 }, { 6, 8 }, { 8, 7 }, { 7, 5 }, { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 } }
function RZ.drawBox(entity, color, alpha)
    local min, max = GetModelDimensions(GetEntityModel(entity))
    local corners = {}
    for _, z in ipairs({ min.z, max.z }) do
        for _, y in ipairs({ min.y, max.y }) do
            for _, x in ipairs({ min.x, max.x }) do
                corners[#corners + 1] = GetOffsetFromEntityInWorldCoords(entity, x, y, z)
            end
        end
    end
    for _, e in ipairs(EDGES) do
        local a, b = corners[e[1]], corners[e[2]]
        DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, color[1], color[2], color[3], alpha or 230)
    end
end
