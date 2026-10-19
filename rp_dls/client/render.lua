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

local function referenceSetting(model, s)
    return model.stages[s] or model.stages[3] or model.stages[1] or model.stages[2] or model.stages[4] or model.stages[5]
end

local function bulb(src, setting, seq, mult, forced)
    local rotate = src.rotate and not forced
    return {
        r = src.color[1], g = src.color[2], b = src.color[3],
        seq = seq, mult = mult,
        beat = 60000.0 / math.max(1.0, setting.bpm * (setting.time > 0 and setting.time or 1.0)),
        range = setting.falloff * R.LightRange,
        intensity = src.intensity * R.LightIntensity,
        light = src.light,
        size = src.corona.size, glow = math.max(0.4, math.min(1.0, src.corona.intensity / 40.0)),
        face = src.rotation.start, rotate = rotate,
        spin = rotate and (src.rotation.speed * (src.rotation.dir and 1 or -1)) or 0.0,
    }
end

--- { native = gyrophares d'origine allumés, lights = { [n° d'ampoule] = ampoule } ou nil }
function DLSC.plan(model, state)
    if not state then return { native = false } end
    local s = state.bo and 0 or state.s
    local ta = (not state.bo and model.ta and state.ta) or 0
    local sb = (not state.bo and model.steady and state.sb) or false
    local key = ('%s|%d|%d|%d|%s'):format(model.name, s, ta, state.tap or 0, tostring(sb))
    if plans[key] then return plans[key] end

    local plan = { native = false }
    local base
    if s > 0 then
        -- Stage d'origine : laissé au jeu, sauf si TA / Steady Burn doivent modifier des ampoules et que le XML
        -- décrit ce stage (sinon TA / Steady Burn sont dessinés par-dessus les gyrophares d'origine)
        if model.native[s] and not ((ta > 0 or sb) and model.stages[s]) then
            plan.native = true
        else
            base = model.stages[s]
        end
    end

    local lights = {}
    if base then
        for i, L in pairs(base.lights) do
            local detail = L.rotate and L.rotation or L.flashiness
            lights[i] = bulb(L, base, detail.seq, detail.mult, false)
        end
    end
    local ref = base or referenceSetting(model, s)
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

local function bonesOf(vehicle)
    local model = GetEntityModel(vehicle)
    local entry = bones[vehicle]
    if entry and entry.model == model then return entry.list end
    local list = {}
    for n = 1, 20 do
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
-- VISIBILITÉ : véhicule caché par un mur / un bâtiment (halos masqués), vérifiée 5 fois par seconde
-- =========================================================================
local hidden = {}  -- [véhicule] = true
local probes = {}  -- [véhicule] = test de ligne de vue en cours

CreateThread(function()
    while true do
        if R.Occlusion and next(DLSC.active) then
            local cam = GetFinalRenderedCamCoord()
            for vehicle in pairs(probes) do
                local status, hit = GetShapeTestResult(probes[vehicle])
                if status ~= 1 then
                    hidden[vehicle] = status == 2 and (hit == 1 or hit == true) or nil
                    probes[vehicle] = nil
                end
            end
            for vehicle, entry in pairs(DLSC.active) do
                if entry.plan.lights and not probes[vehicle] and DoesEntityExist(vehicle) then
                    local top = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, 1.0)
                    -- monde et objets (1 + 16), sans le véhicule lui-même
                    probes[vehicle] = StartShapeTestLosProbe(cam.x, cam.y, cam.z, top.x, top.y, top.z, 17, vehicle, 7)
                end
            end
            Wait(200)
        else
            hidden, probes = {}, {}
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
    local right, forward, up, pos = GetEntityMatrix(vehicle)
    local corona = not firstPersonOwn and not hidden[vehicle]
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

            if corona and dist < R.Distance then
                local onScreen, sx, sy = GetScreenCoordFromWorldCoord(world.x, world.y, world.z)
                if onScreen then
                    local alpha = R.CoronaAlpha * L.glow
                    if R.FacingFade and dist > 0.01 then
                        local facing = (dir.x * toCam.x + dir.y * toCam.y + dir.z * toCam.z) / dist
                        alpha = alpha * clamp((facing + 0.35) / 0.65, 0.0, 1.0)
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
                local at = world + dir * R.LightPush
                DrawLightWithRange(at.x, at.y, at.z, L.r, L.g, L.b, L.range, L.intensity)
            end
        end
    end
end

CreateThread(function()
    while true do
        local any = false
        for _, entry in pairs(DLSC.active) do
            if entry.plan.lights then any = true break end
        end
        if not any then
            Wait(250)
        else
            local t = GetNetworkTime()
            if t == 0 then t = GetGameTimer() end
            local cam = GetFinalRenderedCamCoord()
            local aspect = GetAspectRatio(false)
            local budget = { left = R.MaxLights }
            local own = GetVehiclePedIsIn(PlayerPedId(), false)
            local firstPerson = R.HideOwnFirstPerson and GetFollowVehicleCamViewMode() == 4
            for vehicle, entry in pairs(DLSC.active) do
                if entry.plan.lights and DoesEntityExist(vehicle) then
                    drawVehicle(vehicle, entry.plan, t, cam, budget, aspect, firstPerson and vehicle == own)
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
