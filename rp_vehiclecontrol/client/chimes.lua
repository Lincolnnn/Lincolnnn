--[[
    Vehicle Control - carillons de ceinture et de portière (client)
    ----------------------------------------------------------------
    Même fonctionnement que le son des clignotants (signals.lua), qui tourne en boucle sans faille :
      - un son PAR VÉHICULE (identifiants "chime:<véhicule>" et "door:<véhicule>"), jamais partagé ni
        disputé entre véhicules ;
      - le véhicule est SUIVI tant que son carillon a lieu d'être ; une boucle de 200 ms ne recalcule que le
        volume (position du joueur) et n'envoie au NUI que ce qui change ; rien n'est renvoyé, rien n'est relancé ;
      - carillon fini : son coupé net.
    CARILLON DE CEINTURE (belt_chime.ogg ; deux occupants ou plus détachés : fast_belt_chime.ogg) :
      sonne en boucle dès qu'un occupant détaché a son alarme (seatbelt.lua : moteur allumé, plus de 1 MPH) et
      ne s'arrête QUE si la ceinture est attachée, le moteur coupé ou la personne descendue. Le deuxième
      s'attache : fast_belt_chime coupé, belt_chime reprend.
    CARILLON DE PORTIÈRE (door_chime.ogg) : moteur allumé et une portière (avant / arrière) ouverte, à bord
      comme dehors, même véhicule vide ; ne s'arrête QUE moteur coupé ou portières refermées. Le véhicule dont
      le joueur descend reste suivi (TrackDistance), sans attendre son état réseau.
    Entendus à 100 % à bord ; dehors autour de la carrosserie (VehicleSounds : 3 m portière ouverte, 1 m fermé).
    ChimeSoundMode = 'loop' (fichier en boucle) ou 'repeat' (rejoué toutes les ChimeInterval ms), comme les
    clignotants. Diagnostic : setr vc_debug_sound 1 (console F8).
    Performance : boucle de 200 ms seulement tant qu'un véhicule est suivi (à bord, dernier véhicule moteur
    allumé, joueur détaché ou véhicule au moteur allumé à portée réseau) ; aucune sinon.
]]

local Config = VCConfig.Seatbelt
local Chime = VCConfig.DoorChime or {}

local alarms = {}      -- [id serveur] = true : autres joueurs dont l'alarme de ceinture est allumée
local engines = {}     -- [nom du state bag] = true : véhicules au moteur allumé (vcEngine), même vides
local lastVehicle = 0  -- véhicule dont le joueur vient de descendre (suivi tant que son moteur tourne)
local sent = {}        -- [id NUI] = dernier envoi "fichier|volume|étouffé"
local doorSeen = {}    -- [véhicule] = dernier moment où une portière a été vue ouverte
local running = false

local function keyOf(vehicle)
    if NetworkGetEntityIsNetworked(vehicle) then return ('entity:%d'):format(VehToNet(vehicle)) end
    return ('local:%d'):format(vehicle)
end

local function serverIdOfBag(bagName)
    return tonumber(bagName:match('^player:(%d+)$'))
end

--- Véhicule d'un autre joueur (le sien, ou le dernier s'il vient d'en descendre) ; nil : joueur parti
local function vehicleOf(serverId)
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then vehicle = GetVehiclePedIsIn(ped, true) end
    return vehicle
end

--- Une portière (avant / arrière) ouverte ? Encore vraie DoorHold ms après (une portière qui bouge un
--- instant ne coupe pas le carillon)
local function doorOpen(vehicle)
    local now = GetGameTimer()
    for door = 0, 3 do
        if GetVehicleDoorAngleRatio(vehicle, door) > 0.05 then
            doorSeen[vehicle] = now
            return true
        end
    end
    local seen = doorSeen[vehicle]
    if seen and now - seen < (Chime.DoorHold or 800) then return true end
    doorSeen[vehicle] = nil
    return false
end

-- Réglage des fichiers de carillon dans le NUI (silence maximal entre deux passages), envoyé une fois
local configSent = false
local function sendConfig()
    if configSent then return end
    configSent = true
    local gap = tonumber(Config.ChimeMaxGap) or 0
    SendNUIMessage({ action = 'soundConfig', data = { maxGap = { belt_chime = gap, fast_belt_chime = gap, door_chime = gap } } })
end

--- Envoi au NUI (comme les clignotants) : seulement ce qui change
local function sendSound(id, file, volume, muffled)
    sendConfig()
    volume = math.floor(volume * 100 + 0.5) / 100
    local mark = ('%s|%.2f|%s'):format(file, volume, tostring(volume > 0 and muffled))
    if sent[id] == mark then return end
    if sent[id] == nil then VC.debugSound(('%s : démarré (%s)'):format(id, file)) end
    sent[id] = mark
    local loop = Config.ChimeSoundMode ~= 'repeat'
    VC.soundLoop(id, { file }, Config.ChimeInterval or 1000, volume, loop, muffled)
end

local function stopSound(id, reason)
    if not sent[id] then return end
    sent[id] = nil
    VC.debugSound(('%s : coupé (%s)'):format(id, reason))
    VC.soundLoop(id, { 'belt_chime' }, 0, 0.0, true, false)
end

--- Véhicules suivis : le sien, celui dont il vient de descendre, ceux des joueurs détachés, ceux au moteur
--- allumé à portée
local function candidates()
    local list = {}
    local function add(vehicle)
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then list[vehicle] = true end
    end
    add(VC.vehicle)
    if lastVehicle ~= 0 then
        if DoesEntityExist(lastVehicle) and VC.engineOn(lastVehicle)
            and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(lastVehicle)) <= (Chime.TrackDistance or 60.0) then
            add(lastVehicle)
        else
            lastVehicle = 0
        end
    end
    for serverId in pairs(alarms) do
        local vehicle = vehicleOf(serverId)
        if vehicle == nil then alarms[serverId] = nil else add(vehicle) end
    end
    for bagName in pairs(engines) do
        local vehicle = GetEntityFromStateBagName(bagName) or 0
        if vehicle == 0 then engines[bagName] = nil else add(vehicle) end -- repris quand il revient à portée
    end
    return list
end

--- Carillons d'un véhicule ; `playing` reçoit les sons en cours
local function update(vehicle, playing)
    local key = keyOf(vehicle)
    local hear, muffled
    -- Ceinture : occupants dont l'alarme est allumée (lui-même + autres joueurs)
    local unbuckled = (VC.beltAlarm() and VC.vehicle == vehicle) and 1 or 0
    for serverId in pairs(alarms) do
        if vehicleOf(serverId) == vehicle then unbuckled = unbuckled + 1 end
    end
    if unbuckled > 0 then
        hear, muffled = VC.hearVehicle(vehicle)
        local id = 'chime:' .. key
        sendSound(id, unbuckled >= 2 and 'fast_belt_chime' or 'belt_chime', hear * (Config.ChimeVolume or 1.0), muffled)
        playing[id] = true
    end
    -- Portière : moteur allumé et portière ouverte
    if Chime.Enabled ~= false and VC.engineOn(vehicle) and doorOpen(vehicle) then
        if not hear then hear, muffled = VC.hearVehicle(vehicle) end
        local id = 'door:' .. key
        sendSound(id, 'door_chime', hear * (Chime.Volume or 1.0), muffled)
        playing[id] = true
    end
end

local function refresh()
    local playing = {}
    for vehicle in pairs(candidates()) do update(vehicle, playing) end
    for id in pairs(sent) do
        if not playing[id] then
            stopSound(id, id:sub(1, 5) == 'door:' and 'moteur coupé ou portières fermées' or 'ceinture attachée, moteur coupé ou descendu')
        end
    end
    for vehicle in pairs(doorSeen) do
        if not DoesEntityExist(vehicle) then doorSeen[vehicle] = nil end -- véhicule supprimé
    end
end

local function busy()
    return next(sent) ~= nil or (VC.vehicle or 0) ~= 0 or lastVehicle ~= 0 or next(alarms) ~= nil
        or next(engines) ~= nil or VC.beltAlarm()
end

--- Recalcule tout de suite et suit les véhicules (boucle de 200 ms tant qu'il y a quelque chose à suivre)
function VC.refreshChimes()
    refresh()
    if running then return end
    running = true
    CreateThread(function()
        while busy() do
            Wait(200)
            refresh()
        end
        running = false
    end)
end

VC.on('enter', function()
    lastVehicle = 0
    VC.refreshChimes()
end)

-- Descendu : son véhicule reste suivi (carillon de portière dehors, moteur laissé allumé)
VC.on('leave', function(vehicle)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then lastVehicle = vehicle end
    VC.refreshChimes()
end)

-- Autres joueurs : alarme de ceinture (leur carillon vient de leur véhicule)
AddStateBagChangeHandler('seatbeltAlarm', nil, function(bagName, _, value)
    local serverId = serverIdOfBag(bagName)
    if not serverId or serverId == GetPlayerServerId(PlayerId()) then return end
    alarms[serverId] = value == true or nil
    VC.refreshChimes()
end)

-- Véhicules au moteur allumé (par Vehicle Control) : leur carillon de portière est calculé ici, même vides
AddStateBagChangeHandler('vcEngine', nil, function(bagName, _, value)
    engines[bagName] = value == true or nil
    VC.refreshChimes()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(sent) do VC.soundLoop(id, { 'belt_chime' }, 0, 0.0, true, false) end
end)
