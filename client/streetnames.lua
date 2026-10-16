--[[
    MDC Standalone - Noms de rues et de zones (client)
    ---------------------------------------------------
    SEULE source des noms affichés par le PLD (rue, croisement, quartier), le bouton "Position actuelle" et les
    appels : config/atlanta_streets.lua (table AtlantaNames). Aucun autre fichier, aucune autre ressource.
      - streets : nom de la rue dans le jeu -> nom d'Atlanta (majuscules sans importance) ;
      - pool    : rues absentes de "streets" -> un nom de cette liste, toujours le même pour une même rue
                  (autoRenameUnmapped = false : elles gardent leur nom du jeu) ;
      - zones   : code de zone du jeu -> quartier (aussi renommé sur la carte du menu pause) ;
      - countyZones : zones du comté (countyName) au lieu de la ville (cityName).
    Exports (nom du dossier de cette ressource) : GetStreetName(coords), GetDistrictName(coords),
    GetLocationText(coords), RenameStreet(nomDuJeu).
    Commande /mdc_streets : noms à votre position (F8). Aucune boucle.
]]

local N = AtlantaNames or {}

StreetNames = { loaded = 0, file = 'config/atlanta_streets.lua' }

local byName = {} -- [nom du jeu en minuscules] = nom d'Atlanta
local zones = {}  -- [code de zone, ex. "CYPRE"] = quartier
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
    for code, name in pairs(N.zones or {}) do
        if type(code) == 'string' and type(name) == 'string' and name ~= '' then
            zones[code:upper()] = name
            AddTextEntry(code:upper(), name) -- quartier renommé aussi sur la carte (menu pause)
            StreetNames.loaded = StreetNames.loaded + 1
        end
    end
    for _, name in ipairs(N.pool or {}) do
        if type(name) == 'string' and name ~= '' then pool[#pool + 1] = name end
    end
end

--- Nom d'Atlanta d'une rue du jeu ("Strawberry Ave" -> "Metropolitan Pkwy") ; rue non listée : nom du "pool"
--- (toujours le même pour une même rue), ou son nom du jeu si autoRenameUnmapped = false
function StreetNames.rename(game)
    if type(game) ~= 'string' or game == '' then return '' end
    local cached = renamed[game]
    if cached then return cached end
    local name = byName[game:lower()]
    if not name then
        if N.autoRenameUnmapped ~= false and #pool > 0 then
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

--- Quartier à cette position (ex. "Mechanicsville") ; code absent du fichier : nom du jeu
function StreetNames.zone(x, y, z)
    local code = GetNameOfZone(x, y, z)
    if not code or code == '' then return '' end
    local name = zones[code:upper()]
    if name then return name end
    local label = GetLabelText(code)
    if not label or label == '' or label == 'NULL' then return '' end
    return label
end

--- Ville ou comté de cette position (countyZones : countyName, sinon cityName)
function StreetNames.area(x, y, z)
    local code = (GetNameOfZone(x, y, z) or ''):upper()
    if N.countyZones and N.countyZones[code] then return N.countyName or 'Fayette County' end
    return N.cityName or 'Atlanta'
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

--- "Peachtree St, Buckhead, Atlanta"
exports('GetLocationText', function(coords)
    local x, y, z = xyz(coords)
    local s = GetStreetNameAtCoord(x, y, z)
    local parts = {}
    for _, part in ipairs({ StreetNames.street(s), StreetNames.zone(x, y, z), StreetNames.area(x, y, z) }) do
        if part ~= '' then parts[#parts + 1] = part end
    end
    return table.concat(parts, ', ')
end)

--- Nom du jeu -> nom d'Atlanta ("Strawberry Ave" -> "Metropolitan Pkwy")
exports('RenameStreet', function(name) return StreetNames.rename(name) end)

RegisterCommand('mdc_streets', function()
    local c = GetEntityCoords(PlayerPedId())
    local s, x = GetStreetNameAtCoord(c.x, c.y, c.z)
    print(('[MDC] %d noms lus dans %s (seule source)'):format(StreetNames.loaded, StreetNames.file))
    print(('[MDC] Rue : %s (jeu : %s) | Croisement : %s (jeu : %s) | Quartier : %s (code %s) | %s'):format(
        StreetNames.street(s), GetStreetNameFromHashKey(s), StreetNames.street(x), GetStreetNameFromHashKey(x),
        StreetNames.zone(c.x, c.y, c.z), GetNameOfZone(c.x, c.y, c.z), StreetNames.area(c.x, c.y, c.z)))
end, false)
