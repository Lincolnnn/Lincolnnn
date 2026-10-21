--[[
    RP PlateColors - Client : texte des plaques redessiné en couleur
    -----------------------------------------------------------------
    La couleur du texte d'une plaque est un paramètre du shader du jeu (FontColor du carcols.ymt principal), qu'aucun
    script ne peut changer. Le script fait donc autrement :
      1. la police des plaques du jeu (vehshare : vehicle_generic_plate_font) est remplacée par une texture vide :
         le jeu n'écrit plus rien sur les plaques (fond, relief et saleté de la plaque restent ceux du jeu) ;
      2. le texte de chaque plaque proche (GET_VEHICLE_NUMBER_PLATE_TEXT) est redessiné en 3D, collé sur la plaque,
         avec la couleur de son type de plaque (config.lua / éditeur), comme <FontColor> dans un carcols.
    Position de la plaque : réglée par modèle dans l'éditeur (/plaqueedit), sinon trouvée automatiquement (os
    « platelight » = lumière de plaque, dimensions du modèle, rayon contre la carrosserie).

    Performance : recherche des véhicules toutes les 400 ms ; par image, 4 triangles par caractère pour les plaques
    proches, tournées vers la caméra et non cachées (test de visibilité toutes les 250 ms, asynchrone).
]]

local C = PlateConfig
local TXD = 'rp_platecolors'
local CHARS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-.'    -- ordre de l'atlas (outil/police.py)
local COLS, ATLAS, CELL_W, CELL_H = 8, 512, 64, 96
local drawPoly = DrawTexturedPoly or DrawSpritePoly
local rad, cos, sin, sqrt = math.rad, math.cos, math.sin, math.sqrt

-- État partagé avec client/editor.lua
Plates = {
    positions = {},      -- réglages enregistrés par modèle : [tostring(hash)] = { label, rear = {...}|false, front = ... }
    colors = {},         -- couleurs enregistrées par type : [tostring(index)] = { text = {r,g,b}, outline = {r,g,b}|false }
    preview = nil,       -- éditeur : { model, data } placement en cours de réglage
    previewColors = {},  -- éditeur : couleurs en cours de réglage
    editVeh = nil,       -- éditeur : véhicule réglé (dessiné même sans plaque, cadre affiché)
    editSide = nil,
}

-- Coordonnées de chaque caractère dans l'atlas (demi-pixel de marge : pas de bavure de la case voisine)
local UV = {}
for i = 1, #CHARS do
    local k = i - 1
    local col, row = k % COLS, k // COLS
    UV[CHARS:sub(i, i)] = {
        (col * CELL_W + 0.5) / ATLAS, (row * CELL_H + 0.5) / ATLAS,
        ((col + 1) * CELL_W - 0.5) / ATLAS, ((row + 1) * CELL_H - 0.5) / ATLAS,
    }
end

-- =========================================================================
-- TEXTURES : notre police (blanche, teintée au dessin) et police du jeu masquée
-- =========================================================================
CreateThread(function()
    local txd = CreateRuntimeTxd(TXD)
    CreateRuntimeTextureFromImage(txd, 'font', 'assets/plate_font.png')
    CreateRuntimeTextureFromImage(txd, 'outline', 'assets/plate_font_outline.png')
    CreateRuntimeTextureFromImage(txd, 'blank', 'assets/blank_font.png')
    CreateRuntimeTextureFromImage(txd, 'flat_n', 'assets/flat_n.png')
    AddReplaceTexture('vehshare', 'vehicle_generic_plate_font', TXD, 'blank')
    AddReplaceTexture('vehshare', 'vehicle_generic_plate_font_n', TXD, 'flat_n')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    RemoveReplaceTexture('vehshare', 'vehicle_generic_plate_font')
    RemoveReplaceTexture('vehshare', 'vehicle_generic_plate_font_n')
end)

-- =========================================================================
-- DONNÉES DU SERVEUR (réglages de l'éditeur)
-- =========================================================================
RegisterNetEvent('rp_platecolors:data', function(data)
    Plates.positions = data.positions or {}
    Plates.colors = data.colors or {}
end)

RegisterNetEvent('rp_platecolors:position', function(key, value) Plates.positions[key] = value or nil end)
RegisterNetEvent('rp_platecolors:colors', function(colors) Plates.colors = colors or {} end)

CreateThread(function() TriggerServerEvent('rp_platecolors:request') end)

--- Couleur d'un type de plaque : éditeur en cours > enregistrée > config.lua > Default
function Plates.colorFor(index)
    local key = tostring(index)
    return Plates.previewColors[key] or Plates.colors[key] or C.Plates[index] or C.Default
end

-- =========================================================================
-- PLACEMENT
-- =========================================================================
local Auto, autoBusy = {}, {}

--- Rayon contre CE véhicule uniquement (coordonnées locales) : point de carrosserie touché, ou nil
local function surface(veh, x, y1, y2, z)
    local a = GetOffsetFromEntityInWorldCoords(veh, x, y1, z)
    local b = GetOffsetFromEntityInWorldCoords(veh, x, y2, z)
    local handle = StartShapeTestLosProbe(a.x, a.y, a.z, b.x, b.y, b.z, 2, 0, 7)
    local state, hit, coords, _, ent
    repeat
        Wait(0)
        state, hit, coords, _, ent = GetShapeTestResult(handle)
    until state ~= 1
    if (hit == 1 or hit == true) and ent == veh then
        return GetOffsetFromEntityGivenWorldCoords(veh, coords.x, coords.y, coords.z).y
    end
end

--- Placement estimé pour un modèle jamais réglé (calculé une fois par modèle)
local function computeAuto(veh, model)
    local mn, mx = GetModelDimensions(model)
    local A = C.Auto
    local x, y, z
    local bone = GetEntityBoneIndexByName(veh, 'platelight')
    if bone ~= -1 then
        local w = GetWorldPositionOfEntityBone(veh, bone)
        local l = GetOffsetFromEntityGivenWorldCoords(veh, w.x, w.y, w.z)
        x, y, z = l.x, l.y, l.z - A.BelowLight
    else
        x, z = 0.0, mn.z + (mx.z - mn.z) * A.HeightRatio
        local hit = surface(veh, x, mn.y - 1.0, 0.0, z)
        y = hit and hit + A.Inset or mn.y
    end
    local front = surface(veh, 0.0, mx.y + 1.0, 0.0, z)
    local plateType = GetVehiclePlateType(veh)   -- 0 avant + arrière, 1 avant, 2 arrière, 3 aucune
    return {
        rear = plateType ~= 1 and { x = x, y = y, z = z, pitch = 0.0, yaw = 0.0, scale = 1.0 } or false,
        front = (plateType == 0 or plateType == 1)
            and { x = 0.0, y = front and front - A.Inset or mx.y, z = z, pitch = 0.0, yaw = 0.0, scale = 1.0 } or false,
    }
end

--- Placement en vigueur pour un véhicule (nil : estimation automatique en cours)
function Plates.placementOf(veh, model)
    local p = Plates.preview
    if p and p.model == model then return p.data end
    local saved = Plates.positions[tostring(model)]
    if saved then return saved end
    if Auto[model] then return Auto[model] end
    if not autoBusy[model] then
        autoBusy[model] = true
        CreateThread(function()
            if DoesEntityExist(veh) then Auto[model] = computeAuto(veh, model) end
            autoBusy[model] = nil
        end)
    end
end

function Plates.autoOf(model) return Auto[model] end

--- Repère de la plaque en coordonnées locales : centre, droite du lecteur, haut, normale (sortante)
local function localFrame(side, p)
    local ny = side == 'rear' and -1.0 or 1.0
    local rx = side == 'rear' and 1.0 or -1.0
    local cy, sy = cos(rad(p.yaw or 0.0)), sin(rad(p.yaw or 0.0))
    local cp, sp = cos(rad(p.pitch or 0.0)), sin(rad(p.pitch or 0.0))
    local nx, nyy, nz = -ny * sy * cp, ny * cy * cp, sp       -- lacet autour de Z puis inclinaison vers le haut
    local r1, r2, r3 = rx * cy, rx * sy, 0.0
    local u1, u2, u3 = nyy * r3 - nz * r2, nz * r1 - nx * r3, nx * r2 - nyy * r1   -- haut = normale x droite
    return nx, nyy, nz, r1, r2, r3, u1, u2, u3
end

--- Repère de la plaque dans le monde (matrice du véhicule fournie : une seule native par véhicule et par image)
function Plates.frame(m, side, p)
    local f, r, u, pos = m[1], m[2], m[3], m[4]
    local nx, ny, nz, r1, r2, r3, u1, u2, u3 = localFrame(side, p)
    local function dir(a, b, c) return r.x * a + f.x * b + u.x * c, r.y * a + f.y * b + u.y * c, r.z * a + f.z * b + u.z * c end
    local cx, cy, cz = dir(p.x, p.y, p.z)
    local Nx, Ny, Nz = dir(nx, ny, nz)
    local Rx, Ry, Rz = dir(r1, r2, r3)
    local Ux, Uy, Uz = dir(u1, u2, u3)
    return pos.x + cx, pos.y + cy, pos.z + cz, Rx, Ry, Rz, Ux, Uy, Uz, Nx, Ny, Nz
end

function Plates.matrix(veh)
    local f, r, u, pos = GetEntityMatrix(veh)
    return { f, r, u, pos }
end

-- =========================================================================
-- RECHERCHE DES PLAQUES PROCHES
-- =========================================================================
local entries = {}        -- plaques à dessiner : { veh, model, text, color, p, sides, hidden }
local brightness = 1.0

local function plateText(veh)
    local text = (GetVehicleNumberPlateText(veh) or ''):upper()
    if #text < 8 then text = text .. string.rep(' ', 8 - #text) end
    return text:sub(1, 8)
end

local function dayBrightness()
    local h = GetClockHours() + GetClockMinutes() / 60
    local night = C.NightBrightness
    if h >= 21 or h < 5 then return night end
    if h < 7 then return night + (1 - night) * (h - 5) / 2 end
    if h >= 19 then return 1 - (1 - night) * (h - 19) / 2 end
    return 1.0
end

local function colorOf(veh, index)
    local override = Entity(veh).state.plateColor
    if type(override) == 'table' and type(override.text) == 'table' then return override end
    return Plates.colorFor(index)
end

CreateThread(function()
    while true do
        local cam = GetFinalRenderedCamCoord()
        local near = {}
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            local d = #(GetEntityCoords(veh) - cam)
            if veh == Plates.editVeh or (d < C.MaxDistance + 4.0 and IsEntityVisible(veh) and GetVehiclePlateType(veh) ~= 3) then
                near[#near + 1] = { veh = veh, d = veh == Plates.editVeh and -1 or d }
            end
        end
        table.sort(near, function(a, b) return a.d < b.d end)

        local list = {}
        for i = 1, math.min(#near, C.MaxPlates) do
            local veh = near[i].veh
            local model = GetEntityModel(veh)
            local p = Plates.placementOf(veh, model)
            if p then
                local old = entries[veh]
                list[veh] = {
                    veh = veh, p = p, text = plateText(veh),
                    color = colorOf(veh, GetVehicleNumberPlateTextIndex(veh)),
                    hidden = old and old.hidden or {},
                }
            end
        end
        entries, brightness = list, dayBrightness()
        Wait(C.ScanInterval)
    end
end)

-- Plaque cachée par un mur, un objet ou un autre véhicule (le véhicule du joueur ne cache rien)
CreateThread(function()
    while true do
        local cam = GetFinalRenderedCamCoord()
        local own = GetVehiclePedIsIn(PlayerPedId(), false)
        local probes = {}
        for veh, e in pairs(entries) do
            if DoesEntityExist(veh) and IsEntityOnScreen(veh) then
                local m = Plates.matrix(veh)
                for _, side in ipairs({ 'rear', 'front' }) do
                    local p = e.p[side]
                    if p then
                        local x, y, z = Plates.frame(m, side, p)
                        probes[#probes + 1] = { e = e, side = side, own = own,
                            h = StartShapeTestLosProbe(cam.x, cam.y, cam.z, x, y, z, 19, veh, 7) }
                    end
                end
            end
        end
        local pending = #probes
        while pending > 0 do
            Wait(0)
            pending = 0
            for _, pr in ipairs(probes) do
                if pr.h then
                    local state, hit, _, _, ent = GetShapeTestResult(pr.h)
                    if state == 1 then
                        pending = pending + 1
                    else
                        pr.e.hidden[pr.side] = (hit == 1 or hit == true) and ent ~= pr.own
                        pr.h = nil
                    end
                end
            end
        end
        Wait(C.OcclusionInterval)
    end
end)

-- =========================================================================
-- DESSIN
-- =========================================================================
local function quad(tex, r, g, b, a, x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4, uv)
    local u0, v0, u1, v1 = uv[1], uv[2], uv[3], uv[4]
    -- coin 1 haut-gauche, 2 haut-droit, 3 bas-droit, 4 bas-gauche ; les deux sens (un seul est visible)
    drawPoly(x1, y1, z1, x4, y4, z4, x3, y3, z3, r, g, b, a, TXD, tex, u0, v0, 1.0, u0, v1, 1.0, u1, v1, 1.0)
    drawPoly(x1, y1, z1, x3, y3, z3, x2, y2, z2, r, g, b, a, TXD, tex, u0, v0, 1.0, u1, v1, 1.0, u1, v0, 1.0)
    drawPoly(x1, y1, z1, x3, y3, z3, x4, y4, z4, r, g, b, a, TXD, tex, u0, v0, 1.0, u1, v1, 1.0, u0, v1, 1.0)
    drawPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, r, g, b, a, TXD, tex, u0, v0, 1.0, u1, v0, 1.0, u1, v1, 1.0)
end

local function drawText(text, tex, rgb, lift, scale, cx, cy, cz, Rx, Ry, Rz, Ux, Uy, Uz, Nx, Ny, Nz)
    local T = C.Text
    local slot = T.Width * scale / 8
    local hw, hh = slot / 2, T.Height * scale / 2
    local up = T.OffsetUp * scale
    local bx, by, bz = cx + Ux * up + Nx * lift, cy + Uy * up + Ny * lift, cz + Uz * up + Nz * lift
    local r, g, b = math.floor(rgb[1] * brightness), math.floor(rgb[2] * brightness), math.floor(rgb[3] * brightness)
    for i = 1, 8 do
        local uv = UV[text:sub(i, i)]
        if uv then
            local o = (i - 4.5) * slot
            local mx, my, mz = bx + Rx * o, by + Ry * o, bz + Rz * o
            local ax, ay, az = Rx * hw, Ry * hw, Rz * hw
            local vx, vy, vz = Ux * hh, Uy * hh, Uz * hh
            quad(tex, r, g, b, 255,
                mx - ax + vx, my - ay + vy, mz - az + vz,
                mx + ax + vx, my + ay + vy, mz + az + vz,
                mx + ax - vx, my + ay - vy, mz + az - vz,
                mx - ax - vx, my - ay - vy, mz - az - vz, uv)
        end
    end
end

--- Cadre de la plaque (éditeur)
local function drawFrame(scale, cx, cy, cz, Rx, Ry, Rz, Ux, Uy, Uz)
    local w, h = C.PlateSize[1] * scale / 2, C.PlateSize[2] * scale / 2
    local pts = {}
    for i, s in ipairs({ { -1, 1 }, { 1, 1 }, { 1, -1 }, { -1, -1 } }) do
        pts[i] = { cx + Rx * w * s[1] + Ux * h * s[2], cy + Ry * w * s[1] + Uy * h * s[2], cz + Rz * w * s[1] + Uz * h * s[2] }
    end
    for i = 1, 4 do
        local a, b = pts[i], pts[i % 4 + 1]
        DrawLine(a[1], a[2], a[3], b[1], b[2], b[3], 110, 168, 255, 255)
    end
end

CreateThread(function()
    local lift = C.Text.Lift
    while true do
        if next(entries) == nil then
            Wait(200)
        else
            local cam = GetFinalRenderedCamCoord()
            local maxD2 = C.MaxDistance * C.MaxDistance
            for veh, e in pairs(entries) do
                if DoesEntityExist(veh) and IsEntityOnScreen(veh) then
                    local m = Plates.matrix(veh)
                    local editing = veh == Plates.editVeh
                    for _, side in ipairs({ 'rear', 'front' }) do
                        local p = e.p[side]
                        if p and (editing or not e.hidden[side]) then
                            local cx, cy, cz, Rx, Ry, Rz, Ux, Uy, Uz, Nx, Ny, Nz = Plates.frame(m, side, p)
                            local dx, dy, dz = cam.x - cx, cam.y - cy, cam.z - cz
                            if dx * dx + dy * dy + dz * dz < maxD2 and dx * Nx + dy * Ny + dz * Nz > 0 then
                                local scale = p.scale or 1.0
                                if e.color.outline then
                                    drawText(e.text, 'outline', e.color.outline, lift, scale, cx, cy, cz, Rx, Ry, Rz, Ux, Uy, Uz, Nx, Ny, Nz)
                                end
                                drawText(e.text, 'font', e.color.text, lift + 0.0005, scale, cx, cy, cz, Rx, Ry, Rz, Ux, Uy, Uz, Nx, Ny, Nz)
                            end
                            if editing and side == Plates.editSide then
                                drawFrame(p.scale or 1.0, cx, cy, cz, Rx, Ry, Rz, Ux, Uy, Uz)
                            end
                        end
                    end
                end
            end
            Wait(0)
        end
    end
end)

-- Couleur propre à un véhicule (prioritaire sur le type de plaque), synchronisée : voir README
exports('SetVehiclePlateColor', function(veh, text, outline)
    Entity(veh).state:set('plateColor', text and { text = text, outline = outline or false } or nil, true)
end)
