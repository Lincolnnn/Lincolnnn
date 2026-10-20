--[[
    RP DLS - lecture des fichiers DLS v2 (partagé client / serveur)
    ---------------------------------------------------------------
    Format DLS v2 : <Model vehicles="modèle1,modèle2"> (un fichier pour plusieurs modèles) :
      <Audio>          AudioModes (nom -> <Sound soundbank="" soundset="">, Requirements) et AudioControlGroups
                       (groupe "Siren" : un ton par entrée ; groupe "Horn" : air horn maintenu, exclusif)
      <Modes>          chaque Mode part des gyrophares du carcols du véhicule (apply_default_siren_settings) ou
                       de gyrophares éteints, puis change des <Sequences> (Item id="1,2" sequence="0101…") et des
                       <SirenSettings> (sequencerBpm, sirens/Item id="" : intensity, flashiness…) ; il est allumé
                       par un groupe de commandes ou par ses <Triggers> (vitesse, heure, météo, portières,
                       clignotants, freinage, sirène, autre mode…), sous réserve de ses <Requirements>
      <ControlGroups>  Stages, TA, Cruise, Takedown, Left Alley, Right Alley… (liste de modes au choix)
    Les modes actifs sont appliqués dans l'ordre du fichier (le dernier l'emporte), comme dans DLS v2.
    Le calcul des modes actifs (déclencheurs) se fait chez chaque client : client/dlsv2.lua.
]]

DLS2 = {}
local X = DLSXml

local function bool(v, default)
    if v == nil then return default end
    v = tostring(v):lower()
    if v == 'true' or v == '1' then return true end
    if v == 'false' or v == '0' then return false end
    return default
end

local function ids(text)
    local list = {}
    for n in tostring(text or ''):gmatch('%d+') do list[#list + 1] = tonumber(n) end
    return list
end

local function names(text)
    local list = {}
    for name in tostring(text or ''):gmatch('[^,]+') do
        name = name:match('^%s*(.-)%s*$')
        if name ~= '' then list[#list + 1] = name end
    end
    return list
end
DLS2.names = names

-- =========================================================================
-- CONDITIONS (Triggers / Requirements) : arbre compilé une fois
-- =========================================================================
local CONDITIONS = {
    any = true, all = true, audiomode = true, lightmode = true, speed = true, time = true, weather = true,
    doors = true, lightemissive = true, braking = true, driver = true, vehicleowner = true,
}

local function compile(node)
    local kind = node.name:lower()
    local c = {
        kind = CONDITIONS[kind] and kind or 'unknown', tag = node.name, a = node.attrs,
        delay = tonumber(node.attrs.delay_time), stay = tonumber(node.attrs.stay_on_time),
    }
    if kind == 'any' or kind == 'all' then
        c.children = {}
        for _, child in ipairs(node.children) do c.children[#c.children + 1] = compile(child) end
    elseif kind == 'weather' then
        c.types = {}
        for _, t in ipairs(X.children(X.child(node, 'AllowedConditions'), 'Type')) do
            c.types[#c.types + 1] = t.text:upper()
        end
    end
    return c
end

--- <Triggers> : l'une des conditions suffit ; <Requirements> : toutes sont nécessaires
local function conditions(node, kind)
    if not node or #node.children == 0 then return nil end
    local root = { kind = kind, children = {}, a = {} }
    for _, child in ipairs(node.children) do root.children[#root.children + 1] = compile(child) end
    return root
end

-- =========================================================================
-- MODES
-- =========================================================================
--- <SirenSettings> d'un mode : sequencerBpm et réglages par gyrophare (seuls les champs présents)
local function readSettings(node)
    if not node then return nil end
    local s = { bpm = tonumber(X.value(node, 'sequencerBpm')), sirens = {} }
    for _, item in ipairs(X.children(X.child(node, 'sirens'), 'Item')) do
        local o = {}
        o.intensity = tonumber(X.value(item, 'intensity'))
        local f = X.child(item, 'flashiness')
        if f then
            o.sync = bool(X.value(f, 'syncToBpm'), nil)
            o.speed = tonumber(X.value(f, 'speed'))
            o.multiples = tonumber(X.value(f, 'multiples'))
            local delta = X.value(f, 'delta')
            if delta then o.delta = tonumber(delta) end
        end
        local col = X.value(item, 'color')
        if col then
            local n = tonumber(tostring(col):gsub('^0[xX]', ''), 16)
            if n then o.color = { (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF } end
        end
        for _, id in ipairs(ids(item.attrs.id)) do s.sirens[id] = o end
    end
    if not s.bpm and not next(s.sirens) then return nil end
    return s
end

local function readMode(node)
    local mode = {
        name = node.attrs.name or '?',
        default = bool(node.attrs.apply_default_siren_settings, false),
        triggers = conditions(X.child(node, 'Triggers'), 'any'),
        requirements = conditions(X.child(node, 'Requirements'), 'all'),
        settings = readSettings(X.child(node, 'SirenSettings')),
        seqs = {},
        yield = bool(X.value(node, 'Yield') or (X.child(node, 'Yield') and X.child(node, 'Yield').attrs.enabled), false),
    }
    for _, item in ipairs(X.children(X.child(node, 'Sequences'), 'Item')) do
        local seq = DLS.sequence(item.attrs.sequence)
        for _, id in ipairs(ids(item.attrs.id)) do mode.seqs[id] = seq end
    end
    mode.lname = mode.name:lower()
    return mode
end

-- Rôle d'un groupe de commandes d'après son nom (touches et panneau de rp_dls)
local function groupRole(name)
    name = name:lower()
    if name:find('stage') then return 'stages' end
    if name == 'ta' or name:find('traffic') or name:find('advis') then return 'ta' end
    if name:find('cruise') or name:find('steady') then return 'cruise' end
    if name:find('takedown') or name:find('front') then return 'takedown' end
    if name:find('alley') or name:find('scene') then
        if name:find('left') or name:find('gauche') then return 'alleyLeft' end
        if name:find('right') or name:find('droite') then return 'alleyRight' end
    end
    return 'other'
end

-- Direction du TA d'après le nom du mode (1 gauche, 2 diverge, 3 droite, 4 warn)
local function taDirection(name)
    name = name:lower()
    if name:find('left') then return 1 end
    if name:find('diverge') or name:find('center') or name:find('centre') then return 2 end
    if name:find('right') then return 3 end
    if name:find('warn') or name:find('flash') then return 4 end
    return nil
end

-- =========================================================================
-- AUDIO
-- =========================================================================
local function readAudio(node)
    local audio = { modes = {}, tones = {}, horn = nil, hornInterrupts = false }
    for _, m in ipairs(X.children(X.child(node, 'AudioModes'), 'AudioMode')) do
        local sound = X.child(m, 'Sound')
        if m.attrs.name and sound then
            audio.modes[m.attrs.name] = {
                name = m.attrs.name,
                sound = sound.text,
                bank = sound.attrs.soundbank,
                soundset = sound.attrs.soundset,
                requirements = conditions(X.child(m, 'Requirements'), 'all'),
            }
        end
    end
    for _, g in ipairs(X.children(X.child(node, 'AudioControlGroups'), 'AudioControlGroup')) do
        local gname = (g.attrs.name or ''):lower()
        local entries = X.children(X.child(g, 'AudioModes'), 'AudioMode')
        if gname:find('horn') then
            for _, e in ipairs(entries) do
                if e.attrs.hold and not audio.horn then
                    audio.horn = names(e.text)
                elseif not e.attrs.hold and not e.attrs.toggle and #names(e.text) > 0 then
                    -- Entrée sans touche dans un groupe exclusif : ces sons se taisent pendant l'air horn
                    if bool(g.attrs.exclusive, false) then audio.hornInterrupts = true end
                end
            end
        elseif #audio.tones == 0 then
            -- Premier autre groupe (« Siren ») : un ton par entrée
            for _, e in ipairs(entries) do
                if #audio.tones < 4 and #names(e.text) > 0 then audio.tones[#audio.tones + 1] = names(e.text) end
            end
        end
    end
    return audio
end

--- Fichier DLS v2 ? (<Model vehicles=""> ou balise <Modes>)
function DLS2.is(root)
    local m = X.child(root, 'Model')
    return m ~= nil and (m.attrs.vehicles ~= nil or X.child(m, 'Modes') ~= nil)
end

--- Lit un fichier DLS v2. Retourne le modèle partagé (sans gyrophares du carcols) et la liste des véhicules
function DLS2.read(root, fileName)
    local m = X.child(root, 'Model')
    local model = {
        v2 = true, file = fileName, modes = {}, byName = {}, groups = {},
        stages = {}, native = {}, available = {}, has = {},
        preset = 'none', sirenKill = false,
    }
    for _, node in ipairs(X.children(X.child(m, 'Modes'), 'Mode')) do
        local mode = readMode(node)
        model.modes[#model.modes + 1] = mode
        mode.index = #model.modes
        model.byName[mode.lname] = mode
    end

    -- Groupes de commandes
    model.roles = {}
    for _, g in ipairs(X.children(X.child(m, 'ControlGroups'), 'ControlGroup')) do
        local group = { name = g.attrs.name or '?', toggle = g.attrs.toggle ~= nil, modes = {} }
        for _, entry in ipairs(X.children(X.child(g, 'Modes'), 'Mode')) do
            local mode = model.byName[entry.text:lower()]
            if mode then group.modes[#group.modes + 1] = mode.index end
        end
        group.role = groupRole(group.name)
        if #group.modes > 0 then
            model.groups[#model.groups + 1] = group
            if group.role ~= 'other' and not model.roles[group.role] then model.roles[group.role] = group end
        end
    end

    -- Stages (touche du jeu, J, pavé numérique) : modes du groupe « Stages », 5 au plus
    local stages = model.roles.stages
    if stages then
        for i, index in ipairs(stages.modes) do
            if i > 5 then break end
            model.available[i], model.has[i] = i, true
            local mode = model.modes[index]
            -- Stage = gyrophares d'origine du carcols, sans rien de changé : affiché par le jeu
            if mode.default and not next(mode.seqs) and not mode.settings then model.native[i] = true end
        end
    end
    -- Traffic Advisor : directions d'après les noms des modes
    local ta = model.roles.ta
    if ta then
        model.ta = { v2 = true, type = 'v2', divergeOnly = false, autoEnable = {}, autoDisable = {}, modes = {} }
        for i, index in ipairs(ta.modes) do
            local dir = taDirection(model.modes[index].name) or (i <= 4 and i or nil)
            if dir and not model.ta.modes[dir] then model.ta.modes[dir] = index end
        end
        local count = 0
        for _ in pairs(model.ta.modes) do count = count + 1 end
        model.ta.divergeOnly = count == 1 and model.ta.modes[2] ~= nil
        if count == 0 then model.ta = nil end
    end
    model.cruise = model.roles.cruise and #model.roles.cruise.modes or 0
    model.takedown = model.roles.takedown and #model.roles.takedown.modes or 0
    model.alley = { left = model.roles.alleyLeft ~= nil, right = model.roles.alleyRight ~= nil }

    -- Sons
    model.audio = readAudio(X.child(m, 'Audio'))
    model.tones = {}
    for n, list in ipairs(model.audio.tones) do model.tones[n] = table.concat(list, ',') end
    if model.audio.horn then model.tones[5] = table.concat(model.audio.horn, ',') end
    model.hornInterrupts = model.audio.hornInterrupts

    return model, names(m.attrs.vehicles)
end

--- Copie du modèle partagé pour un véhicule précis (son nom et ses gyrophares du carcols)
function DLS2.forVehicle(shared, vehicleName, base)
    local model = setmetatable({ name = vehicleName, base = base }, { __index = shared })
    return model
end
