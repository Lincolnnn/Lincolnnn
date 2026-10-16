--[[
    RP TrafficControl - client : outil de pose
    -------------------------------------------
    Visée au sol (caméra, jusqu'à Editor.Range m), ACCROCHÉE au milieu de la route la plus proche (Ctrl gauche
    maintenu : pose libre). Aperçu en direct :
      - route barrée : rectangle du tronçon (début, fin, largeur ; largeur de départ = celle de la route visée) ;
      - limitation / arrêt : cercle de la zone (rayon, vitesse) ;
      - NŒUDS DE CIRCULATION du jeu autour de la visée : vert = ouvert, orange = sera fermé par ce tronçon,
        rouge = déjà fermé. Après la pose, les nœuds passent au rouge : on voit tout de suite la déviation.
    Touches : E valider, molette largeur / rayon, ← → vitesse, Retour arrière / clic droit / Échap annuler.
    Performance : boucle à chaque image SEULEMENT pendant la pose ; nœuds relus toutes les 400 ms.
]]

TC = TC or {}
local Config = TrafficConfig
local E = Config.Editor or {}
local C = Config.Closure or {}
local S = Config.Speed or {}

local editing = nil -- { kind, step, a, width, radius, speed, duration }

local DISABLED = { 14, 15, 16, 17, 24, 25, 36, 37, 44, 45, 140, 141, 142, 199, 200, 257, 263, 264, 322, 99, 100, 115, 116 }
local KEY_CONFIRM, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT = 38, 15, 14, 174, 175
local CANCEL = { 177, 194, 202, 25 } -- Retour arrière, clic droit
local PAUSE = { 200, 322 }           -- Échap

-- =========================================================================
-- VISÉE ET ACCROCHE À LA ROUTE
-- =========================================================================
local function camDirection()
    local rot = GetGameplayCamRot(2)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vector3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

--- Point visé au sol (décor), nil si rien
local function aimedGround()
    local cam = GetGameplayCamCoord()
    local to = cam + camDirection() * (E.Range or 150.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1, PlayerPedId(), 7)
    local _, hit, coords = GetShapeTestResult(ray)
    if hit ~= 1 then return nil end
    return coords
end

--- Accroche au milieu de la route : projection sur le tronçon de route le plus proche (deux nœuds du jeu) ;
--- renvoie le point et la largeur de la route (voies), ou nil (pas de route assez près)
local function snapToRoad(p)
    local ok, n1, n2, lanes1, lanes2, median = GetClosestRoad(p.x, p.y, p.z, 1.0, 1, false)
    if not ok or not n1 or not n2 then return nil end
    local dx, dy = n2.x - n1.x, n2.y - n1.y
    local len2 = dx * dx + dy * dy
    if len2 < 0.01 then return nil end
    local t = math.max(0.0, math.min(1.0, ((p.x - n1.x) * dx + (p.y - n1.y) * dy) / len2))
    local q = vector3(n1.x + dx * t, n1.y + dy * t, p.z)
    local ex, ey = p.x - q.x, p.y - q.y
    if math.sqrt(ex * ex + ey * ey) > (E.SnapDistance or 12.0) then return nil end
    local lanes = (tonumber(lanes1) or 0) + (tonumber(lanes2) or 0)
    local width = lanes > 0 and lanes * (C.LaneWidth or 3.8) + (tonumber(median) or 0.0) or nil
    return q, width
end

local function cursor()
    local p = aimedGround()
    if not p then return nil end
    if E.Snap ~= false and not IsDisabledControlPressed(0, 36) then
        local q, width = snapToRoad(p)
        if q then return q, width, true end
    end
    return p, nil, false
end

-- =========================================================================
-- APERÇU
-- =========================================================================
local nodes, nodesAt = {}, 0

--- Nœuds de circulation autour de la visée (fermés compris)
local function readNodes(p)
    nodes = {}
    for n = 1, (E.NodeCount or 60) do
        local id = GetNthClosestVehicleNodeId(p.x, p.y, p.z, n, 1, 300.0, 300.0) -- 1 : nœuds fermés compris
        if id and id ~= 0 and IsVehicleNodeIdValid(id) then
            local pos = GetVehicleNodePosition(id)
            local dx, dy = pos.x - p.x, pos.y - p.y
            if math.sqrt(dx * dx + dy * dy) > 90.0 then break end
            nodes[#nodes + 1] = { pos = pos, off = GetVehicleNodeIsSwitchedOff(id) }
        end
    end
end

local function line(a, b, r, g, bl)
    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, r, g, bl, 230)
end

--- Rectangle du tronçon (et diagonales : « route barrée »)
local function drawClosure(a, b, width, r, g, bl)
    local dx, dy = b.x - a.x, b.y - a.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.1 then return end
    local px, py = -dy / length * width / 2, dx / length * width / 2
    local lift = 0.35
    local c1 = vector3(a.x + px, a.y + py, a.z + lift)
    local c2 = vector3(a.x - px, a.y - py, a.z + lift)
    local c3 = vector3(b.x - px, b.y - py, b.z + lift)
    local c4 = vector3(b.x + px, b.y + py, b.z + lift)
    line(c1, c2, r, g, bl); line(c2, c3, r, g, bl); line(c3, c4, r, g, bl); line(c4, c1, r, g, bl)
    line(c1, c3, r, g, bl); line(c2, c4, r, g, bl)
end

local function inPreview(pos)
    if not editing or editing.kind ~= 'close' or not editing.a or not editing.b then return false end
    local m = { a = editing.a, b = editing.b, width = editing.width }
    local u, v, length = TC.closureLocal(m, pos.x, pos.y)
    return u >= 0 and u <= length and math.abs(v) <= editing.width / 2
end

local function drawNodes()
    if E.NodePreview == false then return end
    for _, node in ipairs(nodes) do
        local r, g, b = 60, 220, 110       -- ouvert
        if node.off then r, g, b = 235, 60, 60 -- fermé
        elseif inPreview(node.pos) then r, g, b = 255, 150, 40 end -- sera fermé
        DrawMarker(28, node.pos.x, node.pos.y, node.pos.z + 0.6, 0, 0, 0, 0, 0, 0, 0.45, 0.45, 0.45, r, g, b, 200,
            false, false, 2, false, nil, nil, false)
    end
end

--- Mesures déjà posées (pour se repérer)
local function drawExisting(p)
    for _, m in ipairs(TC.measures or {}) do
        if m.kind == 'close' and m.a then
            local dx, dy = m.a.x - p.x, m.a.y - p.y
            if math.sqrt(dx * dx + dy * dy) < 250.0 then drawClosure(m.a, m.b, m.width, 235, 60, 60) end
        elseif m.center then
            local dx, dy = m.center.x - p.x, m.center.y - p.y
            if math.sqrt(dx * dx + dy * dy) < 250.0 then
                local col = m.kind == 'stop' and { 200, 30, 30 } or { 255, 150, 40 }
                DrawMarker(1, m.center.x, m.center.y, m.center.z - 1.0, 0, 0, 0, 0, 0, 0, m.radius * 2, m.radius * 2, 2.0,
                    col[1], col[2], col[3], 45, false, false, 2, false, nil, nil, false)
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

local function helpLines(snapped)
    local free = ('~INPUT_DUCK~ maintenu : %s'):format(snapped and 'pose libre' or 'accroche à la route')
    if editing.kind == 'close' then
        return {
            ('~INPUT_CONTEXT~ %s du tronçon'):format(editing.a and 'Fin' or 'Début'),
            ('~INPUT_WEAPON_WHEEL_NEXT~ Largeur : %d m'):format(math.floor(editing.width + 0.5)),
            free, '~INPUT_FRONTEND_CANCEL~ Annuler',
        }
    end
    local lines = {
        '~INPUT_CONTEXT~ Poser la zone',
        ('~INPUT_WEAPON_WHEEL_NEXT~ Rayon : %d m'):format(math.floor(editing.radius + 0.5)),
    }
    if editing.kind == 'speed' then lines[#lines + 1] = ('~INPUT_CELLPHONE_LEFT~ ~INPUT_CELLPHONE_RIGHT~ %d MPH'):format(editing.speed) end
    lines[#lines + 1] = free
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
    if message then TC.notify(message) end
end

local function submit(payload)
    TC.request('create', payload, function(res)
        if not res.ok then return TC.notify(res.error or 'Action impossible.') end
        TC.notify(('Mesure posée (%s).'):format(payload.label ~= '' and payload.label or 'n°' .. tostring(res.id)))
    end)
end

local function confirm(p)
    if editing.kind == 'close' then
        if not editing.a then
            editing.a = p
            return
        end
        local dx, dy = p.x - editing.a.x, p.y - editing.a.y
        local length = math.sqrt(dx * dx + dy * dy)
        if length < (C.MinLength or 6.0) then return TC.notify('Tronçon trop court.') end
        if length > (C.MaxLength or 250.0) then return TC.notify(('Tronçon trop long (%d m au plus).'):format(C.MaxLength or 250)) end
        local mid = vector3((editing.a.x + p.x) / 2, (editing.a.y + p.y) / 2, (editing.a.z + p.z) / 2)
        local payload = { kind = 'close', a = { x = editing.a.x, y = editing.a.y, z = editing.a.z }, b = { x = p.x, y = p.y, z = p.z },
            width = editing.width, duration = editing.duration, label = TC.locationText(mid) }
        stop()
        return submit(payload)
    end
    local payload = { kind = editing.kind, center = { x = p.x, y = p.y, z = p.z }, radius = editing.radius,
        speed = editing.speed, duration = editing.duration, label = TC.locationText(p) }
    stop()
    submit(payload)
end

--- Démarre la pose : kind = 'close' | 'speed' | 'stop' ; opts = { duration, speed }
function TC.startEditor(kind, opts)
    if editing then return end
    opts = type(opts) == 'table' and opts or {}
    editing = {
        kind = kind, duration = tonumber(opts.duration) or Config.DefaultDuration or 30,
        width = C.DefaultWidth or 14.0, autoWidth = C.AutoWidth ~= false,
        radius = S.DefaultRadius or 40.0,
        speed = math.floor(tonumber(opts.speed) or S.DefaultLimit or 25),
    }
    CreateThread(function()
        while editing do
            for _, c in ipairs(DISABLED) do DisableControlAction(0, c, true) end
            local p, roadWidth, snapped = cursor()
            local now = GetGameTimer()
            local probe = p or GetEntityCoords(PlayerPedId())
            if now - nodesAt > 400 then nodesAt = now; readNodes(probe) end
            drawExisting(probe)
            drawNodes()

            -- Réglages
            local step = (IsDisabledControlJustPressed(0, KEY_UP) and 1) or (IsDisabledControlJustPressed(0, KEY_DOWN) and -1) or 0
            if step ~= 0 then
                if editing.kind == 'close' then
                    editing.autoWidth = false
                    editing.width = math.max(C.MinWidth or 4.0, math.min(C.MaxWidth or 40.0, editing.width + step * (C.WidthStep or 1.0)))
                else
                    editing.radius = math.max(S.MinRadius or 10.0, math.min(S.MaxRadius or 200.0, editing.radius + step * (S.RadiusStep or 5.0)))
                end
            end
            if editing.kind == 'speed' then
                local dir = (IsDisabledControlJustPressed(0, KEY_RIGHT) and 1) or (IsDisabledControlJustPressed(0, KEY_LEFT) and -1) or 0
                if dir ~= 0 then
                    editing.speed = math.max(S.MinLimit or 5, math.min(S.MaxLimit or 80, editing.speed + dir * (S.Step or 5)))
                end
            end
            -- Largeur automatique (celle de la route visée) tant qu'elle n'a pas été réglée à la main
            if editing.kind == 'close' and editing.autoWidth and roadWidth then
                editing.width = math.max(C.MinWidth or 4.0, math.min(C.MaxWidth or 40.0, roadWidth))
            end

            if p then
                if editing.kind == 'close' then
                    DrawMarker(1, p.x, p.y, p.z - 0.2, 0, 0, 0, 0, 0, 0, 0.8, 0.8, 1.6, 235, 60, 60, 180, false, false, 2, false, nil, nil, false)
                    if editing.a then
                        editing.b = p
                        DrawMarker(1, editing.a.x, editing.a.y, editing.a.z - 0.2, 0, 0, 0, 0, 0, 0, 0.8, 0.8, 1.6, 235, 60, 60, 180, false, false, 2, false, nil, nil, false)
                        drawClosure(editing.a, p, editing.width, 255, 150, 40)
                    else
                        -- avant le début : largeur visible en travers de la route
                        drawClosure(vector3(p.x - 0.2, p.y, p.z), vector3(p.x + 0.2, p.y, p.z), editing.width, 255, 150, 40)
                    end
                else
                    local col = editing.kind == 'stop' and { 200, 30, 30 } or { 255, 150, 40 }
                    DrawMarker(1, p.x, p.y, p.z - 1.0, 0, 0, 0, 0, 0, 0, editing.radius * 2, editing.radius * 2, 2.5,
                        col[1], col[2], col[3], 70, false, false, 2, false, nil, nil, false)
                end
            end
            if not IsPauseMenuActive() then help(helpLines(snapped)) end

            if IsDisabledControlJustPressed(0, KEY_CONFIRM) and p then
                confirm(p)
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
