--[[
    RP Interact - Radio du véhicule (client)
    ----------------------------------------
    Menu d'interactions > Voiture > Radio : un lien (YouTube, ou lien direct vers une musique, un
    podcast, une radio en ligne) joué DANS LE VÉHICULE.
      - L'état est porté par le véhicule ("rpiRadio" : lien, heure de lancement, volume) : tous les
        joueurs entendent la même chose au même moment, et au même volume de base (89 % = 89 % pour
        tout le monde), réglé seulement par les places avant, ou avec l'œil en visant l'intérieur avant
        du véhicule portière avant ouverte.
      - Chaque joueur entend selon sa position : à bord, normalement ; dehors, le son VIENT DU VÉHICULE
        (à gauche / à droite selon où il se trouve par rapport à la caméra), plus ou moins fort selon la
        distance : jusqu'à 15 m tout fermé (RadioRangeClosed), 25 m avec une portière ouverte ou une vitre
        baissée (RadioRangeOpen). Tout fermé, le son est "insonorisé" : filtre passe-bas (son étouffé)
        et volume encore plus bas (RadioInsulation).
      - YouTube : lu en flux audio (adresse cherchée par le serveur, "stream"), pour que l'étouffement et
        la position marchent ; sans flux, lecteur YouTube classique (volume seulement).
    Le son est joué par le NUI de ce script (html/script.js). Performance : boucle (150 ms) seulement
    tant qu'une radio est allumée dans un véhicule à portée réseau ; aucune sinon.
]]

local Config = InteractConfig
local radios = {}     -- [nom du state bag] = { url, start, volume, stream }
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

--- Facteur de volume (0..1), son étouffé et position gauche / droite (-1..1) pour ce joueur
function RPI.radioHearing(vehicle)
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) == vehicle then return 1.0, false, 0.0 end
    local pos = GetEntityCoords(vehicle)
    local distance = #(GetEntityCoords(ped) - pos)
    local open = RPI.vehicleOpen(vehicle)
    local maxRange = range(open)
    if distance >= maxRange then return 0.0, not open, 0.0 end
    -- Le son vient du véhicule : côté gauche / droit par rapport à la caméra
    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local dx, dy = pos.x - cam.x, pos.y - cam.y
    local len = math.sqrt(dx * dx + dy * dy)
    local pan = 0.0
    if len > 0.5 then
        local heading = math.rad(rot.z)
        local rightX, rightY = math.cos(heading), math.sin(heading) -- droite de la caméra
        pan = math.max(-1.0, math.min(1.0, (dx * rightX + dy * rightY) / len)) * 0.85
    end
    local factor = (1.0 - distance / maxRange) ^ 1.6
    if open then return factor, false, pan end
    return factor * Config.RadioInsulation, true, pan
end

local function send(id, radio, volume, muffled, pan)
    SendNUIMessage({ action = 'radio', data = {
        id = id, url = radio.url, volume = volume, muffled = muffled, pan = pan,
        stream = radio.stream, -- YouTube : flux audio (nil : recherche en cours, false : aucun)
        offset = math.max(0, GetCloudTimeAsInt() - (tonumber(radio.start) or 0)), -- même moment pour tous
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
                    local factor, muffled, pan = RPI.radioHearing(vehicle)
                    local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle))
                    if factor <= 0.0 and distance > range(true) + 20.0 then
                        stop(id) -- loin : lecteur fermé (rouvert à l'approche, au bon moment)
                    else
                        local volume = math.floor((radio.volume or 0) / 100 * factor * Config.RadioMaxVolume * 100 + 0.5) / 100
                        pan = math.floor(pan * 20 + 0.5) / 20
                        local key = ('%s|%s|%s|%.2f|%s|%.2f'):format(radio.url, radio.start, tostring(radio.stream),
                            volume, tostring(muffled), pan)
                        if playing[id] ~= key then
                            playing[id] = key
                            send(id, radio, volume, muffled, pan)
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
        if old and (old.url ~= value.url or old.start ~= value.start) then stop(bagName) end
        radios[bagName] = { url = value.url, start = value.start, volume = tonumber(value.volume) or 60, stream = value.stream }
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
        id = ('entity:%d'):format(VehToNet(vehicle)), -- lecteur du NUI (effets actifs ou non)
        vehicle = RPI.vehicleLabel and RPI.vehicleLabel(vehicle) or nil,
        radio = type(radio) == 'table' and { url = radio.url, volume = radio.volume } or false,
    }
end

RegisterNUICallback('radioInfo', function(_, cb) cb(radioInfo()) end)

RegisterNUICallback('radioAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    local vehicle, mode = radioVehicle()
    if not vehicle or not canControl(vehicle, mode) then
        return cb({ ok = false, error = 'Seules les places avant peuvent régler la radio.' })
    end
    RPI.request('radio', { netId = VehToNet(vehicle), action = data.action, url = data.url, volume = data.volume }, function(res)
        if not res or not res.ok then return cb(res or { ok = false }) end
        local info = radioInfo()
        info.radio = type(res.radio) == 'table' and { url = res.radio.url, volume = res.radio.volume } or false
        cb(info)
    end)
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
