--[[
    MDC Standalone - HUD (client)
    -----------------------------
    Deux affichages indépendants, dessinés par le NUI (html/script.js) :
      - PLD (Player Localisation Display) : direction, rue, croisement le plus proche, bloc,
        heure du jeu
        -> affiché pour chaque joueur dès sa connexion, sans utiliser le MDC
           (désactivable / réglable dans l'onglet "Paramètres" du MDC, réglages propres au joueur)
      - Display MDC : nom de l'unité, tag, statut, n° d'incident de l'appel en cours
        -> affiché uniquement quand le joueur fait partie d'une unité
      (+ le car HUD : client/carhud.lua, données de Vehicle Control / rp_vehiclecontrol)
      (+ la minimap : masquée à pied, affichée en véhicule avec un contour posé à sa place exacte)
    + les notifications (en haut à droite de l'écran) : nouvel appel, nouvel incident (unités du
      police de l'appel), proposition "unité la plus proche" (Y / N), changement de statut de l'unité.

    Performance :
      - Le PLD utilise UNE boucle lente (Config.Interval ms, 500 par défaut) qui
        n'envoie au NUI que ce qui a changé (~0.01ms), et une boucle légère à chaque image qui masque
        les textes du jeu concurrents (HideGameHud, ~0.01ms). PLD désactivé : 0.00ms.
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

    -- PRIORITÉ AU PLD / CAR HUD / DISPLAY MDC : textes du jeu masqués tant que le PLD est affiché (ils se
    -- superposent aux HUD) : 6 nom du véhicule, 7 nom de la zone, 8 classe du véhicule, 9 nom de la rue.
    -- {} pour les garder. (Les scripts de HUD concurrents sont arrêtés par le serveur : ConflictingHuds.)
    HideGameHud = { 6, 7, 8, 9 },
}

local RESOURCE = GetCurrentResourceName()

local settings = {}       -- réglages complets envoyés par le NUI (voir saveSettings)
local hasAccess = false   -- accès au MDC (ACE), donné par le serveur
local pldReady = false    -- le joueur est en jeu (fin du chargement) : le PLD peut s'afficher
local synced = false      -- réponse du serveur reçue (accès + unité)
local unitInfo = nil      -- unité du joueur : { name, tag, color, status, agency, agencyShort, callNumber }
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

-- Noms des rues et des quartiers : config/atlanta_streets.lua uniquement (client/streetnames.lua)
local function streetsAt(x, y, z)
    local streetHash, crossingHash = GetStreetNameAtCoord(x, y, z)
    return StreetNames.street(streetHash), StreetNames.street(crossingHash)
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
        zone = StreetNames.zone(coords.x, coords.y, coords.z), -- zone géographique (ex. Cypress Flats)
        dir = DIRECTIONS[math.floor(((heading + 22.5) % 360) / 45) + 1],
        block = findBlock(coords.x, coords.y, street),
        time = ('%02d:%02d'):format(GetClockHours(), GetClockMinutes()), -- heure du jeu
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

-- Le PLD est toujours affiché (seules sa position et sa taille se règlent dans le MDC)
local function pldActive()
    return pldAllowed()
end

local startLoop

-- Secteur (zone de jeu) du policier : saisi dans le menu d'interactions (rp_interact, Police), publié dans
-- l'état du joueur ("policeSector") et affiché sur le display MDC. La police (WSP, KCSO…) est celle du MDC.
local function policeProfile(sector)
    sector = type(sector) == 'string' and sector:sub(1, 40) or ''
    return { sector = sector }
end
local profile = policeProfile(LocalPlayer.state.policeSector)

local function refreshHud()
    SendNUIMessage({ action = 'hudState', data = { pld = pldAllowed(), unit = unitInfo, profile = profile } })
    if pldActive() then startLoop() end
end

-- Textes du jeu (rue, zone, véhicule) masqués à chaque image tant que le PLD est affiché
local hideRunning = false
local function hideGameHud()
    if hideRunning or #Config.HideGameHud == 0 then return end
    hideRunning = true
    CreateThread(function()
        while pldActive() do
            for _, component in ipairs(Config.HideGameHud) do HideHudComponentThisFrame(component) end
            Wait(0)
        end
        hideRunning = false
    end)
end

-- Boucle du PLD : uniquement quand il est affiché ; envoie seulement les changements
startLoop = function()
    hideGameHud()
    if loopRunning then return end
    loopRunning = true
    CreateThread(function()
        local last = nil
        while pldActive() do
            local data = readLocation()
            -- (l'heure du jeu avance d'une minute toutes les 2 s : un envoi au plus toutes les 2 s)
            local key = ('%s|%s|%s|%s|%s|%s|%s'):format(data.street, data.zone, data.crossing, data.dir, data.block, data.time, tostring(data.paused))
            if key ~= last then
                last = key
                SendNUIMessage({ action = 'pld', data = data })
            end
            Wait(Config.Interval)
        end
        loopRunning = false
    end)
end

-- Changement de secteur (appelé AVANT l'enregistrement : la valeur reçue est utilisée)
local myBag = ('player:%d'):format(GetPlayerServerId(PlayerId()))
AddStateBagChangeHandler('policeSector', myBag, function(_, _, value)
    profile = policeProfile(value)
    refreshHud()
end)

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

-- "Vous êtes l'une des unités les plus proches" : proposition d'un appel à l'unité du joueur.
-- Y : accepter (l'unité est rattachée à l'appel, "En route"), N : refuser. Sans passer par le MDC.
-- Raccourcis FiveM (modifiables : Paramètres > Raccourcis clavier > FiveM) : aucune boucle ; les touches
-- ne font rien quand aucune proposition n'est en attente.
local offer = nil -- { callId, expires }

RegisterNetEvent('mdc:client:nearestOffer', function(call)
    if type(call) ~= 'table' or not call.id then return end
    offer = { callId = call.id, expires = GetGameTimer() + (tonumber(call.timeout) or 30000) }
    SendNUIMessage({ action = 'nearestOffer', data = call })
end)

RegisterNetEvent('mdc:client:offerClosed', function(callId, result)
    if offer and offer.callId == callId then offer = nil end
    SendNUIMessage({ action = 'offerClosed', data = { callId = callId, result = result } })
end)

local function answerOffer(accept)
    if not offer then return end
    if GetGameTimer() > offer.expires then
        offer = nil
        return
    end
    TriggerServerEvent('mdc:server:offerAnswer', offer.callId, accept)
end
RegisterCommand('mdc_offer_yes', function() answerOffer(true) end, false)
RegisterCommand('mdc_offer_no', function() answerOffer(false) end, false)
RegisterKeyMapping('mdc_offer_yes', 'MDC : accepter l\'appel (unité la plus proche)', 'keyboard', 'Y')
RegisterKeyMapping('mdc_offer_no', 'MDC : refuser l\'appel (unité la plus proche)', 'keyboard', 'N')

-- Messagerie entre unités : nouveau message (MDC ouvert ou non : notification en haut à droite et son si reçu, réglage
-- « Notifier les messages des autres unités ») et nombre de non-lus (badge du bouton Messages)
RegisterNetEvent('mdc:client:unitMessage', function(data)
    if type(data) ~= 'table' then return end
    data.notify = data.incoming == true and setting('notify', 'messages')
    SendNUIMessage({ action = 'unitMessage', data = data })
end)

RegisterNetEvent('mdc:client:unitMessages', function(data)
    if type(data) == 'table' then SendNUIMessage({ action = 'unitMessages', data = data }) end
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

-- =========================================================================
-- MINIMAP (non réglable) : masquée à pied, GPS compris ; affichée dès que le joueur monte dans un véhicule.
-- Son contour (noir fondu de rouge) est dessiné par le NUI à la place EXACTE de la minimap, calculée comme le jeu
-- la place : zone de sécurité de l'affichage (Paramètres > Affichage), format et résolution de l'écran ; recalculée
-- dès qu'un de ces réglages change. Ajustement fin propre à chaque joueur : Paramètres > HUD & Display.
-- Une boucle lente (MINIMAP_INTERVAL) : ~0.00ms.
-- =========================================================================
local MINIMAP_INTERVAL = 250
local minimapSent = nil -- dernier état envoyé au NUI (nil : à renvoyer)

--- Place de la minimap en fractions de l'écran (x, y = coin haut gauche ; w, h) : même calcul que le jeu
local function minimapRect()
    local aspect = GetAspectRatio(false)
    local margin = math.abs(1.0 - GetSafeZoneSize()) * 0.5 -- marge de la zone de sécurité (bords gauche et bas)
    local w, h = 1.0 / (4.0 * aspect), 1.0 / 5.674
    local x = margin
    if aspect > 3.5 then x = 1.0 / 3.0 + margin / 3.0 end -- trois écrans : le HUD est sur celui du milieu
    return x, 1.0 - margin - h, w, h
end

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    local wasInVehicle = nil
    while true do
        local inVehicle = IsPedInAnyVehicle(PlayerPedId(), true) -- true : dès qu'il monte (portière, siège)
        if inVehicle ~= wasInVehicle then
            wasInVehicle = inVehicle
            DisplayRadar(inVehicle) -- (un autre script peut la masquer un moment en véhicule : respecté)
        elseif not inVehicle and not IsRadarHidden() then
            DisplayRadar(false) -- à pied : jamais de minimap, même si un autre script la réaffiche
        end
        -- Contour : seulement quand la minimap est vraiment dessinée (ni menu pause, ni grande carte, ni HUD masqué)
        local show = inVehicle and not IsRadarHidden() and IsMinimapRendering() and not IsPauseMenuActive()
            and not IsBigmapActive()
        local x, y, w, h = minimapRect()
        local key = show and ('%.4f|%.4f|%.4f|%.4f'):format(x, y, w, h) or 'off'
        if key ~= minimapSent then
            minimapSent = key
            SendNUIMessage({ action = 'minimap', data = { show = show, x = x, y = y, w = w, h = h } })
        end
        Wait(MINIMAP_INTERVAL)
    end
end)

-- Le NUI (re)chargé demande les réglages et l'état du HUD
RegisterNUICallback('hudReady', function(_, cb)
    minimapSent = nil -- contour de la minimap renvoyé
    cb({ ok = true, settings = settings, pld = pldAllowed(), unit = unitInfo })
    TriggerEvent('mdc:hudReady') -- Vehicle Control (rp_vehiclecontrol) renvoie le car HUD
    if pldActive() then
        SetTimeout(200, function() startLoop() end)
    end
end)

-- Vehicle Control (rp_vehiclecontrol) : volume des sons du véhicule choisi dans "Paramètres"
exports('carSoundVolume', function()
    local car = type(settings.car) == 'table' and settings.car or {}
    return type(car.volume) == 'number' and math.max(0.0, math.min(1.0, car.volume)) or 0.7
end)

-- Mode nuit (Paramètres > MDC > Apparence) pour les menus des AUTRES ressources (rp_interact, /scene, équipement…) :
-- 'night' si le thème est Nuit et qu'il s'applique à toutes les interfaces ou aux menus extérieurs, sinon 'day' ;
-- et sa couleur (vert, jaune, rouge, bleu). Chaque ressource les lit à son démarrage (exports uiTheme, uiNightColor)
-- et reçoit leurs changements (événement client "mdc:uiTheme", theme, color), puis les envoie à son NUI. Le MDC
-- lui-même les applique dans html/script.js.
local function uiTheme()
    local m = type(settings.mdc) == 'table' and settings.mdc or {}
    local scope = (m.themeScope == 'mdc' or m.themeScope == 'menus') and m.themeScope or 'all'
    return (m.theme == 'night' and scope ~= 'mdc') and 'night' or 'day'
end
exports('uiTheme', uiTheme)
--- Couleur du mode nuit : 'green' (par défaut), 'yellow', 'red' ou 'blue'
local NIGHT_COLORS = { green = true, yellow = true, red = true, blue = true }
local function uiNightColor()
    local m = type(settings.mdc) == 'table' and settings.mdc or {}
    return NIGHT_COLORS[m.nightColor] and m.nightColor or 'green'
end
exports('uiNightColor', uiNightColor)
local sentTheme = nil
local function publishTheme()
    local theme, color = uiTheme(), uiNightColor()
    if sentTheme == theme .. ':' .. color then return end
    sentTheme = theme .. ':' .. color
    TriggerEvent('mdc:uiTheme', theme, color)
end

-- Bouton "Tester" / curseur du volume des sons du véhicule
RegisterNUICallback('testCarSound', function(data, cb)
    cb({ ok = true })
    TriggerEvent('rp_vehiclecontrol:testSound', type(data) == 'table' and tonumber(data.volume) or nil)
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
    publishTheme()
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

-- Démarrage (ou redémarrage) du MDC : les autres ressources reçoivent le thème des menus
CreateThread(function()
    Wait(1000)
    publishTheme()
end)
