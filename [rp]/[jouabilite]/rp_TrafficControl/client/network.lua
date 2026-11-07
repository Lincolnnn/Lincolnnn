--[[
    RP TrafficControl - client : mesures appliquées au réseau routier du jeu et aux PNJ
    ----------------------------------------------------------------------------------
    Le serveur publie les mesures (GlobalState.rpTraffic) ; chaque joueur les applique à SON jeu (les nœuds et les
    zones de vitesse sont propres à chaque client ; un PNJ est dirigé par le joueur qui le contrôle).

    Une mesure = un TRONÇON (début -> fin, dans le sens de la circulation concernée) et une PORTÉE :
      'lane' (une voie), 'direction' (un sens), 'road' (route entière).
    Dans GTA V, une route n'a qu'UNE ligne de nœuds (au centre ; chaque liaison porte un nombre de voies par sens) ;
    sur les autoroutes, chaque sens est une chaussée séparée, avec ses propres nœuds. D'où :
      - FERMETURE : les nœuds retenus à la pose (ceux qui ne servent qu'à la portée choisie) sont FERMÉS (les PNJ
        n'y passent plus, aucun véhicule n'y apparaît). Et pour ce que les nœuds ne permettent pas :
          * une voie : il n'existe pas de nœud par voie. Deux moyens, ensemble :
              - FAUX OBSTACLES : rien de physique (ni collision, ni rien de visible, aucun joueur ne les touche),
                mais les PNJ du jeu agissent comme s'il y avait un véhicule arrêté EN TRAVERS de la voie (il couvre
                toute sa largeur : pas de place pour se serrer à côté) et la quittent (comportement d'origine :
                « changer de voie autour d'un obstacle ») ; seulement près du joueur, locaux ;
              - les PNJ que ce joueur contrôle sont conduits EN LIGNE DROITE (style « ForceStraightLine ») sur la
                voie ouverte la plus proche DU MÊME SENS avant le tronçon, la longent, puis reprennent leur route ;
              - les AUTRES VOIES DU MÊME SENS ralentissent à 20 MPH (Closure.SideSlow) : zones de vitesse du jeu sur
                la chaussée (autoroute) et PNJ ralentis, pour que le rabattement ne se fasse pas à pleine vitesse ;
            aucune voie du même sens : demi-tour ;
          * un sens / la route : route recalculée à l'approche, puis demi-tour s'ils continuent vers le tronçon.
      - RALENTISSEMENT / ARRÊT : zone de vitesse du jeu sur les nœuds retenus, et les PNJ de la bande choisie
        (voie / sens / route) ralentissent ou s'arrêtent avant le tronçon ; les autres voies circulent normalement.
    Mesure levée : réseau routier rendu à l'original, PNJ relâchés (route et vitesse normales).
    PLOTS posés par la police (rp_equipment, GlobalState.rpCones) : chaque dispositif (plots proches) reçoit aussi des
    faux obstacles le long de la ligne des plots : les PNJ le traitent comme infranchissable.

    Performance : aucune boucle sans mesure à moins de Config.Range m (400) ; sinon une vérification toutes les
    Config.Interval ms (300) des PNJ que ce joueur contrôle près des tronçons.
]]

TC = TC or {}
local Config = TrafficConfig
local SEG = Config.Segment or {}
local CL = Config.Closure or {}
local SP = Config.Speed or {}
local MPH = 0.44704

TC.measures = {}
local applied = { nodesOff = {}, zones = {}, blips = {} }
local active = {}     -- mesures préparées pour les PNJ (repère du tronçon)
local tracked = {}    -- [véhicule] = { id, phase, driver, at, target }
local running = false

-- =========================================================================
-- OUTILS PARTAGÉS (editor.lua, menu.lua)
-- =========================================================================
--- Herse de Riven (riven_spikes) en main ou son cordon tenu : ses touches (E, G, X, Q, molette) ont la priorité
local SPIKE_MODES = { holding = true, cord = true, throwing = true, busy = true }
function TC.spikesBusy()
    if LocalPlayer.state.rivenSpikeHand ~= nil then return true end
    if GetResourceState('riven_spikes') ~= 'started' then return false end
    local ok, mode = pcall(function() return exports.riven_spikes:getMode() end)
    return ok and SPIKE_MODES[mode] == true
end

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
    return GetStreetNameFromHashKey((GetStreetNameAtCoord(p.x, p.y, p.z)))
end

function TC.isPolice()
    local unit = LocalPlayer.state.mdcUnit
    return unit ~= nil and unit ~= false and unit ~= ''
end

local COMPASS = { 'nord', 'nord-est', 'est', 'sud-est', 'sud', 'sud-ouest', 'ouest', 'nord-ouest' }
--- Direction lisible d'un vecteur (x, y) : "nord-est"…
function TC.compass(x, y)
    local deg = (math.deg(math.atan(x, y)) + 360.0) % 360.0
    return COMPASS[math.floor((deg + 22.5) / 45.0) % 8 + 1]
end

--- Nom d'une voie : 1 = la plus à gauche dans le sens de circulation
function TC.laneName(index, count)
    if not index or not count or count <= 1 then return 'voie unique' end
    if index == 1 then return 'voie de gauche' end
    if index == count then return 'voie de droite' end
    return count == 3 and 'voie centrale' or ('voie %d'):format(index)
end

--- Repère d'un tronçon : origine (début), axe unitaire (sens), côté droit, longueur
function TC.frame(m)
    local dx, dy = m.b.x - m.a.x, m.b.y - m.a.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then return nil end
    local ax, ay = dx / length, dy / length
    return { ox = m.a.x, oy = m.a.y, ax = ax, ay = ay, rx = ay, ry = -ax, length = length }
end

--- Point -> (u le long du tronçon depuis le début, v sur le côté : + à droite du sens)
function TC.localUV(f, x, y)
    local px, py = x - f.ox, y - f.oy
    return px * f.ax + py * f.ay, px * f.rx + py * f.ry
end

--- (u, v) -> point du monde
function TC.worldAt(f, u, v, z)
    return vector3(f.ox + f.ax * u + f.rx * v, f.oy + f.ay * u + f.ry * v, z)
end

-- =========================================================================
-- RÉSEAU ROUTIER DE CE JEU : nœuds fermés, zones de vitesse, cartes
-- =========================================================================
local function nodeBox(n)
    local r, h = CL.NodeBox or 1.2, SEG.Height or 4.0
    return n.x - r, n.y - r, n.z - h, n.x + r, n.y + r, n.z + h
end

local function blipsAllowed()
    if Config.Blips == 'none' then return false end
    if Config.Blips == 'police' then return TC.isPolice() end
    return true
end

local KIND_NAME = { close = 'Fermeture', slow = 'Ralentissement', stop = 'Trafic arrêté' }
local SCOPE_NAME = { lane = 'voie', direction = 'sens', road = 'route' }

function TC.describe(m)
    local what = m.kind == 'slow' and ('Ralentissement %d MPH'):format(m.speed or 0) or KIND_NAME[m.kind] or 'Mesure'
    if m.scope == 'lane' then return ('%s : %s'):format(what, TC.laneName(m.laneIndex, m.laneCount)) end
    if m.scope == 'direction' then return ('%s : sens %s'):format(what, m.compass or '') end
    return ('%s : route entière'):format(what)
end

local function addBlips(m, f)
    local color = (Config.BlipColors or {})[m.kind] or 1
    local mid = TC.worldAt(f, f.length / 2, (m.vmin + m.vmax) / 2, (m.a.z + m.b.z) / 2)
    local area = AddBlipForArea(mid.x, mid.y, mid.z, math.max(m.vmax - m.vmin, 2.0) + 0.0, f.length + 0.0)
    SetBlipRotation(area, math.floor(GetHeadingFromVector_2d(f.ax, f.ay) + 0.5))
    SetBlipColour(area, color)
    SetBlipAlpha(area, 130)
    SetBlipDisplay(area, 3)
    local icon = AddBlipForCoord(mid.x, mid.y, mid.z)
    SetBlipSprite(icon, 1)
    SetBlipColour(icon, color)
    SetBlipScale(icon, 0.75)
    SetBlipAsShortRange(icon, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(TC.describe(m))
    EndTextCommandSetBlipName(icon)
    applied.blips[#applied.blips + 1] = area
    applied.blips[#applied.blips + 1] = icon
end

local function clearApplied()
    for _, n in ipairs(applied.nodesOff) do
        local x1, y1, z1, x2, y2, z2 = nodeBox(n)
        SetRoadsBackToOriginal(x1, y1, z1, x2, y2, z2, false)
    end
    for _, id in ipairs(applied.zones) do RemoveRoadNodeSpeedZone(id) end
    for _, blip in ipairs(applied.blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    applied = { nodesOff = {}, zones = {}, blips = {} }
end

local releaseAll, startLoop, clearObstacles -- (plus bas)

--- Mesures publiées -> réseau routier de ce jeu. Tout est retiré puis redonné (deux mesures qui se chevauchent
--- restent appliquées quand on lève l'une des deux) ; changements rares : aucun coût en continu.
function TC.applyAll(list)
    clearApplied()
    TC.measures = type(list) == 'table' and list or {}
    active = {}
    local showBlips = blipsAllowed()
    for _, m in ipairs(TC.measures) do
        local f = m.a and m.b and TC.frame(m)
        if f then
            for _, n in ipairs(m.nodes or {}) do
                if m.kind == 'close' then
                    local x1, y1, z1, x2, y2, z2 = nodeBox(n)
                    SetRoadsInArea(x1, y1, z1, x2, y2, z2, false, false) -- nœud fermé : plus aucun PNJ ne passe
                    applied.nodesOff[#applied.nodesOff + 1] = n
                else
                    local mph = m.kind == 'stop' and 0 or (m.speed or 25)
                    applied.zones[#applied.zones + 1] = AddRoadNodeSpeedZone(n.x + 0.0, n.y + 0.0, n.z + 0.0,
                        (SP.NodeZoneRadius or 4.0) + 0.0, mph * MPH, false)
                end
            end
            -- Fermeture d'une voie : les autres voies du même sens ralentissent (zones de vitesse sur la chaussée)
            if m.kind == 'close' and m.scope == 'lane' and (CL.SideSlow or 20) > 0 then
                for _, n in ipairs(m.sideNodes or {}) do
                    applied.zones[#applied.zones + 1] = AddRoadNodeSpeedZone(n.x + 0.0, n.y + 0.0, n.z + 0.0,
                        (SP.NodeZoneRadius or 4.0) + 0.0, (CL.SideSlow or 20) * MPH, false)
                end
            end
            active[#active + 1] = { m = m, f = f }
            if showBlips then addBlips(m, f) end
        end
    end
    releaseAll(true)
    clearObstacles() -- reposés à la prochaine vérification (mesures changées)
    if TC.onChange then TC.onChange() end
    startLoop()
end

AddStateBagChangeHandler('rpTraffic', 'global', function(_, _, value)
    SetTimeout(0, function() TC.applyAll(value) end)
end)

AddStateBagChangeHandler('mdcUnit', ('player:%d'):format(GetPlayerServerId(PlayerId())), function()
    if Config.Blips == 'police' then SetTimeout(0, function() TC.applyAll(GlobalState.rpTraffic) end) end
end)

CreateThread(function() TC.applyAll(GlobalState.rpTraffic) end)

-- =========================================================================
-- FAUX OBSTACLES : RIEN DE PHYSIQUE (pas de collision : ni joueur ni PNJ ne heurte quoi que ce soit ; invisibles ; l'œil
-- de rp_interact et les tirs passent au travers), mais présents pour l'IA du jeu, qui contourne un véhicule arrêté
-- (changement de voie d'origine). Véhicules du jeu de base, figés, sans conducteur, LOCAUX (chaque joueur pose les
-- siens, seulement près de lui). Deux sources :
--   - les fermetures (/trafic) : EN TRAVERS de la voie fermée, centrés sur la voie (toute sa largeur couverte : les
--     PNJ ne peuvent pas se serrer à côté et continuer sur la voie) ; sens / route : une rangée au début ;
--   - les plots posés par la police (rp_equipment) : le long de la ligne de chaque dispositif.
-- =========================================================================
local OB = Config.Obstacles or {}
local OB_MODEL = GetHashKey(OB.Model or 'blista')
local obstacles = {}     -- [clé] = { points = { { p, h } }, vehicles = { [i] = véhicule }, retry = {} }
local obstacleCount = 0
local coneSets = {}      -- dispositifs de plots : { key, center, radius, points }

local function obstaclePoints(e)
    local m, f = e.m, e.f
    local pts, max = {}, OB.MaxPerMeasure or 30
    if m.kind ~= 'close' then return pts end
    local heading = GetHeadingFromVector_2d(f.ax, f.ay)
    local function z(u) return m.a.z + (m.b.z - m.a.z) * math.max(0.0, math.min(1.0, u / f.length)) end
    if m.scope == 'lane' then
        -- centre de la bande choisie (celle dessinée à la pose), en travers : couvre la largeur de la voie
        local v = (m.vmin + m.vmax) / 2
        local spacing = math.max(3.0, OB.Spacing or 6.0)
        local u = math.min(OB.StartOffset or 2.5, f.length / 2)
        while u <= f.length - 1.0 and #pts < max do
            pts[#pts + 1] = { p = TC.worldAt(f, u, v, z(u)), h = heading + 90.0 }
            u = u + spacing
        end
    elseif OB.Barrier ~= false then
        local w = m.laneWidth or SEG.LaneWidth or 5.4
        for _, u in ipairs(m.scope == 'road' and { 1.5, f.length - 1.5 } or { 1.5 }) do
            local v = m.vmin + w / 2
            while v <= m.vmax - w / 2 + 0.01 and #pts < max do
                pts[#pts + 1] = { p = TC.worldAt(f, u, v, z(u)), h = heading + 90.0 } -- en travers de la voie
                v = v + w
            end
        end
    end
    return pts
end

-- =========================================================================
-- PLOTS DE LA POLICE (rp_equipment : GlobalState.rpCones) -> dispositifs infranchissables
-- =========================================================================
local CO = OB.Cones or {}

--- Plots proches regroupés ; la ligne d'un dispositif (de l'extrémité à l'autre, dans l'ordre) reçoit des faux
--- obstacles tous les ConeSpacing m, orientés le long de la ligne ; un plot seul : un obstacle dans le sens de la route
local function buildConeSets(list)
    local cones = {}
    for _, c in pairs(type(list) == 'table' and list or {}) do
        if type(c) == 'table' and tonumber(c.x) and tonumber(c.y) then
            cones[#cones + 1] = vector3(c.x + 0.0, c.y + 0.0, (tonumber(c.z) or 0.0) + 0.0)
        end
    end
    local sets, used = {}, {}
    local groupDist = CO.GroupDistance or 6.0
    for i = 1, #cones do
        if not used[i] then
            local group, queue = {}, { i }
            used[i] = true
            while #queue > 0 do
                local k = table.remove(queue)
                group[#group + 1] = cones[k]
                for j = 1, #cones do
                    if not used[j] and #(cones[j].xy - cones[k].xy) <= groupDist then used[j] = true; queue[#queue + 1] = j end
                end
            end
            -- extrémités : les deux plots les plus éloignés ; ordre le long de cet axe
            local a, b, best = group[1], group[1], -1
            for x = 1, #group do for y = x + 1, #group do
                local d = #(group[x].xy - group[y].xy)
                if d > best then a, b, best = group[x], group[y], d end
            end end
            local axis = b - a
            table.sort(group, function(p, q) return (p.x - a.x) * axis.x + (p.y - a.y) * axis.y < (q.x - a.x) * axis.x + (q.y - a.y) * axis.y end)
            local pts, cx, cy, cz = {}, 0.0, 0.0, 0.0
            for _, c in ipairs(group) do cx, cy, cz = cx + c.x, cy + c.y, cz + c.z end
            local center = vector3(cx / #group, cy / #group, cz / #group)
            if #group == 1 then
                local ok, _, heading = GetClosestVehicleNodeWithHeading(center.x, center.y, center.z, 1, 3.0, 0)
                pts[1] = { p = center, h = ok and heading or 0.0 }
            else
                local step = math.max(2.0, CO.Spacing or 3.5)
                for x = 1, #group - 1 do
                    local p1, p2 = group[x], group[x + 1]
                    local d = #(p2.xy - p1.xy)
                    local h = GetHeadingFromVector_2d(p2.x - p1.x, p2.y - p1.y)
                    local n = math.max(1, math.ceil(d / step))
                    for t = (x == 1 and 0 or 1), n do
                        pts[#pts + 1] = { p = p1 + (p2 - p1) * (t / n), h = h }
                    end
                end
            end
            while #pts > (CO.MaxPerGroup or 20) do table.remove(pts) end
            sets[#sets + 1] = { key = ('cone:%d'):format(#sets + 1), center = center, radius = best / 2, points = pts }
        end
    end
    return sets
end

local function deleteObstacle(vehicle)
    if vehicle and DoesEntityExist(vehicle) then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteVehicle(vehicle)
    end
    obstacleCount = math.max(0, obstacleCount - 1)
end

--- id nil : tout ; une clé : cet ensemble ; prefix = true : toutes les clés qui commencent par id
clearObstacles = function(id, prefix)
    for key, set in pairs(obstacles) do
        if id == nil or key == id or (prefix and tostring(key):sub(1, #id) == id) then
            for _, vehicle in pairs(set.vehicles) do deleteObstacle(vehicle) end
            obstacles[key] = nil
        end
    end
end

--- Un faux obstacle : nil (rien posé : limite, véhicule déjà là) ; rien de physique (pas de collision), invisible
local function spawnObstacle(pt)
    if obstacleCount >= (OB.MaxTotal or 80) then return nil end
    local p = pt.p
    local found, ground = GetGroundZFor_3dCoord(p.x, p.y, p.z + 3.0, false)
    local z = found and ground or p.z
    if IsAnyVehicleNearPoint(p.x, p.y, z, OB.FreeRadius or 2.6) then return nil end
    local vehicle = CreateVehicle(OB_MODEL, p.x, p.y, z + 0.3, pt.h % 360.0, false, false)
    if not vehicle or vehicle == 0 then return nil end
    obstacleCount = obstacleCount + 1
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    FreezeEntityPosition(vehicle, true)
    SetEntityInvincible(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, false)
    SetVehicleDoorsLocked(vehicle, 2)
    SetVehicleUndriveable(vehicle, true)
    SetVehicleEngineOn(vehicle, false, true, true)
    SetVehicleLights(vehicle, 1)
    SetVehicleIsConsideredByPlayer(vehicle, false)
    SetEntityCollision(vehicle, OB.Collision == true, OB.Collision == true) -- rien de physique (par défaut)
    if OB.Debug then
        SetEntityAlpha(vehicle, 110, false) -- réglage : visibles en transparence
    else
        SetEntityVisible(vehicle, false, false)
    end
    return vehicle
end

--- Faux obstacles des sources proches (fermetures, dispositifs de plots) posés peu à peu (quelques-uns par
--- vérification) ; ceux des sources lointaines ou disparues retirés
local function updateObstacles(near, here)
    if OB.Enabled == false then return end
    local sources = {}
    local range = OB.Range or 220.0
    for _, e in ipairs(near) do
        if e.m.kind == 'close' then
            local mid = TC.worldAt(e.f, e.f.length / 2, 0, 0)
            sources[#sources + 1] = { key = 'm:' .. tostring(e.m.id), x = mid.x, y = mid.y, radius = e.f.length / 2,
                build = function() return obstaclePoints(e) end }
        end
    end
    if CO.Enabled ~= false then
        for _, set in ipairs(coneSets) do
            sources[#sources + 1] = { key = set.key, x = set.center.x, y = set.center.y, radius = set.radius,
                build = function() return set.points end }
        end
    end
    local keep = {}
    for _, src in ipairs(sources) do
        local dx, dy = src.x - here.x, src.y - here.y
        if math.sqrt(dx * dx + dy * dy) < range + src.radius then
            keep[src.key] = true
            local set = obstacles[src.key]
            if not set then
                set = { points = src.build(), vehicles = {}, retry = {} }
                obstacles[src.key] = set
            end
            if #set.points > 0 then
                if not HasModelLoaded(OB_MODEL) then
                    RequestModel(OB_MODEL)
                else
                    local budget, now = OB.PerTick or 6, GetGameTimer()
                    for i, pt in ipairs(set.points) do
                        if budget <= 0 then break end
                        local vehicle = set.vehicles[i]
                        if (not vehicle or not DoesEntityExist(vehicle)) and (set.retry[i] or 0) <= now then
                            if vehicle then obstacleCount = math.max(0, obstacleCount - 1) end
                            set.vehicles[i] = spawnObstacle(pt)
                            -- place prise (véhicule garé là…) : réessayé plus tard, les suivants passent avant
                            if not set.vehicles[i] then set.retry[i] = now + 3000 end
                            budget = budget - 1
                        end
                    end
                end
            end
        end
    end
    for key in pairs(obstacles) do if not keep[key] then clearObstacles(key) end end
    if next(obstacles) == nil then SetModelAsNoLongerNeeded(OB_MODEL) end
end

function TC.isObstacle(entity)
    for _, set in pairs(obstacles) do
        for _, vehicle in pairs(set.vehicles) do if vehicle == entity then return true end end
    end
    return false
end
exports('isObstacle', TC.isObstacle)

-- Plots posés / ramassés (rp_equipment) : dispositifs recalculés, leurs faux obstacles reposés
local function onCones(list)
    clearObstacles('cone:', true)
    coneSets = buildConeSets(list)
    startLoop()
end
AddStateBagChangeHandler('rpCones', 'global', function(_, _, value)
    SetTimeout(0, function() onCones(value) end)
end)
CreateThread(function() onCones(GlobalState.rpCones) end)

-- =========================================================================
-- PNJ : changement de voie, demi-tour, ralentissement, arrêt
-- =========================================================================
local function measureById(id)
    for _, e in ipairs(active) do if e.m.id == id then return e end end
    return nil
end

local function resume(vehicle, info)
    tracked[vehicle] = nil
    local driver = info.driver
    if not DoesEntityExist(vehicle) or not DoesEntityExist(driver) or not NetworkHasControlOfEntity(driver)
        or GetPedInVehicleSeat(vehicle, -1) ~= driver then return end
    if info.phase == 'slow' then
        SetDriveTaskCruiseSpeed(driver, CL.ResumeSpeed or 17.0)       -- vitesse normale
    elseif info.phase == 'merge' or info.phase == 'pass' or info.phase == 'uturn' then
        TaskVehicleDriveWander(driver, vehicle, CL.ResumeSpeed or 17.0, CL.WanderStyle or 786603) -- reprend sa route
    end -- 'stop' : le freinage s'arrête tout seul ; 'replan' : il roule déjà librement
end

--- Mesures retirées / changées : PNJ relâchés (keep = garder ceux dont la mesure existe encore)
releaseAll = function(keep)
    for vehicle, info in pairs(tracked) do
        if not keep or not measureById(info.id) then resume(vehicle, info) end
    end
end

--- Vers où envoyer un PNJ (u, v dans le repère du tronçon, sens du tronçon)
local function driveTo(driver, vehicle, p, speed)
    TaskVehicleDriveToCoord(driver, vehicle, p.x, p.y, p.z, speed, 0, GetEntityModel(vehicle), CL.DrivingStyle or 786603, 3.0, true)
end

--- Changement de voie : EN LIGNE DROITE vers le point (le suivi de route du jeu garderait sa voie jusqu'au point) ;
--- le style garde l'arrêt pour les véhicules / piétons et le contournement des véhicules arrêtés et des objets
local STRAIGHT = 16777216 -- « ForceStraightLine » (style de conduite du jeu)
local function steerTo(driver, vehicle, p, speed)
    local style = CL.MergeStyle or (STRAIGHT + 1 + 2 + 8 + 32)
    TaskVehicleDriveToCoord(driver, vehicle, p.x, p.y, p.z, speed, 0, GetEntityModel(vehicle), style, 2.0, true)
end

--- Demi-tour : vers l'arrière, sur une voie de l'autre sens (route à double sens), sinon un point loin derrière
local function uturn(e, vehicle, driver, info, sign, pos)
    local m, f = e.m, e.f
    local back
    local u = TC.localUV(f, pos.x, pos.y)
    if (m.oppositeLanes or 0) > 0 then
        -- voies d'en face (à gauche du sens concerné) : premier voie de l'autre sens
        local v = -((m.median or 0) / 2 + (m.laneWidth or 5.4) / 2)
        back = TC.worldAt(f, u - 120 * sign, v * sign, pos.z)
    else
        back = TC.worldAt(f, u - 150 * sign, 0, pos.z)
    end
    TaskVehicleDriveToCoordLongrange(driver, vehicle, back.x, back.y, back.z, CL.RedirectSpeed or 14.0, CL.DrivingStyle or 786603, 15.0)
    info.phase, info.at, info.target = 'uturn', GetGameTimer(), back
end

--- Voie ouverte la plus proche, du même sens que la voie fermée ; nil s'il n'y en a pas
local function openLane(m)
    local best, bestDist
    for _, off in ipairs(m.lanes or {}) do
        if math.abs(off - (m.closedLane or 0)) > 0.5 then
            local d = math.abs(off - m.closedLane)
            if not best or d < bestDist then best, bestDist = off, d end
        end
    end
    return best
end

--- Bande de tout le sens d'une fermeture de voie (pour ralentir les autres voies) : { vmin, vmax } ou nil
local function sideBand(m)
    if m.kind ~= 'close' or m.scope ~= 'lane' or (CL.SideSlow or 20) <= 0 or not m.lanes or #m.lanes < 2 then return nil end
    local lo, hi = math.huge, -math.huge
    for _, off in ipairs(m.lanes) do lo, hi = math.min(lo, off), math.max(hi, off) end
    local half = (m.laneWidth or SEG.LaneWidth or 5.4) / 2
    return { lo - half, hi + half }
end

local function handle(e, vehicle, driver, pos, fwd, speed, now)
    local m, f = e.m, e.f
    local along = fwd.x * f.ax + fwd.y * f.ay
    local sign = along > 0.3 and 1 or (along < -0.3 and -1 or 0)
    if sign == 0 or (m.scope ~= 'road' and sign ~= 1) then return false end
    local u, v = TC.localUV(f, pos.x, pos.y)
    local vmin, vmax = m.vmin, m.vmax
    if sign == -1 then u, v, vmin, vmax = f.length - u, -v, -m.vmax, -m.vmin end -- route entière, autre sens
    local info = tracked[vehicle]
    if info and info.id ~= m.id then return false end
    -- Hors de la bande : pas concerné, sauf un PNJ déjà rabattu sur une autre voie (suivi jusqu'à la fin du tronçon)
    local merging = info and (info.phase == 'merge' or info.phase == 'pass')
    local outside = v < vmin - 0.8 or v > vmax + 0.8
    if outside and not merging then
        -- Fermeture d'une voie : les AUTRES voies du même sens ralentissent (20 MPH) autour du tronçon
        local side = sideBand(m)
        if side and v >= side[1] - 0.8 and v <= side[2] + 0.8 and u >= -(CL.SideSlowFrom or 60.0) and u <= f.length + 5 then
            SetDriveTaskCruiseSpeed(driver, (CL.SideSlow or 20) * MPH)
            if not info then tracked[vehicle] = { id = m.id, phase = 'slow', driver = driver, at = now } end
            return true
        end
        return false
    end

    if m.kind == 'slow' then
        if u >= -(SP.SlowFrom or 25.0) and u <= f.length then
            -- redonnée à chaque vérification (une autre tâche du jeu la remettrait sinon à la vitesse normale)
            SetDriveTaskCruiseSpeed(driver, (m.speed or 25) * MPH)
            if not info then tracked[vehicle] = { id = m.id, phase = 'slow', driver = driver, at = now } end
            return true
        end
        return false
    end

    if m.kind == 'stop' then
        if u >= -(SP.StopBefore or 20.0) and u <= f.length then
            TaskVehicleTempAction(driver, vehicle, 6, (Config.Interval or 300) + 900) -- freine et reste arrêté
            tracked[vehicle] = { id = m.id, phase = 'stop', driver = driver, at = now }
            return true
        end
        return false
    end

    -- FERMETURE
    local approach = CL.ApproachDistance or 60.0
    if m.scope == 'lane' then
        if u < -approach or u > f.length + 5 then return false end
        local target = openLane(m)
        if not target then
            -- aucune voie ouverte dans ce sens : demi-tour
            if not info or info.phase ~= 'uturn' then
                local new = { id = m.id, driver = driver }
                tracked[vehicle] = new
                uturn(e, vehicle, driver, new, 1, pos)
            end
            return true
        end
        -- Rabattement EN LIGNE DROITE sur la voie ouverte (point qui avance avec le PNJ), puis il longe le tronçon
        -- sur cette voie jusqu'après la fin, et reprend sa route. Nouvelle consigne seulement quand il approche du
        -- point visé (pas à chaque vérification).
        local z = pos.z
        local cap = CL.RedirectSpeed or 18.0
        if (CL.SideSlow or 20) > 0 then cap = math.min(cap, (CL.SideSlow or 20) * MPH) end -- comme les voies ralenties
        local spd = math.max(math.min(8.0, cap), math.min(math.max(speed, 8.0), cap))
        local inLane = math.abs(v - target) < (CL.InLaneTolerance or 1.3)
        local phase = (info and info.phase == 'pass' or inLane) and 'pass' or 'merge'
        if phase == 'pass' and u > f.length + 6 then return false end -- tronçon dépassé : relâché (reprend sa route)
        local lead = phase == 'merge' and math.max(CL.MergeLead or 22.0, speed * 1.6) or math.max(CL.PassLead or 25.0, speed * 1.8)
        local wantU = math.min(u + lead, f.length + 15)
        local stale = not info or info.phase ~= phase or not info.wpU or (info.wpU - u) < math.max(8.0, speed * 0.9)
            or now - (info.at or 0) > (CL.Refresh or 4000)
        if stale then
            steerTo(driver, vehicle, TC.worldAt(f, wantU, target, z), spd)
            tracked[vehicle] = { id = m.id, phase = phase, driver = driver, at = now, wpU = wantU, since = info and info.since or now }
        end
        local t = tracked[vehicle]
        if t and now - (t.since or now) > (CL.PhaseTimeout or 25000) then return false end -- bloqué : relâché
        return true
    end

    -- Sens / route fermés : route recalculée à l'approche, demi-tour s'il continue vers le tronçon
    if u > -1 or u < -approach then return false end
    if not info then
        if u < -(CL.ReplanDistance or 45.0) * 0.5 then
            TaskVehicleDriveWander(driver, vehicle, math.max(speed, 10.0), CL.WanderStyle or 786603)
            tracked[vehicle] = { id = m.id, phase = 'replan', driver = driver, at = now }
        else
            tracked[vehicle] = { id = m.id, driver = driver }
            uturn(e, vehicle, driver, tracked[vehicle], sign, pos)
        end
    elseif info.phase == 'replan' and now - info.at > 1500 and u > -(CL.ReplanDistance or 45.0) * 0.5 then
        uturn(e, vehicle, driver, info, sign, pos)
    end
    return true
end

local function tick()
    local here = GetEntityCoords(PlayerPedId())
    local near = {}
    for _, e in ipairs(active) do
        local mid = TC.worldAt(e.f, e.f.length / 2, 0, 0)
        local dx, dy = mid.x - here.x, mid.y - here.y
        if math.sqrt(dx * dx + dy * dy) < (Config.Range or 400.0) + e.f.length / 2 then near[#near + 1] = e end
    end
    local now = GetGameTimer()
    updateObstacles(near, here)
    if #near > 0 then
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            local driver = GetPedInVehicleSeat(vehicle, -1)
            if driver ~= 0 and not IsPedAPlayer(driver) and NetworkHasControlOfEntity(driver) and not IsPedDeadOrDying(driver, true) then
                local pos, fwd, speed = GetEntityCoords(vehicle), GetEntityForwardVector(vehicle), GetEntitySpeed(vehicle)
                local handled = false
                for _, e in ipairs(near) do
                    if handle(e, vehicle, driver, pos, fwd, speed, now) then handled = true break end
                end
                local info = tracked[vehicle]
                -- Sorti de la mesure (dépassé le tronçon, changé de route, demi-tour fait) : relâché
                if info and not handled and info.phase ~= 'uturn' then resume(vehicle, info) end
            end
        end
    end
    for vehicle, info in pairs(tracked) do
        if not DoesEntityExist(vehicle) then
            tracked[vehicle] = nil
        elseif info.phase == 'uturn' and (now - (info.at or now) > 25000
            or (info.target and #(GetEntityCoords(vehicle) - info.target) < 20.0)) then
            resume(vehicle, info)
        end
    end
    return #near > 0 or next(tracked) ~= nil or next(obstacles) ~= nil or #coneSets > 0
end

startLoop = function()
    if running or (#active == 0 and #coneSets == 0) then return end
    running = true
    CreateThread(function()
        while #active > 0 or #coneSets > 0 or next(tracked) ~= nil or next(obstacles) ~= nil do
            local busy = tick()
            Wait(busy and (Config.Interval or 300) or 2000)
        end
        running = false
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    active = {}
    coneSets = {}
    releaseAll(false)
    clearObstacles()
    clearApplied() -- réseau routier rendu tel qu'il était
end)
