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

--- Vitesse (MPH) à u m du début de la zone (u < 0 : en amont) pour une limite `limit` dans la zone : elle baisse
--- progressivement de Speed.UpstreamStart (à Speed.Upstream m avant) jusqu'à la limite (au début de la zone)
function TC.rampMph(u, limit)
    if u >= 0 then return limit end
    local start = SP.UpstreamStart or 70
    if limit >= start then return limit end
    local t = math.min(1.0, -u / (SP.Upstream or 150.0))
    return limit + (start - limit) * t
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
    applied.blips[#applied.blips + 1] = area
    -- Points le long de la zone, du début à la fin (Blip.Spacing m ; au moins le début et la fin)
    local BL = Config.Blip or {}
    local count = math.max(2, math.min(BL.Max or 10, math.floor(f.length / (BL.Spacing or 25.0)) + 1))
    local vmid = (m.vmin + m.vmax) / 2
    for i = 0, count - 1 do
        local u = f.length * i / (count - 1)
        local p = TC.worldAt(f, u, vmid, m.a.z + (m.b.z - m.a.z) * (u / f.length))
        local icon = AddBlipForCoord(p.x, p.y, p.z)
        SetBlipSprite(icon, BL.Sprite or 1)
        SetBlipColour(icon, color)
        SetBlipScale(icon, (i == 0 or i == count - 1) and (BL.EndScale or 0.7) or (BL.Scale or 0.5))
        SetBlipAsShortRange(icon, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(TC.describe(m))
        EndTextCommandSetBlipName(icon)
        applied.blips[#applied.blips + 1] = icon
    end
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
            if m.kind == 'close' then
                for _, n in ipairs(m.nodes or {}) do
                    local x1, y1, z1, x2, y2, z2 = nodeBox(n)
                    SetRoadsInArea(x1, y1, z1, x2, y2, z2, false, false) -- nœud fermé : plus aucun PNJ ne passe
                    applied.nodesOff[#applied.nodesOff + 1] = n
                end
            end
            local e = { m = m, f = f }
            e.vc = TC.virtualCones(e)          -- plots virtuels (plus bas)
            TC.speedZones(e, applied.zones) -- zones de vitesse du jeu (plus bas)
            active[#active + 1] = e
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

--- Voie ouverte la plus proche, du même sens que la voie fermée (décalage) ; nil s'il n'y en a pas
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

--- Bande de TOUT le sens d'une mesure (toutes ses voies) : { vmin, vmax } ; route entière : la bande choisie
local function dirBand(m)
    if m.scope == 'road' or not m.lanes or #m.lanes == 0 then return { m.vmin, m.vmax } end
    local lo, hi = math.huge, -math.huge
    for _, off in ipairs(m.lanes) do lo, hi = math.min(lo, off), math.max(hi, off) end
    local half = (m.laneWidth or SEG.LaneWidth or 5.4) / 2
    return { lo - half, hi + half }
end

-- =========================================================================
-- PLOTS VIRTUELS : invisibles, sans collision (rien dans le monde), traités comme les plots de la police :
--   - fermeture d'une voie (avec une voie ouverte à côté) : biseau en amont (du bord extérieur de la voie fermée au bord
--     de la voie ouverte), puis une ligne le long de ce bord jusqu'à la fin -> les PNJ CONTOURNENT ;
--   - arrêt du trafic, fermeture d'un sens / de la route, voie sans autre voie : une ligne EN TRAVERS du sens au début
--     de la zone (route entière : aussi à la fin, pour l'autre sens) -> les PNJ S'ARRÊTENT devant.
-- Chaque ligne reçoit aussi des faux obstacles (IA du jeu, tous les PNJ) ; les PNJ que ce joueur contrôle suivent
-- la même logique que les plots de la police (contourner si un passage existe sur la route, sinon s'arrêter).
-- =========================================================================
local VC = Config.VirtualCones or {}

local function virtualCones(e)
    local m, f = e.m, e.f
    if VC.Enabled == false or m.kind == 'slow' then return nil end
    local function z(u) return m.a.z + (m.b.z - m.a.z) * math.max(0.0, math.min(1.0, u / f.length)) end
    local cones, inset = {}, VC.Inset or 0.3
    local function addLine(u1, v1, u2, v2, step)
        local d = math.sqrt((u2 - u1) ^ 2 + (v2 - v1) ^ 2)
        local n = math.max(1, math.ceil(d / step))
        for i = (#cones == 0 and 0 or 1), n do
            local t = i / n
            local u, v = u1 + (u2 - u1) * t, v1 + (v2 - v1) * t
            cones[#cones + 1] = TC.worldAt(f, u, v, z(u))
        end
    end
    local target = m.kind == 'close' and m.scope == 'lane' and openLane(m) or nil
    if target then
        -- CORRIDOR : biseau en amont puis ligne le long du bord de la voie ouverte ; les PNJ CONTOURNENT par une voie
        -- du même sens (jamais par l'autre sens) ; faux obstacles le long de la ligne
        local openRight = target > (m.closedLane or (m.vmin + m.vmax) / 2)
        local vNear = openRight and (m.vmax - inset) or (m.vmin + inset)
        local vFar = openRight and (m.vmin + inset) or (m.vmax - inset)
        addLine(-(VC.Taper or 30.0), vFar, 0.0, vNear, VC.Spacing or 3.0)
        addLine(0.0, vNear, f.length, vNear, VC.Spacing or 3.0)
        local side = dirBand(m)
        local open = openRight and { m.vmax, side[2] } or { side[1], m.vmin }
        return { mode = 'deviate', cones = cones, obstacles = true, open = open }
    end
    local twoWay = (m.oppositeLanes or 0) > 0 and m.scope ~= 'road'
    local band = m.kind == 'close' and { m.vmin, m.vmax } or dirBand(m)
    addLine(0.0, band[1] + inset, 0.0, band[2] - inset, VC.LineSpacing or 2.0)
    if m.scope == 'road' then
        local first = #cones
        addLine(f.length, band[1] + inset, f.length, band[2] - inset, VC.LineSpacing or 2.0)
        if #cones == first then cones[#cones + 1] = TC.worldAt(f, f.length, band[1] + inset, z(f.length)) end
    end
    if m.kind == 'stop' then
        -- ARRÊT : ligne d'attente ; jamais de faux obstacle (l'IA du jeu chercherait à doubler par l'autre sens)
        return { mode = 'hold', cones = cones, obstacles = false }
    end
    -- FERMETURE sans autre voie du même sens : demi-tour ; route à double sens : pas de faux obstacle (l'IA
    -- doublerait par la voie d'en face), la voie est gardée par une zone de vitesse à 0 (plus bas)
    return { mode = twoWay and 'uturn' or 'block', cones = cones, obstacles = not twoWay }
end

--- Plots virtuels d'une mesure, avec leur centre et leur rayon (pour ne regarder que les PNJ proches)
function TC.virtualCones(e)
    local set = virtualCones(e)
    if not set or #set.cones == 0 then return nil end
    local cx, cy, cz = 0.0, 0.0, 0.0
    for _, c in ipairs(set.cones) do cx, cy, cz = cx + c.x, cy + c.y, cz + c.z end
    set.center = vector3(cx / #set.cones, cy / #set.cones, cz / #set.cones)
    set.radius = 0.0
    for _, c in ipairs(set.cones) do set.radius = math.max(set.radius, #(c - set.center)) end
    return set
end

--- Faux obstacles le long des plots virtuels (orientés dans l'axe de la ligne)
local function obstaclePoints(e)
    local set = e.vc
    local pts, max = {}, OB.MaxPerMeasure or 60
    if not set or not set.obstacles then return pts end
    for i, c in ipairs(set.cones) do
        if #pts >= max then break end
        local nxt, prv = set.cones[i + 1], set.cones[i - 1]
        local dx, dy = 0.0, 1.0
        if nxt then dx, dy = nxt.x - c.x, nxt.y - c.y elseif prv then dx, dy = c.x - prv.x, c.y - prv.y end
        pts[#pts + 1] = { p = c, h = GetHeadingFromVector_2d(dx, dy) }
    end
    return pts
end

-- =========================================================================
-- ZONES DE VITESSE DU JEU (pour TOUS les PNJ) : des SPHÈRES qui se chevauchent le long de la bande, au centre de la
-- bande, assez grandes pour la couvrir (rayon = demi-largeur + marge), chacune à sa vitesse (progressive en amont).
-- (Avant : de petites zones de 4 m autour des nœuds, que les voitures traversaient en un instant.) En complément, les
-- nœuds de ce sens envoyés à la pose.
-- =========================================================================
local zonesWarned = false
local function sphereBand(e, out, lo, hi, u1, u2, speedAt, margin)
    local m, f = e.m, e.f
    if hi <= lo or u2 < u1 then return end
    local R = math.max(SP.MinSphere or 3.0, (hi - lo) / 2 + (margin or SP.SphereMargin or 1.0))
    -- réparties régulièrement, les deux bouts compris (au plus MaxSpheres ; espacement <= rayon x SphereStep)
    local maxN = SP.MaxSpheres or 20
    local n = math.max(2, math.min(maxN, math.ceil((u2 - u1) / (R * (SP.SphereStep or 1.3))) + 1))
    -- trop de sphères pour la longueur : rayon un peu plus grand (jamais de trou), sans déborder de plus de 3 m
    local spacing = (u2 - u1) / (n - 1)
    if spacing > R * 1.6 then R = math.min(spacing / 1.6, (hi - lo) / 2 + (margin or SP.SphereMargin or 1.0) + 3.0) end
    local vmid = (lo + hi) / 2
    for i = 0, n - 1 do
        if #out >= (SP.MaxZonesTotal or 120) then
            if not zonesWarned then
                zonesWarned = true
                print('^3[rp_TrafficControl]^7 trop de zones de vitesse en même temps (Speed.MaxZonesTotal) : certaines ne sont pas posées')
            end
            return
        end
        local u = u1 + (u2 - u1) * i / (n - 1)
        local z = m.a.z + (m.b.z - m.a.z) * math.max(0.0, math.min(1.0, u / f.length))
        local p = TC.worldAt(f, u, vmid, z)
        local id = AddRoadNodeSpeedZone(p.x + 0.0, p.y + 0.0, p.z + 0.0, R + 0.0, math.max(0.0, speedAt(u)) * MPH, false)
        if not id or id < 0 then return end -- le jeu n'en accepte plus
        out[#out + 1] = id
    end
end

function TC.speedZones(e, out)
    local m, f = e.m, e.f
    local L, up = f.length, SP.Upstream or 150.0
    if m.kind == 'slow' or m.kind == 'stop' then
        local limit = m.kind == 'stop' and 0 or (m.speed or 25)
        local b = dirBand(m)
        if m.scope == 'road' then
            -- route entière : les deux sens, chacun avec son amont (avant le début / après la fin)
            sphereBand(e, out, b[1], b[2], -up, L + up, function(u)
                return TC.rampMph(u < 0 and u or (u > L and (L - u) or 0.0), limit)
            end)
        else
            -- arrêt : jusqu'au début de la zone (le trafic attend devant ; ceux déjà dedans en sortent)
            sphereBand(e, out, b[1], b[2], -up, m.kind == 'stop' and 0.0 or L, function(u) return TC.rampMph(u, limit) end)
        end
        for _, n in ipairs(m.dirNodes or {}) do
            if not (m.kind == 'stop' and m.scope ~= 'road' and (n.u or 0) > 0) then
                out[#out + 1] = AddRoadNodeSpeedZone(n.x + 0.0, n.y + 0.0, n.z + 0.0, (SP.NodeZoneRadius or 4.0) + 0.0,
                    TC.rampMph(n.u or 0, limit) * MPH, false)
            end
        end
        return
    end
    if m.kind ~= 'close' then return end
    if m.scope == 'lane' and openLane(m) then
        -- autres voies du même sens : SideSlow MPH, progressif depuis l'amont
        local vc = e.vc or {}
        local open = vc.open
        if not open then
            local side = dirBand(m)
            open = openLane(m) > (m.closedLane or 0) and { m.vmax, side[2] } or { side[1], m.vmin }
        end
        if (CL.SideSlow or 20) > 0 then
            sphereBand(e, out, open[1], open[2], -up, L, function(u) return TC.rampMph(u, CL.SideSlow or 20) end)
        end
        -- CORRIDOR : la voie fermée, dans la zone, à 0 (un PNJ qui y entrerait s'y arrête au lieu d'y rouler)
        if CL.Corridor ~= false then sphereBand(e, out, m.vmin, m.vmax, 2.0, L, function() return 0 end, 0.3) end
        return
    end
    -- Fermeture sans autre voie du même sens (ou sens / route) : la bande fermée gardée à 0, du début à la fin
    if CL.Corridor ~= false then sphereBand(e, out, m.vmin, m.vmax, -2.0, L, function() return 0 end, 0.3) end
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

local ownObstacle = {} -- [véhicule] = true : nos faux obstacles

local function deleteObstacle(vehicle)
    if vehicle then ownObstacle[vehicle] = nil end
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

--- Un VRAI véhicule (pas un de nos faux obstacles) à moins de `radius` m du point (police garée dans la voie…)
local function realVehicleNear(x, y, radius)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if not ownObstacle[vehicle] then
            local p = GetEntityCoords(vehicle)
            local dx, dy = p.x - x, p.y - y
            if dx * dx + dy * dy <= radius * radius then return true end
        end
    end
    return false
end

--- Un faux obstacle : nil (rien posé : limite, véhicule déjà là) ; rien de physique (pas de collision), invisible
local function spawnObstacle(pt)
    if obstacleCount >= (OB.MaxTotal or 80) then return nil end
    local p = pt.p
    local found, ground = GetGroundZFor_3dCoord(p.x, p.y, p.z + 3.0, false)
    local z = found and ground or p.z
    if realVehicleNear(p.x, p.y, OB.FreeRadius or 2.6) then return nil end
    local vehicle = CreateVehicle(OB_MODEL, p.x, p.y, z + 0.3, pt.h % 360.0, false, false)
    if not vehicle or vehicle == 0 then return nil end
    obstacleCount = obstacleCount + 1
    ownObstacle[vehicle] = true
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
        if e.vc then -- plots virtuels (fermeture, arrêt)
            local mid = TC.worldAt(e.f, e.f.length / 2, 0, 0)
            sources[#sources + 1] = { key = 'm:' .. tostring(e.m.id), x = mid.x, y = mid.y, radius = e.f.length / 2 + (VC.Taper or 30.0),
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
    if info.capped and DoesEntityExist(vehicle) then SetEntityMaxSpeed(vehicle, 500.0) end -- vitesse max rendue
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


local function handle(e, vehicle, driver, pos, fwd, speed, now)
    local m, f = e.m, e.f
    local along = fwd.x * f.ax + fwd.y * f.ay
    local sign = along > 0.3 and 1 or (along < -0.3 and -1 or 0)
    if sign == 0 or (m.scope ~= 'road' and sign ~= 1) then return false end
    local u, v = TC.localUV(f, pos.x, pos.y)
    local vmin, vmax = m.vmin, m.vmax
    local band = dirBand(m)
    if sign == -1 then -- route entière, autre sens
        u, v, vmin, vmax = f.length - u, -v, -m.vmax, -m.vmin
        band = { -band[2], -band[1] }
    end
    local info = tracked[vehicle]
    if info and info.id ~= m.id then return false end
    local up = SP.Upstream or 150.0

    -- GARDE ANTI CONTRESENS (route à double sens) : un PNJ de ce sens sur la voie d'en face, près de la zone (il
    -- double) : fermeture -> demi-tour ; arrêt -> il s'arrête et attend
    local approach = CL.ApproachDistance or 60.0
    if (m.oppositeLanes or 0) > 0 and m.scope ~= 'road' and sign == 1 and m.kind ~= 'slow' then
        local oppWidth = m.oppositeLanes * (m.laneWidth or SEG.LaneWidth or 5.4) + 2.5
        if v < band[1] - 0.8 and v > band[1] - oppWidth and u >= -approach and u <= f.length + 5 then
            if m.kind == 'stop' then
                TaskVehicleTempAction(driver, vehicle, 6, (Config.Interval or 300) + 900)
                tracked[vehicle] = { id = m.id, phase = 'stop', driver = driver, at = now }
            elseif not info or info.phase ~= 'uturn' then
                tracked[vehicle] = { id = m.id, driver = driver }
                uturn(e, vehicle, driver, tracked[vehicle], 1, pos)
            end
            return true
        end
    end

    -- RALENTISSEMENT / ARRÊT : TOUT LE SENS (toutes ses voies, la voie choisie et les autres), progressif depuis
    -- l'amont : la vitesse visée baisse de UpstreamStart jusqu'à la limite au début de la zone, jamais au-dessus de la
    -- vitesse du PNJ quand il est entré dans le périmètre (il freine, il n'accélère jamais) ; redonnée à chaque
    -- vérification, et vitesse max du véhicule bridée d'autant (SetEntityMaxSpeed, rendue à la sortie).
    -- ARRÊT : la route est bloquée. Le PNJ freine progressivement, s'arrête au début de la zone et ATTEND jusqu'à la
    -- levée ; il ne cherche jamais à contourner. File d'attente : un PNJ presque arrêté derrière attend aussi (il ne
    -- double pas). Ceux déjà dans la zone en sortent.
    if m.kind == 'slow' or m.kind == 'stop' then
        local margin = SP.BandMargin or 1.5
        local uMax = (m.kind == 'stop' and m.scope ~= 'road') and 0.0 or f.length
        if v < band[1] - margin or v > band[2] + margin or u < -up or u > uMax then return false end
        local start = info and info.startSpeed or math.max(speed, 6.0)
        local hold = m.kind == 'stop' and (u >= -(SP.StopBefore or 8.0) or (speed < 1.5 and u >= -(SP.QueueLength or 150.0)))
        if hold then
            TaskVehicleTempAction(driver, vehicle, 6, (Config.Interval or 300) + 900) -- freine et reste arrêté
            tracked[vehicle] = { id = m.id, phase = 'stop', driver = driver, at = now, startSpeed = start, capped = info and info.capped }
        else
            local limit = m.kind == 'stop' and 0 or (m.speed or 25)
            local target = math.max(math.min(start, TC.rampMph(u, limit) * MPH), m.kind == 'stop' and 1.5 or 1.0)
            SetDriveTaskCruiseSpeed(driver, target)
            if SP.CapSpeed ~= false then SetEntityMaxSpeed(vehicle, target + (SP.CapMargin or 1.0)) end
            tracked[vehicle] = { id = m.id, phase = 'slow', driver = driver, at = now, startSpeed = start, capped = SP.CapSpeed ~= false }
        end
        return true
    end

    -- Hors de la bande : pas concerné, sauf un PNJ déjà rabattu sur une autre voie (suivi jusqu'à la fin du tronçon)
    local merging = info and (info.phase == 'merge' or info.phase == 'pass')
    local outside = v < vmin - 0.8 or v > vmax + 0.8
    if outside and not merging then
        -- Fermeture d'une voie : les AUTRES voies du même sens ralentissent (20 MPH), progressivement depuis l'amont
        if m.scope == 'lane' and (CL.SideSlow or 20) > 0 and openLane(m)
            and v >= band[1] - 1.0 and v <= band[2] + 1.0 and u >= -up and u <= f.length + 5 then
            local start = info and info.startSpeed or math.max(speed, 6.0)
            local target = math.min(start, TC.rampMph(u, CL.SideSlow or 20) * MPH)
            SetDriveTaskCruiseSpeed(driver, target)
            if SP.CapSpeed ~= false then SetEntityMaxSpeed(vehicle, target + (SP.CapMargin or 1.0)) end
            tracked[vehicle] = { id = m.id, phase = 'slow', driver = driver, at = now, startSpeed = start, capped = SP.CapSpeed ~= false }
            return true
        end
        return false
    end

    -- FERMETURE D'UNE VOIE avec une autre voie du même sens : rabattement sur cette voie (jamais sur l'autre sens)
    local target = m.scope == 'lane' and openLane(m) or nil
    if target then
        if u < -approach or u > f.length + 5 then return false end
        -- Rabattement EN LIGNE DROITE sur la voie ouverte (point qui avance avec le PNJ), puis il longe le tronçon
        -- sur cette voie jusqu'après la fin, et reprend sa route. Nouvelle consigne seulement quand il approche du
        -- point visé (pas à chaque vérification).
        local z = pos.z
        local cap = CL.RedirectSpeed or 18.0
        if (CL.SideSlow or 20) > 0 then cap = math.min(cap, TC.rampMph(u, CL.SideSlow or 20) * MPH) end -- comme les voies ralenties
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

    -- Voie sans autre voie du même sens, sens / route fermés : route recalculée à l'approche, puis DEMI-TOUR s'il
    -- continue vers la zone (jamais par la voie d'en face)
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

-- =========================================================================
-- PNJ et PLOTS VIRTUELS (même logique que les plots de la police, rp_equipment) : dans le repère du PNJ, un plot dans
-- sa trajectoire à moins de VirtualCones.Detect m -> contourner par le passage le plus proche SUR LA ROUTE (fermeture
-- d'une voie) ; sinon (arrêt, sens / route fermés, aucun passage) il s'arrête devant les plots.
-- =========================================================================
local coneTracked = {} -- [véhicule] = { mode = 'deviate' | 'blocked', driver, target, since }

local function coneResume(vehicle, info)
    coneTracked[vehicle] = nil
    local driver = info.driver
    if info.mode == 'deviate' and DoesEntityExist(driver) and DoesEntityExist(vehicle) and NetworkHasControlOfEntity(driver)
        and GetPedInVehicleSeat(vehicle, -1) == driver then
        TaskVehicleDriveWander(driver, vehicle, CL.ResumeSpeed or 17.0, CL.WanderStyle or 786603)
    end
end

--- Passage le plus proche ; `allowed(point)` : le point doit être dans une voie ouverte DU MÊME SENS (jamais l'autre sens)
local function findPassage(cones, halfWidth, farY, toWorld, vehicle, allowed)
    local needed = halfWidth + (VC.Margin or 0.8)
    for i = 0, math.floor((VC.MaxShift or 9.0) / 0.5) do
        for _, sgn in ipairs(i == 0 and { 1 } or { -1, 1 }) do
            local x = sgn * i * 0.5
            local clear = true
            for _, c in ipairs(cones) do
                if c.y > -2.0 and c.y < farY + 2.0 and math.abs(c.x - x) < needed then clear = false break end
            end
            if clear then
                local a, b = toWorld(x, math.max(1.0, farY * 0.5)), toWorld(x, farY + 2.0)
                if IsPointOnRoad(a.x, a.y, a.z, vehicle) and IsPointOnRoad(b.x, b.y, b.z, vehicle)
                    and (not allowed or (allowed(a) and allowed(b))) then return x end
            end
        end
    end
    return nil
end

local function coneHandle(e, vc, vehicle, driver, pos, fwd)
    local right = vector3(fwd.y, -fwd.x, 0.0)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local halfWidth, front = math.max(-min.x, max.x), max.y
    local detect, margin = VC.Detect or 12.0, VC.Margin or 0.8
    local list, inPath, farY = {}, nil, -100.0
    for i, p in ipairs(vc.cones) do
        local dx, dy = p.x - pos.x, p.y - pos.y
        local c = { x = dx * right.x + dy * right.y, y = dx * fwd.x + dy * fwd.y - front }
        list[i] = c
        if c.y > farY then farY = c.y end
        if c.y > -1.0 and c.y <= detect and math.abs(c.x) < halfWidth + margin then
            if not inPath or c.y < inPath.y then inPath = c end
        end
    end
    local info = coneTracked[vehicle]
    if not inPath then
        if info and farY < -2.0 then coneResume(vehicle, info) end
        return false
    end
    if info and (info.mode == 'deviate' or info.mode == 'uturn') then return true end
    if vc.mode == 'deviate' then
        local function toWorld(x, y) return pos + fwd * (y + front) + right * x end
        local open = vc.open
        local allowed = open and function(p)
            local _, pv = TC.localUV(e.f, p.x, p.y)
            return pv >= open[1] - 0.3 and pv <= open[2] + 0.3
        end or nil
        local shift = findPassage(list, halfWidth, farY, toWorld, vehicle, allowed)
        if shift then
            local target = toWorld(shift, farY + (VC.PassBeyond or 8.0))
            TaskVehicleDriveToCoord(driver, vehicle, target.x, target.y, target.z, VC.PassSpeed or 7.0, 0,
                GetEntityModel(vehicle), VC.DrivingStyle or 820, 2.0, true)
            coneTracked[vehicle] = { mode = 'deviate', driver = driver, target = target, since = GetGameTimer() }
            return true
        end
    end
    if vc.mode == 'deviate' or vc.mode == 'uturn' then
        -- fermeture : aucune voie du même sens pour passer -> DEMI-TOUR (jamais par la voie d'en face)
        local t = { id = e.m.id, driver = driver }
        tracked[vehicle] = t
        uturn(e, vehicle, driver, t, 1, pos)
        coneTracked[vehicle] = { mode = 'uturn', driver = driver, since = GetGameTimer() }
        return true
    end
    -- arrêt (attente) / route fermée : il s'arrête devant la ligne et attend
    TaskVehicleTempAction(driver, vehicle, 6, (Config.Interval or 300) + 500)
    coneTracked[vehicle] = { mode = 'blocked', driver = driver }
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
                -- Plots virtuels : sauf pour un PNJ déjà rabattu par la fermeture (il longe déjà la voie ouverte)
                local t = tracked[vehicle]
                local merging = t and (t.phase == 'merge' or t.phase == 'pass')
                for _, e in ipairs(near) do
                    local vc = e.vc
                    if vc and not (merging and vc.mode == 'deviate') and #(pos - vc.center) <= vc.radius + (VC.Detect or 12.0) + 12.0 then
                        if coneHandle(e, vc, vehicle, driver, pos, fwd) then break end
                    end
                end
                local info = tracked[vehicle]
                -- Sorti de la mesure (dépassé le tronçon, changé de route, demi-tour fait) : relâché
                if info and not handled and info.phase ~= 'uturn' then resume(vehicle, info) end
            end
        end
    end
    for vehicle, info in pairs(coneTracked) do
        if not DoesEntityExist(vehicle) then
            coneTracked[vehicle] = nil
        elseif (info.target and #(GetEntityCoords(vehicle) - info.target) < 4.0)
            or (info.since and now - info.since > (VC.MaxDeviateTime or 15000)) then
            coneResume(vehicle, info)
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
    return #near > 0 or next(tracked) ~= nil or next(coneTracked) ~= nil or next(obstacles) ~= nil or #coneSets > 0
end

startLoop = function()
    if running or (#active == 0 and #coneSets == 0) then return end
    running = true
    CreateThread(function()
        while #active > 0 or #coneSets > 0 or next(tracked) ~= nil or next(coneTracked) ~= nil or next(obstacles) ~= nil do
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
    for vehicle, info in pairs(coneTracked) do coneResume(vehicle, info) end
    clearObstacles()
    clearApplied() -- réseau routier rendu tel qu'il était
end)
