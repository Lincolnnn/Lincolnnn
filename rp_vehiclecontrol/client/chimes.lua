--[[
    Vehicle Control - carillon de ceinture (client)
    -----------------------------------------------
    Même fonctionnement que le son des clignotants (signals.lua), qui tourne en boucle sans faille :
      - un son PAR VÉHICULE (identifiant "chime:<véhicule>"), jamais partagé ni disputé entre véhicules ;
      - le véhicule est SUIVI tant que son carillon a lieu d'être ; une boucle de 200 ms ne recalcule que le
        volume (position du joueur) et n'envoie au NUI que ce qui change ; rien n'est renvoyé, rien n'est relancé ;
      - carillon fini : son coupé net.
    CARILLON DE CEINTURE (belt_chime.ogg ; deux occupants ou plus détachés : fast_belt_chime.ogg) :
      sonne en boucle dès qu'un occupant détaché a son alarme (seatbelt.lua : moteur allumé, plus de 1 MPH) et
      ne s'arrête QUE véhicule immobile, ceinture attachée, moteur coupé ou personne descendue. Le deuxième
      s'attache : fast_belt_chime coupé, belt_chime reprend.
    Entendu à 100 % à bord ; dehors autour de la carrosserie (VehicleSounds : 3 m portière ouverte, 1 m fermé).
    ChimeSoundMode = 'loop' (fichier en boucle) ou 'repeat' (rejoué toutes les ChimeInterval ms), comme les
    clignotants. Diagnostic : setr vc_debug_sound 1 (console F8).
    Performance : boucle de 200 ms seulement tant qu'un carillon a lieu d'être (à bord, ou joueur détaché à
    portée) ; aucune sinon.
]]

local Config = VCConfig.Seatbelt

local alarms = {}      -- [id serveur] = true : autres joueurs dont l'alarme de ceinture est allumée
local sent = {}        -- [id NUI] = dernier envoi "fichier|volume|étouffé"
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

-- Réglage des fichiers de carillon dans le NUI (boucle recollée, silence maximal), envoyé une fois
local configSent = false
local function sendConfig()
    if configSent then return end
    configSent = true
    local gap = tonumber(Config.ChimeMaxGap) or 0
    local glue = Config.ChimeSeamless ~= false
    SendNUIMessage({ action = 'soundConfig', data = {
        maxGap = { belt_chime = gap, fast_belt_chime = gap },
        seamless = { belt_chime = glue, fast_belt_chime = glue },
    } })
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

local function stopSound(id)
    if not sent[id] then return end
    sent[id] = nil
    VC.debugSound(('%s : coupé (ceinture attachée, véhicule immobile, moteur coupé ou descendu)'):format(id))
    VC.soundLoop(id, { 'belt_chime' }, 0, 0.0, true, false)
end

--- Véhicules dont un occupant est détaché (lui-même + autres joueurs) : { [véhicule] = nombre }
local function unbuckledVehicles()
    local list = {}
    local mine = VC.vehicle or 0
    if VC.beltAlarm() and mine ~= 0 and DoesEntityExist(mine) then list[mine] = 1 end
    for serverId in pairs(alarms) do
        local vehicle = vehicleOf(serverId)
        if vehicle == nil then alarms[serverId] = nil
        elseif vehicle ~= 0 and DoesEntityExist(vehicle) then list[vehicle] = (list[vehicle] or 0) + 1 end
    end
    return list
end

local function refresh()
    local playing = {}
    for vehicle, count in pairs(unbuckledVehicles()) do
        local id = 'chime:' .. keyOf(vehicle)
        local hear, muffled = VC.hearVehicle(vehicle)
        sendSound(id, count >= 2 and 'fast_belt_chime' or 'belt_chime', hear * (Config.ChimeVolume or 1.0), muffled)
        playing[id] = true
    end
    for id in pairs(sent) do
        if not playing[id] then stopSound(id) end
    end
end

--- Recalcule tout de suite et suit les véhicules (boucle de 200 ms tant qu'un carillon a lieu d'être)
function VC.refreshChimes()
    refresh()
    if running then return end
    running = true
    CreateThread(function()
        while next(sent) ~= nil or next(alarms) ~= nil or VC.beltAlarm() do
            Wait(200)
            refresh()
        end
        running = false
    end)
end

VC.on('enter', function() VC.refreshChimes() end)
VC.on('leave', function() VC.refreshChimes() end)

-- Autres joueurs : alarme de ceinture (leur carillon vient de leur véhicule)
AddStateBagChangeHandler('seatbeltAlarm', nil, function(bagName, _, value)
    local serverId = serverIdOfBag(bagName)
    if not serverId or serverId == GetPlayerServerId(PlayerId()) then return end
    alarms[serverId] = value == true or nil
    VC.refreshChimes()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(sent) do VC.soundLoop(id, { 'belt_chime' }, 0, 0.0, true, false) end
end)
