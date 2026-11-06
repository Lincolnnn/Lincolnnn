--[[
    RP Interact - Radio du véhicule et /musique (client)
    ----------------------------------------------------
    Une SOURCE de son joue un lien (YouTube, ou lien direct vers une musique, un podcast, une radio en ligne) :
      - un VÉHICULE (Menu > Voiture > Radio, ou l'œil portière avant ouverte) : id 'entity:<n° réseau>' ;
      - /musique : SUR UN JOUEUR ('player:<id serveur>' : le suit, aussi dans un véhicule), à un ENDROIT
        ('place:<n°>', GlobalState.rpiPlaces) ou SUR UN OBJET ('entity:<n° réseau>' : le suit s'il bouge).
    L'état est porté par la source ("rpiRadio" : lien, heure de lancement, volume…) : tous les joueurs entendent la
    même chose au même moment, au même volume de base.
    AUDITION de chaque joueur :
      - PORTÉE selon le VOLUME de la source (RadioRanges) : de 10 m (0-9 %, fermé) à 110 m (50 % et plus, ouvert).
        « Fermé » : véhicule aux vitres, portières, coffre et capot fermés ; musique dans un intérieur entendue de
        dehors (ou l'inverse).
      - SON 3D (lecteur de ce script, html/script.js) : direction d'après la caméra (gauche, droite, derrière) ;
        fermé : aigus coupés, BASSES qui traversent et cognent ; auditeur dans un véhicule fermé : étouffé aussi ;
        fort volume : basses qui résonnent ; RÉVERBÉRATION selon l'endroit autour de la source (mesuré ici toutes
        les RadioEnvInterval ms : plein air, rue entre des bâtiments, tunnel / parking couvert, pièce intérieure) et la
        distance ; air : aigus atténués au loin. Lien YouTube : le lecteur YouTube ne laisse passer aucun effet
        (volume seulement), sauf RadioYouTubeAudio.
      - File "Écouter ensuite" (10 liens), pause / reprise, début du morceau, PRÉCÉDENT et DÉJÀ ÉCOUTÉS (aussi quand
        tout est fini : la source reste « arrêtée » avec son historique), suivant, LECTURE EN BOUCLE (un morceau seul,
        ou toute la playlist), arrêter.
      - /musique : INTENSITÉ (force des basses, x Music.Intensities) et PÉRIMÈTRE choisis (ouvert = ce périmètre,
        fermé = x Music.ClosedRatio ; sinon selon le volume).
    MOTEUR 'olisound' (RadioEngine) : radio des véhicules seulement (portée, sans les effets).
    Performance : boucle (150 ms) seulement tant qu'une source joue à portée réseau ; aucune sinon. Mesure de
    l'endroit : 9 rayons toutes les 2 s par source entendue.
]]

local Config = InteractConfig
local MUSIC = Config.Music or {}
local states = {}     -- [id] = état complet (aussi arrêté : historique)
local radios = {}     -- [id] = { url, start, volume, seq, paused, music } : sources qui jouent
local playing = {}    -- [id] = dernier envoi au NUI (clé)
local loopRunning = false
RPI.radioTarget = nil -- véhicule visé avec l'œil (menu ouvert sur la page Radio)

-- =========================================================================
-- SOURCE : où est le son ? { kind, pos, vehicle (véhicule où il est joué), entity, ped }
-- =========================================================================
local function anchorOf(id, radio)
    local kind, n = id:match('^(%a+):(%d+)$')
    n = tonumber(n)
    if kind == 'entity' then
        local entity = GetEntityFromStateBagName(id)
        if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
        if IsEntityAVehicle(entity) then
            return { kind = 'vehicle', pos = GetEntityCoords(entity), vehicle = entity, entity = entity }
        end
        return { kind = 'prop', pos = GetEntityCoords(entity), entity = entity }
    elseif kind == 'player' then
        local index = GetPlayerFromServerId(n)
        if not index or index == -1 then return nil end
        local ped = GetPlayerPed(index)
        if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
        local vehicle = GetVehiclePedIsIn(ped, false)
        return { kind = 'player', pos = GetEntityCoords(ped), vehicle = vehicle ~= 0 and vehicle or nil, entity = ped, ped = ped }
    elseif kind == 'place' then
        local m = radio and radio.music or {}
        if not tonumber(m.x) then return nil end
        return { kind = 'place', pos = vector3(m.x + 0.0, m.y + 0.0, m.z + 0.0) }
    end
    return nil
end

-- =========================================================================
-- AUDITION : portée selon le volume, fermé / ouvert, à bord
-- =========================================================================
-- Vitres avant / arrière : seulement celles que le véhicule possède (un coupé n'a pas de vitres
-- arrière : le jeu les dit "non intactes", ce qui faisait croire à une vitre baissée)
local WINDOW_BONES = { [0] = 'window_lf', [1] = 'window_rf', [2] = 'window_lr', [3] = 'window_rr' }

--- Une vitre baissée / cassée, une portière (ou le coffre / le capot) ouverte, ou un toit décapoté ?
function RPI.vehicleOpen(vehicle)
    for door = 0, 5 do
        if GetVehicleDoorAngleRatio(vehicle, door) > 0.05 then return true end
    end
    for window, bone in pairs(WINDOW_BONES) do
        if GetEntityBoneIndexByName(vehicle, bone) ~= -1 and not IsVehicleWindowIntact(vehicle, window) then
            return true
        end
    end
    return IsVehicleAConvertible(vehicle, false) and GetConvertibleRoofState(vehicle) ~= 0
end

local DEFAULT_RANGES = { { Max = 9, Closed = 10.0, Open = 25.0 }, { Max = 29, Closed = 20.0, Open = 50.0 },
    { Max = 49, Closed = 30.0, Open = 75.0 }, { Max = 100, Closed = 45.0, Open = 110.0 } }

--- Portée (m) selon le volume de la source (0-100) et fermé / ouvert ; `custom` : périmètre choisi pour /musique
--- (ouvert = ce périmètre, fermé = x Music.ClosedRatio)
function RPI.radioRange(volume, closed, custom)
    custom = tonumber(custom)
    if custom and custom > 0 then
        return (closed and custom * (MUSIC.ClosedRatio or 0.4) or custom) + 0.0
    end
    local tiers = Config.RadioRanges or DEFAULT_RANGES
    volume = tonumber(volume) or 0
    local tier = tiers[#tiers]
    for _, t in ipairs(tiers) do
        if volume <= (t.Max or 100) then tier = t; break end
    end
    return (closed and tier.Closed or tier.Open) + 0.0
end

local function interiorOf(src)
    if src.entity then return GetInteriorFromEntity(src.entity) end
    return GetInteriorAtCoords(src.pos.x, src.pos.y, src.pos.z)
end

--- Situation de ce joueur face à la source : inside (à bord du véhicule de la source / porte la musique),
--- closed (source fermée : véhicule fermé, ou murs entre un intérieur et dehors), listenerClosed (auditeur dans un
--- autre véhicule fermé), distance (m)
function RPI.radioSituation(src)
    local ped = PlayerPedId()
    local myVeh = GetVehiclePedIsIn(ped, false)
    local inside = (src.vehicle ~= nil and myVeh == src.vehicle) or (src.ped ~= nil and src.ped == ped and not src.vehicle)
    local closed = false
    if not inside then
        if src.vehicle then
            closed = not RPI.vehicleOpen(src.vehicle)
        elseif interiorOf(src) ~= GetInteriorFromEntity(ped) then
            closed = true -- murs : la musique est dans un intérieur et nous dehors (ou l'inverse)
        end
    end
    local listenerClosed = not inside and myVeh ~= 0 and myVeh ~= src.vehicle and not RPI.vehicleOpen(myVeh)
    return inside, closed, listenerClosed, #(GetEntityCoords(ped) - src.pos)
end

--- Facteur de volume (0..1) pour ce joueur, et la portée utilisée (`custom` : périmètre choisi pour /musique)
function RPI.radioHearing(src, volume, custom)
    local inside, closed, listenerClosed, distance = RPI.radioSituation(src)
    local maxRange = RPI.radioRange(volume, closed, custom)
    if inside then return 1.0, maxRange, distance end
    if distance >= maxRange then return 0.0, maxRange, distance end
    local factor = (1.0 - distance / maxRange) ^ 1.4
    if closed then factor = factor * (Config.RadioInsulation or 0.35) end
    if listenerClosed then factor = factor * 0.6 end
    return factor, maxRange, distance
end

--- Position dans le morceau (s) : la même pour tous (heure de lancement), ou figée pendant la pause
local function offsetOf(radio)
    return radio.paused or math.max(0, GetCloudTimeAsInt() - (tonumber(radio.start) or 0))
end

local function send(id, radio, volume)
    SendNUIMessage({ action = 'radio', data = {
        id = id, url = radio.url, volume = volume, seq = radio.seq, offset = offsetOf(radio), paused = radio.paused ~= nil,
        ytAudio = Config.RadioYouTubeAudio ~= '' and Config.RadioYouTubeAudio or nil,
    } })
end

-- =========================================================================
-- ENDROIT AUTOUR DE LA SOURCE (réverbération) : 8 rayons à l'horizontale + 1 vers le haut, toutes les
-- RadioEnvInterval ms par source entendue : 'room' (intérieur), 'hall' (tunnel, parking couvert), 'street' (entre des
-- bâtiments), 'open' (plein air) ; 'cabin' pour un auditeur à bord du véhicule de la source.
-- =========================================================================
local env = {} -- [id] = { at, preset, size }

local function probe(from, to, ignore)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 1 + 16, ignore or 0, 4)
    local _, hit, point = GetShapeTestResult(handle)
    if hit == 1 or hit == true then return #(point - from) end
    return nil
end

function RPI.radioEnv(id, src, now)
    local e = env[id]
    if e and now - e.at < (Config.RadioEnvInterval or 2000) then return e end
    local origin = src.pos + vector3(0.0, 0.0, 1.0)
    local preset, size
    if not src.vehicle and interiorOf(src) ~= 0 then
        preset, size = 'room', 6.0
    else
        local hits, sum = 0, 0.0
        for i = 0, 7 do
            local a = i * math.pi / 4
            local d = probe(origin, origin + vector3(math.cos(a) * 35.0, math.sin(a) * 35.0, 0.0), src.entity)
            if d then hits, sum = hits + 1, sum + d end
        end
        local ceiling = probe(origin, origin + vector3(0.0, 0.0, 25.0), src.entity)
        size = hits > 0 and sum / hits or 35.0
        if ceiling and hits >= 4 then preset = 'hall'
        elseif hits >= 4 then preset = 'street'
        else preset = 'open' end
    end
    e = { at = now, preset = preset, size = math.floor(size + 0.5) }
    env[id] = e
    return e
end

-- =========================================================================
-- SON 3D : direction vue de la CAMÉRA (repère du Web Audio : x droite, y haut, z vers l'arrière) et acoustique ;
-- envoyé au NUI seulement quand ça change
-- =========================================================================
local lastPos = {} -- [id] = clé du dernier envoi
local intensityFactor -- (plus bas)

local function cameraRelative(pos)
    local cam = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local f = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local r = vector3(math.cos(yaw), math.sin(yaw), 0.0)
    local u = vector3(r.y * f.z - r.z * f.y, r.z * f.x - r.x * f.z, r.x * f.y - r.y * f.x)
    local d = pos - cam
    local x, y, z = d.x * r.x + d.y * r.y + d.z * r.z, d.x * u.x + d.y * u.y + d.z * u.z, d.x * f.x + d.y * f.y + d.z * f.z
    local len = math.sqrt(x * x + y * y + z * z)
    if len < 0.5 then return 0.0, 0.0, -1.0, false end
    return x / len, y / len, -z / len, z < 0
end

--- Intensité de /musique (0 douce .. 3 très forte) -> force des basses / de la résonance (x) ; radio : normale
local DEFAULT_INTENSITIES = { { label = 'Douce', factor = 0.5 }, { label = 'Normale', factor = 1.0 },
    { label = 'Forte', factor = 1.5 }, { label = 'Très forte', factor = 2.1 } }
intensityFactor = function(level)
    local list = MUSIC.Intensities or DEFAULT_INTENSITIES
    local entry = list[(math.tointeger(tonumber(level)) or 1) + 1]
    return entry and tonumber(entry.factor) or 1.0
end

local function sendPos(id, src, radio, maxRange, now)
    local inside, closed, listenerClosed, distance = RPI.radioSituation(src)
    local x, y, z, behind = 0.0, 0.0, -1.0, false -- à bord : les haut-parleurs tout autour (devant)
    if not inside then x, y, z, behind = cameraRelative(src.pos) end
    local e = inside and src.vehicle and { preset = 'cabin', size = 2 } or RPI.radioEnv(id, src, now)
    local data = {
        id = id, x = x, y = y, z = z, inside = inside, closed = closed, listenerClosed = listenerClosed, behind = behind,
        dist = inside and 0 or math.floor(math.min(1.0, distance / math.max(1.0, maxRange)) * 20 + 0.5) / 20,
        loud = math.floor((tonumber(radio.volume) or 0) / 5 + 0.5) * 5 / 100, env = e.preset, size = e.size,
        muffleHz = Config.RadioMuffleHz or 380, behindHz = Config.RadioBehindHz or 6000,
        bassBoost = Config.RadioBassBoost or 2.2, loudBass = Config.RadioLoudBass or 1.6, reverb = Config.RadioReverb or 1.0,
        intensity = intensityFactor(radio.intensity),
    }
    local key = ('%.2f|%.2f|%.2f|%s|%s|%s|%s|%.2f|%.2f|%s|%d|%.2f'):format(x, y, z, tostring(inside), tostring(closed),
        tostring(listenerClosed), tostring(behind), data.dist, data.loud, data.env, data.size, data.intensity)
    if lastPos[id] == key then return end
    lastPos[id] = key
    SendNUIMessage({ action = 'radioPos', data = data })
end

-- =========================================================================
-- MOTEUR OLISOUND (radio des véhicules seulement, si la ressource est démarrée)
-- =========================================================================
local OLI = 'olisound'
local oli = {}   -- [id] = { name, url, seq, start, volume, distance, paused }
local ended = {} -- [id] = n° du morceau dont la fin a été entendue (pas relancé)

local function useOli()
    local engine = Config.RadioEngine or 'nui'
    return (engine == 'olisound' or engine == 'auto') and GetResourceState(OLI) == 'started'
end

local function oliCall(fn, ...)
    local args = { ... }
    local ok, res = pcall(function() return exports[OLI][fn](exports[OLI], table.unpack(args)) end)
    return ok and res or nil
end

local function oliStop(id)
    local s = oli[id]
    if not s then return end
    oli[id] = nil
    s.closing = true -- (olisound appelle onPlayEnd sur un Destroy : ce n'est pas une fin de morceau)
    oliCall('Destroy', s.name)
end

local function requestRadio(id, payload, cb)
    payload.source = id
    RPI.request('radio', payload, cb or function() end)
end

--- Fin du son : vraie fin du morceau (pas notre Destroy, pas le véhicule disparu) -> le serveur lance le suivant
local function oliEnded(id, s, info)
    if s.closing or s.done then return end
    local radio = radios[id]
    if not radio or radio.seq ~= s.seq or radio.paused then return end
    local duration = type(info) == 'table' and tonumber(info.maxDuration) or 0
    if not duration or duration <= 0 or offsetOf(radio) < duration - 5 then return end
    s.done = true
    ended[id] = s.seq
    requestRadio(id, { action = 'ended', seq = s.seq })
end

local function oliPlay(id, radio, vehicle, distance)
    local volume = math.floor((radio.volume or 0) / 100 * Config.RadioMaxVolume * 100 + 0.5) / 100
    local paused = radio.paused ~= nil
    local s = oli[id]
    if s and (s.url ~= radio.url or s.seq ~= radio.seq) then oliStop(id); s = nil end
    if s and not oliCall('soundExists', s.name) then oli[id], s = nil, nil end -- détruit par olisound : relancé
    if not s then
        if ended[id] == radio.seq then return end
        s = { name = 'rpi_radio:' .. id, url = radio.url, seq = radio.seq, start = radio.start, volume = volume,
            distance = distance, paused = paused }
        oli[id] = s
        oliCall('PlayUrlVehicle', s.name, radio.url, volume, vehicle, false, {
            -- lecture lancée (chargement YouTube…) : recalée sur la position commune
            onPlayStart = function()
                local r = radios[id]
                if oli[id] ~= s or not r then return end
                oliCall('setTimeStamp', s.name, offsetOf(r))
                if r.paused then oliCall('Pause', s.name) end
            end,
            onPlayEnd = function(info) oliEnded(id, s, info) end,
        })
        oliCall('Distance', s.name, distance)
        oliCall('setTimeStamp', s.name, offsetOf(radio))
        if paused then oliCall('Pause', s.name) end
        return
    end
    if s.volume ~= volume then s.volume = volume; oliCall('setVolumeMax', s.name, volume) end
    if s.distance ~= distance then s.distance = distance; oliCall('Distance', s.name, distance) end
    if s.paused ~= paused then
        s.paused = paused
        if paused then
            oliCall('Pause', s.name)
        else
            oliCall('setTimeStamp', s.name, offsetOf(radio))
            oliCall('Resume', s.name)
        end
    elseif s.start ~= radio.start then
        oliCall('setTimeStamp', s.name, offsetOf(radio)) -- retour au début du morceau
    end
    s.start = radio.start
end

local function stopNui(id)
    lastPos[id] = nil
    if playing[id] then
        playing[id] = nil
        SendNUIMessage({ action = 'radioStop', data = { id = id } })
    end
end

local function stop(id)
    oliStop(id)
    stopNui(id)
end

local function startLoop()
    if loopRunning then return end
    loopRunning = true
    CreateThread(function()
        while next(radios) do
            local now = GetGameTimer()
            for id, radio in pairs(radios) do
                local src = anchorOf(id, radio)
                if not src then
                    stop(id) -- hors de portée réseau : reprend quand il revient
                else
                    local factor, maxRange, distance = RPI.radioHearing(src, radio.volume, radio.range)
                    if factor <= 0.0 and distance > RPI.radioRange(radio.volume, false, radio.range) + 20.0 then
                        stop(id) -- loin : lecteur fermé (rouvert à l'approche, au bon moment)
                        env[id] = nil
                    elseif src.kind == 'vehicle' and useOli() then
                        stopNui(id)
                        oliPlay(id, radio, src.vehicle, maxRange)
                    else
                        oliStop(id)
                        local volume = math.floor((radio.volume or 0) / 100 * factor * Config.RadioMaxVolume * 100 + 0.5) / 100
                        local key = ('%s|%s|%s|%s|%.2f'):format(radio.url, radio.start, tostring(radio.seq), tostring(radio.paused), volume)
                        if playing[id] ~= key then
                            playing[id] = key
                            send(id, radio, volume)
                        end
                        sendPos(id, src, radio, maxRange, now)
                    end
                end
            end
            Wait(150)
        end
        loopRunning = false
    end)
end

--- Nouvel état d'une source (allumée, réglée, arrêtée avec son historique, ou retirée)
local function apply(id, value)
    states[id] = type(value) == 'table' and value or nil
    if type(value) == 'table' and type(value.url) == 'string' and not value.stopped then
        local old = radios[id]
        -- Autre morceau (lien ou n° différent) : lecteur refermé ; pause / reprise : même lecteur
        if old and (old.url ~= value.url or old.seq ~= value.seq) then stop(id) end
        radios[id] = { url = value.url, start = value.start, volume = tonumber(value.volume) or 60, seq = value.seq,
            paused = tonumber(value.paused), music = value.music, range = tonumber(value.range), intensity = value.intensity }
        startLoop()
    else
        radios[id], ended[id], env[id] = nil, nil, nil
        stop(id)
    end
end

-- Véhicules, objets et joueurs (état "rpiRadio")
AddStateBagChangeHandler('rpiRadio', nil, function(bagName, _, value) apply(bagName, value) end)

-- Endroits (/musique « ici ») : GlobalState.rpiPlaces = { [n°] = état }
local placeIds = {}
local function applyPlaces(all)
    all = type(all) == 'table' and all or {}
    local seen = {}
    for key, value in pairs(all) do
        local id = 'place:' .. tostring(key)
        seen[id] = true
        apply(id, value)
    end
    for id in pairs(placeIds) do
        if not seen[id] then apply(id, nil) end
    end
    placeIds = seen
end
AddStateBagChangeHandler('rpiPlaces', 'global', function(_, _, value) applyPlaces(value) end)
CreateThread(function() applyPlaces(GlobalState.rpiPlaces) end)

-- =========================================================================
-- MENU > VOITURE > RADIO et MENU > MUSIQUE (/musique)
-- =========================================================================
--- Véhicule concerné : celui visé avec l'œil, sinon celui où se trouve le joueur
local function radioVehicle()
    local target = RPI.radioTarget
    if target and DoesEntityExist(target) and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(target)) < 5.0 then
        return target, 'target'
    end
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then return vehicle, 'inside' end
    return nil
end

local function myServerId() return GetPlayerServerId(PlayerId()) end

--- Musique réglable ici : la sienne (où qu'elle soit), sinon la plus proche à ControlDistance m
local function musicSource()
    local me = myServerId()
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, (MUSIC.ControlDistance or 6.0)
    for id, value in pairs(states) do
        local music = type(value.music) == 'table' and value.music or nil
        if music then
            if music.owner == me or id == 'player:' .. me then return id, true end
            local src = anchorOf(id, value)
            if src then
                local d = #(src.pos - pos)
                if d <= bestDist then best, bestDist = id, d end
            end
        end
    end
    return best, false
end

local function historyOf(value)
    local out = {}
    for i, url in ipairs(type(value) == 'table' and type(value.history) == 'table' and value.history or {}) do out[i] = url end
    return out
end

local function radioView(value)
    if type(value) ~= 'table' then return false end
    return { url = value.url, volume = value.volume, queue = value.queue or {}, paused = value.paused ~= nil,
        stopped = value.stopped == true or type(value.url) ~= 'string', history = historyOf(value),
        label = type(value.music) == 'table' and value.music.label or nil, loop = value.loop == true,
        intensity = math.tointeger(tonumber(value.intensity)) or 1, range = tonumber(value.range) }
end

--- Source de la page : 'radio' (véhicule) ou 'music' ; { id, canControl, label } ou erreur
local function pageSource(page)
    if page == 'music' then
        if MUSIC.Enabled == false then return nil, 'La musique est désactivée sur ce serveur.' end
        local id, own = musicSource()
        return { id = id, canControl = id ~= nil, own = own, music = true }
    end
    local vehicle, mode = radioVehicle()
    if not vehicle then return nil end
    if not NetworkGetEntityIsNetworked(vehicle) then return nil, 'Ce véhicule n\'est pas synchronisé avec le serveur.' end
    local ped = PlayerPedId()
    local can = mode == 'target' or GetPedInVehicleSeat(vehicle, -1) == ped or GetPedInVehicleSeat(vehicle, 0) == ped
    return { id = 'entity:' .. VehToNet(vehicle), canControl = can, label = RPI.vehicleLabel and RPI.vehicleLabel(vehicle) or nil }
end

local function radioInfo(page)
    local target, err = pageSource(page)
    if not target then return { ok = true, available = false, error = err, page = page } end
    local value = target.id and (states[target.id] or (page ~= 'music' and Entity(GetEntityFromStateBagName(target.id)).state.rpiRadio)) or nil
    return {
        ok = true, available = true, page = page, canControl = target.canControl, own = target.own,
        ytAudio = (Config.RadioYouTubeAudio or '') ~= '', engine = (page ~= 'music' and useOli()) and 'olisound' or 'nui',
        vehicle = target.label, source = target.id, radio = radioView(value),
        canCreate = page == 'music', controlDistance = MUSIC.ControlDistance or 6.0, ranges = Config.RadioRanges or DEFAULT_RANGES,
        queueMax = Config.RadioQueueMax or 10, perimeters = MUSIC.Ranges or { 10, 25, 50, 75, 110, 150 },
        closedRatio = MUSIC.ClosedRatio or 0.4, intensities = MUSIC.Intensities or DEFAULT_INTENSITIES,
    }
end

RegisterNUICallback('radioInfo', function(data, cb)
    cb(radioInfo(type(data) == 'table' and data.page == 'music' and 'music' or 'radio'))
end)

-- =========================================================================
-- /musique > LANCER SUR UN OBJET : objets autour (liste, celui choisi surligné dans le jeu) ou objet à faire apparaître
-- (Music.SpawnProps : enceinte, chaîne hi-fi, sac… posé devant le joueur, supprimé quand la musique est retirée)
-- =========================================================================
local nearby = {}      -- [n°] = objet de la dernière recherche
local highlighted = nil

local function spawnLabels()
    local out = {}
    for _, p in ipairs(MUSIC.SpawnProps or {}) do
        if p.model then out[GetHashKey(p.model)] = p.label end
    end
    return out
end

--- Nom lisible d'un objet : celui de la liste des objets à faire apparaître, sinon son nom de modèle
local function objectLabel(entity, labels)
    local label = labels[GetEntityModel(entity)]
    if label then return label end
    local name = GetEntityArchetypeName(entity)
    if type(name) == 'string' and name ~= '' then
        return (name:gsub('^prop_', ''):gsub('^v_res_', ''):gsub('^v_ret_', ''):gsub('_', ' '))
    end
    return 'Objet'
end

--- Objets visibles à Music.PlaceDistance m (pas portés, pas accrochés à un véhicule), du plus proche au plus loin
local function scanNearby()
    nearby = {}
    local pos = GetEntityCoords(PlayerPedId())
    local reach = MUSIC.PlaceDistance or 8.0
    local found = {}
    for _, obj in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(obj) and IsEntityVisible(obj) and not IsEntityAttachedToAnyPed(obj) and not IsEntityAttachedToAnyVehicle(obj) then
            local d = #(GetEntityCoords(obj) - pos)
            if d <= reach then found[#found + 1] = { entity = obj, dist = d } end
        end
    end
    table.sort(found, function(a, b) return a.dist < b.dist end)
    local labels = spawnLabels()
    local out = {}
    for i = 1, math.min(#found, MUSIC.NearbyMax or 15) do
        local o = found[i]
        nearby[i] = o.entity
        out[i] = { index = i, label = objectLabel(o.entity, labels), dist = math.floor(o.dist * 10 + 0.5) / 10,
            moving = NetworkGetEntityIsNetworked(o.entity) }
    end
    return out
end

local function setOutline(entity, on)
    if not entity or not DoesEntityExist(entity) then return end
    pcall(function()
        if on then SetEntityDrawOutlineColor(255, 196, 40, 255) end
        SetEntityDrawOutline(entity, on)
    end)
end

--- Surligne l'objet choisi dans la liste (contour + flèche au-dessus) tant que le menu est ouvert
local function highlight(index)
    local entity = index and nearby[index] or nil
    if highlighted == entity then return end
    setOutline(highlighted, false)
    highlighted = entity
    if not entity then return end
    setOutline(entity, true)
    CreateThread(function()
        local min, max = GetModelDimensions(GetEntityModel(entity))
        local height = (max and min) and (max.z - min.z) or 0.5
        while highlighted == entity and DoesEntityExist(entity) and (not RPI.menuIsOpen or RPI.menuIsOpen()) do
            local p = GetEntityCoords(entity)
            DrawMarker(2, p.x, p.y, p.z + height + 0.35, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.25, 0.25, 0.25,
                255, 196, 40, 220, true, true, 2, false, nil, nil, false)
            Wait(0)
        end
        if highlighted == entity then setOutline(entity, false); highlighted = nil end
    end)
end

RegisterNUICallback('musicNearby', function(_, cb) cb({ ok = true, objects = scanNearby() }) end)
RegisterNUICallback('musicHighlight', function(data, cb)
    cb({ ok = true })
    highlight(type(data) == 'table' and tonumber(data.index) or nil)
end)
RegisterNUICallback('musicSpawnList', function(_, cb)
    local out = {}
    for i, p in ipairs(MUSIC.SpawnProps or {}) do out[#out + 1] = { index = i, label = p.label, group = p.group } end
    cb({ ok = true, props = out })
end)

--- Objet -> point d'ancrage pour le serveur : objet synchronisé (la musique le suit) ou sa place (objet du décor)
local function anchorForObject(entity)
    if not entity or not DoesEntityExist(entity) then return nil end
    if NetworkGetEntityIsNetworked(entity) then return { kind = 'prop', netId = ObjToNet(entity) } end
    local o = GetEntityCoords(entity)
    return { kind = 'prop', x = o.x, y = o.y, z = o.z }
end

--- Fait apparaître un objet de Music.SpawnProps devant le joueur (synchronisé) ; nil si impossible
local function spawnObject(index)
    local def = (MUSIC.SpawnProps or {})[index]
    if not def or not def.model then return nil, 'Objet inconnu.' end
    local hash = GetHashKey(def.model)
    if not IsModelInCdimage(hash) then return nil, 'Cet objet n\'existe pas dans le jeu.' end
    RequestModel(hash)
    local stopAt = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < stopAt do Wait(0) end
    if not HasModelLoaded(hash) then return nil, 'Objet pas chargé, réessayez.' end
    local ped = PlayerPedId()
    local at = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.9, 0.0)
    local obj = CreateObject(hash, at.x, at.y, at.z, true, true, false)
    SetModelAsNoLongerNeeded(hash)
    if not obj or obj == 0 then return nil, 'Impossible de faire apparaître l\'objet.' end
    SetEntityHeading(obj, GetEntityHeading(ped) + 180.0) -- tourné vers le joueur
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, def.freeze ~= false)
    SetEntityAsMissionEntity(obj, true, true)
    stopAt = GetGameTimer() + 2000
    while not NetworkGetEntityIsNetworked(obj) and GetGameTimer() < stopAt do Wait(0) end
    if not NetworkGetEntityIsNetworked(obj) then DeleteObject(obj); return nil, 'Objet non synchronisé, réessayez.' end
    return obj
end

RegisterNUICallback('radioAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    local page = data.page == 'music' and 'music' or 'radio'
    local payload = { action = data.action, url = data.url, volume = data.volume, index = data.index, value = data.value,
        intensity = data.intensity, range = data.range, loop = data.loop }
    if data.action == 'create' and type(RPI.menuIsOpen) == 'function' then highlight(nil) end
    if data.action == 'create' then
        if page ~= 'music' then return cb({ ok = false, error = 'Action inconnue.' }) end
        local where = data.where
        if where == 'player' then
            payload.anchor = { kind = 'player' }
        elseif where == 'place' then
            local p = GetEntityCoords(PlayerPedId())
            payload.anchor = { kind = 'place', x = p.x, y = p.y, z = p.z }
        elseif where == 'prop' and tonumber(data.spawn) then
            -- objet à faire apparaître : créé ici, puis la musique dessus (supprimé si le serveur refuse)
            local obj, err = spawnObject(math.tointeger(tonumber(data.spawn)))
            if not obj then return cb({ ok = false, error = err }) end
            payload.anchor = { kind = 'prop', netId = ObjToNet(obj), spawned = true }
            return RPI.request('radio', payload, function(res)
                if not res or not res.ok then
                    if DoesEntityExist(obj) then DeleteObject(obj) end
                    return cb(res or { ok = false })
                end
                if res.source then apply(res.source, res.radio) end
                cb(radioInfo(page))
            end)
        elseif where == 'prop' then
            -- objet autour (choisi dans la liste)
            local entity = tonumber(data.object) and nearby[math.tointeger(tonumber(data.object))] or nil
            payload.anchor = anchorForObject(entity)
            highlight(nil)
            if not payload.anchor then return cb({ ok = false, error = 'Cet objet n\'est plus là.' }) end
        else
            return cb({ ok = false, error = 'Choisissez où jouer la musique.' })
        end
        return RPI.request('radio', payload, function(res)
            if not res or not res.ok then return cb(res or { ok = false }) end
            if res.source then apply(res.source, res.radio) end
            cb(radioInfo(page))
        end)
    end
    local target, err = pageSource(page)
    if not target or not target.id then return cb({ ok = false, error = err or 'Aucune musique ici.' }) end
    if not target.canControl then
        return cb({ ok = false, error = page == 'music' and 'Approchez-vous de la musique pour la régler.'
            or 'Seules les places avant peuvent régler la radio.' })
    end
    requestRadio(target.id, payload, function(res)
        if not res or not res.ok then return cb(res or { ok = false }) end
        apply(target.id, res.radio) -- à jour tout de suite (l'état arrive aussi par le réseau)
        cb(radioInfo(page))
    end)
end)

-- Fin d'un morceau (NUI) : le serveur lance le suivant de la file (une seule fois : même n° de morceau)
RegisterNUICallback('radioEnded', function(data, cb)
    cb({ ok = true })
    data = type(data) == 'table' and data or {}
    local radio = type(data.id) == 'string' and radios[data.id] or nil
    if not radio or radio.seq ~= data.seq then return end
    requestRadio(data.id, { action = 'ended', seq = radio.seq })
end)

-- Passé directement dans un autre véhicule (nouveau véhicule apparu, rp_vehiclecontrol) depuis une place avant :
-- la radio de l'ancien s'arrête aussi
AddEventHandler('rp_vehiclecontrol:swapped', function(netId, seat)
    if type(netId) ~= 'number' or (seat ~= -1 and seat ~= 0) then return end
    if not radios['entity:' .. netId] then return end
    requestRadio('entity:' .. netId, { action = 'swapStop' })
end)

--- Œil : visée de l'intérieur avant, portière avant ouverte -> menu ouvert sur la page Radio
function RPI.openRadio(vehicle)
    RPI.radioTarget = vehicle
    RPI.openMenu('radio')
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    setOutline(highlighted, false)
    for id in pairs(playing) do SendNUIMessage({ action = 'radioStop', data = { id = id } }) end
    for id in pairs(oli) do oliStop(id) end
end)

RPIRadio = { apply = apply, radios = radios, states = states, anchorOf = anchorOf, musicSource = musicSource, -- tests
    radioInfo = radioInfo, env = env }
