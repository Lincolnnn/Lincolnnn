--[[
    Vehicle Control - feux stop à l'arrêt et position des roues (client)
    --------------------------------------------------------------------
    FEUX STOP (StopLights) : véhicule à l'arrêt, moteur tournant, conducteur au volant -> feux stop
      allumés, comme un pied sur le frein. Le conducteur les allume lui-même à chaque image et publie
      l'état du véhicule "vcStopLights" : les autres joueurs les allument aussi de leur côté.
    ROUES (KeepWheelAngle) : en descendant, le jeu remet les roues droites. L'angle du volant juste avant
      la descente est gardé : réappliqué pendant la descente, puis publié dans l'état du véhicule
      "vcSteer" pour les autres joueurs (et pour un véhicule qui revient à portée).
    Performance : à bord, quelques natives par image (déjà dans la boucle du véhicule) ; pour les
    véhicules des autres joueurs, une boucle à chaque image UNIQUEMENT tant qu'un véhicule proche a ses
    feux stop allumés ; roues : boucle de 2 s après une descente.
]]

local Config = VCConfig
local STOPPED_SPEED = 0.3   -- m/s : en dessous, véhicule à l'arrêt
local PUBLISH_DELAY = 400   -- ms d'arrêt avant de publier les feux stop (pas à chaque ralentissement)
local KEEP_MS = 2000        -- ms pendant lesquelles l'angle des roues est réappliqué après la descente

-- =========================================================================
-- FEUX STOP
-- =========================================================================
local published = nil       -- dernière valeur publiée pour le véhicule du joueur
local stoppedSince = nil

local function publishStopLights(vehicle, on)
    if published == on then return end
    published = on
    VC.setState(vehicle, 'vcStopLights', on)
end

VC.on('frame', function(_, vehicle)
    if not Config.StopLights or VC.seat ~= -1 then return end
    local stopped = GetIsVehicleEngineRunning(vehicle) and GetEntitySpeed(vehicle) < STOPPED_SPEED
    if stopped then
        SetVehicleBrakeLights(vehicle, true) -- à refaire à chaque image (le jeu les éteint sinon)
        local now = GetGameTimer()
        stoppedSince = stoppedSince or now
        if now - stoppedSince >= PUBLISH_DELAY then publishStopLights(vehicle, true) end
    else
        stoppedSince = nil
        if published then publishStopLights(vehicle, false) end
    end
end)

-- Feux stop des véhicules des autres joueurs
local lit = {}              -- [nom du state bag] = true
local litRunning = false

local function litLoop()
    if litRunning then return end
    litRunning = true
    CreateThread(function()
        while next(lit) do
            for bagName in pairs(lit) do
                local vehicle = GetEntityFromStateBagName(bagName)
                if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
                    lit[bagName] = nil -- hors de portée : repris quand il revient (état du véhicule)
                elseif vehicle ~= VC.vehicle or VC.seat ~= -1 then
                    SetVehicleBrakeLights(vehicle, true)
                end
            end
            Wait(0)
        end
        litRunning = false
    end)
end

AddStateBagChangeHandler('vcStopLights', nil, function(bagName, _, value)
    if not Config.StopLights then return end
    if value == true then
        lit[bagName] = true
        litLoop()
    else
        lit[bagName] = nil
    end
end)

-- =========================================================================
-- POSITION DES ROUES À LA DESCENTE
-- =========================================================================
local steer = 0.0           -- angle du volant juste avant la descente
local exiting = false

local function holdAngle(vehicle, angle)
    CreateThread(function()
        local untilTime = GetGameTimer() + KEEP_MS
        while GetGameTimer() < untilTime and DoesEntityExist(vehicle) do
            if GetPedInVehicleSeat(vehicle, -1) ~= 0 and GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then break end
            SetVehicleSteeringAngle(vehicle, angle)
            Wait(0)
        end
    end)
end

VC.on('frame', function(ped, vehicle)
    if not Config.KeepWheelAngle or VC.seat ~= -1 then return end
    if GetIsTaskActive(ped, 2) then -- descente commencée : le jeu redresse les roues
        if not exiting then
            exiting = true
            VC.setState(vehicle, 'vcSteer', math.floor(steer * 10 + 0.5) / 10) -- encore conducteur
            holdAngle(vehicle, steer)
        end
    else
        exiting = false
        steer = GetVehicleSteeringAngle(vehicle)
    end
end)

local function takeWheel(vehicle)
    if Config.KeepWheelAngle and type(VC.state(vehicle, 'vcSteer')) == 'number' then
        VC.setState(vehicle, 'vcSteer', false) -- le nouveau conducteur tient le volant
    end
end

VC.on('enter', function(_, vehicle, seat) if seat == -1 then takeWheel(vehicle) end end)
VC.on('seat', function(_, vehicle, seat) if seat == -1 then takeWheel(vehicle) end end)

VC.on('leave', function(vehicle, seat, info)
    if seat ~= -1 or not DoesEntityExist(vehicle) or (info and info.gone) then
        published, stoppedSince, exiting = nil, nil, false
        return
    end
    if published then publishStopLights(vehicle, false) end
    published, stoppedSince = nil, nil
    if Config.KeepWheelAngle and exiting then holdAngle(vehicle, steer) end
    exiting = false
end)

-- Autres joueurs / véhicule revenu à portée : roues remises à l'angle gardé
AddStateBagChangeHandler('vcSteer', nil, function(bagName, _, value)
    if not Config.KeepWheelAngle or type(value) ~= 'number' then return end
    CreateThread(function()
        local timeout = GetGameTimer() + 3000
        local vehicle = GetEntityFromStateBagName(bagName)
        while (not vehicle or vehicle == 0) and GetGameTimer() < timeout do
            Wait(100)
            vehicle = GetEntityFromStateBagName(bagName)
        end
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == 0 then
            holdAngle(vehicle, value)
        end
    end)
end)
