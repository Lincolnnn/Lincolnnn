--[[
    RP Weapons Control - LAMPES (lampe torche / de poche tenue en main, lampes des armes à feu), refaites sur la base des
    projecteurs (rp_spotlight) : vues par tous les joueurs autour.
      - LUMIÈRE : un vrai faisceau (avec ombres pour les plus proches) qui part de la lampe, dans son axe. Réglages
        séparés pour la lampe tenue (Light.Object) et les lampes des armes (Light.Weapon) : DISTANCE (Range) et
        PUISSANCE (Intensity), largeur (Radius), atténuation (Falloff), netteté du bord (Roundness).
      - FAISCEAU VISIBLE dans l'air (Beam : surtout la nuit, plus sous la pluie) et LUEUR sur la lampe (halo vu de face
        + petite lumière autour de la lampe).
      - ÉBLOUISSEMENT (Glare) : un joueur dans le faisceau d'une lampe (ou tout près), la lampe en vue : voile blanc et
        halo sur la lampe à l'écran ; plus fort de près, en regardant la lampe en face, la nuit, et avec le stroboscope.
      - STROBOSCOPE (Strobe) : touche F7 (Raccourcis clavier > FiveM), lampe allumée en main : la lampe clignote très vite
        (Hz) ; vu par tous (état rpStrobe du joueur), plus éblouissant. Rappuyer, changer d'arme, monter en véhicule :
        arrêté, la lampe redevient normale.
    LE SCRIPT PREND LE DESSUS (Flashlight.Override, défaut) : la lampe du jeu n'est jamais affichée, seule celle d'ici ;
    allumée / éteinte avec la touche de la lampe du jeu (E), lue par client/client.lua (état rpLamp, vu par tous).
    Override = false : la lampe du jeu reste allumée en plus, sauf pendant le stroboscope. Lampes de CartoonFlashlight (si Flashlight.Cartoon.Enabled et la ressource démarrée) : sa lumière (distance,
    puissance) et son stroboscope sont réglés dans SON config.lua (Config.Light, Config.Strobe) ; ici : faisceau
    visible, lueur et éblouissement pour ses lampes aussi (liste lue par son export « lamps »).
    Performance : aucune lampe allumée : une lecture toutes les Light.CheckMs ms ; sinon dessin à chaque image tant
    qu'une lampe est allumée à portée (ou qu'un éblouissement s'efface).
]]

local W = WeaponsConfig
local FL = W.Flashlight or {}
local L = FL.Light or {}
if FL.Enabled == false or L.Enabled == false then return end

local u32 = RPWeapons.u32
local OBJ = L.Object or {}
local WPN = L.Weapon or FL.Boost or {} -- (ancien réglage Boost : lampes des armes)
local BE = FL.Beam or {}
local GL = FL.Glare or {}
local ST = FL.Strobe or {}
local CARTOON = FL.Cartoon or {}
local OVERRIDE = FL.Override ~= false
local UNARMED = u32(GetHashKey('WEAPON_UNARMED'))

local HANDLIGHTS = {}
for _, name in ipairs(FL.HandLights or { 'WEAPON_FLASHLIGHT', 'WEAPON_POCKETLIGHT' }) do HANDLIGHTS[u32(GetHashKey(name))] = true end

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function cross(a, b) return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end
local function norm(v)
    local l = math.sqrt(dot(v, v))
    if l < 0.0001 then return nil end
    return vector3(v.x / l, v.y / l, v.z / l)
end

-- =========================================================================
-- TEXTURES (les mêmes que les projecteurs : faisceau dégradé, halo)
-- =========================================================================
local TXD = 'rp_weaponscontrol_fx'
local texReady = false
do
    local txd = CreateRuntimeTxd(TXD)
    local a = CreateRuntimeTextureFromImage(txd, 'beam', 'textures/beam.png')
    local g = CreateRuntimeTextureFromImage(txd, 'glow', 'textures/glow.png')
    texReady = a ~= nil and a ~= 0 and g ~= nil and g ~= 0
end

--- Nuit : 1 de 21 h à 5 h, 0 de 8 h à 18 h, entre les deux au lever / coucher du soleil
local function nightAmount()
    local h = GetClockHours() + GetClockMinutes() / 60.0
    if h >= 21.0 or h < 5.0 then return 1.0 end
    if h >= 18.0 then return (h - 18.0) / 3.0 end
    if h < 8.0 then return (8.0 - h) / 3.0 end
    return 0.0
end

--- Visibilité du faisceau dans l'air : nuit 1, jour Beam.Day ; pluie : x (1 + pluie x Beam.Rain)
local function airFactor()
    local day = BE.Day or 0.0
    return (day + (1.0 - day) * nightAmount()) * (1.0 + (GetRainLevel() or 0.0) * (BE.Rain or 0.6))
end

-- =========================================================================
-- POSITION ET AXE DE LA LAMPE
-- =========================================================================
local BONES = { 'WAPFlshLasr', 'WAPFlshLasr_2', 'Gun_FLMuzzle', 'gun_muzzle', 'Gun_Muzzle' }

-- EMPLACEMENT DE LA LAMPE PAR ARME (armes ajoutées : PM4…) : départ de la lumière, en mètres, dans les axes de l'arme.
-- Config (Flashlight.Positions), puis réglages enregistrés en jeu par un admin (/editflashlight : état global
-- rpFlashPos, gardé par le serveur), puis réglage en cours (pour soi, jusqu'à la déconnexion).
local function vec(p)
    if type(p) ~= 'table' then return nil end
    local x, y, z = tonumber(p[1] or p.x), tonumber(p[2] or p.y), tonumber(p[3] or p.z)
    if not (x and y and z) then return nil end
    return vector3(x + 0.0, y + 0.0, z + 0.0)
end
local POS = {}
for name, p in pairs(FL.Positions or {}) do
    local h = type(name) == 'number' and u32(name) or u32(GetHashKey(tostring(name)))
    POS[h] = vec(p)
end
local saved, mine = {}, {}
local function readSaved(value)
    saved = {}
    if type(value) ~= 'table' then return end
    for k, p in pairs(value) do
        local h = tonumber(k)
        if h then saved[u32(h)] = vec(p) end
    end
end
readSaved(GlobalState.rpFlashPos)
AddStateBagChangeHandler('rpFlashPos', 'global', function(_, _, value) readSaved(value) end)
local function positionOf(weapon)
    return mine[weapon] or saved[weapon] or POS[weapon]
end

--- Axe de l'objet (parmi ses trois axes, dans les deux sens) le plus proche de `want`
local function closestAxis(entity, want)
    local a, b, c = GetEntityMatrix(entity)
    local best, score = nil, 0.0
    for _, axis in ipairs({ a, b, c }) do
        local d = dot(axis, want)
        if math.abs(d) > math.abs(score) then best, score = axis, d end
    end
    return best and norm(score < 0 and vector3(-best.x, -best.y, -best.z) or best) or want
end

--- Où regarde le joueur : la caméra pour soi en visant, sinon l'avant du personnage
local function lookOf(ped)
    if ped == PlayerPedId() and IsPlayerFreeAiming(PlayerId()) then
        local rot = GetFinalRenderedCamRot(2)
        local rx, rz = math.rad(rot.x), math.rad(rot.z)
        return vector3(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx))
    end
    return GetEntityForwardVector(ped)
end

--- Position et direction de la lampe (pos, dir) : lampe d'arme : dans l'axe du canon, depuis la lampe ; lampe tenue :
--- dans l'axe de l'objet le plus proche de là où regarde le joueur
local function beamOf(ped, handLight)
    local weapon = GetCurrentPedWeaponEntityIndex(ped)
    if weapon and weapon ~= 0 and DoesEntityExist(weapon) then
        local origin = GetEntityCoords(weapon)
        local fixed = positionOf(u32(GetSelectedPedWeapon(ped)))
        if fixed then
            -- emplacement réglé pour cette arme : départ exact de la lumière ; direction : axe du canon / de la lampe
            local from = GetOffsetFromEntityInWorldCoords(weapon, fixed.x, fixed.y, fixed.z)
            local dir
            if handLight then
                dir = closestAxis(weapon, lookOf(ped))
            else
                local muzzle = GetEntityBoneIndexByName(weapon, 'gun_muzzle')
                local tip = (muzzle and muzzle ~= -1) and GetWorldPositionOfEntityBone(weapon, muzzle)
                local along = tip and norm(tip - origin)
                dir = along and closestAxis(weapon, along) or closestAxis(weapon, lookOf(ped))
            end
            return from, dir
        end
        if handLight then
            local dir = closestAxis(weapon, lookOf(ped))
            local ahead = OBJ.Ahead or 0.14
            return vector3(origin.x + dir.x * ahead, origin.y + dir.y * ahead, origin.z + dir.z * ahead), dir
        end
        local light
        for _, name in ipairs(BONES) do
            local bone = GetEntityBoneIndexByName(weapon, name)
            if bone and bone ~= -1 then light = GetWorldPositionOfEntityBone(weapon, bone) break end
        end
        local muzzle = GetEntityBoneIndexByName(weapon, 'gun_muzzle')
        local tip = (muzzle and muzzle ~= -1) and GetWorldPositionOfEntityBone(weapon, muzzle) or light
        local along = tip and norm(tip - origin)
        if along then
            local dir = closestAxis(weapon, along)
            local from = light or tip
            local ahead = WPN.Ahead or 0.12
            return vector3(from.x + dir.x * ahead, from.y + dir.y * ahead, from.z + dir.z * ahead), dir
        end
    end
    local p, f = GetEntityCoords(ped), GetEntityForwardVector(ped)
    return vector3(p.x + f.x * 0.4, p.y + f.y * 0.4, p.z + 0.4), f
end
RPWeapons.beamOf = beamOf

--- Lampe de CartoonFlashlight (objet tenu en main) : axe long du modèle, bout tourné vers où regarde le personnage
local propAxes = {}
local function along(i, v)
    if i == 1 then return v, 0.0, 0.0 elseif i == 2 then return 0.0, v, 0.0 end
    return 0.0, 0.0, v
end
local function propBeam(lamp)
    local object = lamp.torch
    local m = GetEntityModel(object)
    local a = propAxes[m]
    if not a then
        local mn, mx = GetModelDimensions(m)
        local lo, hi = { mn.x, mn.y, mn.z }, { mx.x, mx.y, mx.z }
        local i = 1
        for k = 2, 3 do if hi[k] - lo[k] > hi[i] - lo[i] then i = k end end
        a = { i = i, lo = lo[i], hi = hi[i] }
        propAxes[m] = a
    end
    local h, p = math.rad(GetEntityHeading(lamp.ped) + (lamp.yaw or 0.0)), math.rad(lamp.pitch or 0.0)
    local want = vector3(-math.sin(h) * math.cos(p), math.cos(h) * math.cos(p), math.sin(p))
    local dir = norm(GetOffsetFromEntityInWorldCoords(object, along(a.i, 1.0)) - GetEntityCoords(object))
    if not dir then return nil end
    local sign = dot(dir, want) >= 0.0 and 1.0 or -1.0
    local pos = GetOffsetFromEntityInWorldCoords(object, along(a.i, (sign > 0 and a.hi or a.lo) + sign * (lamp.ahead or 0.03)))
    return pos, dir * sign
end

-- =========================================================================
-- STROBOSCOPE (lampe allumée en main) : touche L ; vu par tous (état rpStrobe)
-- =========================================================================
local strobe = false
local strobeWeapon = nil

local function setStrobe(on)
    local ped = PlayerPedId()
    if on == strobe then return end
    strobe = on
    LocalPlayer.state:set('rpStrobe', on, true)
    if on then
        strobeWeapon = u32(GetSelectedPedWeapon(ped))
        if not OVERRIDE then SetFlashLightEnabled(ped, false) end -- la lampe du jeu ne clignoterait pas
    else
        if not OVERRIDE and strobeWeapon and strobeWeapon == u32(GetSelectedPedWeapon(ped)) then SetFlashLightEnabled(ped, true) end
        strobeWeapon = nil
    end
end
RPWeapons.strobing = function() return strobe end

local function cartoon(weapon) return RPWeapons.cartoon and RPWeapons.cartoon(weapon) end

if ST.Enabled ~= false then
    RegisterCommand('rp_flashlight_strobe', function()
        if strobe then return setStrobe(false) end
        local ped = PlayerPedId()
        local weapon = u32(GetSelectedPedWeapon(ped))
        if weapon == 0 or weapon == UNARMED or cartoon(weapon) or IsPedInAnyVehicle(ped, false) then return end
        local on
        if OVERRIDE then on = RPWeapons.lampOn == weapon else on = IsFlashLightOn(ped) end
        if not on then return end -- lampe éteinte (ou arme sans lampe) : rien
        setStrobe(true)
    end, false)
    RegisterKeyMapping('rp_flashlight_strobe', 'Lampe : stroboscope (lampe allumée en main)', 'keyboard', ST.Key or 'F7')
end

-- =========================================================================
-- LAMPES ALLUMÉES (soi et joueurs autour), relues toutes les Light.CheckMs ms
-- =========================================================================
local lamps = {}  -- { { ped, hand, strobe, key } }

local function lampOf(ped, isMe, serverId)
    if not ped or ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then return nil end
    local weapon = u32(GetSelectedPedWeapon(ped))
    if weapon == 0 or weapon == UNARMED or cartoon(weapon) then return nil end
    local strobing = isMe and strobe or (not isMe and serverId and Player(serverId).state.rpStrobe == true)
    local on
    if isMe and OVERRIDE then
        on = RPWeapons.lampOn == weapon
    else
        -- lampe du script (état rpLamp = arme en main) ; sinon lampe du jeu (Override = false)
        local state = not isMe and serverId and Player(serverId).state.rpLamp
        on = (state and u32(state) == weapon) or IsFlashLightOn(ped) == true
    end
    if not strobing and not on then return nil end
    return { ped = ped, hand = HANDLIGHTS[weapon] == true, strobe = strobing == true, key = tostring(ped) }
end

-- =========================================================================
-- DESSIN : lumière, faisceau visible, lueur, éblouissement
-- =========================================================================
local function tri(a, b, c, ua, va, ub, vb, uc, vc, cam, col, alpha, name)
    if dot(cross(b - a, c - a), cam - a) < 0.0 then a, b, c, ua, va, ub, vb, uc, vc = a, c, b, ua, va, uc, vc, ub, vb end
    DrawTexturedPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, col[1], col[2], col[3], alpha, TXD, name,
        ua, va, 1.0, ub, vb, 1.0, uc, vc, 1.0)
end

local reach = {} -- [clé] = { at, dist } : longueur du faisceau jusqu'à l'obstacle (relue toutes les 100 ms)
local function beamLength(key, ped, origin, dir, max, now)
    local r = reach[key]
    if r and now - r.at < 100 then return math.min(r.dist, max) end
    local to = origin + dir * max
    local handle = StartExpensiveSynchronousShapeTestLosProbe(origin.x, origin.y, origin.z, to.x, to.y, to.z, 1 + 2 + 16, ped, 4)
    local _, hit, point = GetShapeTestResult(handle)
    local dist = (hit == 1 or hit == true) and #(point - origin) or max
    reach[key] = { at = now, dist = math.max(0.3, dist) }
    return reach[key].dist
end

--- Faisceau visible (bande tournée vers la caméra, qui s'élargit) + halo de la lampe vue de face
local function drawBeam(key, ped, origin, dir, cam, now, air, col, cat)
    local toCam = cam - origin
    local camDist = #toCam
    local view = camDist > 0.01 and toCam / camDist or vector3(0.0, 0.0, 1.0)
    local facing = math.max(0.0, dot(dir, view))
    local glowA = math.floor((BE.GlowAlpha or 200) * facing * facing * math.min(1.0, 0.4 + air) + 0.5)
    if glowA > 4 and camDist > 0.4 then
        local right = cross(view, vector3(0.0, 0.0, 1.0))
        if #right < 1e-3 then right = vector3(1.0, 0.0, 0.0) else right = right / #right end
        local up = cross(right, view)
        local g = (cat.GlowSize or BE.GlowSize or 0.16) * (0.6 + 0.4 * facing)
        local c = origin + dir * 0.03
        local p1, p2, p3, p4 = c - right * g - up * g, c + right * g - up * g, c + right * g + up * g, c - right * g + up * g
        tri(p1, p2, p3, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, cam, col, glowA, 'glow')
        tri(p1, p3, p4, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, cam, col, glowA, 'glow')
    end
    local alpha = (cat.BeamAlpha or BE.Alpha or 45) * air
    if alpha < 2 then return end
    local full = cat.BeamLength or (cat.Range or 40.0) * (BE.LengthRatio or 0.6)
    local len = beamLength(key, ped, origin, dir, full, now)
    local mid = origin + dir * (len * 0.5)
    local side = cross(dir, cam - mid)
    local sl = #side
    if sl < 1e-4 then return end
    side = side / sl
    alpha = math.floor(alpha * (0.35 + 0.65 * #cross(dir, view)) + 0.5)
    local tanH = math.tan(math.rad((cat.Radius or 16.0) * (BE.SpreadRatio or 0.8) * 0.5))
    local w0, segs, flare = BE.Start or 0.04, BE.Segments or 3, BE.EndFlare or 0.6
    for i = 0, segs - 1 do
        local d0, d1 = len * i / segs, len * (i + 1) / segs
        local h0 = w0 + d0 * tanH * (1.0 + flare * d0 / full)
        local h1 = w0 + d1 * tanH * (1.0 + flare * d1 / full)
        local c0, c1 = origin + dir * d0, origin + dir * d1
        local v0, v1 = d0 / full, d1 / full
        local a, b, c, d = c0 - side * h0, c0 + side * h0, c1 + side * h1, c1 - side * h1
        tri(a, b, c, 0.0, v0, 1.0, v0, 1.0, v1, cam, col, alpha, 'beam')
        tri(a, c, d, 0.0, v0, 1.0, v1, 0.0, v1, cam, col, alpha, 'beam')
    end
end

-- Éblouissement
local glare, glareSpot = 0.0, nil
local sight = {} -- [clé] = { at, clear }
local function inSight(key, origin, cam, ped, now)
    local v = sight[key]
    if v and now - v.at < 150 then return v.clear end
    local back = cam - origin
    local l = #back
    local stop = l > 0.5 and origin + back / l * 0.3 or origin
    local me = PlayerPedId()
    local handle = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, stop.x, stop.y, stop.z, 1 + 2 + 16, me, 4)
    local _, hit, _, _, entity = GetShapeTestResult(handle)
    local clear = not (hit == 1 or hit == true) or entity == ped
    sight[key] = { at = now, clear = clear }
    return clear
end

local function glareFrom(lamp, cat, origin, dir, cam, camFwd, night, now)
    local toCam = cam - origin
    local dist = #toCam
    local range = cat.GlareRange or GL.Range or 30.0
    if dist < 0.3 or dist > range then return 0.0 end
    local v = toCam / dist
    local angle = math.deg(math.acos(math.max(-1.0, math.min(1.0, dot(dir, v)))))
    local inner = (cat.Radius or 16.0) * 0.5
    local outer = math.max(inner + 0.1, GL.NearAngle or 22.0)
    local cone = angle <= inner and 1.0 or math.max(0.0, 1.0 - (angle - inner) / (outer - inner))
    if cone <= 0.0 then return 0.0 end
    local look = math.max(0.0, -dot(camFwd, v))
    local away = GL.Away or 0.12
    local facing = away + (1.0 - away) * look ^ 6
    local near = 1.0 - (dist / range) ^ 2
    local day = GL.Day or 0.3
    local f = cone * cone * facing * near * (day + (1.0 - day) * night) * (cat.GlareStrength or 1.0)
    if lamp.strobe then f = f * (ST.GlareBoost or 1.6) end
    if f < 0.01 or not inSight(lamp.key, origin, cam, lamp.ped, now) then return 0.0 end
    return math.min(1.0, f * (GL.Strength or 1.0))
end

local function drawGlare(color)
    if glare < 0.01 then return end
    local veil = math.floor(glare * (GL.Veil or 150) + 0.5)
    if veil > 0 then DrawRect(0.5, 0.5, 1.0, 1.0, color[1], color[2], color[3], veil) end
    if texReady and glareSpot then
        local size = (GL.Size or 0.7) * (0.4 + 0.6 * glare)
        DrawSprite(TXD, 'glow', glareSpot.x, glareSpot.y, size / GetAspectRatio(false), size, 0.0, color[1], color[2], color[3],
            math.floor(math.min(255, glare * 300) + 0.5))
    end
end

--- Stroboscope : allumé pendant la première partie de chaque période (Hz, Duty) ; décalé d'une lampe à l'autre
local function strobeOn(lamp, now)
    local period = 1000.0 / math.max(1.0, lamp.hz or ST.Hz or 10.0)
    local offset = (lamp.ped % 7) * 13
    return ((now + offset) % period) < period * (lamp.duty or ST.Duty or 0.5)
end

local SHADOW_BASE = 5200

--- Lumière d'une lampe : CENTRE PUISSANT (Core : part du cône, à Intensity) + BORDS MOINS ÉCLAIRÉS (cône entier, à
--- Intensity x Edge, bord doux) : la tache est nettement plus forte au milieu, sur une bonne largeur
local function drawLight(pos, dir, col, range, power, cat, shadowId)
    local radius = (cat.Radius or 16.0) + 0.0
    local core = math.max(0.1, math.min(1.0, cat.Core or L.Core or 0.6))
    local edge = math.max(0.0, cat.Edge or L.Edge or 0.3)
    local falloff = (cat.Falloff or 20.0) + 0.0
    local layers = {
        { power * edge, (cat.Roundness or 3.0) + 0.0, radius },                           -- bords
        { power, (cat.CoreRoundness or L.CoreRoundness or 8.0) + 0.0, radius * core },    -- centre
    }
    for n, l in ipairs(layers) do
        if l[1] > 0.0 then
            if shadowId then
                DrawSpotLightWithShadow(pos.x, pos.y, pos.z, dir.x, dir.y, dir.z, col[1], col[2], col[3], range, l[1] + 0.0, l[2],
                    l[3], falloff, shadowId + n - 1)
            else
                DrawSpotLight(pos.x, pos.y, pos.z, dir.x, dir.y, dir.z, col[1], col[2], col[3], range, l[1] + 0.0, l[2], l[3], falloff)
            end
        end
    end
end
local rendering = false
local function render()
    if rendering then return end
    rendering = true
    CreateThread(function()
        local last = GetGameTimer()
        while #lamps > 0 or glare > 0.01 do
            local now = GetGameTimer()
            local dt = math.min(0.1, (now - last) / 1000.0)
            last = now
            local me = PlayerPedId()
            local cam = GetFinalRenderedCamCoord()
            local air = texReady and BE.Enabled ~= false and airFactor() or 0.0
            local glareOn = GL.Enabled ~= false and not IsPauseMenuActive()
            local camFwd, night
            if glareOn then
                local rot = GetFinalRenderedCamRot(2)
                local rx, rz = math.rad(rot.x), math.rad(rot.z)
                camFwd = vector3(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx))
                night = nightAmount()
            end
            local target, spot = 0.0, nil
            local shadows = L.Shadows or 2
            for i, lamp in ipairs(lamps) do
                if DoesEntityExist(lamp.ped) and (not lamp.cartoon or DoesEntityExist(lamp.torch)) then
                    local cat = lamp.cat or (lamp.hand and OBJ or WPN)
                    local col = cat.Color or L.Color or { 255, 247, 235 }
                    local visible = not lamp.strobe or strobeOn(lamp, now)
                    local pos, dir
                    if visible then
                        if lamp.cartoon then pos, dir = propBeam(lamp) else pos, dir = beamOf(lamp.ped, lamp.hand) end
                        visible = pos ~= nil
                    end
                    if visible then
                        local range, power = (cat.Range or 40.0) + 0.0, (cat.Intensity or 8.0) * (lamp.strobe and (ST.Power or 1.4) or 1.0)
                        if not lamp.cartoon then -- (CartoonFlashlight dessine sa lumière elle-même : Config.Light)
                            drawLight(pos, dir, col, range, power, cat, i <= shadows and SHADOW_BASE + i * 2 or nil)
                        end
                        -- lueur : petite lumière autour de la lampe
                        if (cat.GlowRange or 1.2) > 0 then
                            local g = pos + dir * 0.04
                            DrawLightWithRange(g.x, g.y, g.z, col[1], col[2], col[3], (cat.GlowRange or 1.2) + 0.0, (cat.GlowIntensity or 1.5) + 0.0)
                        end
                        if texReady and BE.Enabled ~= false then drawBeam(lamp.key, lamp.ped, pos, dir, cam, now, air, BE.Color or col, cat) end
                        if glareOn and lamp.ped ~= me then
                            local gv = glareFrom(lamp, cat, pos, dir, cam, camFwd, night, now)
                            if gv > target then
                                target = gv
                                local onScreen, sx, sy = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
                                spot = onScreen and { x = sx, y = sy } or nil
                            end
                        end
                    end
                end
            end
            local speed = target > glare and (GL.Rise or 12.0) or (GL.Fall or 3.0)
            glare = glare + (target - glare) * math.min(1.0, dt * speed)
            if target > 0.0 then glareSpot = spot end
            if glare < 0.01 then glare, glareSpot = 0.0, nil end
            drawGlare(L.Color or { 255, 247, 235 })
            Wait(0)
        end
        rendering = false
    end)
end

CreateThread(function()
    while true do
        local me = PlayerPedId()
        -- stroboscope arrêté : arme changée / rangée, véhicule, mort
        if strobe then
            local weapon = u32(GetSelectedPedWeapon(me))
            if weapon ~= strobeWeapon or IsPedInAnyVehicle(me, true) or IsEntityDead(me)
                or (OVERRIDE and RPWeapons.lampOn ~= weapon) then setStrobe(false) end -- lampe éteinte (E) : arrêté
        end
        local list = {}
        local mine = lampOf(me, true)
        if mine then list[1] = mine end
        if L.Others ~= false then
            local myPos, range = GetEntityCoords(me), L.OthersRange or 80.0
            for _, player in ipairs(GetActivePlayers()) do
                local ped = GetPlayerPed(player)
                if ped ~= me and ped ~= 0 and #(GetEntityCoords(ped) - myPos) < range then
                    local lamp = lampOf(ped, false, GetPlayerServerId(player))
                    if lamp then list[#list + 1] = lamp end
                end
            end
        end
        -- lampes de CartoonFlashlight (soi et joueurs autour) : faisceau visible, lueur, éblouissement
        if CARTOON.Enabled ~= false and CARTOON.Resource and GetResourceState(CARTOON.Resource) == 'started' then
            local ok, cl = pcall(function() return exports[CARTOON.Resource]:lamps() end)
            if ok and type(cl) == 'table' then
                local myPos, range = GetEntityCoords(me), L.OthersRange or 80.0
                for _, c in ipairs(cl) do
                    if type(c) == 'table' and c.ped and c.torch and DoesEntityExist(c.torch)
                        and (c.ped == me or (L.Others ~= false and #(GetEntityCoords(c.ped) - myPos) < range)) then
                        list[#list + 1] = { ped = c.ped, torch = c.torch, cartoon = true, hand = true, strobe = c.strobe == true,
                            key = 'c' .. tostring(c.torch), yaw = c.yaw, pitch = c.pitch, ahead = c.ahead, hz = c.hz, duty = c.duty,
                            cat = setmetatable({ Range = c.range, Radius = c.radius }, { __index = OBJ }) }
                    end
                end
            end
        end
        lamps = list
        RPWeapons.lamps = list -- pour les tests
        if #list > 0 then render() end
        Wait(L.CheckMs or 250)
    end
end)

-- =========================================================================
-- RÉGLAGE DE L'EMPLACEMENT DE LA LAMPE (admins : /editflashlight, comme /editspotlight) : arme en main, un POINT
-- ROUGE montre le départ de la lumière, curseurs X / Y / Z (axes de l'arme) en haut au milieu ; « Enregistrer pour
-- tous » : gardé par le serveur pour tous les joueurs (même après un redémarrage) ; la ligne pour config.lua
-- (Flashlight.Positions) s'affiche aussi. Le serveur vérifie la permission (Flashlight.EditAce).
-- =========================================================================
local editing = nil -- { weapon, entity }

local function notify(text)
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started' and pcall(function() exports[chat]:addPrivate({ title = 'Lampe', text = text }) end) then return end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent('rp_weaponscontrol:notify', function(text) notify(tostring(text)) end)

local function configLine(weapon, p)
    return ('[0x%08X] = { %.3f, %.3f, %.3f },'):format(weapon, p.x, p.y, p.z)
end

local function closeEdit()
    if not editing then return end
    editing = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'flashEdit', data = { on = false } })
end

RegisterNetEvent('rp_weaponscontrol:editFlash', function()
    if editing then return end
    local ped = PlayerPedId()
    local weapon = u32(GetSelectedPedWeapon(ped))
    local entity = GetCurrentPedWeaponEntityIndex(ped)
    if weapon == 0 or weapon == UNARMED or not entity or entity == 0 or not DoesEntityExist(entity) then
        return notify('Prenez en main l\'arme (ou la lampe) dont il faut régler la lampe, puis refaites /' .. (FL.EditCommand or 'editflashlight') .. '.')
    end
    if cartoon(weapon) then return notify('Lampe de CartoonFlashlight : sa position dépend de ses animations (son script).') end
    local p = positionOf(weapon)
    if not p then
        local pos = beamOf(ped, HANDLIGHTS[weapon] == true)
        p = GetOffsetFromEntityGivenWorldCoords(entity, pos.x, pos.y, pos.z)
    end
    editing = { weapon = weapon, entity = entity }
    mine[weapon] = vector3(p.x, p.y, p.z)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'flashEdit', data = { on = true, x = p.x, y = p.y, z = p.z, weapon = ('0x%08X'):format(weapon),
        line = configLine(weapon, mine[weapon]) } })
    CreateThread(function()
        local col = L.Color or { 255, 247, 235 }
        local cat = HANDLIGHTS[weapon] and OBJ or WPN
        while editing do
            local me = PlayerPedId()
            if u32(GetSelectedPedWeapon(me)) ~= editing.weapon or not DoesEntityExist(editing.entity) then closeEdit() break end
            local pos, dir = beamOf(me, HANDLIGHTS[weapon] == true)
            DrawMarker(28, pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.012, 0.012, 0.012, 255, 20, 20, 235,
                false, false, 2, false, nil, nil, false)
            DrawLine(pos.x, pos.y, pos.z, pos.x + dir.x * 0.5, pos.y + dir.y * 0.5, pos.z + dir.z * 0.5, 255, 40, 40, 220)
            if RPWeapons.lampOn ~= weapon and not IsFlashLightOn(me) then -- lampe éteinte : lumière d'essai
                drawLight(pos, dir, col, (cat.Range or 40.0) + 0.0, (cat.Intensity or 8.0) + 0.0, cat, SHADOW_BASE + 90)
            end
            Wait(0)
        end
    end)
end)

RegisterNUICallback('flashOffset', function(d, cb)
    cb({ ok = true })
    if not (editing and type(d) == 'table') then return end
    local function c(v) return math.max(-0.8, math.min(0.8, tonumber(v) or 0.0)) + 0.0 end
    mine[editing.weapon] = vector3(c(d.x), c(d.y), c(d.z))
    SendNUIMessage({ action = 'flashLine', data = { line = configLine(editing.weapon, mine[editing.weapon]) } })
end)

RegisterNUICallback('flashSave', function(_, cb)
    cb({ ok = true })
    if not editing then return end
    local p = mine[editing.weapon]
    TriggerServerEvent('rp_weaponscontrol:saveFlashPos', editing.weapon, { p.x, p.y, p.z })
end)

RegisterNUICallback('flashReset', function(_, cb)
    cb({ ok = true })
    if not editing then return end
    local weapon = editing.weapon
    mine[weapon] = nil
    TriggerServerEvent('rp_weaponscontrol:saveFlashPos', weapon, false)
    closeEdit()
    notify('Emplacement de la lampe remis par défaut (pour tous). Le réglage du config.lua, s\'il y en a un, reste.')
end)

RegisterNUICallback('flashDone', function(_, cb)
    cb({ ok = true })
    if not editing then return end
    local weapon = editing.weapon
    local line = configLine(weapon, mine[weapon])
    closeEdit()
    print('[rp_weaponscontrol] ligne pour config.lua (Flashlight.Positions) : ' .. line)
    notify('Réglage gardé pour vous (jusqu\'à la déconnexion) ; « Enregistrer pour tous » pour tout le monde. Ligne pour config.lua (aussi dans F8) : ' .. line)
end)

RPWeapons.flashPositions = { positionOf = positionOf, mine = mine, saved = function() return saved end, editing = function() return editing end }

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if editing then SetNuiFocus(false, false) end
    if strobe then LocalPlayer.state:set('rpStrobe', false, true) end
    if OVERRIDE then
        -- la lampe du script disparaît : la lampe du jeu reprend, allumée si la nôtre l'était
        if RPWeapons.lampOn then SetFlashLightEnabled(PlayerPedId(), true) end
        LocalPlayer.state:set('rpLamp', false, true)
    elseif strobe then
        SetFlashLightEnabled(PlayerPedId(), true)
    end
end)
