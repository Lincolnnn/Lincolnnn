--[[
    RP TrafficControl - client : mesures appliquées au réseau routier du jeu
    ------------------------------------------------------------------------
    Le serveur publie les mesures (GlobalState.rpTraffic) ; chaque joueur les applique à SON jeu (les nœuds de
    circulation et les zones de vitesse sont propres à chaque client) :
      - ROUTE BARRÉE : nœuds de circulation du tronçon FERMÉS (SetRoadsInAngledArea). Les PNJ ne passent plus par
        là et prennent une autre route (déviation), aucun véhicule n'y apparaît ; rien n'est supprimé. Les PNJ qui
        arrivent quand même (route déjà choisie) recalculent leur route à l'approche (SmartDetour).
      - LIMITATION DE VITESSE / ARRÊT DU TRAFIC : zone de vitesse du jeu (AddRoadNodeSpeedZone), 0 = arrêt.
      - Cartes : zone (tronçon / cercle) et icône sur la carte du menu pause et la mini-carte.
    Mesure levée : le réseau routier revient à l'original (toutes les routes fermées restantes sont redonnées,
    pour que deux tronçons qui se chevauchent restent fermés).

    Performance : aucune boucle sans route barrée à moins de Config.Range m (400) ; sinon une vérification toutes
    les 500 ms des véhicules PNJ que ce joueur contrôle près des tronçons.
]]

TC = TC or {}
local Config = TrafficConfig
local C = Config.Closure or {}
local N = Config.NodeNative or {}
local MPH = 0.44704

TC.measures = {}          -- mesures publiées par le serveur
local applied = { closures = {}, zones = {}, blips = {} }
local detourRunning = false

-- =========================================================================
-- OUTILS PARTAGÉS (aussi utilisés par editor.lua / menu.lua)
-- =========================================================================
function TC.notify(text)
    if GetResourceState('rp_chat') == 'started'
        and pcall(function() exports.rp_chat:addPrivate({ title = 'Trafic', text = text }) end) then
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end

--- Lieu lisible (noms du MDC si présent : rues d'Atlanta ; sinon ceux du jeu)
function TC.locationText(p)
    local mdc = GlobalState.mdcResource
    if mdc and GetResourceState(mdc) == 'started' then
        local ok, text = pcall(function() return exports[mdc]:GetLocationText(vector3(p.x, p.y, p.z)) end)
        if ok and type(text) == 'string' and text ~= '' then return text end
    end
    local street, crossing = GetStreetNameAtCoord(p.x, p.y, p.z)
    local name = GetStreetNameFromHashKey(street)
    if crossing ~= 0 then name = ('%s / %s'):format(name, GetStreetNameFromHashKey(crossing)) end
    return name
end

--- Policier en service (unité du MDC)
function TC.isPolice()
    local unit = LocalPlayer.state.mdcUnit
    return unit ~= nil and unit ~= false and unit ~= ''
end

--- Tronçon fermé : bornes de la zone inclinée (milieux de deux côtés opposés, hauteurs) et largeur
function TC.closureArea(m)
    local h = C.Height or 8.0
    local zlo, zhi = math.min(m.a.z, m.b.z) - h, math.max(m.a.z, m.b.z) + h
    return m.a.x, m.a.y, zlo, m.b.x, m.b.y, zhi, m.width
end

--- Point (x, y) dans le repère du tronçon : u le long (0 = début, L = fin), v sur le côté ; longueur L
function TC.closureLocal(m, x, y)
    local dx, dy = m.b.x - m.a.x, m.b.y - m.a.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then return 0.0, 0.0, 0.0, 0.0, 0.0 end
    local ux, uy = dx / length, dy / length
    local px, py = x - m.a.x, y - m.a.y
    return px * ux + py * uy, px * -uy + py * ux, length, ux, uy
end

-- =========================================================================
-- APPLICATION AU RÉSEAU ROUTIER DE CE JEU
-- =========================================================================
local function closeRoads(m)
    local x1, y1, z1, x2, y2, z2, width = TC.closureArea(m)
    -- nœuds de circulation du tronçon : fermés (les PNJ ne les empruntent plus, aucun véhicule n'y apparaît)
    SetRoadsInAngledArea(x1, y1, z1, x2, y2, z2, width, N.unknown1 == true, false, N.network == true)
end

local function restoreRoads(m)
    local x1, y1, z1, x2, y2, z2, width = TC.closureArea(m)
    SetRoadsBackToOriginalInAngledArea(x1, y1, z1, x2, y2, z2, width, N.network == true)
end

local function addZone(x, y, z, radius, mph)
    local id = AddRoadNodeSpeedZone(x + 0.0, y + 0.0, z + 0.0, radius + 0.0, mph * MPH, false)
    applied.zones[#applied.zones + 1] = id
end

local function blipsAllowed()
    if Config.Blips == 'none' then return false end
    if Config.Blips == 'police' then return TC.isPolice() end
    return true
end

local KIND_NAME = { close = 'Route barrée', speed = 'Limitation de vitesse', stop = 'Trafic arrêté' }

local function addBlips(m)
    local colors = Config.BlipColors or {}
    local color = colors[m.kind] or 1
    local cx, cy, cz, area
    if m.kind == 'close' then
        cx, cy, cz = (m.a.x + m.b.x) / 2, (m.a.y + m.b.y) / 2, (m.a.z + m.b.z) / 2
        local _, _, length = TC.closureLocal(m, m.b.x, m.b.y)
        area = AddBlipForArea(cx, cy, cz, m.width + 0.0, length + 0.0)
        SetBlipRotation(area, math.floor(GetHeadingFromVector_2d(m.b.x - m.a.x, m.b.y - m.a.y) + 0.5))
    else
        cx, cy, cz = m.center.x, m.center.y, m.center.z
        area = AddBlipForRadius(cx, cy, cz, m.radius + 0.0)
    end
    SetBlipColour(area, color)
    SetBlipAlpha(area, 110)
    SetBlipDisplay(area, 3)
    local icon = AddBlipForCoord(cx, cy, cz)
    SetBlipSprite(icon, 1)
    SetBlipColour(icon, color)
    SetBlipScale(icon, 0.75)
    SetBlipAsShortRange(icon, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(m.kind == 'speed' and ('Limitation %d MPH'):format(m.speed) or KIND_NAME[m.kind])
    EndTextCommandSetBlipName(icon)
    applied.blips[#applied.blips + 1] = area
    applied.blips[#applied.blips + 1] = icon
end

local function clearApplied()
    for _, m in ipairs(applied.closures) do restoreRoads(m) end
    for _, id in ipairs(applied.zones) do RemoveRoadNodeSpeedZone(id) end
    for _, blip in ipairs(applied.blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    applied = { closures = {}, zones = {}, blips = {} }
end

local startDetour -- (plus bas)

--- Mesures publiées -> réseau routier de ce jeu. Tout est retiré puis redonné : deux tronçons qui se chevauchent
--- restent fermés quand on lève l'un des deux (les changements sont rares : aucun coût en continu).
function TC.applyAll(list)
    clearApplied()
    TC.measures = type(list) == 'table' and list or {}
    local showBlips = blipsAllowed()
    for _, m in ipairs(TC.measures) do
        if m.kind == 'close' and m.a and m.b then
            closeRoads(m)
            applied.closures[#applied.closures + 1] = m
            if C.StopEntries then
                local r = math.max(m.width / 2, 4.0)
                addZone(m.a.x, m.a.y, m.a.z, r, 0)
                addZone(m.b.x, m.b.y, m.b.z, r, 0)
            end
        elseif (m.kind == 'speed' or m.kind == 'stop') and m.center then
            addZone(m.center.x, m.center.y, m.center.z, m.radius, m.kind == 'stop' and 0 or (m.speed or 25))
        end
        if showBlips then addBlips(m) end
    end
    if TC.onChange then TC.onChange() end
    startDetour()
end

AddStateBagChangeHandler('rpTraffic', 'global', function(_, _, value)
    SetTimeout(0, function() TC.applyAll(value) end)
end)

-- Policier qui entre / sort du service : cartes affichées ou retirées (Blips = 'police')
AddStateBagChangeHandler('mdcUnit', ('player:%d'):format(GetPlayerServerId(PlayerId())), function()
    if Config.Blips == 'police' then SetTimeout(0, function() TC.applyAll(GlobalState.rpTraffic) end) end
end)

CreateThread(function() TC.applyAll(GlobalState.rpTraffic) end)

-- =========================================================================
-- DÉVIATION INTELLIGENTE : PNJ qui arrivent sur un tronçon fermé (route déjà choisie avant la fermeture)
-- =========================================================================
local retasked = {} -- [véhicule] = heure

local function nearClosures(pos)
    local list = {}
    for _, m in ipairs(applied.closures) do
        local cx, cy = (m.a.x + m.b.x) / 2, (m.a.y + m.b.y) / 2
        local dx, dy = pos.x - cx, pos.y - cy
        if math.sqrt(dx * dx + dy * dy) < (Config.Range or 400.0) then list[#list + 1] = m end
    end
    return list
end

--- Ce véhicule arrive sur ce tronçon (devant l'entrée, roulant vers lui) ?
local function approaching(m, pos, vel)
    local u, v, length, ux, uy = TC.closureLocal(m, pos.x, pos.y)
    if math.abs(v) > m.width / 2 then return false end
    local along = vel.x * ux + vel.y * uy
    local approach = C.ApproachDistance or 25.0
    if u < 0 and u > -approach then return along > 1.0 end            -- avant le début, roule vers lui
    if u > length and u < length + approach then return along < -1.0 end -- après la fin, roule vers lui
    return false
end

local function detourTick(list)
    local now = GetGameTimer()
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local driver = GetPedInVehicleSeat(vehicle, -1)
        if driver ~= 0 and not IsPedAPlayer(driver) and NetworkHasControlOfEntity(driver)
            and not IsPedDeadOrDying(driver, true) and (not retasked[vehicle] or now - retasked[vehicle] > 8000) then
            local pos, vel = GetEntityCoords(vehicle), GetEntityVelocity(vehicle)
            for _, m in ipairs(list) do
                if approaching(m, pos, vel) then
                    -- Route recalculée sur le réseau actuel (nœuds du tronçon fermés) : il tourne / fait demi-tour
                    retasked[vehicle] = now
                    TaskVehicleDriveWander(driver, vehicle, math.max(GetEntitySpeed(vehicle), 10.0), 786603)
                    break
                end
            end
        end
    end
    for vehicle, at in pairs(retasked) do
        if now - at > 30000 or not DoesEntityExist(vehicle) then retasked[vehicle] = nil end
    end
end

startDetour = function()
    if detourRunning or not C.SmartDetour or #applied.closures == 0 then return end
    detourRunning = true
    CreateThread(function()
        while #applied.closures > 0 do
            local list = nearClosures(GetEntityCoords(PlayerPedId()))
            if #list > 0 then
                detourTick(list)
                Wait(500)
            else
                Wait(2000) -- tronçons loin du joueur : rien à faire
            end
        end
        retasked = {}
        detourRunning = false
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearApplied() -- réseau routier rendu tel qu'il était
end)
