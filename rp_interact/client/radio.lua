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
    Le son est joué par le NUI de ce script (html/script.js). Performance : boucle (150 ms) seulement
    tant qu'une radio est allumée dans un véhicule à portée réseau ; aucune sinon.
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

local function send(id, radio, volume)
    -- Position dans le morceau : la même pour tous (heure de lancement), ou figée pendant la pause
    local offset = radio.paused or math.max(0, GetCloudTimeAsInt() - (tonumber(radio.start) or 0))
    SendNUIMessage({ action = 'radio', data = {
        id = id, url = radio.url, volume = volume, seq = radio.seq, offset = offset, paused = radio.paused ~= nil,
    } })
end

local function stop(id)
    if playing[id] then
        playing[id] = nil
        SendNUIMessage({ action = 'radioStop', data = { id = id } })
    end
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
                    else
                        local volume = math.floor((radio.volume or 0) / 100 * factor * Config.RadioMaxVolume * 100 + 0.5) / 100
                        local key = ('%s|%s|%s|%s|%.2f'):format(radio.url, radio.start, tostring(radio.seq), tostring(radio.paused), volume)
                        if playing[id] ~= key then
                            playing[id] = key
                            send(id, radio, volume)
                        end
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
        radios[bagName] = nil
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
        ok = true, available = true, canControl = canControl(vehicle, mode),
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

--- Œil : visée de l'intérieur avant, portière avant ouverte -> menu ouvert sur la page Radio
function RPI.openRadio(vehicle)
    RPI.radioTarget = vehicle
    RPI.openMenu('radio')
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(playing) do SendNUIMessage({ action = 'radioStop', data = { id = id } }) end
end)
