--[[
    MDC Standalone - HUD (client)
    -----------------------------
    Deux affichages indépendants, dessinés par le NUI (html/script.js) :
      - PLD (Player Localisation Display) : rue, croisement, direction, bloc
      - Display MDC : nom de l'unité, tag, statut, n° d'incident de l'appel en cours

    Performance :
      - Le HUD n'est actif que si le joueur fait partie d'une unité (Config.ShowWhen).
        Hors unité : aucune boucle, 0.00ms dans le resmon.
      - Le PLD utilise UNE boucle lente (Config.Interval ms, 500 par défaut) qui ne tourne
        que lorsqu'il est affiché, et n'envoie au NUI que ce qui a changé (~0.01ms).
      - Le display MDC n'a pas de boucle : le serveur envoie les changements (événements).

    Les blocs de localisation se configurent dans config/blocks.json (voir config/LISEZMOI.txt).
    Les réglages (position, taille, éléments affichés) sont modifiés dans l'onglet
    "Paramètres" du MDC et gardés chez le joueur (KVP), même après une reconnexion.
]]

local Config = {
    -- 'unit'   : HUD affiché uniquement quand le joueur fait partie d'une unité (en service)
    -- 'always' : HUD toujours affiché (PLD en permanence ; display MDC seulement en unité)
    ShowWhen = 'unit',

    Interval = 500,          -- délai (ms) entre deux mises à jour du PLD
    BlocksFile = 'config/blocks.json',
    UnknownStreet = 'Rue inconnue',
}

local RESOURCE = GetCurrentResourceName()

-- Réglages par défaut (doivent correspondre à HUD_DEFAULTS dans script.js)
local DEFAULT_SETTINGS = {
    pld = { enabled = true },
    unit = { enabled = true },
}

local settings = DEFAULT_SETTINGS   -- réglages complets envoyés par le NUI (voir saveSettings)
local hasAccess = false             -- accès au MDC (ACE), donné par le serveur
local unitInfo = nil                -- unité du joueur : { name, tag, color, status, dept, callNumber }
local loopRunning = false

-- =========================================================================
-- RÉGLAGES (KVP : gardés chez le joueur)
-- =========================================================================
local function loadSettings()
    local raw = GetResourceKvpString('mdc_hud_settings')
    if not raw then return end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then settings = decoded end
end

local function pldEnabled()
    return type(settings.pld) ~= 'table' or settings.pld.enabled ~= false
end

loadSettings()

-- =========================================================================
-- BLOCS DE LOCALISATION (config/blocks.json)
-- =========================================================================
local Blocks = {}
local DefaultBlock = ''

local function toPoint(value)
    if type(value) == 'table' and type(value[1]) == 'number' and type(value[2]) == 'number' then
        return { x = value[1], y = value[2] }
    end
    return nil
end

local function loadBlocks()
    local raw = LoadResourceFile(RESOURCE, Config.BlocksFile)
    if not raw then
        print(('^3[MDC] HUD : %s introuvable, aucun bloc ne sera affiché.^0'):format(Config.BlocksFile))
        return
    end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        print(('^1[MDC] HUD : %s est un JSON invalide, aucun bloc ne sera affiché.^0'):format(Config.BlocksFile))
        return
    end

    DefaultBlock = type(decoded.default) == 'string' and decoded.default or ''
    for index, entry in ipairs(type(decoded.blocks) == 'table' and decoded.blocks or {}) do
        local block = { name = tostring(entry.name or ''), street = type(entry.street) == 'string' and entry.street:lower() or nil }

        if entry.type == 'rect' then
            local a, b = toPoint(entry.min), toPoint(entry.max)
            if a and b then
                block.kind = 'rect'
                block.minX, block.maxX = math.min(a.x, b.x), math.max(a.x, b.x)
                block.minY, block.maxY = math.min(a.y, b.y), math.max(a.y, b.y)
            end
        elseif entry.type == 'circle' then
            local c = toPoint(entry.center)
            if c and type(entry.radius) == 'number' then
                block.kind, block.cx, block.cy, block.r2 = 'circle', c.x, c.y, entry.radius * entry.radius
                block.minX, block.maxX = c.x - entry.radius, c.x + entry.radius
                block.minY, block.maxY = c.y - entry.radius, c.y + entry.radius
            end
        elseif entry.type == 'poly' and type(entry.points) == 'table' then
            local points = {}
            for _, value in ipairs(entry.points) do points[#points + 1] = toPoint(value) end
            if #points >= 3 then
                block.kind, block.points = 'poly', points
                block.minX, block.maxX, block.minY, block.maxY = math.huge, -math.huge, math.huge, -math.huge
                for _, p in ipairs(points) do
                    block.minX, block.maxX = math.min(block.minX, p.x), math.max(block.maxX, p.x)
                    block.minY, block.maxY = math.min(block.minY, p.y), math.max(block.maxY, p.y)
                end
            end
        end

        if block.kind and block.name ~= '' then
            Blocks[#Blocks + 1] = block
        else
            print(('^3[MDC] HUD : bloc n°%d ignoré dans %s (format invalide).^0'):format(index, Config.BlocksFile))
        end
    end
    print(('^5[MDC]^0 HUD : %d bloc(s) de localisation chargé(s).'):format(#Blocks))
end

-- Point dans un polygone (lancer de rayon)
local function inPolygon(x, y, points)
    local inside, j = false, #points
    for i = 1, #points do
        local a, b = points[i], points[j]
        if (a.y > y) ~= (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x then
            inside = not inside
        end
        j = i
    end
    return inside
end

--- Premier bloc de la liste qui contient la position (l'ordre du fichier compte).
local function findBlock(x, y, street)
    street = street:lower()
    for _, block in ipairs(Blocks) do
        if x >= block.minX and x <= block.maxX and y >= block.minY and y <= block.maxY
            and (not block.street or block.street == street) then
            if block.kind == 'rect'
                or (block.kind == 'circle' and (x - block.cx) ^ 2 + (y - block.cy) ^ 2 <= block.r2)
                or (block.kind == 'poly' and inPolygon(x, y, block.points)) then
                return block.name
            end
        end
    end
    return DefaultBlock
end

loadBlocks()

-- =========================================================================
-- LOCALISATION
-- =========================================================================
-- Cap GTA : 0 = Nord, 90 = Ouest, 180 = Sud, 270 = Est (sens inverse des aiguilles)
local DIRECTIONS = { 'N', 'NW', 'W', 'SW', 'S', 'SE', 'E', 'NE' }

local function readLocation()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or ''
    local crossing = crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or ''

    local vehicle = GetVehiclePedIsIn(ped, false)
    local heading = GetEntityHeading(vehicle ~= 0 and vehicle or ped)
    local direction = DIRECTIONS[math.floor(((heading + 22.5) % 360) / 45) + 1]

    return {
        street = street ~= '' and street or Config.UnknownStreet,
        crossing = crossing,
        dir = direction,
        block = findBlock(coords.x, coords.y, street),
        paused = IsPauseMenuActive(), -- masqué dans le menu pause
    }, coords
end

-- =========================================================================
-- ÉTAT DU HUD
-- =========================================================================
local function hudActive()
    return hasAccess and (Config.ShowWhen == 'always' or unitInfo ~= nil)
end

local startLoop

local function refreshHud()
    SendNUIMessage({ action = 'hudState', data = { active = hudActive(), unit = unitInfo } })
    if hudActive() and pldEnabled() then startLoop() end
end

-- Boucle du PLD : uniquement quand il est affiché ; envoie seulement les changements
startLoop = function()
    if loopRunning then return end
    loopRunning = true
    CreateThread(function()
        local last = nil
        while hudActive() and pldEnabled() do
            local data = readLocation()
            local key = ('%s|%s|%s|%s|%s'):format(data.street, data.crossing, data.dir, data.block, tostring(data.paused))
            if key ~= last then
                last = key
                SendNUIMessage({ action = 'pld', data = data })
            end
            Wait(Config.Interval)
        end
        loopRunning = false
    end)
end

-- Unité du joueur (nom, tag, statut, appel) : envoyée par le serveur à chaque changement
RegisterNetEvent('mdc:client:hud', function(access, info)
    hasAccess = access == true
    unitInfo = type(info) == 'table' and info or nil
    refreshHud()
end)

-- Au démarrage : on demande au serveur l'accès et l'unité actuelle
CreateThread(function()
    TriggerServerEvent('mdc:server:hudSync')
end)

-- =========================================================================
-- CALLBACKS NUI
-- =========================================================================

-- Le NUI (re)chargé demande les réglages et l'état du HUD
RegisterNUICallback('hudReady', function(_, cb)
    cb({ ok = true, settings = settings, active = hudActive(), unit = unitInfo })
    if hudActive() and pldEnabled() then
        SetTimeout(200, function() startLoop() end)
    end
end)

-- Onglet "Paramètres" : réglages du HUD et du MDC
RegisterNUICallback('saveSettings', function(data, cb)
    if type(data) ~= 'table' then
        cb({ ok = false, error = 'Réglages invalides.' })
        return
    end
    local encoded = json.encode(data)
    if #encoded > 4000 then
        cb({ ok = false, error = 'Réglages trop volumineux.' })
        return
    end
    settings = data
    SetResourceKvp('mdc_hud_settings', encoded)
    cb({ ok = true })
    refreshHud()
end)

-- Onglet "Paramètres" : position actuelle, pour configurer config/blocks.json
RegisterNUICallback('getPosition', function(_, cb)
    local location, coords = readLocation()
    cb({
        ok = true,
        x = math.floor(coords.x * 100 + 0.5) / 100,
        y = math.floor(coords.y * 100 + 0.5) / 100,
        z = math.floor(coords.z * 100 + 0.5) / 100,
        street = location.street, crossing = location.crossing, block = location.block,
    })
end)

-- Commande /mdc_pos : affiche la position dans la console F8 (format de config/blocks.json)
RegisterCommand('mdc_pos', function()
    local location, coords = readLocation()
    print(('[MDC] Rue : %s | Croisement : %s | Bloc actuel : %s'):format(location.street, location.crossing, location.block))
    print(('{ "name": "A RENOMMER", "type": "circle", "center": [%.2f, %.2f], "radius": 60 }'):format(coords.x, coords.y))
end, false)
