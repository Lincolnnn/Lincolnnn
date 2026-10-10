--[[
    MDC Standalone - HUD (client)
    -----------------------------
    Deux affichages indépendants, dessinés par le NUI (html/script.js) :
      - PLD (Player Localisation Display) : direction, rue, croisement le plus proche, bloc
        -> affiché pour chaque joueur dès sa connexion, sans utiliser le MDC
           (désactivable / réglable dans l'onglet "Paramètres" du MDC, réglages propres au joueur)
      - Display MDC : nom de l'unité, tag, statut, n° d'incident de l'appel en cours
        -> affiché uniquement quand le joueur fait partie d'une unité
    + les notifications (en haut à droite de l'écran) : nouvel appel, nouvel incident,
      changement de statut de l'unité.

    Performance :
      - Le PLD utilise UNE boucle lente (Config.Interval ms, 500 par défaut) qui
        n'envoie au NUI que ce qui a changé (~0.01ms). PLD désactivé : 0.00ms.
      - Le display MDC et les notifications n'ont pas de boucle : le serveur envoie
        les changements (événements).

    Les blocs de localisation se configurent dans config/blocks.json (voir config/LISEZMOI.txt).
    Les réglages (position, taille, éléments affichés) sont modifiés dans l'onglet
    "Paramètres" du MDC et gardés chez le joueur (KVP), même après une reconnexion.
]]

local Config = {
    -- PLD affiché pour TOUS les joueurs dès leur connexion (sans nom RP, sans unité, sans ouvrir
    -- le MDC). false : seulement pour les joueurs ayant accès au MDC (permission ACE).
    PldForEveryone = true,

    Interval = 500,          -- délai (ms) entre deux mises à jour du PLD
    BlocksFile = 'config/blocks.json',
    UnknownStreet = 'Rue inconnue',

    -- Recherche du croisement le plus proche quand le joueur n'est pas sur une intersection :
    -- points testés devant et derrière le joueur (en mètres), du plus proche au plus loin.
    CrossingProbe = { 15, 30, 50, 75, 110, 150, 200, 260 },
}

local RESOURCE = GetCurrentResourceName()

local settings = {}       -- réglages complets envoyés par le NUI (voir saveSettings)
local hasAccess = false   -- accès au MDC (ACE), donné par le serveur
local pldReady = false    -- le joueur est en jeu (fin du chargement) : le PLD peut s'afficher
local synced = false      -- réponse du serveur reçue (accès + unité)
local unitInfo = nil      -- unité du joueur : { name, tag, color, status, dept, callNumber }
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

--- Réglage booléen (vrai par défaut), ex : setting('pld', 'enabled')
local function setting(group, key)
    return type(settings[group]) ~= 'table' or settings[group][key] ~= false
end

loadSettings()

-- =========================================================================
-- BLOCS DE LOCALISATION (config/blocks.json)
-- Le bloc qui contient le joueur est affiché ; sinon, le bloc le plus proche.
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
                block.kind, block.cx, block.cy, block.r = 'circle', c.x, c.y, entry.radius
            end
        elseif entry.type == 'poly' and type(entry.points) == 'table' then
            local points = {}
            for _, value in ipairs(entry.points) do points[#points + 1] = toPoint(value) end
            if #points >= 3 then block.kind, block.points = 'poly', points end
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

local function distanceToSegment(x, y, a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    local length2 = dx * dx + dy * dy
    local t = length2 > 0 and math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / length2)) or 0
    local px, py = a.x + t * dx, a.y + t * dy
    return math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
end

--- Distance (m) entre la position et le bord du bloc ; 0 si la position est dedans.
local function blockDistance(block, x, y)
    if block.kind == 'circle' then
        return math.max(0, math.sqrt((x - block.cx) ^ 2 + (y - block.cy) ^ 2) - block.r)
    elseif block.kind == 'rect' then
        local dx = math.max(block.minX - x, 0, x - block.maxX)
        local dy = math.max(block.minY - y, 0, y - block.maxY)
        return math.sqrt(dx * dx + dy * dy)
    end
    if inPolygon(x, y, block.points) then return 0 end
    local best, points = math.huge, block.points
    for i = 1, #points do
        best = math.min(best, distanceToSegment(x, y, points[i], points[i % #points + 1]))
    end
    return best
end

--- Bloc qui contient la position (le premier de la liste), sinon le bloc le plus proche.
--- Un bloc limité à une rue ("street") n'est utilisé que sur cette rue.
local function findBlock(x, y, street)
    street = street:lower()
    local nearest, nearestDistance = nil, math.huge
    for _, block in ipairs(Blocks) do
        if not block.street or block.street == street then
            local distance = blockDistance(block, x, y)
            if distance == 0 then return block.name end
            if distance < nearestDistance then nearest, nearestDistance = block.name, distance end
        end
    end
    return nearest or DefaultBlock
end

loadBlocks()

-- =========================================================================
-- LOCALISATION
-- =========================================================================
-- Cap GTA : 0 = Nord, 90 = Ouest, 180 = Sud, 270 = Est (sens inverse des aiguilles)
local DIRECTIONS = { 'N', 'NW', 'W', 'SW', 'S', 'SE', 'E', 'NE' }

local function streetsAt(x, y, z)
    local streetHash, crossingHash = GetStreetNameAtCoord(x, y, z)
    return streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or '',
        crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or ''
end

--- Rue de croisement la plus proche : on teste des points devant / derrière le joueur.
local function nearestCrossing(coords, forward, street)
    for _, distance in ipairs(Config.CrossingProbe) do
        for sign = 1, -1, -2 do
            local s, c = streetsAt(coords.x + forward.x * distance * sign, coords.y + forward.y * distance * sign, coords.z)
            if c ~= '' and c ~= street then return c end
            if s ~= '' and s ~= street then return s end
        end
    end
    return nil
end

-- Dernier croisement connu (gardé tant que le joueur reste sur la même rue)
local lastStreet, lastCrossing = '', ''

local function readLocation()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local entity = vehicle ~= 0 and vehicle or ped
    local street, crossing = streetsAt(coords.x, coords.y, coords.z)

    -- Toujours un croisement : sur une intersection celui du jeu, sinon le plus proche
    if crossing == '' or crossing == street then
        crossing = nearestCrossing(coords, GetEntityForwardVector(entity), street)
            or (street == lastStreet and lastCrossing) or ''
    end
    lastStreet, lastCrossing = street, crossing

    local heading = GetEntityHeading(entity)
    return {
        street = street ~= '' and street or Config.UnknownStreet,
        crossing = crossing,
        dir = DIRECTIONS[math.floor(((heading + 22.5) % 360) / 45) + 1],
        block = findBlock(coords.x, coords.y, street),
        -- masqué dans le menu pause et pendant les écrans noirs (chargement, mort…)
        paused = IsPauseMenuActive() or IsScreenFadedOut() or GetIsLoadingScreenActive(),
    }, coords
end

-- =========================================================================
-- ÉTAT DU HUD
-- =========================================================================
--- PLD autorisé pour ce joueur (indépendant du MDC : ni nom RP, ni unité nécessaires)
local function pldAllowed()
    return pldReady and (Config.PldForEveryone or hasAccess)
end

local function pldActive()
    return pldAllowed() and setting('pld', 'enabled')
end

local startLoop

local function refreshHud()
    SendNUIMessage({ action = 'hudState', data = { pld = pldAllowed(), unit = unitInfo } })
    if pldActive() then startLoop() end
end

-- Boucle du PLD : uniquement quand il est affiché ; envoie seulement les changements
startLoop = function()
    if loopRunning then return end
    loopRunning = true
    CreateThread(function()
        local last = nil
        while pldActive() do
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

-- Accès au MDC + unité du joueur (nom, tag, statut, appel) : envoyés par le serveur à chaque changement
RegisterNetEvent('mdc:client:hud', function(access, info)
    synced = true
    hasAccess = access == true
    unitInfo = type(info) == 'table' and info or nil
    refreshHud()
end)

-- Nouvelle intervention / nouvel incident : notification en haut à droite de l'écran.
-- Le son est joué par le NUI (script.js, playSound) pour respecter le volume réglé
-- dans "Paramètres > MDC" (PlaySoundFrontend n'a pas de réglage de volume).
RegisterNetEvent('mdc:client:callNotify', function(call)
    if type(call) ~= 'table' or not setting('notify', 'calls') then return end
    SendNUIMessage({ action = 'callNotify', data = call })
end)

-- Changement de statut de l'unité du joueur : notification en haut à droite
RegisterNetEvent('mdc:client:statusNotify', function(unit)
    if type(unit) ~= 'table' or not setting('notify', 'status') then return end
    SendNUIMessage({ action = 'statusNotify', data = unit })
end)

-- À la connexion : le PLD démarre dès que le joueur est en jeu (sans passer par le MDC),
-- puis on demande au serveur l'accès au MDC et l'unité actuelle (nouvel essai si pas de réponse).
CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    pldReady = true
    refreshHud()

    for _ = 1, 10 do
        if synced then break end
        TriggerServerEvent('mdc:server:hudSync')
        Wait(3000)
    end
end)

-- =========================================================================
-- CALLBACKS NUI
-- =========================================================================

-- Le NUI (re)chargé demande les réglages et l'état du HUD
RegisterNUICallback('hudReady', function(_, cb)
    cb({ ok = true, settings = settings, pld = pldAllowed(), unit = unitInfo })
    if pldActive() then
        SetTimeout(200, function() startLoop() end)
    end
end)

-- Onglet "Paramètres" : réglages du HUD, des notifications et du MDC
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

-- Bouton "Position actuelle" des formulaires d'intervention / d'incident : rue, croisement, bloc
RegisterNUICallback('getLocation', function(_, cb)
    local location = readLocation()
    cb({ ok = true, street = location.street, crossing = location.crossing, block = location.block })
end)

-- Commande /mdc_pos (cadres) : position dans la console F8, au format de config/blocks.json
RegisterCommand('mdc_pos', function()
    local location, coords = readLocation()
    print(('[MDC] Rue : %s | Croisement : %s | Bloc affiché : %s'):format(location.street, location.crossing, location.block))
    print(('{ "name": "A RENOMMER", "type": "circle", "center": [%.2f, %.2f], "radius": 60 }'):format(coords.x, coords.y))
end, false)
