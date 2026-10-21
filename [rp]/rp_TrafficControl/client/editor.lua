--[[
    RP TrafficControl - client : outil de pose d'un tronçon
    -------------------------------------------------------
    On vise la route (caméra, jusqu'à Editor.Range m). Le script lit la route du jeu à cet endroit : ligne de nœuds,
    nombre de voies dans chaque sens, terre-plein. L'endroit visé choisit le SENS (côté de la route visé) et la VOIE
    (la plus proche du point visé) ; la portée se change ensuite :
      - VOIE : une voie de ce sens (ex. la voie de gauche d'une interstate), molette pour changer de voie ;
      - SENS : toutes les voies de ce sens ;
      - ROUTE : les deux sens (molette : largeur).
    E au début du tronçon, E à la fin (dans un sens ou dans l'autre : le début est toujours là où arrive le trafic).
    Aperçu : bande concernée (couleur de la mesure) avec une flèche du sens, et les NŒUDS du jeu :
      vert = ouvert ; orange = concerné (sera fermé / ralenti) ; jaune = partagé avec l'autre sens (les PNJ sont
      dirigés à la place) ; rouge = déjà fermé.
    Touches : E valider, ↑ ↓ portée, molette voie / largeur, ← → vitesse, R inverser le sens, Retour arrière /
    clic droit / Échap annuler. Boucle à chaque image SEULEMENT pendant la pose ; nœuds relus toutes les 400 ms.
]]

TC = TC or {}
local Config = TrafficConfig
local E = Config.Editor or {}
local SEG = Config.Segment or {}
local SP = Config.Speed or {}
local LW = SEG.LaneWidth or 5.4

local editing = nil

local DISABLED = { 14, 15, 16, 17, 24, 25, 37, 44, 45, 140, 141, 142, 172, 173, 174, 175, 199, 200, 257, 263, 264, 322, 99, 100, 115, 116 }
local KEY = { confirm = 38, wheelUp = 15, wheelDown = 14, up = 172, down = 173, left = 174, right = 175, flip = 45 }
local CANCEL = { 177, 194, 202, 25 } -- Retour arrière, clic droit
local PAUSE = { 200, 322 }           -- Échap
local SCOPES = { 'lane', 'direction', 'road' }
local SCOPE_LABEL = { lane = 'Voie', direction = 'Sens', road = 'Route entière' }
local COLORS = { close = { 235, 60, 60 }, slow = { 255, 150, 40 }, stop = { 200, 30, 30 } }

-- =========================================================================
-- VISÉE ET LECTURE DE LA ROUTE
-- =========================================================================
local function camDirection()
    local rot = GetGameplayCamRot(2)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vector3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

local function aimedGround()
    local cam = GetGameplayCamCoord()
    local to = cam + camDirection() * (E.Range or 150.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1, PlayerPedId(), 7)
    local _, hit, coords = GetShapeTestResult(ray)
    if hit ~= 1 then return nil end
    return coords
end

--- Route du jeu au point p : centre (sur la ligne de nœuds), direction de la liaison, côté visé, voies, terre-plein
local function roadAt(p)
    local ok, n1, n2, l1, l2, median = GetClosestRoad(p.x, p.y, p.z, 1.0, 1, false)
    if not ok or not n1 or not n2 then return nil end
    local dx, dy = n2.x - n1.x, n2.y - n1.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return nil end
    local lx, ly = dx / len, dy / len
    local t = math.max(0.0, math.min(1.0, ((p.x - n1.x) * dx + (p.y - n1.y) * dy) / (len * len)))
    local c = vector3(n1.x + dx * t, n1.y + dy * t, n1.z + (n2.z - n1.z) * t)
    local vL = (p.x - c.x) * ly + (p.y - c.y) * -lx -- + à droite de la liaison
    if math.abs(vL) > (E.SnapDistance or 14.0) + 3 * LW then return nil end
    return { c = c, lx = lx, ly = ly, vL = vL, l1 = math.floor(tonumber(l1) or 0), l2 = math.floor(tonumber(l2) or 0),
        median = tonumber(median) or 0.0 }
end

--- Sens et voies depuis le côté visé : D (sens de circulation), n (voies dans ce sens), nOpp (voies en face),
--- décalages des voies (à droite de D ; 1 = voie de gauche), voie visée
local function setupFrom(r, flip)
    local twoWay = r.l1 > 0 and r.l2 > 0
    local s = { twoWay = twoWay, median = twoWay and r.median or 0.0 }
    local side = flip and -r.vL or r.vL
    if twoWay then
        if side >= 0 then s.dx, s.dy, s.n, s.nOpp = r.lx, r.ly, r.l1, r.l2
        else s.dx, s.dy, s.n, s.nOpp = -r.lx, -r.ly, r.l2, r.l1 end
    else
        -- chaussée à sens unique (ex. un sens d'une autoroute) : le sens est celui de la liaison
        if r.l1 > 0 or r.l2 == 0 then s.dx, s.dy, s.n = r.lx, r.ly, math.max(r.l1, 1)
        else s.dx, s.dy, s.n = -r.lx, -r.ly, r.l2 end
        s.nOpp = 0
    end
    local vD = (r.vL) * ((s.dx * r.lx + s.dy * r.ly) > 0 and 1 or -1)
    s.offsets = {}
    for i = 1, s.n do
        s.offsets[i] = twoWay and (s.median / 2 + (i - 0.5) * LW) or ((i - (s.n + 1) / 2) * LW)
    end
    local best, bestDist = 1, math.huge
    for i, off in ipairs(s.offsets) do
        local d = math.abs(off - vD)
        if d < bestDist then best, bestDist = i, d end
    end
    s.baseLane, s.lane = best, best
    return s
end

--- Autre sens d'une route à double sens (même endroit)
local function flipSetup(s)
    if not s.twoWay then return s end
    local f = { twoWay = true, median = s.median, dx = -s.dx, dy = -s.dy, n = s.nOpp, nOpp = s.n, offsets = {} }
    for i = 1, f.n do f.offsets[i] = f.median / 2 + (i - 0.5) * LW end
    f.baseLane = math.min(s.baseLane, f.n)
    f.lane = f.baseLane
    return f
end

--- Voie choisie : voie visée + décalage à la molette
local function applyLane(s)
    if s then s.lane = math.max(1, math.min(s.n, s.baseLane + (editing.laneDelta or 0))) end
end

--- Bande concernée (à droite du sens D : + ; - à gauche), selon la portée
local function strip(s, scope, extra)
    if scope == 'lane' then
        local off = s.offsets[s.lane]
        return off - LW / 2, off + LW / 2
    end
    local vmin, vmax
    if s.twoWay then
        vmin, vmax = s.median / 2, s.median / 2 + s.n * LW
        if scope == 'road' then vmin = -(s.median / 2 + s.nOpp * LW) end
    else
        vmin, vmax = -s.n * LW / 2, s.n * LW / 2
    end
    if scope == 'road' and (extra or 0) > 0 then vmin, vmax = vmin - extra / 2, vmax + extra / 2 end
    return vmin, vmax
end

-- =========================================================================
-- NŒUDS CONCERNÉS
-- =========================================================================
local nodeCache = {} -- [id] = { oneWay, tx, ty }

--- Sens de circulation d'un nœud : chaussée à sens unique (et son sens) ou partagée par les deux sens
local function nodeTraffic(id, pos)
    local c = nodeCache[id]
    if c then return c end
    local ok, n1, n2, l1, l2 = GetClosestRoad(pos.x, pos.y, pos.z, 1.0, 1, false)
    c = { oneWay = false, tx = 0, ty = 0 }
    if ok and n1 and n2 then
        l1, l2 = tonumber(l1) or 0, tonumber(l2) or 0
        local dx, dy = n2.x - n1.x, n2.y - n1.y
        local len = math.max(math.sqrt(dx * dx + dy * dy), 0.01)
        if (l1 > 0) ~= (l2 > 0) then
            local sgn = l1 > 0 and 1 or -1
            c = { oneWay = true, tx = dx / len * sgn, ty = dy / len * sgn }
        end
    end
    nodeCache[id] = c
    return c
end

local nodes, nodesAt = {}, 0

--- Nœuds autour du point p (fermés compris), avec leur état pour la mesure en cours
local function readNodes(p, radius)
    nodes = {}
    for n = 1, (E.NodeCount or 80) do
        local id = GetNthClosestVehicleNodeId(p.x, p.y, p.z, n, 1, 300.0, 300.0) -- 1 : nœuds fermés compris
        if id and id ~= 0 and IsVehicleNodeIdValid(id) then
            local pos = GetVehicleNodePosition(id)
            local dx, dy = pos.x - p.x, pos.y - p.y
            if math.sqrt(dx * dx + dy * dy) > radius then break end
            nodes[#nodes + 1] = { id = id, pos = pos, off = GetVehicleNodeIsSwitchedOff(id) }
        end
    end
end

--- Tronçon en cours (début / fin dans le sens du trafic) : { a, b, f, vmin, vmax }
local function currentSegment(cur)
    local s = editing.setup
    if not s then return nil end
    local a, b
    if editing.a then
        a, b = editing.a, editing.b or cur
        if not b then return nil end
        if (b.x - a.x) * s.dx + (b.y - a.y) * s.dy < 0 then a, b = b, a end -- début = là où arrive le trafic
    elseif cur then
        a = vector3(cur.x - s.dx * 4, cur.y - s.dy * 4, cur.z)
        b = vector3(cur.x + s.dx * 4, cur.y + s.dy * 4, cur.z)
    else
        return nil
    end
    local f = TC.frame({ a = a, b = b })
    if not f then return nil end
    local vmin, vmax = strip(s, editing.scope, editing.extra)
    return { a = a, b = b, f = f, vmin = vmin, vmax = vmax }
end

--- État d'un nœud pour ce tronçon : 'off' (déjà fermé), 'take' (concerné), 'shared' (partagé, PNJ dirigés), nil
local function nodeState(node, seg)
    if node.off then return 'off' end
    if not seg then return nil end
    local u, v = TC.localUV(seg.f, node.pos.x, node.pos.y)
    local margin = SEG.NodeMargin or 1.5
    if u < -1 or u > seg.f.length + 1 or v < seg.vmin - margin or v > seg.vmax + margin then return nil end
    if math.abs(node.pos.z - (seg.a.z + seg.b.z) / 2) > (SEG.Height or 4.0) + 6 then return nil end
    if editing.scope == 'road' then return 'take' end
    local t = nodeTraffic(node.id, node.pos)
    local s = editing.setup
    local same = t.oneWay and (t.tx * s.dx + t.ty * s.dy) > 0.5
    if editing.scope == 'direction' and same then return 'take' end
    if editing.scope == 'lane' and same and s.n == 1 then return 'take' end -- seule voie de ce sens
    return 'shared'
end

-- =========================================================================
-- APERÇU
-- =========================================================================
local function line(a, b, c)
    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, c[1], c[2], c[3], 230)
end

local function drawStrip(seg, color, cross)
    local f, z1, z2 = seg.f, seg.a.z + 0.35, seg.b.z + 0.35
    local c1 = TC.worldAt(f, 0, seg.vmin, z1)
    local c2 = TC.worldAt(f, 0, seg.vmax, z1)
    local c3 = TC.worldAt(f, f.length, seg.vmax, z2)
    local c4 = TC.worldAt(f, f.length, seg.vmin, z2)
    line(c1, c2, color); line(c2, c3, color); line(c3, c4, color); line(c4, c1, color)
    if cross then line(c1, c3, color); line(c2, c4, color) end
    -- flèche du sens de circulation concerné
    local mid, zc = (seg.vmin + seg.vmax) / 2, (z1 + z2) / 2
    local u = f.length / 2
    local tip = TC.worldAt(f, u + 2.0, mid, zc)
    line(TC.worldAt(f, u - 1.0, mid - 1.4, zc), tip, color)
    line(TC.worldAt(f, u - 1.0, mid + 1.4, zc), tip, color)
end

local NODE_COLOR = { off = { 235, 60, 60 }, take = { 255, 150, 40 }, shared = { 245, 215, 60 } }

local function drawNodes(seg)
    if E.NodePreview == false then return end
    for _, node in ipairs(nodes) do
        local c = NODE_COLOR[nodeState(node, seg)] or { 60, 220, 110 }
        DrawMarker(28, node.pos.x, node.pos.y, node.pos.z + 0.6, 0, 0, 0, 0, 0, 0, 0.45, 0.45, 0.45, c[1], c[2], c[3], 200,
            false, false, 2, false, nil, nil, false)
    end
end

--- Mesures déjà posées (pour se repérer)
local function drawExisting(p)
    for _, m in ipairs(TC.measures or {}) do
        local f = m.a and m.b and TC.frame(m)
        if f then
            local dx, dy = m.a.x - p.x, m.a.y - p.y
            if math.sqrt(dx * dx + dy * dy) < 300.0 then
                drawStrip({ a = m.a, b = m.b, f = f, vmin = m.vmin, vmax = m.vmax }, COLORS[m.kind] or COLORS.close, m.kind == 'close')
            end
        end
    end
end

-- =========================================================================
-- AIDE EN HAUT À GAUCHE (morceaux de moins de 99 caractères : CELL_EMAIL_BCON)
-- =========================================================================
local function help(lines)
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

local function scopeText(s)
    if not s then return 'Visez une route' end
    local dir = 'sens ' .. TC.compass(s.dx, s.dy)
    if editing.scope == 'lane' then
        return ('Voie : %s (%d/%d), %s'):format(TC.laneName(s.lane, s.n), s.lane, s.n, dir)
    end
    if editing.scope == 'direction' then return ('Sens : %s (%d voie%s)'):format(dir, s.n, s.n > 1 and 's' or '') end
    return 'Route entière (les deux sens)'
end

local function helpLines(s)
    local lines = {
        ('~INPUT_CONTEXT~ %s du tronçon'):format(editing.a and 'Fin' or 'Début'),
        ('~INPUT_CELLPHONE_UP~~INPUT_CELLPHONE_DOWN~ %s'):format(scopeText(s)),
    }
    if editing.scope == 'lane' and s and s.n > 1 then lines[#lines + 1] = '~INPUT_WEAPON_WHEEL_NEXT~ Changer de voie' end
    if editing.scope == 'road' then lines[#lines + 1] = ('~INPUT_WEAPON_WHEEL_NEXT~ Élargir : +%d m'):format(math.floor(editing.extra + 0.5)) end
    if editing.kind == 'slow' then lines[#lines + 1] = ('~INPUT_CELLPHONE_LEFT~~INPUT_CELLPHONE_RIGHT~ %d MPH'):format(editing.speed) end
    if s and s.twoWay then lines[#lines + 1] = '~INPUT_RELOAD~ Inverser le sens' end
    lines[#lines + 1] = '~INPUT_FRONTEND_CANCEL~ Annuler'
    return lines
end

-- =========================================================================
-- POSE
-- =========================================================================
local function blockPauseAfter()
    CreateThread(function()
        local untilTime, extra = GetGameTimer() + 3000, 10
        while extra > 0 and GetGameTimer() < untilTime do
            for _, c in ipairs({ 199, 200, 322 }) do DisableControlAction(0, c, true) end
            if IsPauseMenuActive() then SetPauseMenuActive(false) end
            if not (IsDisabledControlPressed(0, 200) or IsDisabledControlPressed(0, 322)) then extra = extra - 1 end
            Wait(0)
        end
    end)
end

local function stop(message)
    editing = nil
    nodes = {}
    nodeCache = {}
    if message then TC.notify(message) end
end

local function vec(p) return { x = p.x + 0.0, y = p.y + 0.0, z = p.z + 0.0 } end

local function submit(seg)
    local s = editing.setup
    local list = {}
    for _, node in ipairs(nodes) do
        if nodeState(node, seg) == 'take' then list[#list + 1] = vec(node.pos) end
    end
    local payload = {
        kind = editing.kind, scope = editing.scope, a = vec(seg.a), b = vec(seg.b),
        vmin = seg.vmin, vmax = seg.vmax, lanes = s.offsets, closedLane = s.offsets[s.lane],
        laneIndex = s.lane, laneCount = s.n, oppositeLanes = s.nOpp, median = s.median, laneWidth = LW,
        compass = TC.compass(s.dx, s.dy), nodes = list, speed = editing.speed, duration = editing.duration,
        label = TC.locationText(TC.worldAt(seg.f, seg.f.length / 2, 0, (seg.a.z + seg.b.z) / 2)),
    }
    stop()
    TC.request('create', payload, function(res)
        if not res.ok then return TC.notify(res.error or 'Action impossible.') end
        TC.notify(('Mesure posée : %s (%d nœud%s du jeu %s).'):format(payload.label ~= '' and payload.label or 'n°' .. tostring(res.id),
            #list, #list > 1 and 's' or '', payload.kind == 'close' and 'fermés' or 'ralentis'))
    end)
end

local function confirm(cur, r)
    if not editing.a then
        if not r then return TC.notify('Visez une route.') end
        editing.a = r.c
        editing.setup = setupFrom(r, editing.flip)
        return
    end
    local b = r and r.c or cur
    local dx, dy = b.x - editing.a.x, b.y - editing.a.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < (SEG.MinLength or 6.0) then return TC.notify('Tronçon trop court.') end
    if length > (SEG.MaxLength or 200.0) then return TC.notify(('Tronçon trop long (%d m au plus) : faites-en plusieurs.'):format(SEG.MaxLength or 200)) end
    editing.b = b
    local seg = currentSegment(b)
    if seg then submit(seg) end
end

--- Démarre la pose : kind = 'close' | 'slow' | 'stop' ; opts = { scope, duration, speed }
function TC.startEditor(kind, opts)
    if editing then return end
    opts = type(opts) == 'table' and opts or {}
    editing = {
        kind = kind, scope = (opts.scope == 'direction' or opts.scope == 'road') and opts.scope or 'lane',
        duration = tonumber(opts.duration) or Config.DefaultDuration or 30,
        speed = math.floor(tonumber(opts.speed) or SP.DefaultLimit or 25), extra = 0.0, flip = false, laneDelta = 0,
    }
    CreateThread(function()
        while editing do
            for _, c in ipairs(DISABLED) do DisableControlAction(0, c, true) end
            local cur = aimedGround()
            local r = cur and roadAt(cur) or nil
            if not editing.a then editing.setup = r and setupFrom(r, editing.flip) or nil end
            applyLane(editing.setup)
            local now = GetGameTimer()

            -- Réglages
            if IsDisabledControlJustPressed(0, KEY.up) or IsDisabledControlJustPressed(0, KEY.down) then
                local step = IsDisabledControlJustPressed(0, KEY.up) and -1 or 1
                local idx = 1
                for i, sc in ipairs(SCOPES) do if sc == editing.scope then idx = i end end
                editing.scope = SCOPES[(idx - 1 + step) % #SCOPES + 1]
            end
            local wheel = (IsDisabledControlJustPressed(0, KEY.wheelUp) and 1) or (IsDisabledControlJustPressed(0, KEY.wheelDown) and -1) or 0
            if wheel ~= 0 and editing.setup then
                local s = editing.setup
                if editing.scope == 'lane' then
                    -- molette vers le haut : vers la voie de gauche
                    editing.laneDelta = math.max(-s.baseLane + 1, math.min(s.n - s.baseLane, (editing.laneDelta or 0) - wheel))
                    applyLane(s)
                elseif editing.scope == 'road' then
                    editing.extra = math.max(0.0, math.min((SEG.MaxRoadWidth or 60.0), editing.extra + wheel * 2 * (SEG.RoadWidthStep or 1.0)))
                end
            end
            if editing.kind == 'slow' then
                local dir = (IsDisabledControlJustPressed(0, KEY.right) and 1) or (IsDisabledControlJustPressed(0, KEY.left) and -1) or 0
                if dir ~= 0 then editing.speed = math.max(SP.MinLimit or 5, math.min(SP.MaxLimit or 80, editing.speed + dir * (SP.Step or 5))) end
            end
            if IsDisabledControlJustPressed(0, KEY.flip) and editing.setup and editing.setup.twoWay then
                editing.flip = not editing.flip
                if editing.a then editing.setup = flipSetup(editing.setup); applyLane(editing.setup) end
            end

            -- Aperçu
            local seg = currentSegment(r and r.c or cur)
            local probe = seg and TC.worldAt(seg.f, seg.f.length / 2, 0, seg.a.z) or cur or GetEntityCoords(PlayerPedId())
            if now - nodesAt > 400 then
                nodesAt = now
                readNodes(probe, seg and (seg.f.length / 2 + 40.0) or 80.0)
            end
            drawExisting(probe)
            drawNodes(seg)
            if seg then drawStrip(seg, COLORS[editing.kind] or COLORS.close, editing.kind == 'close') end
            if cur and not r then
                DrawMarker(1, cur.x, cur.y, cur.z - 0.2, 0, 0, 0, 0, 0, 0, 0.6, 0.6, 1.2, 150, 150, 150, 160, false, false, 2, false, nil, nil, false)
            end
            if not IsPauseMenuActive() then help(helpLines(editing.setup)) end

            if IsDisabledControlJustPressed(0, KEY.confirm) and cur then
                confirm(cur, r)
            else
                -- Échap d'abord (le menu pause du jeu ne s'ouvre pas), puis Retour arrière / clic droit
                for _, c in ipairs(PAUSE) do
                    if IsDisabledControlJustPressed(0, c) then stop('Pose annulée.'); blockPauseAfter() break end
                end
                if editing then
                    for _, c in ipairs(CANCEL) do
                        if IsDisabledControlJustPressed(0, c) then stop('Pose annulée.') break end
                    end
                end
            end
            Wait(0)
        end
    end)
end

function TC.editing() return editing ~= nil end
