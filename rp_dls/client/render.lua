--[[
    RP DLS - gyrophares dessinés (client)
    -------------------------------------
    Sur FiveM, un véhicule n'a qu'un réglage de gyrophares : celui de son carcols (le jeu ne sait pas en changer
    pendant la partie, DLS solo le fait en modifiant la mémoire du jeu avec RagePluginHook). Les autres stages
    sont donc DESSINÉS ici, à partir des <Sirens> du XML de DLS, exactement comme le jeu le ferait :
      - chaque ampoule = l'os "sirenN" du véhicule (N = n° de l'<Item> dans le XML) ;
      - allumée selon la séquence de 32 temps (flashiness ou rotation) au rythme de sequencerBpm, × multiples ;
      - halo de la couleur du XML sur l'ampoule (atténué quand elle regarde de l'autre côté, masqué derrière un
        mur) et éclairage de la route / des murs (light = true) ;
      - Traffic Advisor et Steady Burn remplacent la séquence de leurs ampoules, comme dans DLS.
    Horloge commune (heure du réseau) : tous les joueurs voient les mêmes éclats au même moment.
    Performance : rien n'est fait sans véhicule à gyrophares dessinés à portée ; positions des ampoules lues une
    fois par véhicule ; visibilité vérifiée 5 fois par seconde.
]]

local Config = DLSConfig
local R = Config.Render
local TXD, GLOW = 'rp_dls', 'glow'

DLSC.active = DLSC.active or {} -- [véhicule] = { model, state, plan } (tenu à jour par client/vehicles.lua)

CreateThread(function()
    local txd = CreateRuntimeTxd(TXD)
    CreateRuntimeTextureFromImage(txd, GLOW, 'img/glow.png')
end)

-- =========================================================================
-- PLAN : ampoules à dessiner pour un modèle et un état (gardé en cache)
-- =========================================================================
local plans = {}
local bonesOf -- (plus bas)

local function referenceSetting(model, s)
    return model.stages[s] or model.stages[3] or model.stages[1] or model.stages[2] or model.stages[4] or model.stages[5]
        or model.base
end

--- Ampoule à dessiner : gyrophare `src` du XML / carcols, au rythme de `setting`, séquence `seq`.
--- `o` : réglages d'un mode DLS v2 (intensity, color, delta…). Direction de l'ampoule : flashiness.delta
--- (rotation.start pour un gyrophare tournant), 0 = vers l'avant, pi/2 = vers la gauche.
local function bulb(src, setting, seq, mult, forced, o)
    o = o or {}
    local rotate = src.rotate and not forced
    local color = o.color or src.color
    local intensity = o.intensity or src.intensity
    return {
        r = color[1], g = color[2], b = color[3],
        seq = seq, mult = math.max(1, math.floor(mult or 1)),
        beat = 60000.0 / math.max(1.0, setting.bpm * ((setting.time or 1.0) > 0 and setting.time or 1.0)),
        range = setting.falloff * R.LightRange,
        intensity = intensity * R.LightIntensity,
        light = src.light,
        size = src.corona.size, glow = math.max(0.4, math.min(1.0, src.corona.intensity / 40.0)),
        face = rotate and src.rotation.start or (o.delta or src.flashiness.delta), rotate = rotate,
        spin = rotate and (src.rotation.speed * (src.rotation.dir and 1 or -1)) or 0.0,
        -- Feu de travail (takedown, alley… intensité forte) : projecteur dans la direction de l'ampoule
        work = intensity >= (R.WorkLightIntensity or 5),
    }
end
DLSC.bulb = bulb

local PARK_LEFT, PARK_RIGHT = DLS.sequence('11100000111000001110000011100000'), DLS.sequence('00001110000011100000111000001110')

--- { native = gyrophares d'origine allumés, lights = { [n° d'ampoule] = ampoule } ou nil }
--- `park` (DLS v1) : véhicule arrêté, sans sirène : motif de stationnement (côté gauche / côté droit)
function DLSC.plan(model, state, vehicle, park)
    if not state then return { native = false } end
    local s = state.bo and 0 or state.s
    local ta = (not state.bo and model.ta and state.ta) or 0
    local sb = (not state.bo and model.steady and state.sb) or false
    local parkSrc = park and s > 0 and vehicle and (model.stages[s] or model.base) or nil
    local key = ('%s|%d|%d|%d|%d|%s|%s'):format(model.name, DLS.version or 0, s, ta, state.tap or 0, tostring(sb), tostring(parkSrc ~= nil))
    if plans[key] then return plans[key] end

    local plan = { native = false }
    local base
    if parkSrc then
        local list = bonesOf(vehicle)
        local Park = Config.Park or {}
        local setting = { bpm = Park.Bpm or 300, time = 1.0, falloff = parkSrc.falloff }
        local lights = {}
        for i, L in pairs(parkSrc.lights) do
            local detail = L.rotate and L.rotation or L.flashiness
            local off = list[i]
            if detail.seq ~= 0 and off then
                lights[i] = bulb(L, setting, off.x < 0 and PARK_LEFT or PARK_RIGHT, 1, true)
            end
        end
        plan.park = true
        plan.lights = lights
        s = 0 -- (le motif de stationnement remplace le stage ; TA / Steady Burn s'ajoutent par-dessus)
    end
    if s > 0 then
        -- Stage d'origine : laissé au jeu, sauf si TA / Steady Burn doivent modifier des ampoules et que le XML
        -- décrit ce stage (sinon TA / Steady Burn sont dessinés par-dessus les gyrophares d'origine)
        if model.native[s] and not ((ta > 0 or sb) and model.stages[s]) then
            plan.native = true
        else
            base = model.stages[s]
        end
    end

    local lights = plan.lights or {}
    if base then
        for i, L in pairs(base.lights) do
            local detail = L.rotate and L.rotation or L.flashiness
            lights[i] = bulb(L, base, detail.seq, detail.mult, false)
        end
    end
    local ref = base or parkSrc or referenceSetting(model, s)
    if ref and ta > 0 then
        local pattern = DLS.taPattern(model, state.tap ~= 0 and state.tap or nil)
        if pattern then
            local seqs = pattern[model.ta.type][model.ta.divergeOnly and 'diverge' or DLS.TA_DIRECTIONS[ta]]
            for _, seg in ipairs(DLS.TA_SEGMENTS[model.ta.type]) do
                for _, i in ipairs(model.ta.segments[seg] or {}) do
                    local src = ref.lights[i]
                    if src then lights[i] = bulb(src, ref, seqs[seg] or 0, 1, true) end
                end
            end
        end
    end
    if ref and sb then
        for _, i in ipairs(model.steady.sirens) do
            local src = ref.lights[i]
            if src then lights[i] = bulb(src, ref, model.steady.seq, 1, true) end
        end
    end
    plan.lights = next(lights) and lights or nil
    plans[key] = plan
    return plan
end

-- =========================================================================
-- AMPOULES : position de l'os "sirenN" par rapport au véhicule (lue une fois)
-- =========================================================================
local bones = {} -- [véhicule] = { model, list = { [n] = vector3 local } }

function bonesOf(vehicle)
    local model = GetEntityModel(vehicle)
    local entry = bones[vehicle]
    if entry and entry.model == model then return entry.list end
    local list = {}
    for n = 1, DLS.MAX_SIRENS do
        local index = GetEntityBoneIndexByName(vehicle, 'siren' .. n)
        if index ~= -1 then
            local world = GetWorldPositionOfEntityBone(vehicle, index)
            list[n] = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z)
        end
    end
    bones[vehicle] = { model = model, list = list }
    return list
end
DLSC.bonesOf = bonesOf

function DLSC.forgetBones(vehicle) bones[vehicle] = nil end

--- Ampoule allumée à l'instant t (ms) ?
local function lit(L, t)
    local beat = t / L.beat
    local index = math.floor(beat) % 32
    if (L.seq >> (31 - index)) & 1 == 0 then return false end
    if L.mult <= 1 then return true end
    return math.floor((beat % 1.0) * L.mult * 2) % 2 == 0
end

-- =========================================================================
-- VISIBILITÉ : chaque ampoule cachée (toit, carrosserie, boîtier de la rampe, mur…) n'a pas de halo ; vérifiée
-- par des tests de ligne de vue caméra -> ampoule, quelques-uns à chaque passage (10 fois par seconde)
-- =========================================================================
local hidden = {}  -- [véhicule] = { [n° d'ampoule] = true }
local probes = {}  -- tests en cours : { handle, vehicle, n }
local cursor = {}  -- [véhicule] = dernière ampoule testée (tests à tour de rôle)
local PROBES_PER_PASS = 24

local function bulbWorld(vehicle, off)
    return GetOffsetFromEntityInWorldCoords(vehicle, off.x, off.y, off.z)
end

CreateThread(function()
    while true do
        if R.Occlusion and next(DLSC.active) then
            local cam = GetFinalRenderedCamCoord()
            -- Résultats des tests précédents
            local pending = {}
            for _, p in ipairs(probes) do
                local status, hit = GetShapeTestResult(p.handle)
                if status == 1 then
                    pending[#pending + 1] = p
                elseif DoesEntityExist(p.vehicle) then
                    hidden[p.vehicle] = hidden[p.vehicle] or {}
                    hidden[p.vehicle][p.n] = status == 2 and (hit == 1 or hit == true) or nil
                end
            end
            probes = pending
            -- Nouveaux tests, à tour de rôle sur les ampoules de chaque véhicule
            local budget = PROBES_PER_PASS - #probes
            for vehicle, entry in pairs(DLSC.active) do
                if budget <= 0 then break end
                if entry.plan.lights and DoesEntityExist(vehicle) then
                    local list = bonesOf(vehicle)
                    local n = cursor[vehicle]
                    if n ~= nil and entry.plan.lights[n] == nil then n = nil end -- (stage changé depuis)
                    for _ = 1, DLS.MAX_SIRENS do
                        if budget <= 0 then break end
                        n = next(entry.plan.lights, n)
                        if n == nil then n = next(entry.plan.lights) end
                        local off = n and list[n]
                        if off then
                            local at = bulbWorld(vehicle, off)
                            local back = cam - at
                            local len = #back
                            if len > 0.5 then
                                -- (arrêt 25 cm avant l'ampoule : son propre verre ne la cache pas)
                                local stop = at + back * (0.25 / len)
                                probes[#probes + 1] = {
                                    handle = StartShapeTestLosProbe(cam.x, cam.y, cam.z, stop.x, stop.y, stop.z, 19, 0, 7),
                                    vehicle = vehicle, n = n,
                                }
                                budget = budget - 1
                            end
                        end
                        if n == cursor[vehicle] then break end
                    end
                    cursor[vehicle] = n
                end
            end
            for vehicle in pairs(hidden) do
                if not DLSC.active[vehicle] then hidden[vehicle], cursor[vehicle] = nil, nil end
            end
            Wait(100)
        else
            hidden, probes, cursor = {}, {}, {}
            Wait(500)
        end
    end
end)

-- =========================================================================
-- DESSIN (chaque image, seulement s'il y a des gyrophares dessinés à portée)
-- =========================================================================
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

local function drawVehicle(vehicle, plan, t, cam, budget, aspect, firstPersonOwn)
    local list = bonesOf(vehicle)
    local forward, right, up, pos = GetEntityMatrix(vehicle) -- (ordre de la native : avant, droite, haut, position)
    local corona = not firstPersonOwn
    local masked = hidden[vehicle] or {}
    local Lens = R.Lens or {}
    for n, L in pairs(plan.lights) do
        local off = list[n]
        if off and lit(L, t) then
            local world = pos + right * off.x + forward * off.y + up * off.z
            local angle = L.face
            if L.rotate then angle = angle + (t / 1000.0) * L.spin * math.pi end
            local dx, dy = -math.sin(angle), math.cos(angle)
            local dir = right * dx + forward * dy
            local toCam = cam - world
            local dist = #toCam

            -- Le boîtier de la rampe s'éclaire autour de l'ampoule (petite lumière au cœur du verre), comme les
            -- gyrophares du jeu, même quand le halo n'est pas visible
            if Lens.Enabled ~= false and budget.lens > 0 and dist < R.LightDistance then
                budget.lens = budget.lens - 1
                local at = world + dir * (Lens.Push or 0.06)
                DrawLightWithRange(at.x, at.y, at.z, L.r, L.g, L.b, Lens.Range or 0.7, Lens.Intensity or 10.0)
            end

            if corona and not masked[n] and L.size > 0 and dist < R.Distance then
                local onScreen, sx, sy = GetScreenCoordFromWorldCoord(world.x, world.y, world.z)
                if onScreen then
                    local alpha = R.CoronaAlpha * L.glow
                    if R.FacingFade and dist > 0.01 then
                        -- Halo seulement du côté où l'ampoule éclaire (rien de profil ni de dos)
                        local facing = (dir.x * toCam.x + dir.y * toCam.y + dir.z * toCam.z) / dist
                        alpha = alpha * clamp(facing / 0.35, 0.0, 1.0)
                    end
                    if alpha > 4 then
                        local h = clamp(R.CoronaSize * L.size * 10.0 / math.max(dist, 0.5), R.CoronaMin, R.CoronaMax)
                        DrawSprite(TXD, GLOW, sx, sy, h / aspect, h, 0.0, L.r, L.g, L.b, math.floor(alpha))
                        if R.CoronaCore then
                            DrawSprite(TXD, GLOW, sx, sy, h * 0.35 / aspect, h * 0.35, 0.0, 255, 255, 255, math.floor(alpha))
                        end
                    end
                end
            end

            if L.light and budget.left > 0 and dist < R.LightDistance then
                budget.left = budget.left - 1
                if L.work then
                    -- Takedown / alley : projecteur vers l'avant / le côté, un peu vers le sol
                    local S = R.Work or {}
                    DrawSpotLight(world.x, world.y, world.z, dir.x, dir.y, (S.Tilt or -0.12), L.r, L.g, L.b,
                        S.Distance or 45.0, (S.Brightness or 2.0) * L.intensity / R.LightIntensity, S.Hardness or 2.0,
                        S.Radius or 25.0, S.Falloff or 40.0)
                else
                    local at = world + dir * R.LightPush
                    DrawLightWithRange(at.x, at.y, at.z, L.r, L.g, L.b, L.range, L.intensity)
                end
            end
        end
    end
end

-- Takedown / alley des véhicules sans DLS v2 (DLS v1, véhicules d'urgence) : projecteurs blancs depuis le haut
-- du véhicule (gyrophares les plus hauts, sinon le toit), vers l'avant et vers les côtés
local tops = {} -- [véhicule] = { model, x, y, z } : point de départ des projecteurs (repère du véhicule)

local function topOf(vehicle)
    local model = GetEntityModel(vehicle)
    local t = tops[vehicle]
    if t and t.model == model then return t end
    local maxZ, list = nil, bonesOf(vehicle)
    for _, off in pairs(list) do
        if not maxZ or off.z > maxZ then maxZ = off.z end
    end
    t = { model = model }
    if maxZ then
        local sx, sy, n = 0.0, 0.0, 0
        for _, off in pairs(list) do
            if off.z >= maxZ - 0.15 then sx, sy, n = sx + off.x, sy + off.y, n + 1 end
        end
        t.x, t.y, t.z = sx / n, sy / n, maxZ
    else
        local _, max = GetModelDimensions(model)
        t.x, t.y, t.z = 0.0, max.y * 0.2, max.z
    end
    tops[vehicle] = t
    return t
end

local function drawScene(vehicle, state, cam, budget, aspect)
    local S = Config.Scene or {}
    local forward, right, up, pos = GetEntityMatrix(vehicle) -- (ordre de la native : avant, droite, haut, position)
    local top = topOf(vehicle)
    local function spot(lx, ly, dx, dy)
        if budget.left <= 0 then return end
        budget.left = budget.left - 1
        local at = pos + right * (top.x + lx) + forward * (top.y + ly) + up * (top.z + 0.05)
        local dir = right * dx + forward * dy
        DrawSpotLight(at.x, at.y, at.z, dir.x, dir.y, S.Tilt or -0.12, 255, 255, 245, S.Distance or 45.0,
            S.Brightness or 14.0, S.Hardness or 2.0, S.Radius or 25.0, S.Falloff or 40.0)
        local onScreen, sx, sy = GetScreenCoordFromWorldCoord(at.x, at.y, at.z)
        local toCam = cam - at
        local dist = #toCam
        if onScreen and not hidden[vehicle] and dist < R.Distance then
            local facing = (dir.x * toCam.x + dir.y * toCam.y) / math.max(dist, 0.01)
            local alpha = math.floor(R.CoronaAlpha * clamp((facing + 0.2) / 0.6, 0.0, 1.0))
            if alpha > 4 then
                local h = clamp(R.CoronaSize * 1.4 * 10.0 / math.max(dist, 0.5), R.CoronaMin, R.CoronaMax)
                DrawSprite(TXD, GLOW, sx, sy, h / aspect, h, 0.0, 255, 255, 245, alpha)
            end
        end
    end
    if (state.td or 0) > 0 then
        spot(-0.35, 0.1, 0.0, 1.0)
        spot(0.35, 0.1, 0.0, 1.0)
    end
    local al = state.al or 0
    if al & 1 ~= 0 then spot(-0.45, 0.0, -1.0, 0.08) end
    if al & 2 ~= 0 then spot(0.45, 0.0, 1.0, 0.08) end
end

function DLSC.forgetTop(vehicle) tops[vehicle] = nil end

CreateThread(function()
    while true do
        local any = false
        for _, entry in pairs(DLSC.active) do
            if entry.plan.lights or entry.scene then any = true break end
        end
        if not any then
            Wait(250)
        else
            local t = GetNetworkTime()
            if t == 0 then t = GetGameTimer() end
            local cam = GetFinalRenderedCamCoord()
            local aspect = GetAspectRatio(false)
            local budget = { left = R.MaxLights, lens = R.MaxLensLights or 64 }
            local own = GetVehiclePedIsIn(PlayerPedId(), false)
            local firstPerson = R.HideOwnFirstPerson and GetFollowVehicleCamViewMode() == 4
            for vehicle, entry in pairs(DLSC.active) do
                if DoesEntityExist(vehicle) then
                    if entry.plan.lights then
                        drawVehicle(vehicle, entry.plan, t, cam, budget, aspect, firstPerson and vehicle == own)
                    end
                    if entry.scene then drawScene(vehicle, entry.state, cam, budget, aspect) end
                end
            end
            Wait(0)
        end
    end
end)

-- =========================================================================
-- DIAGNOSTIC : setr dls_debug 1 -> numéro de chaque ampoule (os sirenN) sur le véhicule le plus proche
-- (pour remplir les segments L / C / R… du Traffic Advisor ou les Sirens du Steady Burn)
-- =========================================================================
CreateThread(function()
    while true do
        if GetConvarInt('dls_debug', 0) ~= 1 then
            Wait(1000)
        else
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle == 0 then vehicle = GetClosestVehicle(GetEntityCoords(ped), 8.0, 0, 70) end
            if vehicle ~= 0 then
                for n, off in pairs(bonesOf(vehicle)) do
                    local world = GetOffsetFromEntityInWorldCoords(vehicle, off.x, off.y, off.z)
                    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(world.x, world.y, world.z + 0.05)
                    if onScreen then
                        SetTextFont(4)
                        SetTextScale(0.0, 0.32)
                        SetTextColour(255, 255, 255, 230)
                        SetTextOutline()
                        SetTextCentre(true)
                        BeginTextCommandDisplayText('STRING')
                        AddTextComponentSubstringPlayerName(tostring(n))
                        EndTextCommandDisplayText(sx, sy)
                    end
                end
            end
            Wait(0)
        end
    end
end)
