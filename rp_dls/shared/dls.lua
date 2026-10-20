--[[
    RP DLS - lecture des fichiers de véhicules DLS (partagé client / serveur)
    -------------------------------------------------------------------------
    Mêmes fichiers que DLS (Dynamic Lighting System, GTA V solo) : un .xml par modèle dans dls/ (nom du
    fichier = nom du modèle), groupes de Traffic Advisor dans dls/trafficadvisory/.
      <StageSettings>    Stage1Enabled… CustomStage2Enabled, GetStage3FromCarcols
      <SpecialModes>     PresetSirenOnLeaveVehicle, WailSetup, SteadyBurn (Pattern, Sirens)
      <SoundSettings>    Tone1…Tone4, Horn, AirHornInterruptsSiren, SirenKillOverride
      <TrafficAdvisory>  Type (three/four/five/six), DivergeOnly, Auto(En|Dis)ableStages,
                         DefaultEnabledDirection, TAgroup, DefaultTApattern, L EL CL C CR ER R (n° de gyrophares)
      <Sirens>           Stage1, Stage2, Stage3, CustomStage1, CustomStage2 : chacun est un <Item> de sirènes
                         de carcols.meta (sequencerBpm, sirens/Item : flashiness, rotation, corona, color…)
    Numéros de stages : 1, 2, 3, 4 (custom 1), 5 (custom 2), comme les réglages de DLS.
    Numéros de tons : 1, 2, 3 (Warning), 4 (Warning 2), 5 (Horn).
]]

DLS = DLS or {}
DLS.models = {}      -- [hash du modèle] = modèle lu
DLS.taGroups = {}    -- [nom du groupe] = { patterns = { { name, three = { left = { L = n, … }, … }, … } } }

local X = DLSXml
local Config = DLSConfig

DLS.STAGE_NAMES = { [1] = 'stage1', [2] = 'stage2', [3] = 'stage3', [4] = 'custom1', [5] = 'custom2' }
local STAGE_TAGS = { 'Stage1', 'Stage2', 'Stage3', 'CustomStage1', 'CustomStage2' }
local STAGE_ENABLED = { 'Stage1Enabled', 'Stage2Enabled', 'Stage3Enabled', 'CustomStage1Enabled', 'CustomStage2Enabled' }
DLS.TA_DIRECTIONS = { 'left', 'diverge', 'right', 'warn' } -- 1..4 (0 : éteint)
DLS.TA_SEGMENTS = {
    three = { 'L', 'C', 'R' },
    four = { 'L', 'CL', 'CR', 'R' },
    five = { 'L', 'CL', 'C', 'CR', 'R' },
    six = { 'L', 'EL', 'CL', 'CR', 'ER', 'R' },
}
local ALL_SEGMENTS = { 'L', 'EL', 'CL', 'C', 'CR', 'ER', 'R' }

-- ---- Petits convertisseurs ----
local function bool(v, default)
    if v == nil then return default end
    v = tostring(v):lower()
    if v == 'true' or v == '1' then return true end
    if v == 'false' or v == '0' then return false end
    return default
end

local function num(v, default)
    return tonumber(v) or default
end

--- Liste "1, 2,3" -> { 1, 2, 3 }
local function numbers(v)
    local list = {}
    if not v then return list end
    for n in tostring(v):gmatch('%d+') do list[#list + 1] = tonumber(n) end
    return list
end

--- Séquence de 32 temps : nombre (4294967295) ou texte binaire ("0011…") -> entier 32 bits
local function sequence(v)
    if v == nil then return 0 end
    v = tostring(v):gsub('%s', '')
    if #v == 32 and not v:find('[^01]') then return tonumber(v, 2) end
    local n = tonumber(v)
    if not n then return 0 end
    return math.floor(n) & 0xFFFFFFFF
end
DLS.sequence = sequence

--- Couleur carcols "0xFFFF0A0A" (AARRGGBB) -> { r, g, b }
local function color(v)
    local n = tonumber(tostring(v or ''):gsub('^0[xX]', ''), 16) or 0xFFFFFFFF
    return { (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF }
end

-- ---- Un stage (un <Item> de sirènes de carcols) ----
local function readDetail(node)
    return {
        delta = num(X.value(node, 'delta'), 0.0),
        start = num(X.value(node, 'start'), 0.0),
        speed = num(X.value(node, 'speed'), 1.0),
        seq = sequence(X.value(node, 'sequencer')),
        mult = math.max(1, math.floor(num(X.value(node, 'multiples'), 1))),
        dir = bool(X.value(node, 'direction'), true),
        sync = bool(X.value(node, 'syncToBpm'), true),
    }
end

local function readSetting(node)
    if not node then return nil end
    local setting = {
        bpm = num(X.value(node, 'sequencerBpm'), 100),
        time = num(X.value(node, 'timeMultiplier'), 1.0),
        falloff = num(X.value(node, 'lightFalloffMax'), 10.0),
        exponent = num(X.value(node, 'lightFalloffExponent'), 10.0),
        inner = num(X.value(node, 'lightInnerConeAngle'), 2.0),
        outer = num(X.value(node, 'lightOuterConeAngle'), 70.0),
        offset = num(X.value(node, 'lightOffset'), 0.0),
        lights = {},
    }
    for i, item in ipairs(X.children(X.child(node, 'sirens'), 'Item')) do
        if i > 20 then break end
        local corona = X.child(item, 'corona')
        setting.lights[i] = {
            rotation = readDetail(X.child(item, 'rotation')),
            flashiness = readDetail(X.child(item, 'flashiness')),
            corona = {
                intensity = num(X.value(corona, 'intensity'), 50.0),
                size = num(X.value(corona, 'size'), 1.0),
                pull = num(X.value(corona, 'pull'), 0.2),
            },
            color = color(X.value(item, 'color')),
            intensity = num(X.value(item, 'intensity'), 1.0),
            rotate = bool(X.value(item, 'rotate'), false),
            scale = bool(X.value(item, 'scale'), true),
            flash = bool(X.value(item, 'flash'), true),
            light = bool(X.value(item, 'light'), true),
            spot = bool(X.value(item, 'spotLight'), true),
        }
    end
    return setting
end

-- ---- Un groupe de Traffic Advisor (dls/trafficadvisory/<nom>.xml, format TAgroup de DLS) ----
local function readTaGroup(root)
    local group = { patterns = {}, byName = {} }
    for _, p in ipairs(X.children(X.child(root, 'TAgroup') or root, 'TApattern')) do
        local pattern = { name = p.attrs.name or ('motif ' .. (#group.patterns + 1)) }
        for count in pairs(DLS.TA_SEGMENTS) do
            local countNode = X.child(p, count)
            pattern[count] = {}
            for _, direction in ipairs(DLS.TA_DIRECTIONS) do
                local d = X.child(countNode, direction)
                local seqs = {}
                for _, seg in ipairs(ALL_SEGMENTS) do seqs[seg] = sequence(X.value(d, seg)) end
                pattern[count][direction] = seqs
            end
        end
        group.patterns[#group.patterns + 1] = pattern
        group.byName[pattern.name:lower()] = #group.patterns
    end
    return group
end

-- ---- Un véhicule ----
local function readModel(root, name)
    local m = X.child(root, 'Model')
    if not m then return nil, 'balise <Model> absente' end

    local stageSettings = X.child(m, 'StageSettings')
    local special = X.child(m, 'SpecialModes')
    local sounds = X.child(m, 'SoundSettings')
    local ta = X.child(m, 'TrafficAdvisory')
    local sirens = X.child(m, 'Sirens')

    local model = { name = name, stages = {}, native = {}, available = {} }

    -- Stages : présents dans <Sirens> (et pas désactivés par <StageSettings>)
    for n, tag in ipairs(STAGE_TAGS) do
        if bool(X.value(stageSettings, STAGE_ENABLED[n]), true) then
            model.stages[n] = readSetting(X.child(sirens, tag))
        end
    end
    -- Stage 3 du carcols : gyrophares d'origine du véhicule (seul stage que FiveM sait afficher tout seul)
    local fromCarcols = bool(X.value(stageSettings, 'GetStage3FromCarcols'), false) or Config.Stage3FromCarcols
    if fromCarcols and bool(X.value(stageSettings, 'Stage3Enabled'), true) then
        model.native[3] = true
    end

    -- Sons
    model.tones = {}
    for n = 1, 4 do
        local tone = X.value(sounds, 'Tone' .. n)
        model.tones[n] = tone and tone ~= '' and tone or nil
    end
    local horn = X.value(sounds, 'Horn')
    model.tones[5] = horn and horn ~= '' and horn or Config.DefaultHorn
    model.hornInterrupts = bool(X.value(sounds, 'AirHornInterruptsSiren'), false)
    model.sirenKill = bool(X.value(sounds, 'SirenKillOverride'), false)

    -- Modes spéciaux
    model.preset = (X.value(special, 'PresetSirenOnLeaveVehicle') or 'none'):lower()
    local wail = X.child(special, 'WailSetup')
    model.wail = bool(X.value(wail, 'WailSetupEnabled'), false) and {
        light = num(X.value(wail, 'WailLightStage'), nil),
        tone = num(X.value(wail, 'WailSirenTone'), nil),
    } or nil
    if model.wail and not (model.wail.light and model.wail.tone) then model.wail = nil end
    local sb = X.child(special, 'SteadyBurn')
    if bool(X.value(sb, 'SteadyBurnEnabled'), false) then
        local pattern = X.value(sb, 'Pattern')
        model.steady = {
            seq = pattern and sequence(pattern) or 0xFFFFFFFF,
            sirens = numbers(X.value(sb, 'Sirens')),
        }
        if #model.steady.sirens == 0 then model.steady = nil end
    end

    -- Traffic Advisor
    local taType = (X.value(ta, 'Type') or 'off'):lower()
    if DLS.TA_SEGMENTS[taType] then
        model.ta = {
            type = taType,
            divergeOnly = bool(X.value(ta, 'DivergeOnly'), false),
            autoEnable = numbers(X.value(ta, 'AutoEnableStages')),
            autoDisable = numbers(X.value(ta, 'AutoDisableStages')),
            default = (X.value(ta, 'DefaultEnabledDirection') or 'diverge'):lower(),
            group = (X.value(ta, 'TAgroup') or 'default'):lower(),
            pattern = (X.value(ta, 'DefaultTApattern') or 'default'):lower(),
            segments = {},
        }
        for _, seg in ipairs(ALL_SEGMENTS) do model.ta.segments[seg] = numbers(X.value(ta, seg)) end
    end

    -- Stages disponibles, dans l'ordre (cycle de la touche « stage suivant »)
    for n = 1, 5 do
        if model.stages[n] or model.native[n] then model.available[#model.available + 1] = n end
    end
    model.has = {}
    for _, n in ipairs(model.available) do model.has[n] = true end
    return model
end

--- Stage n disponible sur ce modèle (0 : éteint, toujours possible)
function DLS.hasStage(model, n)
    return n == 0 or (model and model.has[n]) == true
end

--- Charge les groupes de Traffic Advisor et les véhicules de la configuration
function DLS.load()
    local resource = GetCurrentResourceName()
    local side = IsDuplicityVersion() and 'serveur' or 'client'

    for _, name in ipairs(Config.TrafficAdvisoryGroups or { 'default' }) do
        local text = LoadResourceFile(resource, ('dls/trafficadvisory/%s.xml'):format(name))
        local root, err = DLSXml.parse(text)
        if root then
            DLS.taGroups[name:lower()] = readTaGroup(root)
        else
            print(('^3[rp_dls] Traffic Advisor "%s" illisible (%s) : %s^0'):format(name, side, err))
        end
    end

    local count = 0
    for _, entry in ipairs(Config.Vehicles or {}) do
        local modelName = type(entry) == 'table' and entry.model or entry
        local file = type(entry) == 'table' and entry.file or modelName
        local text = LoadResourceFile(resource, ('dls/%s.xml'):format(file))
        local root, err = DLSXml.parse(text)
        local model
        if root then model, err = readModel(root, modelName) end
        if model then
            if type(entry) == 'table' and entry.native then
                for _, n in ipairs(entry.native) do model.native[n] = true end
                model.available, model.has = {}, {}
                for n = 1, 5 do
                    if model.stages[n] or model.native[n] then
                        model.available[#model.available + 1] = n
                        model.has[n] = true
                    end
                end
            end
            DLS.models[GetHashKey(modelName)] = model
            count = count + 1
            if side == 'serveur' then
                -- Ce qui a été trouvé dans le fichier (console serveur) : un fichier lu mais sans aucun stage
                -- décrit ni Traffic Advisor est d'un autre format que celui de DLS (ex. DLS v2)
                local drawn = {}
                for n = 1, 5 do
                    if model.stages[n] then drawn[#drawn + 1] = DLS.STAGE_NAMES[n] end
                end
                print(('[rp_dls] %s (dls/%s.xml) : stages %s, Traffic Advisor %s, Steady Burn %s'):format(
                    modelName, file, #model.available > 0 and table.concat(model.available, ', ') or 'aucun',
                    model.ta and model.ta.type or 'non', model.steady and 'oui' or 'non'))
                if #drawn == 0 and not model.ta and not model.steady then
                    print(('^3[rp_dls] dls/%s.xml : aucun stage <Sirens>, ni Traffic Advisor, ni Steady Burn reconnu. '
                        .. 'Format différent de celui de DLS v1 (fichier DLS v2 ?) : seul le stage d\'origine (carcols) '
                        .. 'fonctionnera.^0'):format(file))
                end
            end
        else
            print(('^3[rp_dls] dls/%s.xml illisible (%s) : %s^0'):format(file, side, err or 'fichier absent'))
        end
    end
    if side == 'serveur' then print(('[rp_dls] %d véhicule(s) DLS chargé(s).'):format(count)) end
end

--- Modèle générique : véhicule d'urgence sans fichier DLS (gyrophares du jeu, sons et klaxon pris en charge)
DLS.generic = {
    name = 'generic', generic = true, stages = {}, native = { [3] = true }, available = { 3 }, has = { [3] = true },
    tones = {}, hornInterrupts = false, sirenKill = false, preset = 'none',
}
for n, tone in ipairs(Config.DefaultTones) do DLS.generic.tones[n] = tone end
DLS.generic.tones[5] = Config.DefaultHorn

--- Groupe de TA du modèle, motif n° index (ou par défaut)
function DLS.taPattern(model, index)
    if not model.ta then return nil end
    local group = DLS.taGroups[model.ta.group] or DLS.taGroups.default
    if not group or #group.patterns == 0 then return nil end
    index = index or group.byName[model.ta.pattern] or 1
    if index < 1 or index > #group.patterns then index = 1 end
    return group.patterns[index], index, #group.patterns
end

--- Nombre de motifs de TA du modèle
function DLS.taPatternCount(model)
    if not model or not model.ta then return 0 end
    local group = DLS.taGroups[model.ta.group] or DLS.taGroups.default
    return group and #group.patterns or 0
end
