--[[
    RP STAGES - logique (client ET serveur, sans aucun native : testable seule)
    -----------------------------------------------------------------------------
    État d'un véhicule : { stage = 0..3, taLeft, taRight, steadyBurn = booléens, siren = booléen,
                           prev = stage d'avant le passage automatique au stage 3 (sirène) ou nil, v = n° de version }
]]

RPStagesLogic = {}
local L = RPStagesLogic

L.SECONDARY = { 'taLeft', 'taRight', 'steadyBurn' }
L.SECONDARY_LABEL = { taLeft = 'Traffic Advisor Left', taRight = 'Traffic Advisor Right', steadyBurn = 'Steady Burn' }

local function bool(v, default)
    if v == nil then return default end
    return v == true
end

--- Extras d'une table de configuration -> { [id entier] = booléen } (entrées invalides ignorées)
local function extrasOf(t)
    local out = {}
    if type(t) ~= 'table' then return out end
    for k, v in pairs(t) do
        local id = math.tointeger(tonumber(k))
        if id and id >= 0 and id <= 20 and type(v) == 'boolean' then out[id] = v end
    end
    return out
end

--- Configuration d'un véhicule, vérifiée et complétée (valeurs par défaut) ; retourne (config, avertissements)
function L.normalize(spawn, raw)
    local warn = {}
    local cfg = { spawn = spawn, label = type(raw.label) == 'string' and raw.label or spawn, stages = {}, secondary = {},
        taExclusive = bool(raw.taExclusive, true), controlled = {} }
    for n = 1, 3 do
        local s = type(raw.stages) == 'table' and raw.stages[n]
        if s then
            if type(s) ~= 'table' then warn[#warn + 1] = ('stage %d ignoré (doit être une table)'):format(n)
            else cfg.stages[n] = { extras = extrasOf(s.extras), lights = bool(s.lights, true), label = s.label or ('Stage ' .. n) } end
        end
    end
    if type(raw.stages) == 'table' then
        for k in pairs(raw.stages) do
            if not (k == 1 or k == 2 or k == 3) then warn[#warn + 1] = ('stage « %s » ignoré (1, 2 ou 3 seulement)'):format(tostring(k)) end
        end
    end
    if type(raw.secondary) == 'table' then
        for k, s in pairs(raw.secondary) do
            if not L.SECONDARY_LABEL[k] then
                warn[#warn + 1] = ('stage secondaire « %s » ignoré (taLeft, taRight ou steadyBurn)'):format(tostring(k))
            elseif type(s) == 'table' then
                cfg.secondary[k] = { extras = extrasOf(s.extras), lights = bool(s.lights, true), overlay = bool(s.overlay, true),
                    label = s.label or L.SECONDARY_LABEL[k] }
            end
        end
    end
    cfg.off = type(raw.off) == 'table' and extrasOf(raw.off) or nil
    -- extras pilotés par ce script (tous ceux cités) : les autres extras du véhicule ne sont jamais touchés
    local function add(t) for id in pairs(t) do cfg.controlled[id] = true end end
    for _, s in pairs(cfg.stages) do add(s.extras) end
    for _, s in pairs(cfg.secondary) do add(s.extras) end
    if cfg.off then add(cfg.off) end
    if not next(cfg.stages) and not next(cfg.secondary) then warn[#warn + 1] = 'aucun stage ni stage secondaire' end
    return cfg, warn
end

function L.newState() return { stage = 0, taLeft = false, taRight = false, steadyBurn = false, siren = false, prev = nil, v = 0 } end

local function copy(st)
    local c = {}
    for k, v in pairs(st or {}) do c[k] = v end
    return c
end

--- La sirène demande le stage 3 (seulement si le véhicule a un stage 3)
function L.sirenNeedsStage3(cfg) return cfg.stages[3] ~= nil end

local function sirenOff(st)
    st.siren = false
    if st.prev ~= nil then st.stage, st.prev = st.prev, nil end
end

local function dropNonOverlay(cfg, st)
    for _, k in ipairs(L.SECONDARY) do
        if st[k] and cfg.secondary[k] and not cfg.secondary[k].overlay then st[k] = false end
    end
end

--- Met le véhicule au stage n (0 = aucun) : hors stage 3, la sirène est coupée
local function setStage(cfg, st, n)
    st.stage, st.prev = n, nil
    if n ~= 3 and st.siren and L.sirenNeedsStage3(cfg) then st.siren = false end -- sirène : stage 3 seulement
    if n > 0 then dropNonOverlay(cfg, st) end
end

--- Stages principaux du véhicule, dans l'ordre (ex. { 1, 2, 3 } ou { 1, 3 })
function L.stageList(cfg)
    local list = {}
    for n = 1, 3 do if cfg.stages[n] then list[#list + 1] = n end end
    return list
end

--- TOUCHE UNIQUE des stages principaux : passe au stage suivant du véhicule (aucun -> 1 -> 2 -> 3 -> aucun ; seulement
--- les stages configurés). `cycleOff` false : après le dernier stage, retour au premier (sans passer par « aucun »).
--- Au stage 3 automatique (sirène), la touche passe au stage suivant comme d'habitude (et coupe donc la sirène).
function L.cycleStage(cfg, state, cycleOff)
    local st = copy(state)
    local list = L.stageList(cfg)
    if #list == 0 then return st, false end
    local nextStage = list[1]
    for i, n in ipairs(list) do
        if n == st.stage then
            nextStage = list[i + 1] or (cycleOff == false and list[1] or 0)
            break
        end
    end
    if nextStage == st.stage then return st, false end
    setStage(cfg, st, nextStage)
    return st, true
end

--- Touche d'un stage secondaire (taLeft, taRight, steadyBurn) : allume / éteint
function L.pressSecondary(cfg, state, key)
    local st = copy(state)
    local s = cfg.secondary[key]
    if not s then return st, false end
    st[key] = not st[key]
    if st[key] then
        if cfg.taExclusive and (key == 'taLeft' or key == 'taRight') then
            st[key == 'taLeft' and 'taRight' or 'taLeft'] = false
        end
        if not s.overlay then -- ne se superpose pas : le stage principal (et la sirène) s'éteignent
            st.stage, st.prev = 0, nil
            if L.sirenNeedsStage3(cfg) then st.siren = false end
        end
    end
    return st, true
end

--- Touche « sirène » : allume / coupe. Allumée hors stage 3 : passage automatique au stage 3 (stage d'avant gardé) ;
--- coupée : retour au stage d'avant le passage automatique.
function L.pressSiren(cfg, state)
    local st = copy(state)
    if st.siren then sirenOff(st) return st, true end
    if L.sirenNeedsStage3(cfg) and st.stage ~= 3 then
        st.prev = st.stage
        st.stage = 3
        dropNonOverlay(cfg, st)
    end
    st.siren = true
    return st, true
end

--- État reçu (client -> serveur) : rendu cohérent avec la configuration
function L.sanitize(cfg, data)
    local st = L.newState()
    if type(data) ~= 'table' then return st end
    local n = math.tointeger(tonumber(data.stage) or 0) or 0
    st.stage = cfg.stages[n] and n or 0
    for _, k in ipairs(L.SECONDARY) do st[k] = data[k] == true and cfg.secondary[k] ~= nil end
    if cfg.taExclusive and st.taLeft and st.taRight then st.taRight = false end
    if st.stage > 0 then
        for _, k in ipairs(L.SECONDARY) do
            if st[k] and not cfg.secondary[k].overlay then st[k] = false end
        end
    end
    st.siren = data.siren == true and (not L.sirenNeedsStage3(cfg) or st.stage == 3)
    local prev = math.tointeger(tonumber(data.prev))
    st.prev = (st.siren and st.stage == 3 and prev and prev >= 0 and prev <= 2 and (prev == 0 or cfg.stages[prev])) and prev or nil
    return st
end

--- Extras voulus : { [id] = allumé } pour tous les extras pilotés
function L.extras(cfg, st)
    local out = {}
    for id in pairs(cfg.controlled) do out[id] = false end
    if cfg.off and (st.stage or 0) == 0 then for id, on in pairs(cfg.off) do out[id] = on end end
    local stage = cfg.stages[st.stage or 0]
    if stage then for id, on in pairs(stage.extras) do out[id] = on end end
    for _, k in ipairs(L.SECONDARY) do
        if st[k] and cfg.secondary[k] then for id, on in pairs(cfg.secondary[k].extras) do out[id] = on end end
    end
    return out
end

--- Gyrophares du jeu (SetVehicleSiren) : sirène, ou un stage / stage secondaire actif qui les demande
function L.lights(cfg, st)
    if st.siren then return true end
    local stage = cfg.stages[st.stage or 0]
    if stage and stage.lights then return true end
    for _, k in ipairs(L.SECONDARY) do
        if st[k] and cfg.secondary[k] and cfg.secondary[k].lights then return true end
    end
    return false
end

--- Hachage d'un spawn code (joaat), comme GetHashKey, en entier non signé : indépendant du client / serveur
function L.joaat(s)
    s = tostring(s):lower()
    local h = 0
    for i = 1, #s do
        h = (h + s:byte(i)) & 0xFFFFFFFF
        h = (h + (h << 10)) & 0xFFFFFFFF
        h = h ~ (h >> 6)
    end
    h = (h + (h << 3)) & 0xFFFFFFFF
    h = h ~ (h >> 11)
    h = (h + (h << 15)) & 0xFFFFFFFF
    return h
end
function L.unsigned(h) return (math.tointeger(h) or 0) & 0xFFFFFFFF end

--- Toutes les configurations : { byHash = { [hash] = cfg }, warnings = { texte } }
function L.load(config)
    local byHash, warnings = {}, {}
    for spawn, raw in pairs(type(config) == 'table' and config.Vehicles or {}) do
        if type(raw) == 'table' and type(spawn) == 'string' then
            local cfg, warn = L.normalize(spawn, raw)
            byHash[L.joaat(spawn)] = cfg
            for _, w in ipairs(warn) do warnings[#warnings + 1] = ('%s : %s'):format(spawn, w) end
        end
    end
    return { byHash = byHash, warnings = warnings }
end
