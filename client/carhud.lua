--[[
    MDC Standalone - Car HUD + ceinture de sécurité (client)
    ---------------------------------------------------------
    Car HUD (dessiné par le NUI, html/script.js) : à bord d'un véhicule, au-dessus de la minimap, sans fond :
      - vitesse en MPH (un simple nombre, pas de compteur) ;
      - petite barre horizontale d'accélération (régime du moteur) ;
      - jauge d'essence verticale (ox_fuel, LegacyFuel ou niveau du jeu ; masquée sans réservoir) ;
      - petit logo de la ceinture (masqué pour les motos, vélos, bateaux et aéronefs).
    Position, taille, éléments affichés et volume : onglet "Paramètres" du MDC (HUD & Display).

    Ceinture : touche K (Raccourcis clavier > FiveM > "Véhicule : attacher / détacher la ceinture").
      - Attachée : le personnage ne passe plus à travers le pare-brise.
      - Détachée et véhicule à plus de 5 MPH : bip continu jusqu'à l'arrêt du véhicule (ou jusqu'à ce
        qu'elle soit attachée). Retirée automatiquement en descendant du véhicule.
      - Sons synchronisés : attacher / détacher et le bip de l'alarme sont entendus par les occupants du
        véhicule et par les joueurs autour (volume selon la distance, Car.HearRange). État publié dans
        l'état du joueur ("seatbelt", "seatbeltAlarm"), lu par les autres clients.

    Performance :
      - à pied : une vérification toutes les 500 ms (~0.00 ms) ;
      - en véhicule : toutes les 100 ms, n'envoie au NUI que ce qui a changé (~0.01 ms) ;
      - bip des autres joueurs : boucle (250 ms) uniquement pendant qu'une alarme est active à portée.
]]

local Car = {
    Interval = 100,        -- ms entre deux mises à jour à bord d'un véhicule
    IdleInterval = 500,    -- ms entre deux vérifications à pied
    SeatbeltKey = 'K',     -- touche par défaut (modifiable par chaque joueur dans les raccourcis FiveM)
    AlarmSpeed = 5.0,      -- MPH : le bip démarre au-dessus de cette vitesse (ceinture détachée)
    StopSpeed = 1.0,       -- MPH : en dessous, le véhicule est arrêté et le bip s'arrête
    HearRange = 15.0,      -- m : distance à laquelle les autres joueurs entendent la ceinture
    OutsideVolume = 0.7,   -- volume entendu hors du véhicule (à 0 m), les occupants entendent à 100 %
    -- Classes sans ceinture : motos, vélos, bateaux, hélicoptères, avions, trains
    NoBeltClasses = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true },
}

local MPH = 2.236936 -- m/s -> MPH

local belt, alarm = false, false
local current = 0      -- véhicule où se trouve le joueur
local lastKey = nil    -- dernier état envoyé au NUI
local alarms = {}      -- [id serveur] = true : joueurs (autres que soi) dont l'alarme est active
local beepRunning = false

local function hasBelt(vehicle)
    return not Car.NoBeltClasses[GetVehicleClass(vehicle)]
end

local function clamp(value) return math.max(0.0, math.min(100.0, value + 0.0)) end

--- Essence en % : ox_fuel (état "fuel"), LegacyFuel (décor "_FUEL_LEVEL"), sinon niveau du jeu.
--- nil = pas de réservoir (vélo, véhicule sans réservoir) : jauge masquée.
local function fuelLevel(vehicle)
    if GetVehicleClass(vehicle) == 13 then return nil end
    if NetworkGetEntityIsNetworked(vehicle) then
        local fuel = Entity(vehicle).state.fuel
        if type(fuel) == 'number' then return clamp(fuel) end
    end
    if DecorIsRegisteredAsType('_FUEL_LEVEL', 1) and DecorExistOn(vehicle, '_FUEL_LEVEL') then
        return clamp(DecorGetFloat(vehicle, '_FUEL_LEVEL'))
    end
    local tank = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fPetrolTankVolume')
    if not tank or tank <= 0.0 then return nil end
    return clamp(GetVehicleFuelLevel(vehicle) / tank * 100.0)
end

-- =========================================================================
-- SONS : volume selon la distance (occupants du même véhicule : 100 %)
-- =========================================================================
local function serverIdOfBag(bagName)
    return tonumber(bagName:match('^player:(%d+)$'))
end

--- Volume auquel ce client entend le joueur `serverId` (0 hors de portée, nil s'il n'est plus là)
local function hearVolume(serverId)
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local me = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and vehicle == GetVehiclePedIsIn(me, false) then return 1.0 end
    local distance = #(GetEntityCoords(ped) - GetEntityCoords(me))
    if distance >= Car.HearRange then return 0.0 end
    return (1.0 - distance / Car.HearRange) * Car.OutsideVolume
end

local function beltSound(kind, volume)
    SendNUIMessage({ action = 'beltSound', data = { kind = kind, volume = volume } })
end

--- Bip de l'alarme : le plus fort entre la sienne (100 %) et celles des joueurs à portée.
--- Boucle uniquement tant qu'une alarme est active.
local function beepLoop()
    if beepRunning then return end
    beepRunning = true
    CreateThread(function()
        local last = 0.0
        while alarm or next(alarms) do
            local volume = alarm and 1.0 or 0.0
            for serverId in pairs(alarms) do
                local v = hearVolume(serverId)
                if v == nil then
                    alarms[serverId] = nil -- joueur parti / hors de portée réseau
                elseif v > volume then
                    volume = v
                end
            end
            volume = math.floor(volume * 20 + 0.5) / 20
            if volume ~= last then
                last = volume
                SendNUIMessage({ action = 'beltBeep', data = { volume = volume } })
            end
            Wait(250)
        end
        if last ~= 0.0 then SendNUIMessage({ action = 'beltBeep', data = { volume = 0.0 } }) end
        beepRunning = false
    end)
end

-- =========================================================================
-- CEINTURE (joueur local)
-- =========================================================================
local function setAlarm(state)
    if state == alarm then return end
    alarm = state
    LocalPlayer.state:set('seatbeltAlarm', state, true) -- entendu par les joueurs proches
    beepLoop()
end

local function setBelt(state, silent)
    if state == belt then return end
    belt = state
    SetPedConfigFlag(PlayerPedId(), 32, not state) -- 32 : peut passer à travers le pare-brise
    LocalPlayer.state:set('seatbelt', state, true)  -- les joueurs proches entendent le son
    if state then setAlarm(false) end
    if not silent then beltSound(state and 'on' or 'off', 1.0) end
end

RegisterCommand('mdc_seatbelt', function()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 or not hasBelt(vehicle) or IsPauseMenuActive() then return end
    setBelt(not belt)
end, false)
RegisterKeyMapping('mdc_seatbelt', 'Véhicule : attacher / détacher la ceinture', 'keyboard', Car.SeatbeltKey)

-- Ceinture et alarme des AUTRES joueurs (état "seatbelt" / "seatbeltAlarm" de leur personnage)
AddStateBagChangeHandler('seatbelt', nil, function(bagName, _, value)
    local serverId = serverIdOfBag(bagName)
    if not serverId or serverId == GetPlayerServerId(PlayerId()) then return end
    local volume = hearVolume(serverId)
    if volume and volume > 0.0 then beltSound(value == true and 'on' or 'off', volume) end
end)

AddStateBagChangeHandler('seatbeltAlarm', nil, function(bagName, _, value)
    local serverId = serverIdOfBag(bagName)
    if not serverId or serverId == GetPlayerServerId(PlayerId()) then return end
    alarms[serverId] = value == true or nil
    if value == true then beepLoop() end
end)

-- =========================================================================
-- CAR HUD
-- =========================================================================
local function sendHud(data)
    local key = data.show and ('%d|%.2f|%s|%s|%s|%s'):format(data.speed, data.rpm, tostring(data.fuel),
        tostring(data.belt), tostring(data.alarm), tostring(data.paused)) or 'hidden'
    if key == lastKey then return end
    lastKey = key
    SendNUIMessage({ action = 'carHud', data = data })
end

local function update(ped, vehicle)
    local speed = GetEntitySpeed(vehicle) * MPH
    local withBelt = hasBelt(vehicle)

    -- Descend du véhicule : ceinture retirée (avec le son)
    if belt and GetIsTaskActive(ped, 2) then setBelt(false) end

    -- Alarme : ceinture détachée au-dessus de 5 MPH, jusqu'à l'arrêt du véhicule
    if withBelt and not belt then
        if not alarm and speed > Car.AlarmSpeed then
            setAlarm(true)
        elseif alarm and speed < Car.StopSpeed then
            setAlarm(false)
        end
    elseif alarm then
        setAlarm(false)
    end

    -- Barre d'accélération : régime du moteur (ralenti ~0.2 -> 0 %, régime maximal -> 100 %)
    local rpm = GetIsVehicleEngineRunning(vehicle) and GetVehicleCurrentRpm(vehicle) or 0.0
    rpm = math.max(0.0, math.min(1.0, (rpm - 0.2) / 0.8))
    local fuel = fuelLevel(vehicle)

    local data = {
        show = true,
        speed = math.floor(speed + 0.5),
        rpm = math.floor(rpm * 50 + 0.5) / 50,
        fuel = fuel and math.floor(fuel + 0.5) or nil, -- nil : pas de réservoir (jauge masquée)
        alarm = alarm,
        paused = IsPauseMenuActive() or IsScreenFadedOut(),
    }
    if withBelt then data.belt = belt end -- absent : pas de ceinture (logo masqué)
    sendHud(data)
end

local function leave()
    current = 0
    if belt then setBelt(false) end
    setAlarm(false)
    sendHud({ show = false })
end

CreateThread(function()
    -- Ressource redémarrée : état publié remis à zéro
    if LocalPlayer.state.seatbelt then LocalPlayer.state:set('seatbelt', false, true) end
    if LocalPlayer.state.seatbeltAlarm then LocalPlayer.state:set('seatbeltAlarm', false, true) end
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 then
            if vehicle ~= current then
                if current ~= 0 then leave() end
                current = vehicle
            end
            update(ped, vehicle)
            Wait(Car.Interval)
        else
            if current ~= 0 then leave() end
            Wait(Car.IdleInterval)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetPedConfigFlag(PlayerPedId(), 32, true)
    LocalPlayer.state:set('seatbelt', false, true)
    LocalPlayer.state:set('seatbeltAlarm', false, true)
end)

-- NUI rechargé (client/hud.lua, "hudReady") : état renvoyé à la prochaine mise à jour
MdcCarHud = {
    resend = function() lastKey = nil end,
    isBuckled = function() return belt end,
}
