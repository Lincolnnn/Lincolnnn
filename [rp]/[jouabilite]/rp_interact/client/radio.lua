--[[
    RP Interact - Radio du véhicule (client)
    ----------------------------------------
    Menu d'interactions > Voiture > Radio : un lien (YouTube, ou lien direct vers une musique, un
    podcast, une radio en ligne) joué DANS LE VÉHICULE.
      - L'état est porté par le véhicule ("rpiRadio" : lien, heure de lancement, volume) : tous les
        joueurs entendent la même chose au même moment, et au même volume de base (89 % = 89 % pour
        tout le monde), réglé seulement par les places avant, ou avec l'œil en visant l'intérieur avant
        du véhicule portière avant ouverte.
      - Chaque joueur entend selon sa position : à bord, normalement ; dehors, plus ou moins fort selon la
        distance : jusqu'à 15 m tout fermé (RadioRangeClosed), 25 m avec une portière ouverte ou une vitre
        baissée (RadioRangeOpen) ; tout fermé, volume plus bas (RadioInsulation). Pas d'effet sur le son
        (lecture telle quelle : lecteur YouTube, ou lecteur audio pour un lien direct).
      - File "Écouter ensuite" (5 liens max, bouton "+") : à la fin d'un morceau, le NUI d'un joueur qui
        l'entend le signale au serveur, qui lance le suivant pour tout le monde.
      - Pause / reprise (même position pour tous), retour au début du morceau (deux appuis rapprochés :
        morceau précédent), suivant, arrêter : boutons à icônes de la page Radio.
    MOTEUR DU SON (RadioEngine) : par défaut le NUI de ce script (html/script.js) : son 3D (HRTF) placé selon la
    caméra (on entend de quel côté est le véhicule : gauche, droite, derrière), étouffé dehors portières et vitres
    fermées. Pour un lien audio direct (mp3, radio en ligne…) ; un lien YouTube passe par le lecteur YouTube, qui
    ne laisse aucun effet s'appliquer : volume selon la distance seulement (sauf RadioYouTubeAudio). 'olisound' :
    la ressource olisound à la place (même limite pour YouTube).
    Performance : boucle (150 ms) seulement tant qu'une radio est allumée dans un véhicule à portée réseau ; aucune
    sinon.
]]

local Config = InteractConfig
local radios = {}     -- [nom du state bag] = { url, start, volume }
local playing = {}    -- [nom du state bag] = dernier envoi au NUI (clé)
local loopRunning = false
RPI.radioTarget = nil -- véhicule visé avec l'œil (menu ouvert sur la page Radio)

-- =========================================================================
-- AUDITION : distance, vitres / portières, à bord
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

--- Portée de la radio dehors (m) : tout fermé / portière ouverte ou vitre baissée
local function range(open)
    return open and (Config.RadioRangeOpen or 25.0) or (Config.RadioRangeClosed or 15.0)
end

--- Facteur de volume (0..1) pour ce joueur (1 à bord ; dehors selon la distance et les ouvertures)
function RPI.radioHearing(vehicle)
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) == vehicle then return 1.0 end
    local distance = #(GetEntityCoords(ped) - GetEntityCoords(vehicle))
    local open = RPI.vehicleOpen(vehicle)
    local maxRange = range(open)
    if distance >= maxRange then return 0.0 end
    local factor = (1.0 - distance / maxRange) ^ 1.6
    return open and factor or factor * Config.RadioInsulation
end

--- Position dans le morceau (s) : la même pour tous (heure de lancement), ou figée pendant la pause
local function offsetOf(radio)
    return radio.paused or math.max(0, GetCloudTimeAsInt() - (tonumber(radio.start) or 0))
end

local function send(id, radio, volume)
    local offset = offsetOf(radio)
    SendNUIMessage({ action = 'radio', data = {
        id = id, url = radio.url, volume = volume, seq = radio.seq, offset = offset, paused = radio.paused ~= nil,
        ytAudio = Config.RadioYouTubeAudio ~= '' and Config.RadioYouTubeAudio or nil,
    } })
end

-- =========================================================================
-- SON 3D (lecteur de ce script) : d'où vient la musique, vu de la CAMÉRA du joueur (devant, derrière, à gauche, à
-- droite, au-dessus), et son ÉTOUFFÉ dehors quand portières et vitres sont fermées. Envoyé au NUI seulement quand
-- ça change : position dans le repère de la caméra (x : droite, y : haut, z : vers l'arrière, comme le Web Audio),
-- coupure des aigus (Hz) : étouffé (RadioMuffleHz), derrière soi (RadioBehindHz, un peu plus sourd), sinon aucune.
-- =========================================================================
local lastPos = {} -- [nom du state bag] = clé du dernier envoi

--- Position du véhicule vue de la caméra, normalisée (seule la DIRECTION compte : la distance est dans le volume)
local function cameraRelative(vehicle)
    local cam = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local f = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local r = vector3(math.cos(yaw), math.sin(yaw), 0.0)
    local u = vector3(r.y * f.z - r.z * f.y, r.z * f.x - r.x * f.z, r.x * f.y - r.y * f.x)
    local d = GetEntityCoords(vehicle) - cam
    local x, y, z = d.x * r.x + d.y * r.y + d.z * r.z, d.x * u.x + d.y * u.y + d.z * u.z, d.x * f.x + d.y * f.y + d.z * f.z
    local len = math.sqrt(x * x + y * y + z * z)
    if len < 0.5 then return 0.0, 0.0, -1.0, false end
    return x / len, y / len, -z / len, z < 0
end

local function sendPos(id, vehicle)
    local inside = GetVehiclePedIsIn(PlayerPedId(), false) == vehicle
    local x, y, z, behind = 0.0, 0.0, -1.0, false -- à bord : les haut-parleurs tout autour (devant)
    local cutoff = 20000
    if not inside then
        x, y, z, behind = cameraRelative(vehicle)
        if not RPI.vehicleOpen(vehicle) then cutoff = Config.RadioMuffleHz or 550
        elseif behind then cutoff = Config.RadioBehindHz or 5000 end
    end
    local key = ('%.2f|%.2f|%.2f|%d'):format(x, y, z, cutoff)
    if lastPos[id] == key then return end
    lastPos[id] = key
    SendNUIMessage({ action = 'radioPos', data = { id = id, x = x, y = y, z = z, cutoff = cutoff,
        muffled = cutoff < 1000, boost = Config.RadioMuffleBoost or 1.8 } })
end

-- =========================================================================
-- MOTEUR OLISOUND (si la ressource est démarrée) : un son par véhicule, accroché au véhicule
-- =========================================================================
local OLI = 'olisound'
local oli = {}   -- [nom du state bag] = { name, url, seq, start, volume, distance, paused }
local ended = {} -- [nom du state bag] = n° du morceau dont la fin a été entendue (pas relancé)

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

--- Fin du son : vraie fin du morceau (pas notre Destroy, pas le véhicule disparu) -> le serveur lance le suivant
local function oliEnded(id, s, info)
    if s.closing or s.done then return end
    local radio = radios[id]
    if not radio or radio.seq ~= s.seq or radio.paused then return end
    local duration = type(info) == 'table' and tonumber(info.maxDuration) or 0
    if not duration or duration <= 0 or offsetOf(radio) < duration - 5 then return end
    s.done = true
    ended[id] = s.seq
    local netId = tonumber(id:match('^entity:(%d+)$'))
    if netId then RPI.request('radio', { netId = netId, action = 'ended', seq = s.seq }, function() end) end
end

local function oliPlay(id, radio, vehicle)
    local volume = math.floor((radio.volume or 0) / 100 * Config.RadioMaxVolume * 100 + 0.5) / 100
    local distance = range(RPI.vehicleOpen(vehicle))
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
            for id, radio in pairs(radios) do
                local vehicle = GetEntityFromStateBagName(id)
                if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
                    stop(id) -- hors de portée réseau : reprend quand il revient
                else
                    local factor = RPI.radioHearing(vehicle)
                    local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle))
                    if factor <= 0.0 and distance > range(true) + 20.0 then
                        stop(id) -- loin : lecteur fermé (rouvert à l'approche, au bon moment)
                    elseif useOli() then
                        stopNui(id)
                        oliPlay(id, radio, vehicle)
                    else
                        oliStop(id)
                        local volume = math.floor((radio.volume or 0) / 100 * factor * Config.RadioMaxVolume * 100 + 0.5) / 100
                        local key = ('%s|%s|%s|%s|%.2f'):format(radio.url, radio.start, tostring(radio.seq), tostring(radio.paused), volume)
                        if playing[id] ~= key then
                            playing[id] = key
                            send(id, radio, volume)
                        end
                        sendPos(id, vehicle)
                    end
                end
            end
            Wait(150)
        end
        loopRunning = false
    end)
end

-- Radio allumée / réglée / coupée dans un véhicule (ou véhicule arrivé à portée)
AddStateBagChangeHandler('rpiRadio', nil, function(bagName, _, value)
    if type(value) == 'table' and type(value.url) == 'string' then
        local old = radios[bagName]
        -- Autre morceau (lien ou n° différent) : lecteur refermé ; pause / reprise : même lecteur
        if old and (old.url ~= value.url or old.seq ~= value.seq) then stop(bagName) end
        radios[bagName] = { url = value.url, start = value.start, volume = tonumber(value.volume) or 60, seq = value.seq,
            paused = tonumber(value.paused) }
        startLoop()
    else
        radios[bagName], ended[bagName] = nil, nil
        stop(bagName)
    end
end)

-- =========================================================================
-- MENU > VOITURE > RADIO
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

local function canControl(vehicle, mode)
    if mode == 'target' then return true end
    local ped = PlayerPedId()
    return GetPedInVehicleSeat(vehicle, -1) == ped or GetPedInVehicleSeat(vehicle, 0) == ped
end

local function radioInfo()
    local vehicle, mode = radioVehicle()
    if not vehicle then return { ok = true, available = false } end
    if not NetworkGetEntityIsNetworked(vehicle) then
        return { ok = true, available = false, error = 'Ce véhicule n\'est pas synchronisé avec le serveur.' }
    end
    local radio = Entity(vehicle).state.rpiRadio
    return {
        ok = true, available = true, canControl = canControl(vehicle, mode), ytAudio = (Config.RadioYouTubeAudio or '') ~= '',
        engine = useOli() and 'olisound' or 'nui',
        vehicle = RPI.vehicleLabel and RPI.vehicleLabel(vehicle) or nil,
        radio = type(radio) == 'table' and { url = radio.url, volume = radio.volume, queue = radio.queue or {},
            paused = radio.paused ~= nil, history = #(radio.history or {}) } or false,
    }
end

RegisterNUICallback('radioInfo', function(_, cb) cb(radioInfo()) end)

RegisterNUICallback('radioAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    local vehicle, mode = radioVehicle()
    if not vehicle or not canControl(vehicle, mode) then
        return cb({ ok = false, error = 'Seules les places avant peuvent régler la radio.' })
    end
    RPI.request('radio', { netId = VehToNet(vehicle), action = data.action, url = data.url, volume = data.volume,
        index = data.index }, function(res)
        if not res or not res.ok then return cb(res or { ok = false }) end
        local info = radioInfo()
        info.radio = type(res.radio) == 'table'
            and { url = res.radio.url, volume = res.radio.volume, queue = res.radio.queue or {},
                paused = res.radio.paused ~= nil, history = #(res.radio.history or {}) } or false
        cb(info)
    end)
end)

-- Fin d'un morceau (NUI) : le serveur lance le suivant de la file (une seule fois : même n° de morceau)
RegisterNUICallback('radioEnded', function(data, cb)
    cb({ ok = true })
    data = type(data) == 'table' and data or {}
    local radio = type(data.id) == 'string' and radios[data.id] or nil
    if not radio or radio.seq ~= data.seq then return end
    local netId = tonumber(data.id:match('^entity:(%d+)$'))
    if netId then RPI.request('radio', { netId = netId, action = 'ended', seq = radio.seq }, function() end) end
end)

-- Passé directement dans un autre véhicule (nouveau véhicule apparu, rp_vehiclecontrol) depuis une place avant :
-- la radio de l'ancien s'arrête aussi
AddEventHandler('rp_vehiclecontrol:swapped', function(netId, seat)
    if type(netId) ~= 'number' or (seat ~= -1 and seat ~= 0) then return end
    local vehicle = NetworkDoesNetworkIdExist(netId) and NetToVeh(netId) or 0
    if vehicle == 0 or type(Entity(vehicle).state.rpiRadio) ~= 'table' then return end
    RPI.request('radio', { netId = netId, action = 'swapStop' }, function() end)
end)

--- Œil : visée de l'intérieur avant, portière avant ouverte -> menu ouvert sur la page Radio
function RPI.openRadio(vehicle)
    RPI.radioTarget = vehicle
    RPI.openMenu('radio')
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(playing) do SendNUIMessage({ action = 'radioStop', data = { id = id } }) end
    for id in pairs(oli) do oliStop(id) end
end)
