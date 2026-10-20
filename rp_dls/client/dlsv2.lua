--[[
    RP DLS - moteur DLS v2 (client)
    -------------------------------
    Pour chaque véhicule DLS v2 à portée, chaque client calcule lui-même :
      - les sons actifs : ton choisi (groupe « Siren » : ses AudioModes, ex. Siren2 + Siren1d = deux sirènes),
        air horn maintenu (groupe « Horn », qui fait taire la sirène s'il est exclusif), selon leurs Requirements ;
      - les modes actifs : ceux choisis par les groupes de commandes (état "dls" du véhicule : stage, TA,
        cruise, takedown, alley) + ceux allumés par leurs Triggers (vitesse, heure, météo, portières,
        clignotants, freinage, sirène, autre mode…), sous réserve de leurs Requirements ;
      - les gyrophares : carcols du véhicule (mode apply_default_siren_settings) ou tout éteint, puis chaque mode
        actif dans l'ordre du fichier (séquences, intensité, bpm…). Gyrophares d'origine laissés au jeu tant que
        les modes ne font qu'en ajouter (ex. stage 3 + clignotants sur des gyrophares éteints dans le carcols).
    Les déclencheurs ne dépendent que de l'état du véhicule (vitesse, portières, clignotants…), le même pour tous
    les joueurs : seul ce qui est choisi aux touches passe par le réseau.
]]

local mem = {} -- [véhicule] = { nodes = { [condition] = minuteurs }, prev = { [n° de mode] = true }, speed, at, brake }

local function memOf(vehicle)
    local m = mem[vehicle]
    if not m then
        m = { nodes = {}, prev = {}, prevNames = {} }
        mem[vehicle] = m
    end
    return m
end

function DLSC.forgetV2(vehicle) mem[vehicle] = nil end

local function yes(v, default)
    if v == nil then return default end
    v = tostring(v):lower()
    return v == 'true' or v == '1'
end

-- =========================================================================
-- CONDITIONS
-- =========================================================================
local DOORS = { frontleft = 0, frontright = 1, rearleft = 2, rearright = 3, hood = 4, bonnet = 4, trunk = 5, boot = 5 }
local SPEED_UNITS = { mps = 1.0, kph = 3.6, kmh = 3.6, mph = 2.236936 }

local function minutes(text)
    local h, m = tostring(text or ''):match('(%d+):(%d+)')
    return h and (tonumber(h) * 60 + tonumber(m)) or nil
end

local function inTime(a)
    local from, to = minutes(a.start), minutes(a['end'])
    if not from or not to then return false end
    local now = GetClockHours() * 60 + GetClockMinutes()
    if from <= to then return now >= from and now < to end
    return now >= from or now < to -- passe minuit
end

local function weatherIs(types)
    local current = GetPrevWeatherTypeHashName()
    for _, t in ipairs(types) do
        if GetHashKey(t) == current then return true end
    end
    return false
end

local function braking(vehicle, m)
    -- Conducteur de ce véhicule : touche de frein ; sinon (autres joueurs) : forte décélération
    local driver = GetPedInVehicleSeat(vehicle, -1)
    if driver == PlayerPedId() then
        return DLSC.bool(IsControlPressed(0, 72)) and GetEntitySpeed(vehicle) > 0.5
    end
    return (m.decel or 0) > 2.0
end

local eval

--- Délais : delay_time (vraie depuis assez longtemps), stay_on_time (reste vraie un moment après)
local function timed(c, raw, ctx)
    if not c.delay and not c.stay then return raw end
    local t = ctx.mem.nodes[c]
    if not t then
        t = {}
        ctx.mem.nodes[c] = t
    end
    local now = ctx.now
    if raw then
        t.since = t.since or now
        if c.delay and now - t.since < c.delay then
            return c.stay ~= nil and t.last ~= nil and now - t.last < c.stay
        end
        t.last = now
        return true
    end
    t.since = nil
    return c.stay ~= nil and t.last ~= nil and now - t.last < c.stay
end

local LEAVES = {}

function LEAVES.any(c, ctx)
    for _, child in ipairs(c.children) do
        if eval(child, ctx) then return true end
    end
    return false
end

function LEAVES.all(c, ctx)
    for _, child in ipairs(c.children) do
        if not eval(child, ctx) then return false end
    end
    return true
end

function LEAVES.audiomode(c, ctx)
    return (ctx.audio[c.a.name or ''] == true) == yes(c.a.active, true)
end

function LEAVES.lightmode(c, ctx)
    return (ctx.lights[(c.a.name or ''):lower()] == true) == yes(c.a.active, true)
end

function LEAVES.speed(c, ctx)
    local v = GetEntitySpeed(ctx.vehicle) * (SPEED_UNITS[(c.a.units or 'mps'):lower()] or 1.0)
    local inclusive = yes(c.a.inclusive, true)
    local max, min = tonumber(c.a.max), tonumber(c.a.min)
    if max and (inclusive and v > max or not inclusive and v >= max) then return false end
    if min and (inclusive and v < min or not inclusive and v <= min) then return false end
    return true
end

function LEAVES.time(c) return inTime(c.a) end

function LEAVES.weather(c) return weatherIs(c.types) end

function LEAVES.doors(c, ctx)
    local door = DOORS[(c.a.door or ''):lower():gsub('[%s_]', '')]
    if not door then return false end
    local open = GetVehicleDoorAngleRatio(ctx.vehicle, door) > 0.05
    return open == ((c.a.state or 'open'):lower() == 'open')
end

function LEAVES.lightemissive(c, ctx)
    local id = (c.a.id or ''):lower()
    local on
    if id:find('^indicator') then
        local mask = GetVehicleIndicatorLights(ctx.vehicle) or 0
        local bit = (id:find('_l') and 1) or (id:find('_r') and 2) or 3
        on = mask & bit ~= 0
    elseif id:find('brake') then
        on = braking(ctx.vehicle, ctx.mem)
    else
        on = false
    end
    return on == yes(c.a.status, true)
end

function LEAVES.braking(c, ctx)
    return braking(ctx.vehicle, ctx.mem) == yes(c.a.status, true)
end

function LEAVES.driver(c, ctx)
    local has = not DLSC.bool(IsVehicleSeatFree(ctx.vehicle, -1))
    return has == yes(c.a.has_driver, true)
end

function LEAVES.vehicleowner(c, ctx)
    local driver = GetPedInVehicleSeat(ctx.vehicle, -1)
    local player = driver ~= 0 and DLSC.bool(IsPedAPlayer(driver))
    return player == yes(c.a.is_player_vehicle, true)
end

local warned = {}
function LEAVES.unknown(c)
    if not warned[c.tag] then
        warned[c.tag] = true
        print(('^3[rp_dls] Condition DLS v2 <%s> pas encore prise en charge : considérée fausse.^0'):format(tostring(c.tag)))
    end
    return false
end

eval = function(c, ctx)
    return timed(c, LEAVES[c.kind](c, ctx), ctx)
end

-- =========================================================================
-- SONS ACTIFS
-- =========================================================================
--- Noms des AudioModes actifs : { [nom] = true }
local function audioModes(vehicle, model, state, m, now)
    local wanted = {}
    local horn = state.horn or state.tone == 5
    local list = state.tone and state.tone >= 1 and state.tone <= 4 and model.audio.tones[state.tone]
    if list and not (horn and model.hornInterrupts) then
        for _, name in ipairs(list) do wanted[name] = true end
    end
    if horn and model.audio.horn then
        for _, name in ipairs(model.audio.horn) do wanted[name] = true end
    end
    local active = {}
    local ctx = { vehicle = vehicle, model = model, audio = wanted, lights = m.prevNames, mem = m, now = now }
    for name in pairs(wanted) do
        local mode = model.audio.modes[name]
        if mode and (not mode.requirements or eval(mode.requirements, ctx)) then active[name] = true end
    end
    return active
end

-- =========================================================================
-- MODES ACTIFS
-- =========================================================================
local function selectedModes(model, state)
    local selected = {}
    if state.bo then return selected end
    local roles = model.roles
    local function pick(group, n)
        if group and n and n > 0 and group.modes[n] then selected[group.modes[n]] = true end
    end
    pick(roles.stages, state.s)
    if model.ta and state.ta and state.ta > 0 and model.ta.modes[state.ta] then selected[model.ta.modes[state.ta]] = true end
    pick(roles.cruise, state.cr)
    pick(roles.takedown, state.td)
    if (state.al or 0) & 1 ~= 0 then pick(roles.alleyLeft, 1) end
    if (state.al or 0) & 2 ~= 0 then pick(roles.alleyRight, 1) end
    return selected
end

--- Modes et sons actifs d'un véhicule DLS v2 : liste des n° de modes (ordre du fichier), { [son] = true }
function DLSC.v2Active(vehicle, model, state)
    local m = memOf(vehicle)
    local now = GetGameTimer()
    -- Décélération (freinage vu par les autres joueurs)
    local speed = GetEntitySpeed(vehicle)
    if m.at and now > m.at then m.decel = (m.speed - speed) / ((now - m.at) / 1000.0) end
    m.speed, m.at = speed, now

    local audio = audioModes(vehicle, model, state, m, now)
    local selected = selectedModes(model, state)
    local lights = {}
    for index in pairs(selected) do lights[model.modes[index].lname] = true end
    for name in pairs(m.prevNames) do lights[name] = true end
    local ctx = { vehicle = vehicle, model = model, audio = audio, lights = lights, mem = m, now = now }

    local active, names, set = {}, {}, {}
    for _, mode in ipairs(model.modes) do
        local on = selected[mode.index] == true
        if not on and mode.triggers and not state.bo then on = eval(mode.triggers, ctx) end
        if on and mode.requirements then on = eval(mode.requirements, ctx) end
        if on then
            active[#active + 1] = mode.index
            names[mode.lname] = true
            set[mode.index] = true
        end
    end
    m.prev, m.prevNames = set, names
    return active, audio
end

-- =========================================================================
-- GYROPHARES : carcols + modes actifs -> plan dessiné (ou gyrophares d'origine)
-- =========================================================================
local plans = {}

--- { native, lights, modes = { noms } } pour ces modes actifs. `stage` : stage choisi (ExtraStages : ce stage
--- est affiché par les gyrophares du jeu, les extras cachant les ampoules qui n'en font pas partie)
function DLSC.v2Plan(model, active, stage)
    local es = model.extraStages
    local stageMode = es and stage and stage > 0 and model.roles.stages and model.roles.stages.modes[stage] or nil
    local hidden = stageMode and DLS.hiddenSirens(model, stage) or {}
    local key = model.name .. '|' .. (DLS.version or 0) .. '|' .. tostring(stageMode and stage) .. '|' .. table.concat(active, ',')
    if plans[key] then return plans[key] end
    local names = {}
    for _, index in ipairs(active) do names[#names + 1] = model.modes[index].name end

    local anyDefault = false
    for _, index in ipairs(active) do
        if model.modes[index].default or index == stageMode then anyDefault = true end
    end
    local base = model.base
    local plan = { native = false, modes = names }
    if #active == 0 then
        plans[key] = plan
        return plan
    end
    if not base then
        -- Pas de carcols lu : seuls les modes « gyrophares d'origine » peuvent s'afficher
        plan.native = anyDefault
        plans[key] = plan
        return plan
    end

    local bpm, bpmChanged = base.bpm, false
    local final = {}
    for i, L in pairs(base.lights) do
        local detail = L.rotate and L.rotation or L.flashiness
        if hidden[i] then
            final[i] = { orig = 0, seq = 0, mult = detail.mult, src = L } -- (ampoule cachée par son extra)
        else
            final[i] = { orig = detail.seq, seq = anyDefault and detail.seq or 0, mult = detail.mult, src = L }
        end
    end
    for _, index in ipairs(active) do
        local mode = model.modes[index]
        if index == stageMode then
            mode = { seqs = {} } -- stage par extras : gyrophares du jeu tels quels
        end
        if mode.settings then
            if mode.settings.bpm then bpm, bpmChanged = mode.settings.bpm, true end
            for id, o in pairs(mode.settings.sirens) do
                local f = final[id]
                if f then
                    f.over = f.over or {}
                    for k, v in pairs(o) do f.over[k] = v end
                    f.changed = true
                end
            end
        end
        for id, seq in pairs(mode.seqs) do
            local f = final[id]
            if f then
                f.seq, f.changed = seq, true
            end
        end
    end

    -- Gyrophares d'origine possibles : un mode « par défaut » actif, même rythme, et les modes n'ont touché
    -- que des gyrophares éteints dans le carcols (ils sont alors dessinés par-dessus)
    local native = anyDefault and not bpmChanged
    if native then
        for _, f in pairs(final) do
            if f.changed and f.orig ~= 0 and (f.seq ~= f.orig or f.over) then
                native = false
                break
            end
        end
    end

    local setting = { bpm = bpm, time = base.time, falloff = base.falloff }
    local lights = {}
    for i, f in pairs(final) do
        local draw = f.seq ~= 0 and (not native or (f.changed and f.orig == 0))
        if draw then
            local o = f.over or {}
            local mult = o.multiples or f.mult
            -- Non synchronisé au bpm et allumé en continu : feu fixe (takedown, alley, cruise…)
            if o.sync == false and f.seq == 0xFFFFFFFF then mult = 1 end
            lights[i] = DLSC.bulb(f.src, setting, f.seq, mult, false, o)
        end
    end
    plan.native = native
    plan.lights = next(lights) and lights or nil
    plans[key] = plan
    return plan
end
