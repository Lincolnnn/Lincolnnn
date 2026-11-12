--[[
    MDC Standalone - Noms de rues et de zones (client) : ÉTAT DE WASHINGTON (King County)
    ------------------------------------------------------------------------------------
    SEULE source des noms affichés par le PLD (rue, croisement, quartier, ville), le bouton "Position actuelle" et les
    appels : config/washington.json (liste lisible : config/WASHINGTON_CARTE.md). Aucun autre fichier.
      - streets : nom de la rue dans le jeu -> nom affiché (I-5, I-90, I-405, US-2, US-12, routes de l'État, routes du
                  comté…), majuscules sans importance ; rue absente : son nom du jeu (ou un nom de "pool" si
                  autoRenameUnmapped = true) ;
      - zones   : code de zone du jeu -> quartier (ville) ou zone géographique, et sa municipalité (aussi renommé sur la
                  carte du menu pause) ;
      - municipalities : ville affichée après le quartier (Seattle, Bellevue, Kenmore…) et police compétente.
    Exports (nom du dossier de cette ressource) : GetStreetName(coords), GetDistrictName(coords),
    GetLocationText(coords), RenameStreet(nomDuJeu), GetJurisdiction(coords).
    Commande /mdc_streets : noms à votre position (F8). Aucune boucle.
]]

local FILE = 'config/washington.json'
local N = {}
do
    local raw = LoadResourceFile(GetCurrentResourceName(), FILE)
    local ok, data = pcall(json.decode, raw or '')
    if ok and type(data) == 'table' then
        N = data
    else
        print(('^1[MDC] %s introuvable ou JSON invalide : noms du jeu affichés.^0'):format(FILE))
    end
end

StreetNames = { loaded = 0, file = FILE }

local byName = {} -- [nom du jeu en minuscules] = nom affiché
local zones = {}  -- [code de zone, ex. "CYPRE"] = { name, municipality }
local pool = {}
local renamed = {} -- cache : [nom du jeu] = nom affiché

local function u32(n)
    n = math.tointeger(tonumber(n)) or 0
    return n & 0xFFFFFFFF
end

function StreetNames.load()
    byName, zones, pool, renamed = {}, {}, {}, {}
    StreetNames.loaded = 0
    for game, name in pairs(N.streets or {}) do
        if type(game) == 'string' and type(name) == 'string' and name ~= '' then
            byName[game:lower()] = name
            StreetNames.loaded = StreetNames.loaded + 1
        end
    end
    for code, zone in pairs(N.zones or {}) do
        local name = type(zone) == 'table' and zone.name or zone
        if type(code) == 'string' and type(name) == 'string' and name ~= '' then
            zones[code:upper()] = { name = name, municipality = type(zone) == 'table' and zone.municipality or nil }
            AddTextEntry(code:upper(), name) -- quartier renommé aussi sur la carte (menu pause)
            StreetNames.loaded = StreetNames.loaded + 1
        end
    end
    for _, name in ipairs(N.pool or {}) do
        if type(name) == 'string' and name ~= '' then pool[#pool + 1] = name end
    end
end

--- Nom affiché d'une rue du jeu ("Great Ocean Hwy" -> "I-90") ; rue non listée : son nom du jeu, ou un nom du
--- "pool" (toujours le même pour une même rue) si autoRenameUnmapped = true
function StreetNames.rename(game)
    if type(game) ~= 'string' or game == '' then return '' end
    local cached = renamed[game]
    if cached then return cached end
    local name = byName[game:lower()]
    if not name then
        if N.autoRenameUnmapped == true and #pool > 0 then
            name = pool[u32(GetHashKey(game:lower())) % #pool + 1]
        else
            name = game
        end
    end
    renamed[game] = name
    return name
end

--- Nom d'une rue (hash renvoyé par GetStreetNameAtCoord)
function StreetNames.street(hash)
    if not hash or hash == 0 then return '' end
    return StreetNames.rename(GetStreetNameFromHashKey(hash) or '')
end

--- Quartier / zone géographique à cette position (ex. "Capitol Hill") ; code absent du fichier : nom du jeu
function StreetNames.zone(x, y, z)
    local code = GetNameOfZone(x, y, z)
    if not code or code == '' then return '' end
    local zone = zones[code:upper()]
    if zone then return zone.name end
    local label = GetLabelText(code)
    if not label or label == '' or label == 'NULL' then return '' end
    return label
end

--- Municipalité de cette position (Seattle, Bellevue, Kenmore, Carnation, Maple Valley, Ravensdale, King County)
local function municipalityOf(x, y, z)
    local zone = zones[(GetNameOfZone(x, y, z) or ''):upper()]
    return zone and zone.municipality and (N.municipalities or {})[zone.municipality] or nil
end
function StreetNames.area(x, y, z)
    local m = municipalityOf(x, y, z)
    return (m and m.name) or N.defaultArea or 'King County'
end
--- Police compétente à cette position (Seattle PD, Bellevue PD, KCSO - Précinct 2 / 3)
function StreetNames.agency(x, y, z)
    local m = municipalityOf(x, y, z)
    return (m and m.agency) or ''
end

StreetNames.load()

-- =========================================================================
-- EXPORTS (autres scripts : téléphone, dispatch…)
-- =========================================================================
local function xyz(coords)
    if type(coords) ~= 'table' and type(coords) ~= 'vector3' and type(coords) ~= 'vector4' then
        coords = GetEntityCoords(PlayerPedId())
    end
    return coords.x + 0.0, coords.y + 0.0, coords.z + 0.0
end

--- Rue, croisement
exports('GetStreetName', function(coords)
    local x, y, z = xyz(coords)
    local s, c = GetStreetNameAtCoord(x, y, z)
    return StreetNames.street(s), StreetNames.street(c)
end)

--- Quartier, ville / comté
exports('GetDistrictName', function(coords)
    local x, y, z = xyz(coords)
    return StreetNames.zone(x, y, z), StreetNames.area(x, y, z)
end)

--- "I-5, Capitol Hill, Seattle"
exports('GetLocationText', function(coords)
    local x, y, z = xyz(coords)
    local s = GetStreetNameAtCoord(x, y, z)
    local parts = {}
    for _, part in ipairs({ StreetNames.street(s), StreetNames.zone(x, y, z), StreetNames.area(x, y, z) }) do
        if part ~= '' then parts[#parts + 1] = part end
    end
    return table.concat(parts, ', ')
end)

--- Nom du jeu -> nom affiché ("Great Ocean Hwy" -> "I-90")
exports('RenameStreet', function(name) return StreetNames.rename(name) end)

--- Police compétente et municipalité à cette position : "KCSO - Précinct 3", "Maple Valley"
exports('GetJurisdiction', function(coords)
    local x, y, z = xyz(coords)
    return StreetNames.agency(x, y, z), StreetNames.area(x, y, z)
end)

RegisterCommand('mdc_streets', function()
    local c = GetEntityCoords(PlayerPedId())
    local s, x = GetStreetNameAtCoord(c.x, c.y, c.z)
    print(('[MDC] %d noms lus dans %s (seule source)'):format(StreetNames.loaded, StreetNames.file))
    print(('[MDC] Rue : %s (jeu : %s) | Croisement : %s (jeu : %s) | Quartier : %s (code %s) | %s'):format(
        StreetNames.street(s), GetStreetNameFromHashKey(s), StreetNames.street(x), GetStreetNameFromHashKey(x),
        StreetNames.zone(c.x, c.y, c.z), GetNameOfZone(c.x, c.y, c.z), StreetNames.area(c.x, c.y, c.z)))
    print(('[MDC] Police compétente : %s'):format(StreetNames.agency(c.x, c.y, c.z)))
end, false)
