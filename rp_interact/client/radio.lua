--[[
    RP Interact - Radio du véhicule (client)
    ----------------------------------------
    Menu d'interactions > Voiture > Radio : un lien (YouTube, ou lien direct vers une musique, un
    podcast, une radio en ligne) joué DANS LE VÉHICULE.
      - L'état est porté par le véhicule ("rpiRadio" : lien, heure de lancement, volume) : tous les
        joueurs entendent la même chose au même moment, et au même volume de base (89 % = 89 % pour
        tout le monde), réglé seulement par les places avant, ou avec l'œil en visant l'intérieur avant
        du véhicule portière avant ouverte.
      - Chaque joueur entend selon sa position : à bord, normalement ; dehors, plus ou moins fort selon
        la distance (RadioRange) et "insonorisé" (son étouffé, plus faible) si aucune vitre n'est
        baissée et aucune portière ouverte.
    Le son est joué par le NUI de ce script (html/script.js). Performance : boucle (250 ms) seulement
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
--- Une vitre baissée / cassée, une portière (ou le coffre / le capot) ouverte, ou un toit décapoté ?
local function isOpen(vehicle)
    for door = 0, 5 do
        if GetVehicleDoorAngleRatio(vehicle, door) > 0.05 then return true end
    end
    for window = 0, 3 do
        if not IsVehicleWindowIntact(vehicle, window) then return true end
    end
    return IsVehicleAConvertible(vehicle, false) and GetConvertibleRoofState(vehicle) ~= 0
end

--- Facteur de volume (0..1) et son étouffé pour ce joueur
function RPI.radioHearing(vehicle)
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) == vehicle then return 1.0, false end
    local distance = #(GetEntityCoords(ped) - GetEntityCoords(vehicle))
    if distance >= Config.RadioRange then return 0.0, true end
    local factor = (1.0 - distance / Config.RadioRange) ^ 1.6
    if isOpen(vehicle) then return factor, false end
    return factor * Config.RadioInsulation, true
end

local function send(id, radio, volume, muffled)
    SendNUIMessage({ action = 'radio', data = {
        id = id, url = radio.url, volume = volume, muffled = muffled,
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
                    local factor, muffled = RPI.radioHearing(vehicle)
                    local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle))
                    if factor <= 0.0 and distance > Config.RadioRange + 20.0 then
                        stop(id) -- loin : lecteur fermé (rouvert à l'approche, au bon moment)
                    else
                        local volume = math.floor((radio.volume or 0) / 100 * factor * Config.RadioMaxVolume * 100 + 0.5) / 100
                        local key = ('%s|%s|%.2f|%s'):format(radio.url, radio.start, volume, tostring(muffled))
                        if playing[id] ~= key then
                            playing[id] = key
                            send(id, radio, volume, muffled)
                        end
                    end
                end
            end
            Wait(250)
        end
        loopRunning = false
    end)
end

-- Radio allumée / réglée / coupée dans un véhicule (ou véhicule arrivé à portée)
AddStateBagChangeHandler('rpiRadio', nil, function(bagName, _, value)
    if type(value) == 'table' and type(value.url) == 'string' then
        if radios[bagName] and radios[bagName].url ~= value.url then stop(bagName) end
        radios[bagName] = { url = value.url, start = value.start, volume = tonumber(value.volume) or 60 }
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
