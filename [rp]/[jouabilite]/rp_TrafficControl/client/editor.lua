--[[
    RP TrafficControl - client : choix de la ZONE du trafic, puis de l'action
    -------------------------------------------------------------------------
    1. ZONE : on choisit les nœuds du trafic concernés. On vise la route (caméra, jusqu'à Editor.Range m). Le script lit la route du jeu à cet endroit : ligne de nœuds,
    nombre de voies dans chaque sens, terre-plein. L'endroit visé choisit le SENS (côté de la route visé) et la VOIE
    (la plus proche du point visé) ; la portée se change ensuite :
      - VOIE : une voie de ce sens (ex. la voie de gauche d'une interstate), molette pour changer de voie ;
      - SENS : toutes les voies de ce sens ;
      - ROUTE : les deux sens (molette : largeur).
    E au début de la zone, E à la fin (dans un sens ou dans l'autre : le début est toujours là où arrive le trafic).
    2. ACTION : la zone reste affichée dans le monde et le panneau (menu.lua) propose l'action sur ce trafic :
       fermeture de voie (le trafic se réoriente vers une autre voie), ralentissement, arrêt du trafic ; puis la durée.
       « Appliquer » envoie la mesure ; « Rechoisir la zone » revient à l'étape 1 ; Échap / « Annuler » abandonne.
    Aperçu : bande concernée (bleue pendant le choix ; couleur de l'action choisie ensuite) avec une flèche du sens,
    et les NŒUDS du jeu :
      vert = ouvert ; orange = concerné (sera fermé / ralenti) ; jaune = partagé avec l'autre sens (les PNJ sont
      dirigés à la place) ; rouge = déjà fermé.
    VUES (choisie dans le menu, V pour changer pendant le choix) :
      - joueur : la vue du jeu (le personnage se déplace normalement) ;
      - dessus : caméra à 50 m au-dessus du joueur, regard vers le sol (ZQSD / WASD : glisser, souris : tourner,
        Espace / Ctrl : monter / descendre, Maj : plus vite) ;
      - libre : caméra libre comme /scene et /freecam (souris : regarder, ZQSD / WASD, Espace / Ctrl, Maj) ;
      dessus et libre restent à moins de 100 m du joueur (Editor.CameraRange) ; le personnage ne bouge pas.
    Les VOIES de la route visée sont REMPLIES au sol (cases transparentes) : bleu la zone choisie, vert les autres
    voies du même sens (orange une fois la fermeture choisie : elles ralentiront à 20 MPH), gris l'autre sens.
    Touches : E valider, ↑ ↓ portée, molette voie / largeur, R inverser le sens, V vue, Retour arrière / clic droit /
    Échap annuler. Boucle à chaque image SEULEMENT pendant le choix ; nœuds relus toutes les 400 ms.
]]

TC = TC or {}
local Config = TrafficConfig
local E = Config.Editor or {}
local SEG = Config.Segment or {}
local SP = Config.Speed or {}
local LW = SEG.LaneWidth or 5.4
-- Largeur des voies (Maj + ← →) gardée d'une pose à l'autre ; décalage latéral (← →) remis à zéro à chaque pose
local calib = { lw = LW }
local function laneW() return calib.lw end

local editing = nil

local DISABLED = { 0, 14, 15, 16, 17, 24, 25, 37, 44, 45, 140, 141, 142, 172, 173, 174, 175, 199, 200, 257, 263, 264, 322, 99, 100, 115, 116 }
local KEY = { confirm = 38, wheelUp = 15, wheelDown = 14, up = 172, down = 173, left = 174, right = 175, flip = 45 }
local CANCEL = { 177, 194, 202, 25 } -- Retour arrière, clic droit
local PAUSE = { 200, 322 }           -- Échap
local SCOPES = { 'lane', 'direction', 'road' }
local SCOPE_LABEL = { lane = 'Voie', direction = 'Sens', road = 'Route entière' }
local COLORS = { close = { 235, 60, 60 }, slow = { 255, 150, 40 }, stop = { 200, 30, 30 }, zone = { 70, 150, 255 } }

-- =========================================================================
-- VISÉE ET LECTURE DE LA ROUTE
-- =========================================================================
local function camDirection()
    local rot = GetGameplayCamRot(2)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vector3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

-- =========================================================================
-- VUES : joueur (vue du jeu), dessus (50 m au-dessus du joueur), libre (comme /scene et /freecam)
-- =========================================================================
local VIEWS = { 'player', 'top', 'free' }
local VIEW_LABEL = { player = 'Vue du joueur', top = 'Vue du dessus', free = 'Vue libre' }
local FREE_BLOCKED = { 1, 2, 21, 22, 30, 31, 32, 33, 34, 35, 36, 44, 0, 26, 79 }
local view = { mode = 'player' } -- + cam, pos, rot (dessus / libre)

local function rotDirection(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vector3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

local function stopView()
    if view.cam then
        RenderScriptCams(false, true, 300, true, true)
        DestroyCam(view.cam, false)
        ClearFocus()
    end
    view = { mode = 'player' }
end

local function setView(mode)
    stopView()
    if mode ~= 'top' and mode ~= 'free' then return end
    local ped = PlayerPedId()
    local me = GetEntityCoords(ped)
    local grot = GetGameplayCamRot(2)
    local pos, rot
    if mode == 'top' then
        pos = vector3(me.x, me.y, me.z + (E.TopHeight or 50.0))
        rot = vector3(-89.0, 0.0, grot.z)
    else
        pos, rot = GetGameplayCamCoord(), vector3(grot.x, 0.0, grot.z)
    end
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, pos.x, pos.y, pos.z)
    SetCamRot(cam, rot.x, 0.0, rot.z, 2)
    SetCamFov(cam, mode == 'top' and (E.TopFov or 60.0) or GetGameplayCamFov())
    RenderScriptCams(true, true, 350, true, true)
    view = { mode = mode, cam = cam, pos = pos, rot = rot }
end

--- Caméra du dessus / libre : déplacement (une image) ; reste à moins de CameraRange m du joueur
local function updateView(dt)
    if not view.cam then return end
    for _, c in ipairs(FREE_BLOCKED) do DisableControlAction(0, c, true) end
    local lookX, lookY = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
    local rz = (view.rot.z - lookX * 8.0) % 360.0
    local rx = view.mode == 'top' and -89.0 or math.max(-85.0, math.min(85.0, view.rot.x - lookY * 8.0))
    view.rot = vector3(rx, 0.0, rz)
    local forward = view.mode == 'top' and vector3(-math.sin(math.rad(rz)), math.cos(math.rad(rz)), 0.0) or rotDirection(view.rot)
    local right = vector3(math.cos(math.rad(rz)), math.sin(math.rad(rz)), 0.0)
    local move = vector3(0.0, 0.0, 0.0)
    if IsDisabledControlPressed(0, 32) then move = move + forward end
    if IsDisabledControlPressed(0, 33) then move = move - forward end
    if IsDisabledControlPressed(0, 35) then move = move + right end
    if IsDisabledControlPressed(0, 34) then move = move - right end
    if IsDisabledControlPressed(0, 22) then move = move + vector3(0.0, 0.0, 1.0) end
    if IsDisabledControlPressed(0, 36) then move = move - vector3(0.0, 0.0, 1.0) end
    local speed = (view.mode == 'top' and (E.TopSpeed or 18.0) or (E.FreeSpeed or 8.0)) * (IsDisabledControlPressed(0, 21) and 3.0 or 1.0)
    local pos = view.pos + move * (speed * dt)
    local me = GetEntityCoords(PlayerPedId())
    local max = E.CameraRange or 100.0
    local dx, dy = pos.x - me.x, pos.y - me.y
    local flat = math.sqrt(dx * dx + dy * dy)
    if flat > max then pos = vector3(me.x + dx / flat * max, me.y + dy / flat * max, pos.z) end
    if view.mode == 'top' then
        pos = vector3(pos.x, pos.y, math.max(me.z + (E.TopMin or 15.0), math.min(me.z + (E.TopMax or 120.0), pos.z)))
    elseif pos.z > me.z + max then
        pos = vector3(pos.x, pos.y, me.z + max)
    end
    view.pos = pos
    SetCamCoord(view.cam, pos.x, pos.y, pos.z)
    SetCamRot(view.cam, rx, 0.0, rz, 2)
    SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0) -- le monde se charge autour de la caméra
end

--- Petite croix au centre de l'écran (vues dessus / libre : c'est elle qui vise)
local function crosshair()
    DrawRect(0.5, 0.5, 0.012, 0.0022, 255, 255, 255, 220)
    DrawRect(0.5, 0.5, 0.0012, 0.02, 255, 255, 255, 220)
end

local function aimedGround()
    local cam, dir, range
    if view.cam then
        cam, dir = view.pos, rotDirection(view.rot)
        range = math.max(E.Range or 150.0, (view.pos.z - GetEntityCoords(PlayerPedId()).z) + 60.0)
    else
        cam, dir, range = GetGameplayCamCoord(), camDirection(), E.Range or 150.0
    end
    local to = cam + dir * range
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
    if math.abs(vL) > (E.SnapDistance or 14.0) + 3 * laneW() then return nil end
    return { c = c, lx = lx, ly = ly, vL = vL, l1 = math.floor(tonumber(l1) or 0), l2 = math.floor(tonumber(l2) or 0),
        median = tonumber(median) or 0.0 }
end

-- =========================================================================
-- SENS DE CIRCULATION d'une chaussée à sens unique (autoroute) : +1 = sens de la liaison n1 -> n2, -1 = l'inverse.
-- Sources, dans l'ordre (Editor.DirectionOrder) : le TRAFIC observé (véhicules en mouvement sur cette chaussée, autour
-- du point visé), le CAP du nœud du jeu (celui qui sert à faire apparaître les voitures dans le bon sens), les VOIES
-- du jeu (nombre de voies « avant / arrière » ; convention inversable : Editor.SwapOneWayLanes). R inverse à la main.
-- =========================================================================
local DIR_SOURCE = { traffic = 'trafic observé', node = 'nœud du jeu', lanes = 'voies du jeu', manual = 'inversé à la main' }
local dirCache = { key = nil, at = 0 }

local function oneWaySign(r)
    local key = ('%d:%d:%d'):format(math.floor(r.c.x / 8), math.floor(r.c.y / 8), math.floor(math.deg(math.atan(r.ly, r.lx)) / 10))
    local now = GetGameTimer()
    if dirCache.key == key and now - dirCache.at < 800 then return dirCache.sign, dirCache.source end
    local sign, source
    for _, method in ipairs(E.DirectionOrder or { 'traffic', 'node', 'lanes' }) do
        if method == 'traffic' then
            local vote, range = 0, E.TrafficVoteRange or 60.0
            local half = math.max(r.l1, r.l2, 1) * laneW() / 2 + 2.0
            for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                if IsEntityVisible(vehicle) then -- (pas nos faux obstacles)
                    local p = GetEntityCoords(vehicle)
                    local dx, dy = p.x - r.c.x, p.y - r.c.y
                    if math.abs(dx * r.lx + dy * r.ly) < range and math.abs(dx * r.ly - dy * r.lx) < half and math.abs(p.z - r.c.z) < 6.0 then
                        local vel = GetEntityVelocity(vehicle)
                        if vel.x * vel.x + vel.y * vel.y > 6.0 then -- > 2,5 m/s
                            vote = vote + ((vel.x * r.lx + vel.y * r.ly) > 0 and 1 or -1)
                        end
                    end
                end
            end
            if vote ~= 0 then sign, source = vote > 0 and 1 or -1, 'traffic' end
        elseif method == 'node' then
            local ok, _, heading = GetClosestVehicleNodeWithHeading(r.c.x, r.c.y, r.c.z, 1, 3.0, 0)
            if ok and heading then
                local hx, hy = -math.sin(math.rad(heading)), math.cos(math.rad(heading))
                sign, source = (hx * r.lx + hy * r.ly) >= 0 and 1 or -1, 'node'
                if E.SwapNodeHeading then sign = -sign end
            end
        elseif method == 'lanes' then
            sign, source = (r.l1 > 0 or r.l2 == 0) and 1 or -1, 'lanes'
            if E.SwapOneWayLanes then sign = -sign end
        end
        if sign then break end
    end
    sign = sign or 1
    dirCache = { key = key, at = now, sign = sign, source = source or 'lanes' }
    return sign, dirCache.source
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
        -- chaussée à sens unique (ex. un sens d'une autoroute) : sens détecté (trafic, nœud, voies), R l'inverse
        local sgn, source = oneWaySign(r)
        if flip then sgn, source = -sgn, 'manual' end
        s.dx, s.dy, s.n = r.lx * sgn, r.ly * sgn, math.max(r.l1, r.l2, 1)
        s.nOpp, s.source = 0, source
    end
    if twoWay then s.source = flip and 'manual' or 'side' end
    local vD = (r.vL) * ((s.dx * r.lx + s.dy * r.ly) > 0 and 1 or -1)
    -- Voies (à droite du sens D : +), décalées de `shift` (← → : aligner la bande sur les voies peintes)
    local lw, shift = laneW(), editing and editing.shift or 0.0
    s.lw = lw
    s.offsets, s.opp = {}, {}
    for i = 1, s.n do
        s.offsets[i] = shift + (twoWay and (s.median / 2 + (i - 0.5) * lw) or ((i - (s.n + 1) / 2) * lw))
    end
    for i = 1, s.nOpp do s.opp[i] = shift - (s.median / 2 + (i - 0.5) * lw) end
    local best, bestDist = 1, math.huge
    for i, off in ipairs(s.offsets) do
        local d = math.abs(off - vD)
        if d < bestDist then best, bestDist = i, d end
    end
    s.baseLane, s.lane = best, best
    return s
end


--- Voie choisie : voie visée + décalage à la molette
local function applyLane(s)
    if not s then return end
    -- après le début de la zone, la voie visée reste celle du début (même si on décale la bande)
    if editing.a and editing.lockBase then s.baseLane = math.min(editing.lockBase, s.n) end
    s.lane = math.max(1, math.min(s.n, s.baseLane + (editing.laneDelta or 0)))
end

--- Bande concernée (à droite du sens D : + ; - à gauche), selon la portée
local function strip(s, scope, extra)
    local half = s.lw / 2
    if scope == 'lane' then
        local off = s.offsets[s.lane]
        return off - half, off + half
    end
    local lo, hi = math.huge, -math.huge
    for _, off in ipairs(s.offsets) do lo, hi = math.min(lo, off), math.max(hi, off) end
    if scope == 'road' then
        for _, off in ipairs(s.opp) do lo = math.min(lo, off) end
    end
    local vmin, vmax = lo - half, hi + half
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
    -- nœud d'une chaussée à sens unique DANS la bande : c'est la chaussée de ce sens (l'autre chaussée est à côté,
    -- hors de la bande) ; le sens se lit ainsi sans dépendre de la convention des voies du jeu
    local same = t.oneWay
    if editing.scope == 'direction' and same then return 'take' end
    if editing.scope == 'lane' and same and editing.setup.n == 1 then return 'take' end -- seule voie de ce sens
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
    -- FLÈCHES DU SENS DE CIRCULATION : pleines, d'une autre couleur (Editor.ArrowColor), tout le long de la zone
    local ac = E.ArrowColor or { 255, 220, 0 }
    local alpha = E.ArrowAlpha or 235
    local mid = (seg.vmin + seg.vmax) / 2
    local half = math.min(1.6, math.max(0.6, (seg.vmax - seg.vmin) * 0.32))
    local len = E.ArrowLength or 2.8
    local spacing = math.max(4.0, E.ArrowSpacing or 9.0)
    local count = math.max(1, math.floor(f.length / spacing))
    for i = 1, count do
        local u = f.length * (i - 0.5) / count
        local zc = z1 + (z2 - z1) * (u / f.length) + 0.1
        local tip = TC.worldAt(f, u + len / 2, mid, zc)
        local l = TC.worldAt(f, u - len / 2, mid - half, zc)
        local r = TC.worldAt(f, u - len / 2, mid + half, zc)
        local back = TC.worldAt(f, u - len / 4, mid, zc)
        -- pointe de flèche (deux triangles, visibles des deux côtés)
        for _, tri in ipairs({ { tip, l, back }, { tip, back, r } }) do
            local p1, p2, p3 = tri[1], tri[2], tri[3]
            DrawPoly(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, p3.x, p3.y, p3.z, ac[1], ac[2], ac[3], alpha)
            DrawPoly(p3.x, p3.y, p3.z, p2.x, p2.y, p2.z, p1.x, p1.y, p1.z, ac[1], ac[2], ac[3], alpha)
        end
        line(l, tip, ac); line(r, tip, ac)
    end
end

--- Case remplie au sol (transparente, visible de dessus comme de dessous) entre u0..u1 et v0..v1 du repère f
local function cell(f, u0, u1, v0, v1, z0, z1, c, alpha)
    local p1, p2 = TC.worldAt(f, u0, v0, z0), TC.worldAt(f, u0, v1, z0)
    local p3, p4 = TC.worldAt(f, u1, v1, z1), TC.worldAt(f, u1, v0, z1)
    DrawPoly(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, p3.x, p3.y, p3.z, c[1], c[2], c[3], alpha)
    DrawPoly(p1.x, p1.y, p1.z, p3.x, p3.y, p3.z, p4.x, p4.y, p4.z, c[1], c[2], c[3], alpha)
    DrawPoly(p3.x, p3.y, p3.z, p2.x, p2.y, p2.z, p1.x, p1.y, p1.z, c[1], c[2], c[3], alpha)
    DrawPoly(p4.x, p4.y, p4.z, p3.x, p3.y, p3.z, p1.x, p1.y, p1.z, c[1], c[2], c[3], alpha)
end

local CELL = { side = { 70, 210, 120 }, sideSlow = { 255, 150, 40 }, opposite = { 200, 200, 210 } }

--- Voies de la route REMPLIES : la zone (couleur de la zone / de l'action), les autres voies du même sens (vert ;
--- orange pour une fermeture de voie : elles ralentiront), l'autre sens (gris)
local function drawCells(seg, s, scope, kind)
    if E.FillLanes == false or not seg or not s then return end
    local f, z0, z1 = seg.f, seg.a.z + 0.3, seg.b.z + 0.3
    local main = COLORS[kind] or COLORS.zone
    local half = s.lw / 2
    for i, off in ipairs(s.offsets) do
        local chosen = scope ~= 'lane' or i == s.lane
        if chosen then
            cell(f, 0, f.length, off - half, off + half, z0, z1, main, 85)
        else
            cell(f, 0, f.length, off - half, off + half, z0, z1, (kind == 'close' and scope == 'lane') and CELL.sideSlow or CELL.side, 45)
        end
    end
    for _, off in ipairs(s.opp or {}) do
        cell(f, 0, f.length, off - half, off + half, z0, z1, scope == 'road' and main or CELL.opposite, scope == 'road' and 85 or 30)
    end
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
-- AIDE EN HAUT À GAUCHE : petit panneau de l'interface (NUI, sans curseur), PAS l'aide du jeu. Envoyé seulement quand
-- il change. (L'aide du jeu, trop longue en plusieurs morceaux, sortait coupée et gênait celle des autres scripts.)
-- =========================================================================
local lastHint = nil
local function hint(data)
    local key = data and (data.title or '') or ''
    if data then for _, row in ipairs(data.rows) do key = key .. '|' .. table.concat(row.keys, '+') .. ':' .. row.text end end
    if data == nil then key = nil end
    if key == lastHint then return end
    lastHint = key
    SendNUIMessage({ action = 'hint', data = data or { hidden = true } })
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

local function fmt(m) return (('%+.2f'):format(m)):gsub('%.', ',') end

--- Lignes de l'aide : { keys = { touches }, text }
local function hintData(s)
    local rows = {
        { keys = { 'E' }, text = editing.a and 'Fin de la zone du trafic' or 'Début de la zone du trafic' },
        { keys = { '↑', '↓' }, text = 'Portée : voie, sens ou route entière' },
    }
    if editing.scope == 'lane' and s and s.n > 1 then rows[#rows + 1] = { keys = { 'Molette' }, text = 'Changer de voie' } end
    if editing.scope == 'road' then rows[#rows + 1] = { keys = { 'Molette' }, text = ('Élargir : +%d m'):format(math.floor(editing.extra + 0.5)) } end
    rows[#rows + 1] = { keys = { '←', '→' }, text = ('Aligner sur les voies peintes (%s m)'):format(fmt(editing.shift or 0)) }
    rows[#rows + 1] = { keys = { 'Maj', '←', '→' }, text = ('Largeur des voies : %s m'):format((('%.1f'):format(laneW())):gsub('%.', ',')) }
    if s then
        rows[#rows + 1] = { keys = { 'R' }, text = s.twoWay and 'Inverser le sens (l\'autre côté de la route)'
            or ('Inverser le sens (sens détecté : %s)'):format(DIR_SOURCE[s.source] or DIR_SOURCE.lanes) }
    end
    rows[#rows + 1] = { keys = { 'V' }, text = VIEW_LABEL[view.mode] or VIEW_LABEL.player }
    if view.mode == 'top' then rows[#rows + 1] = { keys = { 'ZQSD', 'Souris' }, text = 'Glisser, tourner ; Espace / Ctrl : hauteur' }
    elseif view.mode == 'free' then rows[#rows + 1] = { keys = { 'ZQSD', 'Souris' }, text = 'Se déplacer ; Espace / Ctrl ; Maj : vite' } end
    rows[#rows + 1] = { keys = { 'Échap' }, text = 'Annuler' }
    return { title = scopeText(s), rows = rows }
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
    stopView()
    hint(nil)
    nodes = {}
    nodeCache = {}
    if message then TC.notify(message) end
end

local function vec(p) return { x = p.x + 0.0, y = p.y + 0.0, z = p.z + 0.0 } end

--- Voie vers laquelle le trafic se réoriente (fermeture d'une voie) : la plus proche du même sens ; nil s'il n'y en a pas
local function redirectLane(s)
    local best, bestDist
    for i, off in ipairs(s.offsets) do
        if i ~= s.lane then
            local d = math.abs(off - s.offsets[s.lane])
            if not best or d < bestDist then best, bestDist = i, d end
        end
    end
    return best
end

--- Zone choisie : figée (toujours affichée dans le monde) et proposée au panneau des actions (menu.lua)
local function choose(seg)
    local s = editing.setup
    local list = {}
    for _, node in ipairs(nodes) do
        if nodeState(node, seg) == 'take' then list[#list + 1] = vec(node.pos) end
    end
    -- Nœuds du trafic de CE SENS dans la zone et EN AMONT (Speed.Upstream m avant) : ralentissement progressif (zones
    -- de vitesse du jeu, pour tous les PNJ), u = distance le long de la zone (négative en amont). Chaussée à sens
    -- unique (autoroute) : ses nœuds ; route entière : aussi l'autre sens et les nœuds partagés. Une route à double
    -- sens (nœuds partagés) ne peut pas être ralentie dans un seul sens par les nœuds : PNJ dirigés seulement.
    local upstream = SP.Upstream or 120.0
    readNodes(TC.worldAt(seg.f, seg.f.length / 2, 0, seg.a.z), seg.f.length / 2 + upstream + 10.0)
    local dirNodes = {}
    local dmin, dmax = strip(s, editing.scope == 'road' and 'road' or 'direction', editing.extra)
    local zMid, L = (seg.a.z + seg.b.z) / 2, seg.f.length
    for _, node in ipairs(nodes) do
        if not node.off and math.abs(node.pos.z - zMid) <= (SEG.Height or 4.0) + 6 then
            local u, v = TC.localUV(seg.f, node.pos.x, node.pos.y)
            if v >= dmin - 2 and v <= dmax + 2 then
                local t = nodeTraffic(node.id, node.pos)
                local du = nil
                if t.oneWay and (editing.scope ~= 'road' or not s.twoWay) then
                    du = u                                         -- chaussée de ce sens (dans la bande)
                elseif editing.scope == 'road' and not t.oneWay then
                    du = u < 0 and u or (u > L and (L - u) or 0.0) -- partagé : amont des deux côtés
                end
                if du and du >= -upstream and du <= L + 5 then
                    local p = vec(node.pos)
                    p.u = math.floor(du * 10 + 0.5) / 10
                    dirNodes[#dirNodes + 1] = p
                end
            end
        end
    end
    local label = TC.locationText(TC.worldAt(seg.f, seg.f.length / 2, 0, (seg.a.z + seg.b.z) / 2))
    editing.phase, editing.seg = 'chosen', seg
    editing.zone = {
        scope = editing.scope, a = vec(seg.a), b = vec(seg.b),
        vmin = seg.vmin, vmax = seg.vmax, lanes = s.offsets, closedLane = s.offsets[s.lane],
        laneIndex = s.lane, laneCount = s.n, oppositeLanes = s.nOpp, median = s.median, laneWidth = s.lw,
        compass = TC.compass(s.dx, s.dy), nodes = list, dirNodes = dirNodes, label = label,
    }
    local redirect = editing.scope == 'lane' and redirectLane(s) or nil
    local info = {
        scope = editing.scope, label = label, compass = editing.zone.compass, length = math.floor(seg.f.length + 0.5),
        nodes = #list, laneIndex = s.lane, laneCount = s.n, oppositeLanes = s.nOpp,
        redirect = redirect and TC.laneName(redirect, s.n) or nil, redirectIndex = redirect,
        sideSlow = (editing.scope == 'lane' and s.n > 1) and ((Config.Closure or {}).SideSlow or 20) or 0,
        dirNodes = #dirNodes,
        scopeText = scopeText(s),
    }
    if TC.onZoneChosen then TC.onZoneChosen(info) end
end

--- Couleur de la zone dans le monde selon l'action surlignée dans le panneau (nil : bleu du choix de zone)
function TC.zonePreview(kind)
    if editing and editing.phase == 'chosen' then editing.previewKind = COLORS[kind] and kind or nil end
end

--- Action choisie pour la zone : 'close' | 'slow' | 'stop' ; mesure envoyée au serveur
function TC.applyZone(kind, speed, duration)
    if not editing or editing.phase ~= 'chosen' or not editing.zone then return false end
    if kind ~= 'close' and kind ~= 'slow' and kind ~= 'stop' then return false end
    local payload = {}
    for key, value in pairs(editing.zone) do payload[key] = value end
    payload.kind = kind
    payload.speed = math.floor(tonumber(speed) or editing.speed or SP.DefaultLimit or 25)
    payload.duration = tonumber(duration) or editing.duration
    stop()
    TC.request('create', payload, function(res)
        if not res.ok then return TC.notify(res.error or 'Action impossible.') end
        local done = kind == 'close' and 'fermés' or (kind == 'slow' and 'ralentis' or 'arrêtés')
        TC.notify(('Mesure posée : %s (%d nœud%s du trafic %s).'):format(payload.label ~= '' and payload.label or 'n°' .. tostring(res.id),
            #payload.nodes, #payload.nodes > 1 and 's' or '', done))
    end)
    return true
end

--- Retour au choix de la zone (même portée)
function TC.reselectZone()
    if not editing then return end
    editing.phase, editing.a, editing.b, editing.seg, editing.zone, editing.previewKind = 'pick', nil, nil, nil, nil, nil
    editing.road = nil
    editing.laneDelta = 0
end

function TC.cancelZone()
    if editing then stop('Choix de la zone annulé.') end
end

local function confirm(cur, r)
    if not editing.a then
        if not r then return TC.notify('Visez une route.') end
        editing.a, editing.road = r.c, r
        editing.setup = setupFrom(r, editing.flip)
        editing.lockBase = editing.setup.baseLane
        return
    end
    local b = r and r.c or cur
    local dx, dy = b.x - editing.a.x, b.y - editing.a.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < (SEG.MinLength or 6.0) then return TC.notify('Zone trop courte.') end
    if length > (SEG.MaxLength or 200.0) then return TC.notify(('Zone trop longue (%d m au plus) : faites-en plusieurs.'):format(SEG.MaxLength or 200)) end
    editing.b = b
    local seg = currentSegment(b)
    if seg then choose(seg) end
end

--- Démarre le choix de la zone du trafic : opts = { scope, duration, speed } (l'action est choisie après la zone)
function TC.startEditor(opts)
    if editing then return end
    opts = type(opts) == 'table' and opts or {}
    editing = {
        phase = 'pick', scope = (opts.scope == 'direction' or opts.scope == 'road') and opts.scope or 'lane',
        viewMode = (opts.view == 'top' or opts.view == 'free') and opts.view or 'player',
        duration = tonumber(opts.duration) or Config.DefaultDuration or 30,
        speed = math.floor(tonumber(opts.speed) or SP.DefaultLimit or 25), extra = 0.0, flip = false, laneDelta = 0,
        shift = 0.0,
    }
    setView(editing.viewMode)
    CreateThread(function()
        local last = GetGameTimer()
        while editing do
            if editing.phase == 'chosen' then
                -- Zone choisie : affichée (bande + nœuds) pendant que le panneau propose l'action
                hint(nil)
                local seg = editing.seg
                local probe = TC.worldAt(seg.f, seg.f.length / 2, 0, seg.a.z)
                local now = GetGameTimer()
                if now - nodesAt > 400 then
                    nodesAt = now
                    readNodes(probe, seg.f.length / 2 + 70.0)
                end
                drawExisting(probe)
                drawCells(seg, editing.setup, editing.scope, editing.previewKind)
                drawNodes(seg)
                local kind = editing.previewKind
                drawStrip(seg, COLORS[kind] or COLORS.zone, kind == 'close')
                Wait(0)
                goto continue
            end
            for _, c in ipairs(DISABLED) do DisableControlAction(0, c, true) end
            local tnow = GetGameTimer()
            updateView(math.min(0.1, (tnow - last) / 1000.0))
            last = tnow
            if IsDisabledControlJustPressed(0, 0) then -- V : vue suivante
                local idx = 1
                for i, v in ipairs(VIEWS) do if v == view.mode then idx = i end end
                editing.viewMode = VIEWS[idx % #VIEWS + 1]
                setView(editing.viewMode)
            end
            local cur = aimedGround()
            local r = cur and roadAt(cur) or nil
            -- Voies recalculées à chaque image (alignement ← →, largeur Maj + ← →) ; après le début : route du début
            if editing.a then editing.setup = setupFrom(editing.road, editing.flip)
            else editing.setup = r and setupFrom(r, editing.flip) or nil end
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
            if IsDisabledControlJustPressed(0, KEY.flip) and editing.setup then -- R : inverser le sens (toute route)
                editing.flip = not editing.flip
                editing.lockBase = nil
                editing.shift = -(editing.shift or 0) -- même place dans le monde (le sens s'inverse)
                if editing.a then editing.setup = setupFrom(editing.road, editing.flip); applyLane(editing.setup) end
            end
            -- ← → : décaler la bande (aligner sur les voies peintes) ; Maj + ← → : largeur des voies
            local nudge = (IsDisabledControlJustPressed(0, KEY.right) and 1) or (IsDisabledControlJustPressed(0, KEY.left) and -1) or 0
            if nudge ~= 0 then
                if IsDisabledControlPressed(0, 21) then
                    calib.lw = math.max(SEG.MinLaneWidth or 2.5, math.min(SEG.MaxLaneWidth or 7.0, calib.lw + nudge * 0.1))
                else
                    editing.shift = math.max(-(SEG.MaxShift or 8.0), math.min(SEG.MaxShift or 8.0, (editing.shift or 0) + nudge * 0.25))
                end
                local base = editing.a and editing.road or r
                if base then editing.setup = setupFrom(base, editing.flip); applyLane(editing.setup) end
            end

            -- Aperçu
            local seg = currentSegment(r and r.c or cur)
            local probe = seg and TC.worldAt(seg.f, seg.f.length / 2, 0, seg.a.z) or cur or GetEntityCoords(PlayerPedId())
            if now - nodesAt > 400 then
                nodesAt = now
                readNodes(probe, seg and (seg.f.length / 2 + 70.0) or 80.0)
            end
            drawExisting(probe)
            drawCells(seg, editing.setup, editing.scope, nil)
            drawNodes(seg)
            if view.cam then crosshair() end
            if seg then drawStrip(seg, COLORS.zone, false) end
            if cur and not r then
                DrawMarker(1, cur.x, cur.y, cur.z - 0.2, 0, 0, 0, 0, 0, 0, 0.6, 0.6, 1.2, 150, 150, 150, 160, false, false, 2, false, nil, nil, false)
            end
            hint(not IsPauseMenuActive() and hintData(editing.setup) or nil)

            if IsDisabledControlJustPressed(0, KEY.confirm) and cur then
                confirm(cur, r)
            else
                -- Échap d'abord (le menu pause du jeu ne s'ouvre pas), puis Retour arrière / clic droit
                for _, c in ipairs(PAUSE) do
                    if IsDisabledControlJustPressed(0, c) then stop('Choix de la zone annulé.'); blockPauseAfter() break end
                end
                if editing then
                    for _, c in ipairs(CANCEL) do
                        if IsDisabledControlJustPressed(0, c) then stop('Choix de la zone annulé.') break end
                    end
                end
            end
            Wait(0)
            ::continue::
        end
    end)
end

function TC.editing() return editing ~= nil end
function TC.zoneChosen() return editing ~= nil and editing.phase == 'chosen' end
