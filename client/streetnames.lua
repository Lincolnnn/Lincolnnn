--[[
    MDC Standalone - Noms de rues et de zones (client)
    ---------------------------------------------------
    Les noms affichés par le PLD (rue, croisement, zone géographique) et par le bouton "Position actuelle"
    viennent de la ressource de noms de rues du serveur (RESOURCE, dossier "rp_atlanta_streetnames"),
    sinon des noms du jeu.

    Lecture de cette ressource (au démarrage, et quand elle (re)démarre) : les fichiers listés dans son
    fxmanifest.lua (+ quelques noms habituels) sont lus et analysés. Formats reconnus :
      - AddTextEntryByHash(0x1A2B3C4D, "Peachtree St")       -> rue (par son hash)
      - AddTextEntry("CYPRE", "Cypress Flats")                -> zone (code de zone du jeu) / rue (clé)
      - tables : [0x1A2B3C4D] = "Nom", ["Strawberry Ave"] = "Nom", ["CYPRE"] = "Nom"
      - JSON : mêmes clés ({ "0x1A2B3C4D": "Nom", "Strawberry Ave": "Nom", "CYPRE": "Nom" }), ou
        listes d'objets { hash / street / name / zone / label… }
    Si la ressource renomme les rues avec AddTextEntry, le jeu renvoie déjà ces noms : ils sont utilisés
    de toute façon. Commande /mdc_streets : nombre de noms chargés et noms à votre position (F8).
    Aucune boucle.
]]

local RESOURCE = 'rp_atlanta_streetnames'
local EXTRA_FILES = {
    'streetnames.lua', 'streets.lua', 'zones.lua', 'zonenames.lua', 'config.lua', 'shared.lua', 'client.lua',
    'client/client.lua', 'client/main.lua', 'client/streetnames.lua', 'data/streetnames.lua',
    'streetnames.json', 'streets.json', 'zones.json', 'data/streetnames.json', 'data/streets.json', 'data/zones.json',
}

StreetNames = { loaded = 0, files = {} }

local byHash = {}   -- [hash de la rue (0..2^32-1)] = nom
local byName = {}   -- [nom de la rue dans le jeu] = nom
local zones = {}    -- [code de zone, ex. "CYPRE"] = nom

local function u32(n)
    n = math.tointeger(tonumber(n)) or 0
    return n & 0xFFFFFFFF
end

--- Clé lue dans un fichier -> hash (nombre / "0x…"), ou nil
local function asHash(key)
    if type(key) == 'number' then return u32(key) end
    if type(key) == 'string' then
        local hex = key:match('^%s*0[xX](%x+)%s*$')
        if hex then return u32(tonumber(hex, 16)) end
        if key:match('^%-?%d+$') then return u32(tonumber(key)) end
    end
    return nil
end

local function isZoneCode(key)
    return type(key) == 'string' and #key <= 10 and key:match('^[%u%d_]+$') ~= nil
end

--- Une paire clé -> nom trouvée dans un fichier
local function add(key, name)
    if type(name) ~= 'string' or name == '' then return end
    local hash = asHash(key)
    if hash then
        byHash[hash] = name
    elseif isZoneCode(key) then
        zones[key] = name
        byHash[u32(GetHashKey(key))] = name -- clé de texte d'une rue (AddTextEntry)
    elseif type(key) == 'string' and key ~= '' then
        byName[key] = name
    end
    StreetNames.loaded = StreetNames.loaded + 1
end

local STRING = '["\']([^"\']*)["\']'

local function parseLua(text)
    -- AddTextEntryByHash(0x…, "Nom") / AddTextEntryByHash(123, "Nom")
    for key, name in text:gmatch('AddTextEntryByHash%s*%(%s*([%-%dxXa-fA-F]+)%s*,%s*' .. STRING) do add(key, name) end
    for key, name in text:gmatch('AddTextEntryByHash%s*%(%s*[`"\']([^`"\']+)[`"\']%s*,%s*' .. STRING) do
        byHash[u32(GetHashKey(key))] = name
        StreetNames.loaded = StreetNames.loaded + 1
    end
    -- AddTextEntry("CLE", "Nom")
    for key, name in text:gmatch('AddTextEntry%s*%(%s*' .. STRING .. '%s*,%s*' .. STRING) do add(key, name) end
    -- Tables : [0x…] = "Nom" / ["Clé"] = "Nom"
    for key, name in text:gmatch('%[%s*(0[xX]%x+)%s*%]%s*=%s*' .. STRING) do add(key, name) end
    for key, name in text:gmatch('%[%s*(%-?%d+)%s*%]%s*=%s*' .. STRING) do add(key, name) end
    for key, name in text:gmatch('%[%s*' .. STRING .. '%s*%]%s*=%s*' .. STRING) do add(key, name) end
end

local function parseJson(text)
    local ok, data = pcall(json.decode, text)
    if not ok or type(data) ~= 'table' then return end
    local function walk(value, depth)
        if type(value) ~= 'table' or depth > 4 then return end
        -- Objet décrivant une rue / une zone
        local name = value.name or value.label or value.newName or value.new or value.text
        local key = value.hash or value.street or value.original or value.old or value.gta or value.zone or value.code
        if type(name) == 'string' and key ~= nil then add(key, name) end
        for k, v in pairs(value) do
            if type(v) == 'string' and type(k) == 'string' then add(k, v)
            elseif type(v) == 'table' then walk(v, depth + 1) end
        end
    end
    walk(data, 0)
end

--- Fichiers de la ressource : ceux de son fxmanifest (sans les caractères génériques) + noms habituels
local function resourceFiles()
    local list, seen = {}, {}
    local function push(path)
        if not seen[path] and not path:find('[%*%?]') then seen[path] = true; list[#list + 1] = path end
    end
    for _, manifest in ipairs({ 'fxmanifest.lua', '__resource.lua' }) do
        local text = LoadResourceFile(RESOURCE, manifest)
        if text then
            for path in text:gmatch('["\']([^"\']+%.[lLjJ][uUsS][aAoO][nN]?)["\']') do push(path) end
        end
    end
    for _, path in ipairs(EXTRA_FILES) do push(path) end
    return list
end

function StreetNames.load()
    byHash, byName, zones = {}, {}, {}
    StreetNames.loaded, StreetNames.files = 0, {}
    if GetResourceState(RESOURCE) == 'missing' then return end
    for _, path in ipairs(resourceFiles()) do
        local text = LoadResourceFile(RESOURCE, path)
        if text and text ~= '' then
            local before = StreetNames.loaded
            if path:lower():match('%.json$') then parseJson(text) else parseLua(text) end
            if StreetNames.loaded > before then StreetNames.files[#StreetNames.files + 1] = path end
        end
    end
end

--- Nom d'une rue (hash renvoyé par GetStreetNameAtCoord)
function StreetNames.street(hash)
    if not hash or hash == 0 then return '' end
    local name = byHash[u32(hash)]
    if name then return name end
    local game = GetStreetNameFromHashKey(hash) or ''
    return byName[game] or game
end

--- Zone géographique à cette position (ex. "Cypress Flats")
function StreetNames.zone(x, y, z)
    local code = GetNameOfZone(x, y, z)
    if not code or code == '' then return '' end
    local name = zones[code] or zones[code:upper()] or byHash[u32(GetHashKey(code))]
    if name then return name end
    local label = GetLabelText(code)
    if not label or label == '' or label == 'NULL' then return '' end
    return byName[label] or label
end

StreetNames.load()

AddEventHandler('onClientResourceStart', function(resource)
    if resource == RESOURCE then StreetNames.load() end
end)

RegisterCommand('mdc_streets', function()
    local c = GetEntityCoords(PlayerPedId())
    local s, x = GetStreetNameAtCoord(c.x, c.y, c.z)
    print(('[MDC] %s : %s (%d noms lus dans %s)'):format(RESOURCE, GetResourceState(RESOURCE), StreetNames.loaded,
        #StreetNames.files > 0 and table.concat(StreetNames.files, ', ') or 'aucun fichier'))
    print(('[MDC] Rue : %s (jeu : %s, hash 0x%08X) | Croisement : %s | Zone : %s (code %s)'):format(
        StreetNames.street(s), GetStreetNameFromHashKey(s), u32(s), StreetNames.street(x),
        StreetNames.zone(c.x, c.y, c.z), GetNameOfZone(c.x, c.y, c.z)))
end, false)
