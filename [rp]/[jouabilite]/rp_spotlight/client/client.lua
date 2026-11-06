--[[
    RP Spotlight - client
    ---------------------
    Projecteur(s) de portière des véhicules de config.lua (Vehicles) : côté conducteur (d) et, s'il est configuré, côté
    passager avant (p). La lumière est dessinée chez TOUS les joueurs proches à partir de l'état du véhicule « rpSpot »
    (publié par le serveur) ; le joueur qui tient le projecteur le voit bouger sans délai (valeurs locales).
    Modes : 0 manuel (direction par rapport au véhicule), 1 verrouillé (point du monde).
    Faisceau visible (Beam) : un rayon de lumière dessiné dans l'air (deux textures du dossier textures/, faites pour
    ce script), plus visible la nuit et sous la pluie, coupé là où la lumière touche un mur / le sol ; halo sur la lampe.
    Éblouissement (Glare) : joueur dans le faisceau ou tout près, la lampe en vue (rien entre les deux) : voile blanc
    et halo sur la lampe à l'écran, d'autant plus forts qu'on la regarde en face, de près, la nuit ; s'efface en
    ~1 s après (persistance rétinienne).
    Performance : 0.00 ms hors d'un véhicule équipé et sans projecteur allumé à proximité ; une vérification de la
    place toutes les 500 ms à bord d'un véhicule ; boucle par image seulement pour dessiner un projecteur allumé
    (à moins de RenderDistance) ou pendant la visée.
]]

local C = SpotlightConfig or {}
local L = C.Light or {}
local RESOURCE = GetCurrentResourceName()

local function u32(h) return (math.tointeger(tonumber(h) or 0) or 0) & 0xFFFFFFFF end
local function vec(t, fallback)
    t = type(t) == 'table' and t or fallback
    return vector3((t[1] or t.x or 0.0) + 0.0, (t[2] or t.y or 0.0) + 0.0, (t[3] or t.z or 0.0) + 0.0)
end

-- [modèle] = { name, d = offset, p = offset }
local MODELS = {}
for name, def in pairs(C.Vehicles or {}) do
    if type(def) == 'table' then
        MODELS[u32(GetHashKey(name:lower()))] = {
            name = name:lower(),
            d = def.driver and vec(def.driver.offset, C.DefaultDriver or { -0.95, 0.8, 0.55 }) or nil,
            p = def.passenger and vec(def.passenger.offset, C.DefaultPassenger or { 0.95, 0.8, 0.55 }) or nil,
        }
    end
end
local override = {} -- [modèle][côté] = offset (réglage en jeu, /editspotlight : ce joueur seulement)

local function modelOf(vehicle) return MODELS[u32(GetEntityModel(vehicle))] end
local function offsetOf(vehicle, side)
    local m = modelOf(vehicle)
    if not m then return nil end
    local o = override[u32(GetEntityModel(vehicle))]
    return (o and o[side]) or m[side]
end

-- =========================================================================
-- GÉOMÉTRIE : direction relative au véhicule (yaw, pitch en degrés) <-> direction dans le monde
-- =========================================================================
local function axes(vehicle)
    local pos = GetEntityCoords(vehicle)
    return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 1.0, 0.0) - pos,
        GetOffsetFromEntityInWorldCoords(vehicle, 1.0, 0.0, 0.0) - pos,
        GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, 1.0) - pos
end

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function norm(v)
    local l = math.sqrt(dot(v, v))
    if l < 1e-6 then return vector3(0.0, 1.0, 0.0) end
    return v / l
end

--- Débattement du projecteur : celui du conducteur, inversé (gauche / droite) pour le passager
local function limits(side)
    local y, p = C.Yaw or { Min = -110.0, Max = 50.0 }, C.Pitch or { Min = -35.0, Max = 25.0 }
    if side == 'p' then return -y.Max, -y.Min, p.Min, p.Max end
    return y.Min, y.Max, p.Min, p.Max
end

local function clampAngles(side, yaw, pitch)
    local y1, y2, p1, p2 = limits(side)
    return math.max(y1, math.min(y2, yaw)), math.max(p1, math.min(p2, pitch))
end

local function toWorld(vehicle, yaw, pitch)
    local f, r, u = axes(vehicle)
    local cy, sy = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
    local cp, sp = math.cos(math.rad(pitch)), math.sin(math.rad(pitch))
    return norm((f * cy + r * sy) * cp + u * sp)
end

local function toRelative(vehicle, dir)
    local f, r, u = axes(vehicle)
    local yaw = math.deg(math.atan(dot(dir, r), dot(dir, f)))
    local pitch = math.deg(math.asin(math.max(-1.0, math.min(1.0, dot(dir, u)))))
    return yaw, pitch
end

-- =========================================================================
-- PROJECTEUR TENU PAR CE JOUEUR
-- =========================================================================
local my = nil          -- { veh, side, on, yaw, pitch, mode, tx, ty, tz }
local aiming = false
local lastSend = 0
local lit = {}          -- [véhicule] = true : projecteurs allumés publiés (état rpSpot)
local smooth = {}       -- [véhicule .. côté] = { yaw, pitch } : direction affichée (autres joueurs : lissée)
local renderRunning = false

local function notify(text)
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started' and pcall(function() exports[chat]:addPrivate({ title = 'Projecteur', text = text }) end) then return end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end

--- Place du joueur dans ce véhicule -> projecteur tenu ('d', 'p') ou nil
local function seatSide(ped, vehicle)
    local m = modelOf(vehicle)
    if not m then return nil end
    if GetPedInVehicleSeat(vehicle, -1) == ped then return m.d and 'd' or nil end
    if GetPedInVehicleSeat(vehicle, 0) == ped and m.p then return 'p' end
    return nil
end

local function published(vehicle, side)
    local st = Entity(vehicle).state.rpSpot
    return type(st) == 'table' and type(st[side]) == 'table' and st[side] or nil
end

local function send(force)
    if not my then return end
    local now = GetGameTimer()
    if not force and now - lastSend < (C.SendMs or 100) then return end
    lastSend = now
    TriggerServerEvent('rp_spotlight:set', VehToNet(my.veh), my.side, {
        on = my.on, yaw = math.floor(my.yaw * 10 + 0.5) / 10, pitch = math.floor(my.pitch * 10 + 0.5) / 10,
        mode = my.mode, tx = my.tx, ty = my.ty, tz = my.tz })
end

-- Panneau d'état (mode) et réticule
local lastUi = nil
local function sendUi()
    local key = my and my.on and ('%d:%s:%s'):format(my.mode, my.side, tostring(aiming)) or 'off'
    if key == lastUi then return end
    lastUi = key
    if not (my and my.on) then
        SendNUIMessage({ action = 'status', data = { show = false, aim = aiming } })
    else
        SendNUIMessage({ action = 'status', data = { show = true, mode = my.mode,
            side = my.side == 'p' and 'Passager' or 'Conducteur', aim = aiming } })
    end
end

local startRender -- défini plus bas

local function setOn(on)
    if not my then return end
    my.on = on
    if not on then my.mode = 0 end
    send(true)
    sendUi()
    if on then lit[my.veh] = true; startRender() end
end

--- Point visé par la caméra (réticule au centre de l'écran)
local function cameraAim(vehicle)
    local cam = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(z) * math.cos(x), math.cos(z) * math.cos(x), math.sin(x))
    local dist = C.RaycastDistance or 120.0
    local to = cam + dir * dist
    local handle = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, -1, vehicle, 4)
    local _, hit, point = GetShapeTestResult(handle)
    if hit == 1 or hit == true then return point end
    return to
end

--- Direction actuelle d'un projecteur : manuelle, ou vers le point verrouillé
local function aimOf(vehicle, side, s, origin)
    if s.mode == 1 and tonumber(s.tx) then
        local yaw, pitch = toRelative(vehicle, norm(vector3(s.tx, s.ty, s.tz) - origin))
        return clampAngles(side, yaw, pitch)
    end
    return s.yaw or 0.0, s.pitch or 0.0
end

-- =========================================================================
-- FAISCEAU VISIBLE (Beam) : rayon dans l'air + halo de la lampe, deux textures dessinées en 3D (DrawTexturedPoly)
-- =========================================================================
local B = C.Beam or {}
local G = C.Glare or {}
local BEAM_TXD = 'rp_spotlight_fx'
local texReady = false
if B.Enabled ~= false or G.Enabled ~= false then
    local txd = CreateRuntimeTxd(BEAM_TXD)
    local a = CreateRuntimeTextureFromImage(txd, 'beam', 'textures/beam.png')
    local g = CreateRuntimeTextureFromImage(txd, 'glow', 'textures/glow.png')
    texReady = a ~= nil and a ~= 0 and g ~= nil and g ~= 0
end
local beamReady = texReady and B.Enabled ~= false

local function cross(a, b) return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end

--- Nuit : 1 de 21 h à 5 h, 0 de 8 h à 18 h, entre les deux au lever / coucher du soleil
local function nightAmount()
    local h = GetClockHours() + GetClockMinutes() / 60.0
    if h >= 21.0 or h < 5.0 then return 1.0 end
    if h >= 18.0 then return (h - 18.0) / 3.0 end
    if h < 8.0 then return (8.0 - h) / 3.0 end
    return 0.0
end

--- Visibilité dans l'air selon l'heure (nuit 1, jour B.Day) et la pluie (x 1 + pluie x B.Rain)
local function airFactor()
    local day = B.Day or 0.0
    local f = day + (1.0 - day) * nightAmount()
    return f * (1.0 + (GetRainLevel() or 0.0) * (B.Rain or 0.6))
end

--- Triangle texturé visible depuis la caméra (le jeu n'en dessine qu'une face : l'ordre est inversé au besoin)
local function tri(a, b, c, ua, va, ub, vb, uc, vc, cam, col, alpha, name)
    if dot(cross(b - a, c - a), cam - a) < 0.0 then a, b, c, ua, va, ub, vb, uc, vc = a, c, b, ua, va, uc, vc, ub, vb end
    DrawTexturedPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, col[1], col[2], col[3], alpha, BEAM_TXD, name,
        ua, va, 1.0, ub, vb, 1.0, uc, vc, 1.0)
end

local reach = {} -- [clé] = { at, dist } : longueur du faisceau jusqu'à l'obstacle (relue toutes les 100 ms)
local function beamLength(key, vehicle, origin, dir, now)
    local r = reach[key]
    local max = B.Length or 45.0
    if r and now - r.at < 100 then return r.dist end
    local to = origin + dir * max
    local handle = StartExpensiveSynchronousShapeTestLosProbe(origin.x, origin.y, origin.z, to.x, to.y, to.z, 1 + 2 + 16, vehicle, 4) -- décor, véhicules, objets
    local _, hit, point = GetShapeTestResult(handle)
    local dist = (hit == 1 or hit == true) and #(point - origin) or max
    reach[key] = { at = now, dist = math.max(0.5, dist) }
    return reach[key].dist
end

--- Rayon (bande tournée vers la caméra, élargie selon l'ouverture) + halo sur la lampe
local function drawBeam(key, vehicle, origin, dir, cam, now, air, col)
    local len = beamLength(key, vehicle, origin, dir, now)
    local toCam = cam - origin
    local camDist = #toCam
    local view = camDist > 0.01 and toCam / camDist or vector3(0.0, 0.0, 1.0)
    -- halo : fort quand on regarde la lampe de face (même de jour, plus discret)
    local facing = math.max(0.0, dot(dir, view))
    local glowA = math.floor((B.GlowAlpha or 220) * facing * facing * math.min(1.0, 0.35 + air) + 0.5)
    if glowA > 4 and camDist > 0.6 then
        local right = cross(view, vector3(0.0, 0.0, 1.0))
        if #right < 1e-3 then right = vector3(1.0, 0.0, 0.0) else right = right / #right end
        local up = cross(right, view)
        local g = (B.GlowSize or 0.35) * (0.6 + 0.4 * facing)
        local c = origin + dir * 0.06
        local p1, p2, p3, p4 = c - right * g - up * g, c + right * g - up * g, c + right * g + up * g, c - right * g + up * g
        tri(p1, p2, p3, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, cam, col, glowA, 'glow')
        tri(p1, p3, p4, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, cam, col, glowA, 'glow')
    end
    local alpha = (B.Alpha or 70) * air
    if alpha < 2 then return end
    local mid = origin + dir * (len * 0.5)
    local side = cross(dir, cam - mid)
    local sl = #side
    if sl < 1e-4 then return end
    side = side / sl
    -- vu dans l'axe, la bande est presque un trait : moins opaque (le halo prend le relais)
    alpha = math.floor(alpha * (0.35 + 0.65 * #cross(dir, view)) + 0.5)
    local tanH = math.tan(math.rad((B.Spread or L.Radius or 9.0) * 0.5))
    local w0, full, segs = B.Start or 0.08, B.Length or 45.0, B.Segments or 4
    for i = 0, segs - 1 do
        local d0, d1 = len * i / segs, len * (i + 1) / segs
        -- s'élargit avec la distance, et encore plus vers la fin (EndFlare) : rejoint la tache éclairée
        local flare = B.EndFlare or 0.9
        local h0 = w0 + d0 * tanH * (1.0 + flare * d0 / len)
        local h1 = w0 + d1 * tanH * (1.0 + flare * d1 / len)
        local c0, c1 = origin + dir * d0, origin + dir * d1
        local v0, v1 = d0 / full, d1 / full
        local a, b, c, d = c0 - side * h0, c0 + side * h0, c1 + side * h1, c1 - side * h1
        tri(a, b, c, 0.0, v0, 1.0, v0, 1.0, v1, cam, col, alpha, 'beam')
        tri(a, c, d, 0.0, v0, 1.0, v1, 0.0, v1, cam, col, alpha, 'beam')
    end
end

-- =========================================================================
-- ÉBLOUISSEMENT (Glare) : ce joueur dans le faisceau d'un projecteur (ou tout près), la lampe en vue
-- =========================================================================
local glare = 0.0        -- éblouissement affiché (lissé : monte vite, redescend lentement)
local glareSpot = nil    -- { x, y } : position à l'écran de la lampe la plus éblouissante
local sight = {}         -- [clé] = { at, clear } : rien entre la lampe et la caméra (relu toutes les 150 ms)

--- Rien entre la caméra et la lampe (ni mur, ni véhicule, ni objet ; son propre véhicule ne compte pas : pare-brise)
local function inSight(key, origin, cam, now)
    local v = sight[key]
    if v and now - v.at < 150 then return v.clear end
    local back = cam - origin
    local l = #back
    local stop = l > 0.7 and origin + back / l * 0.6 or origin -- s'arrête juste avant la lampe (et son véhicule)
    local ped = PlayerPedId()
    local own = GetVehiclePedIsIn(ped, false)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, stop.x, stop.y, stop.z, 1 + 2 + 16,
        own ~= 0 and own or ped, 4)
    local _, hit = GetShapeTestResult(handle)
    local clear = not (hit == 1 or hit == true)
    sight[key] = { at = now, clear = clear }
    return clear
end

--- Éblouissement causé par ce projecteur (0 - 1)
local function glareFrom(key, origin, dir, cam, camFwd, night, now)
    local toCam = cam - origin
    local dist = #toCam
    local range = G.Range or L.Distance or 90.0
    if dist < 0.3 or dist > range then return 0.0 end
    local v = toCam / dist
    -- dans le faisceau (Spread / 2) : plein ; à côté : diminue jusqu'à NearAngle
    local angle = math.deg(math.acos(math.max(-1.0, math.min(1.0, dot(dir, v)))))
    local inner = (B.Spread or L.Radius or 9.0) * 0.5
    local outer = math.max(inner + 0.1, G.NearAngle or 15.0)
    local cone = angle <= inner and 1.0 or math.max(0.0, 1.0 - (angle - inner) / (outer - inner))
    if cone <= 0.0 then return 0.0 end
    -- regard : en face de la lampe = plein ; détourné = un peu (lumière tout autour)
    local look = math.max(0.0, -dot(camFwd, v))
    local facing = (G.Away or 0.12) + (1.0 - (G.Away or 0.12)) * look ^ 6
    local near = 1.0 - (dist / range) ^ 2
    local day = G.Day or 0.35
    local f = cone * cone * facing * near * (day + (1.0 - day) * night)
    if f < 0.01 or not inSight(key, origin, cam, now) then return 0.0 end
    return math.min(1.0, f * (G.Strength or 1.0))
end

--- Voile blanc sur tout l'écran + halo sur la lampe (texture du halo, à l'endroit de la lampe à l'écran)
local function drawGlare(color)
    if glare < 0.01 then return end
    local veil = math.floor(glare * (G.Veil or 170) + 0.5)
    if veil > 0 then DrawRect(0.5, 0.5, 1.0, 1.0, color[1], color[2], color[3], veil) end
    if texReady and glareSpot then
        local size = (G.Size or 0.9) * (0.4 + 0.6 * glare)
        local ratio = GetAspectRatio(false)
        DrawSprite(BEAM_TXD, 'glow', glareSpot.x, glareSpot.y, size / ratio, size, 0.0, color[1], color[2], color[3],
            math.floor(math.min(255, glare * 300) + 0.5))
    end
end

-- =========================================================================
-- DESSIN (chez tous) : chaque projecteur allumé à portée, à chaque image
-- =========================================================================
local SHADOW_BASE = 4200
startRender = function()
    if renderRunning then return end
    renderRunning = true
    CreateThread(function()
        local color = L.Color or { 235, 240, 255 }
        local lastFrame = GetGameTimer()
        while next(lit) ~= nil or (my and my.on) or glare > 0.01 do
            local now = GetGameTimer()
            local dt = math.min(0.1, (now - lastFrame) / 1000.0)
            lastFrame = now
            local ped = PlayerPedId()
            local me = GetEntityCoords(ped)
            local myVeh = GetVehiclePedIsIn(ped, false)
            local cam = GetFinalRenderedCamCoord()
            local air = beamReady and airFactor() or 0.0
            local glareOn = G.Enabled ~= false and not IsPauseMenuActive()
            local camFwd, night
            if glareOn then
                local rot = GetFinalRenderedCamRot(2)
                local rx, rz = math.rad(rot.x), math.rad(rot.z)
                camFwd = vector3(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx))
                night = nightAmount()
            end
            local target, spot = 0.0, nil
            local index = 0
            for vehicle in pairs(lit) do
                if not DoesEntityExist(vehicle) then
                    lit[vehicle] = nil
                    reach[tostring(vehicle) .. 'd'], reach[tostring(vehicle) .. 'p'] = nil, nil
                    sight[tostring(vehicle) .. 'd'], sight[tostring(vehicle) .. 'p'] = nil, nil
                elseif #(GetEntityCoords(vehicle) - me) <= (C.RenderDistance or 160.0) then
                    for _, side in ipairs({ 'd', 'p' }) do
                        index = index + 1
                        local mine = my and my.veh == vehicle and my.side == side
                        local s = mine and my or published(vehicle, side)
                        local offset = s and s.on and offsetOf(vehicle, side)
                        if offset then
                            local origin = GetOffsetFromEntityInWorldCoords(vehicle, offset.x, offset.y, offset.z)
                            local yaw, pitch = aimOf(vehicle, side, s, origin)
                            local key = tostring(vehicle) .. side
                            local sm = smooth[key]
                            if mine or not sm then
                                sm = { yaw = yaw, pitch = pitch }
                                smooth[key] = sm
                            else
                                local k = math.min(1.0, dt * 12.0)
                                sm.yaw = sm.yaw + (yaw - sm.yaw) * k
                                sm.pitch = sm.pitch + (pitch - sm.pitch) * k
                            end
                            if mine and my.mode ~= 0 then my.yaw, my.pitch = yaw, pitch end
                            local dir = toWorld(vehicle, sm.yaw, sm.pitch)
                            DrawSpotLightWithShadow(origin.x, origin.y, origin.z, dir.x, dir.y, dir.z, color[1], color[2], color[3],
                                L.Distance or 90.0, L.Brightness or 22.0, L.Roundness or 4.0, L.Radius or 9.0, L.Falloff or 60.0,
                                SHADOW_BASE + index)
                            if L.Lamp ~= false then
                                local glow = origin + dir * 0.12
                                DrawLightWithRange(glow.x, glow.y, glow.z, color[1], color[2], color[3], 0.6, 3.0)
                            end
                            if beamReady then drawBeam(key, vehicle, origin, dir, cam, now, air, B.Color or color) end
                            -- éblouissement : pas pour les occupants du véhicule de ce projecteur
                            if glareOn and vehicle ~= myVeh then
                                local g = glareFrom(key, origin, dir, cam, camFwd, night, now)
                                if g > target then
                                    target = g
                                    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(origin.x, origin.y, origin.z)
                                    spot = onScreen and { x = sx, y = sy } or nil
                                end
                            end
                        end
                    end
                end
            end
            -- projecteur allumé tenu par ce joueur : le clic droit sert à viser le projecteur (pas l'arme / la visée du véhicule)
            if my and my.on then for _, c in ipairs({ 25, 68, 91 }) do DisableControlAction(0, c, true) end end
            -- le sien, pas encore publié (ou éteint chez les autres) : dessiné quand même
            if my and my.on and not lit[my.veh] then lit[my.veh] = true end
            -- éblouissement : monte vite (Rise), redescend lentement (Fall : persistance rétinienne)
            local speed = target > glare and (G.Rise or 10.0) or (G.Fall or 2.5)
            glare = glare + (target - glare) * math.min(1.0, dt * speed)
            if target > 0.0 then glareSpot = spot end
            if glare < 0.01 then glare, glareSpot = 0.0, nil end
            drawGlare(L.Color or color)
            Wait(0)
        end
        renderRunning = false
    end)
end

AddStateBagChangeHandler('rpSpot', nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle == 0 then return end
    if type(value) == 'table' and ((value.d and value.d.on) or (value.p and value.p.on)) then
        lit[vehicle] = true
        startRender()
    else
        lit[vehicle] = nil
    end
end)

-- =========================================================================
-- VISÉE (clic droit maintenu) : le projecteur suit la caméra (la souris) ; clic gauche verrouille sur le point visé
-- =========================================================================
local function aimLoop()
    CreateThread(function()
        while aiming and my do
            local ped = PlayerPedId()
            if GetVehiclePedIsIn(ped, false) ~= my.veh or IsPauseMenuActive() then break end
            -- clics : au projecteur, pas aux armes / au klaxon
            for _, c in ipairs({ 24, 25, 68, 69, 70, 91, 92, 114, 140, 141, 142, 257, 263 }) do DisableControlAction(0, c, true) end
            local offset = offsetOf(my.veh, my.side)
            local origin = GetOffsetFromEntityInWorldCoords(my.veh, offset.x, offset.y, offset.z)
            local point = cameraAim(my.veh)
            local yaw, pitch = clampAngles(my.side, toRelative(my.veh, norm(point - origin)))
            local lock = IsDisabledControlJustPressed(0, 24) or IsDisabledControlJustPressed(0, 69) or IsDisabledControlJustPressed(0, 92)
            if lock then
                if my.mode == 1 then my.mode = 0
                else my.mode, my.tx, my.ty, my.tz = 1, point.x, point.y, point.z end
                send(true); sendUi()
            end
            if my.mode == 0 then
                my.yaw, my.pitch = yaw, pitch
                send(false)
            end
            Wait(0)
        end
        aiming = false
        SendNUIMessage({ action = 'aim', data = { on = false } })
        if my then send(true) end
        sendUi()
    end)
end

-- Ctrl (Key) : allumer / éteindre ; clic droit MAINTENU (AimButton) : viser avec la souris ; relâché : il garde la direction
RegisterCommand('+rp_spotlight', function()
    if not my or IsPauseMenuActive() then return end
    if aiming then aiming = false end
    setOn(not my.on)
end, false)
RegisterCommand('-rp_spotlight', function() end, false)
RegisterKeyMapping('+rp_spotlight', 'Projecteur : allumer / éteindre', 'keyboard', C.Key or 'LCONTROL')

RegisterCommand('+rp_spotlight_aim', function()
    if not my or not my.on or aiming or IsPauseMenuActive() then return end
    aiming = true
    SendNUIMessage({ action = 'aim', data = { on = true } })
    sendUi()
    aimLoop()
end, false)
RegisterCommand('-rp_spotlight_aim', function() aiming = false end, false)
RegisterKeyMapping('+rp_spotlight_aim', 'Projecteur : viser (maintenir, puis bouger la souris)', 'mouse_button', C.AimButton or 'MOUSE_RIGHT')

-- =========================================================================
-- PLACE DU JOUEUR : quel projecteur il tient (toutes les 500 ms à bord d'un véhicule ; 1 s sinon)
-- =========================================================================
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local side = vehicle ~= 0 and seatSide(ped, vehicle) or nil
        if not side then
            if my then my = nil; aiming = false; sendUi() end
        elseif not my or my.veh ~= vehicle or my.side ~= side then
            -- reprend l'état publié (projecteur déjà allumé par un collègue, ou laissé allumé)
            local p = published(vehicle, side) or {}
            my = { veh = vehicle, side = side, on = p.on == true, yaw = tonumber(p.yaw) or 0.0, pitch = tonumber(p.pitch) or -2.0,
                mode = tonumber(p.mode) == 1 and 1 or 0, tx = p.tx, ty = p.ty, tz = p.tz }
            sendUi()
            if my.on then lit[vehicle] = true; startRender() end
        end
        Wait(vehicle ~= 0 and 500 or 1000)
    end
end)

-- =========================================================================
-- RÉGLAGE EN JEU : /editspotlight (projecteur conducteur), /editspotlightside (projecteur passager)
-- Point rouge sur le départ de la lumière, faisceau d'essai, panneau en haut au milieu ; ligne de config.lua à copier
-- =========================================================================
local editing = nil -- { veh, side }
local function configLine(vehicle)
    local m = modelOf(vehicle)
    local parts = {}
    for _, side in ipairs({ 'd', 'p' }) do
        local o = offsetOf(vehicle, side)
        if o then
            parts[#parts + 1] = ('%s = { offset = { %.2f, %.2f, %.2f } }'):format(side == 'd' and 'driver' or 'passenger', o.x, o.y, o.z)
        end
    end
    return ('%s = { %s },'):format(m.name, table.concat(parts, ', '))
end

--- Pendant le réglage, à chaque image : point rouge au départ de la lumière ; faisceau d'essai si ce projecteur est éteint
local function editLoop()
    CreateThread(function()
        local color = L.Color or { 235, 240, 255 }
        while editing do
            local vehicle, side = editing.veh, editing.side
            local offset = DoesEntityExist(vehicle) and offsetOf(vehicle, side)
            if not offset then break end
            local o = GetOffsetFromEntityInWorldCoords(vehicle, offset.x, offset.y, offset.z)
            DrawMarker(28, o.x, o.y, o.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.07, 0.07, 0.07, 255, 20, 20, 230,
                false, false, 2, false, nil, nil, false)
            local s = (my and my.veh == vehicle and my.side == side) and my or published(vehicle, side)
            if not (s and s.on) then
                local dir = toWorld(vehicle, 0.0, -4.0)
                DrawSpotLightWithShadow(o.x, o.y, o.z, dir.x, dir.y, dir.z, color[1], color[2], color[3],
                    L.Distance or 90.0, L.Brightness or 22.0, L.Roundness or 4.0, L.Radius or 9.0, L.Falloff or 60.0, 4299)
            end
            Wait(0)
        end
        if editing then editing = nil; SetNuiFocus(false, false); SendNUIMessage({ action = 'adjust', data = { on = false } }) end
    end)
end

local function startEdit(side)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    local m = vehicle ~= 0 and modelOf(vehicle)
    if not m then return notify('Montez dans un véhicule de la liste des projecteurs (config.lua : Vehicles).') end
    if not m[side] then
        return notify(side == 'p' and 'Ce véhicule n\'a pas de projecteur côté passager (config.lua : passenger).'
            or 'Ce véhicule n\'a pas de projecteur côté conducteur (config.lua : driver).')
    end
    if editing then return end
    editing = { veh = vehicle, side = side }
    local o = offsetOf(vehicle, side)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'adjust', data = { on = true, x = o.x, y = o.y, z = o.z, side = side == 'p' and 'passager (droite)' or 'conducteur (gauche)',
        model = m.name, line = configLine(vehicle) } })
    editLoop()
end
RegisterCommand(C.AdjustCommand or 'editspotlight', function() startEdit('d') end, false)
RegisterCommand(C.AdjustSideCommand or 'editspotlightside', function() startEdit('p') end, false)

RegisterNUICallback('offset', function(d, cb)
    cb({ ok = true })
    if not (editing and type(d) == 'table') then return end
    local hash = u32(GetEntityModel(editing.veh))
    override[hash] = override[hash] or {}
    override[hash][editing.side] = vector3(math.max(-3.0, math.min(3.0, tonumber(d.x) or 0.0)),
        math.max(-4.0, math.min(4.0, tonumber(d.y) or 0.0)), math.max(-1.0, math.min(3.0, tonumber(d.z) or 0.0)))
    SendNUIMessage({ action = 'line', data = { line = configLine(editing.veh) } })
end)

RegisterNUICallback('adjustDone', function(_, cb)
    cb({ ok = true })
    local vehicle = editing and editing.veh
    editing = nil
    SetNuiFocus(false, false)
    if vehicle and DoesEntityExist(vehicle) then
        local line = configLine(vehicle)
        print('[rp_spotlight] ligne pour config.lua (Vehicles) : ' .. line)
        notify('Réglage gardé pour vous jusqu\'à la déconnexion. Ligne pour config.lua (aussi dans la console F8) : ' .. line)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    if editing then SetNuiFocus(false, false) end
    if my and my.on then my.on = false; send(true) end
end)

RPSpotlight = { toWorld = toWorld, toRelative = toRelative, clampAngles = clampAngles, seatSide = seatSide, -- tests
    my = function() return my end, lit = lit, setOn = setOn, models = MODELS, offsetOf = offsetOf, editing = function() return editing end,
    airFactor = airFactor, drawBeam = drawBeam, beamReady = function() return beamReady end,
    glare = function() return glare end, glareFrom = glareFrom }
