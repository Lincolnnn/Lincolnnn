--[[
    Vehicle Control - essence (client)
    ----------------------------------
    - Essence en % dans l'état du véhicule ("fuel", même format qu'ox_fuel : lisible par d'autres
      scripts), écrite par le serveur, lue par tous (passagers, car HUD).
    - Consommation calculée par le CONDUCTEUR, en temps réel (pas l'heure du jeu) : un plein dure
      Fuel.FullTankMinutes (3 h 30) en conduite normale ; selon la charge du moteur, de 40 % (ralenti)
      à 160 % (pied au plancher) de cette consommation. Moteur laissé allumé sans conducteur : le
      joueur qui l'a laissé continue de compter (ralenti). Réservoir percé : fuite.
    - Panne sèche : moteur coupé, impossible à redémarrer avant d'avoir remis de l'essence.
    - Plein (pompe avec un vrai pistolet, jerrican) : client/refuel.lua.
    Performance : aucune boucle ici (mise à jour du véhicule de main.lua, à bord seulement).
]]

local Config = VCConfig.Fuel
local RATE = 100.0 / (Config.FullTankMinutes * 60.0) -- % par seconde en conduite normale

local tracked = {} -- [véhicule] = { fuel, sent, sentAt } : véhicules dont CE client compte l'essence

local function hasTank(vehicle)
    return not Config.NoFuelClasses[GetVehicleClass(vehicle)]
end

local function clamp(value) return math.max(0.0, math.min(100.0, value + 0.0)) end

local function tankVolume(vehicle)
    local volume = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fPetrolTankVolume')
    return (volume and volume > 0.0) and volume or 65.0
end

--- Essence actuelle (%) ; nil = inconnue (jamais conduit) ou pas de réservoir
function VC.fuel(vehicle)
    if not hasTank(vehicle) then return nil end
    local t = tracked[vehicle]
    if t then return t.fuel end
    local fuel = VC.state(vehicle, 'fuel')
    return type(fuel) == 'number' and fuel or nil
end

--- Le moteur peut-il tourner ? (pas en panne sèche)
function VC.hasFuel(vehicle)
    local fuel = VC.fuel(vehicle)
    return fuel == nil or fuel > 0.0
end

--- Essence d'un véhicule jamais vu : créé par un script = plein, circulation = au hasard
local function initialFuel(vehicle)
    if GetEntityPopulationType(vehicle) == 7 then return Config.SpawnedFuel end
    return Config.AmbientFuel.min + math.random() * (Config.AmbientFuel.max - Config.AmbientFuel.min)
end

--- Envoi au serveur (état du véhicule, lu par tous)
local function sendFuel(vehicle, fuel, reason)
    if NetworkGetEntityIsNetworked(vehicle) then
        VC.setPending(vehicle, 'fuel', fuel) -- tout de suite chez ce client
        TriggerServerEvent('rp_vehiclecontrol:fuel', VehToNet(vehicle), fuel, reason)
    else
        VC.setState(vehicle, 'fuel', fuel)
    end
end

--- Nouvelle valeur d'un véhicule compté par ce client : envoyée à chaque % ou toutes les 15 s
local function setFuel(vehicle, fuel, force)
    local t = tracked[vehicle]
    if not t then return end
    t.fuel = clamp(fuel)
    SetVehicleFuelLevel(vehicle, tankVolume(vehicle) * t.fuel / 100.0)
    local now = GetGameTimer()
    if force or math.floor(t.fuel) ~= math.floor(t.sent) or now - t.sentAt > 15000 then
        t.sent, t.sentAt = t.fuel, now
        sendFuel(vehicle, t.fuel, 'drive')
    end
end

--- Ce client compte l'essence de ce véhicule (il le conduit)
local function track(vehicle)
    local t = tracked[vehicle]
    if t then return t end
    local fuel = VC.state(vehicle, 'fuel')
    local fresh = type(fuel) ~= 'number'
    if fresh then fuel = initialFuel(vehicle) end
    t = { fuel = clamp(fuel), sent = clamp(fuel), sentAt = GetGameTimer() }
    tracked[vehicle] = t
    SetVehicleFuelLevel(vehicle, tankVolume(vehicle) * t.fuel / 100.0)
    if fresh then sendFuel(vehicle, t.fuel, 'init') end
    return t
end

--- Consommation pendant `dt` secondes (idleOnly : moteur laissé allumé, personne au volant)
local function consume(vehicle, t, dt, idleOnly)
    local fuel = t.fuel
    if fuel > 0.0 and GetIsVehicleEngineRunning(vehicle) then
        local load = 0.0
        if not idleOnly then
            load = math.max(0.0, math.min(1.0, (GetVehicleCurrentRpm(vehicle) - 0.2) / 0.8))
        end
        local factor = Config.IdleFactor + (Config.MaxFactor - Config.IdleFactor) * load
        fuel = fuel - RATE * factor * (Config.ClassFactor[GetVehicleClass(vehicle)] or 1.0) * dt
    end
    -- Réservoir percé : fuite proportionnelle aux dégâts du réservoir
    local tank = GetVehiclePetrolTankHealth(vehicle)
    if fuel > 0.0 and tank < Config.LeakBelow then
        local leak = (Config.LeakBelow - math.max(tank, 0.0)) / Config.LeakBelow
        fuel = fuel - Config.LeakPerMinute / 60.0 * leak * dt
    end
    if fuel <= 0.0005 then
        fuel = 0.0
        -- Panne sèche : moteur coupé (impossible à redémarrer, voir controls.lua)
        if GetIsVehicleEngineRunning(vehicle) then SetVehicleEngineOn(vehicle, false, true, true) end
        if VC.state(vehicle, 'vcEngine') == true then VC.setState(vehicle, 'vcEngine', false) end
    end
    if fuel ~= t.fuel then setFuel(vehicle, fuel, fuel == 0.0) end
end

VC.on('tick', function(_, vehicle, dt)
    if not hasTank(vehicle) then
        VC.hud.fuel = nil
        return
    end
    if VC.seat == -1 then
        local t = track(vehicle)
        consume(vehicle, t, dt, false)
        VC.hud.fuel = t.fuel
    else
        VC.hud.fuel = VC.fuel(vehicle)
    end
end)

-- Descend du véhicule (conducteur) : dernière valeur envoyée ; moteur laissé allumé : ce client
-- continue de compter (ralenti), tant que personne ne prend le volant et qu'il reste à moins de 300 m.
VC.on('leave', function(vehicle, seat, info)
    local t = tracked[vehicle]
    if not t then return end
    if info and info.gone then tracked[vehicle] = nil return end -- supprimé : son essence ne passe à aucun autre
    if seat == -1 and DoesEntityExist(vehicle) then setFuel(vehicle, t.fuel, true) end
    CreateThread(function()
        Wait(1500) -- fin de la descente (le moteur "toujours allumé" est relancé entre-temps)
        while tracked[vehicle] == t and VC.vehicle ~= vehicle and DoesEntityExist(vehicle)
            and GetIsVehicleEngineRunning(vehicle) and GetPedInVehicleSeat(vehicle, -1) == 0
            and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle)) < 300.0 do
            consume(vehicle, t, 1.0, true)
            Wait(1000)
        end
        if tracked[vehicle] == t and VC.vehicle ~= vehicle then
            if DoesEntityExist(vehicle) then setFuel(vehicle, t.fuel, true) end
            tracked[vehicle] = nil
        end
    end)
end)

-- Passager qui prend le volant : il compte à partir de la valeur partagée
VC.on('seat', function(_, vehicle, seat)
    if seat ~= -1 then tracked[vehicle] = nil end
end)

-- Partagé avec client/refuel.lua (plein à la pompe, jerrican)
VC.hasTank = hasTank
VC.sendFuel = sendFuel
VC.initialFuel = initialFuel

--- Plein fait par ce client : la valeur comptée (s'il conduit ce véhicule) suit
function VC.refueled(vehicle, fuel)
    local t = tracked[vehicle]
    if t then t.fuel, t.sent = fuel, fuel end
end

-- Stations-service sur la carte
if Config.Blips then
    for _, pos in ipairs(Config.Stations) do
        local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
        SetBlipSprite(blip, 361)
        SetBlipScale(blip, 0.6)
        SetBlipColour(blip, 1)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Station-service')
        EndTextCommandSetBlipName(blip)
    end
end
