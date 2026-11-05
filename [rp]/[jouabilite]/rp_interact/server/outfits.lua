--[[
    RP Interact - serveur : MES TENUES (tenue enregistrée après l'avoir modifiée dans /eup)
    ----------------------------------------------------------------------------------------
    Répertoire propre à chaque joueur (sa licence) : data/saved_outfits.json, { [licence] = { nextId, list = {
      { id, name, gender ('male' / 'female'), service, components = { { n°, modèle, texture } }, props = { ... }, at } } } }.
    Enregistrée depuis /eup > Modifier ma tenue > « Enregistrer ma tenue » ; mise / supprimée depuis
    Menu Interaction > Équipements > Mes tenues. Valeurs vérifiées (numéros des parties, bornes), Eup.MaxSaved au plus.
]]

local S = RPIServer
local Config = InteractConfig
local E = Config.Eup or {}
local FILE = 'data/saved_outfits.json'
local MAX = E.MaxSaved or 20
local COMPONENTS = { [1] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true }
local PROPS = { [0] = true, [1] = true, [2] = true, [6] = true, [7] = true }

local Saved, locked = {}, false
do
    local raw = LoadResourceFile(GetCurrentResourceName(), FILE)
    if raw and raw:match('%S') then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then Saved = data
        else
            locked = true -- illisible : rien n'est écrasé
            print(('^1[RP Interact] %s illisible (JSON invalide) : les tenues ne seront pas enregistrées.^0'):format(FILE))
        end
    end
end

local function save()
    if locked then return false end
    return SaveResourceFile(GetCurrentResourceName(), FILE, json.encode(Saved, { indent = true }), -1)
end

local function int(v, min, max)
    v = math.tointeger(tonumber(v))
    if not v or v < min or v > max then return nil end
    return v
end

--- Parties reçues -> { { n°, modèle, texture } } propres (n° autorisés, bornes)
local function clean(list, allowed, minDrawable)
    local out, seen = {}, {}
    for _, e in ipairs(type(list) == 'table' and list or {}) do
        if type(e) == 'table' then
            local n, d, t = int(e[1], 0, 20), int(e[2], minDrawable, 4000), int(e[3], 0, 255)
            if n and allowed[n] and d and t and not seen[n] then
                seen[n] = true
                out[#out + 1] = { n, d, t }
            end
        end
    end
    return out
end

local function cleanName(name)
    name = type(name) == 'string' and name:gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '') or ''
    return name ~= '' and name:sub(1, 40) or nil
end

local function listOf(src)
    local mine = Saved[S.identifier(src)]
    local out = {}
    for _, o in ipairs(mine and mine.list or {}) do
        out[#out + 1] = { id = o.id, name = o.name, gender = o.gender, service = o.service, at = o.at }
    end
    return out
end

local function find(src, id)
    local mine = Saved[S.identifier(src)]
    for i, o in ipairs(mine and mine.list or {}) do
        if o.id == tonumber(id) then return o, i, mine end
    end
    return nil
end

S.on('outfitList', function(src) return { ok = true, outfits = listOf(src), max = MAX } end)

S.on('outfitSave', function(src, p)
    if locked then return { ok = false, error = 'Enregistrement bloqué : fichier illisible (voir console serveur).' } end
    local name = cleanName(p.name)
    if not name then return { ok = false, error = 'Donnez un nom à la tenue.' } end
    local gender = (p.gender == 'male' or p.gender == 'female') and p.gender or nil
    if not gender then return { ok = false, error = 'Tenues enregistrables uniquement avec un personnage multijoueur.' } end
    local components, props = clean(p.components, COMPONENTS, 0), clean(p.props, PROPS, -1)
    if #components == 0 then return { ok = false, error = 'Tenue illisible.' } end
    local licence = S.identifier(src)
    Saved[licence] = Saved[licence] or { nextId = 1, list = {} }
    local mine = Saved[licence]
    -- même nom : remplacée (mise à jour de la tenue)
    local entry
    for _, o in ipairs(mine.list) do if o.name:lower() == name:lower() then entry = o end end
    if not entry then
        if #mine.list >= MAX then return { ok = false, error = ('%d tenues maximum : supprimez-en une.'):format(MAX) } end
        entry = { id = mine.nextId or (#mine.list + 1) }
        mine.nextId = entry.id + 1
        mine.list[#mine.list + 1] = entry
    end
    entry.name, entry.gender, entry.components, entry.props, entry.at = name, gender, components, props, os.time()
    entry.service = type(p.service) == 'string' and p.service:sub(1, 20) or nil
    if not save() then return { ok = false, error = 'Enregistrement impossible (dossier data ?).' } end
    return { ok = true, id = entry.id, name = name, outfits = listOf(src) }
end)

S.on('outfitWear', function(src, p)
    local o = find(src, p.id)
    if not o then return { ok = false, error = 'Tenue introuvable.' } end
    return { ok = true, outfit = { name = o.name, gender = o.gender, service = o.service, components = o.components, props = o.props } }
end)

S.on('outfitDelete', function(src, p)
    local o, index, mine = find(src, p.id)
    if not o then return { ok = false, error = 'Tenue introuvable.' } end
    if locked then return { ok = false, error = 'Suppression bloquée : fichier illisible (voir console serveur).' } end
    table.remove(mine.list, index)
    save()
    return { ok = true, outfits = listOf(src) }
end)
