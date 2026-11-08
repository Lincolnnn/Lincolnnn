--[[
    Vehicle Control - pneus crevés au couteau (client)
    --------------------------------------------------
    Un joueur qui tient un couteau crève un pneu visé avec l'œil (rp_interact). Le serveur garde la fuite dans l'état du
    véhicule (rpLeaks : { [pneu] = { wheel, at = temps réseau du coup de couteau, dur } }) ; le joueur qui CONTRÔLE le
    véhicule applique la fuite : le pneu se DÉGONFLE LENTEMENT (santé du pneu qui baisse, pneu qui s'affaisse peu à peu),
    puis il est à plat (crevé) au bout de Tyres.LeakDuration secondes. Pendant ce temps, le VOYANT de pression des pneus
    s'allume sur le car HUD du MDC (le conducteur). Réparé (réparation complète, mécanicien…) : la fuite s'arrête.
    Performance : aucune boucle sans fuite ; sinon une vérification toutes les Tyres.Interval ms des véhicules qui fuient.
]]

local T = VCConfig.Tyres or {}
local leaking = {}   -- [netId] = true : véhicules avec une fuite (état rpLeaks)
local applied = {}   -- [netId..':'..pneu] = dernière santé posée par ce joueur
local running = false

-- Pneus : index du pneu (crevaison) et de la roue (santé du pneu)
local TYRE_WHEEL = { [0] = 0, [1] = 1, [2] = 2, [3] = 3, [4] = 2, [5] = 3 }

local function vehicleOf(net)
    if not NetworkDoesNetworkIdExist(net) then return nil end
    local vehicle = NetToVeh(net)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    return vehicle
end

--- Avancement de la fuite (0 -> 1) d'après le temps réseau (le même chez tous les joueurs)
local function progress(leak)
    local dur = (tonumber(leak.dur) or T.LeakDuration or 75) * 1000
    return math.max(0.0, math.min(1.0, (GetNetworkTime() - (tonumber(leak.at) or 0)) / dur))
end

--- Le véhicule a-t-il une fuite en cours (pneu pas encore à plat) ou un pneu crevé ? (voyant du car HUD)
function VC.tyreWarning(vehicle)
    local net = NetworkGetEntityIsNetworked(vehicle) and VehToNet(vehicle) or nil
    local leaks = net and Entity(vehicle).state.rpLeaks or nil
    if type(leaks) == 'table' and next(leaks) then return true end
    if T.LampOnFlat ~= false then
        for _, tyre in ipairs({ 0, 1, 4, 5 }) do
            if IsVehicleTyreBurst(vehicle, tyre, false) then return true end
        end
    end
    return false
end

local function tick()
    for net in pairs(leaking) do
        local vehicle = vehicleOf(net)
        local leaks = vehicle and Entity(vehicle).state.rpLeaks or nil
        if type(leaks) ~= 'table' or not next(leaks) then
            leaking[net] = nil
        elseif NetworkHasControlOfEntity(vehicle) then
            for key, leak in pairs(leaks) do
                local tyre = tonumber(key)
                local wheel = tonumber(leak.wheel) or TYRE_WHEEL[tyre] or 0
                local id = net .. ':' .. key
                local p = progress(leak)
                if applied[id] and GetTyreHealth(vehicle, wheel) > applied[id] + (T.RepairDetect or 80.0) then
                    -- réparé entre-temps (santé du pneu remise à neuf) : la fuite s'arrête
                    applied[id] = nil
                    TriggerServerEvent('rp_vehiclecontrol:leakEnd', net, tyre, 'repaired')
                elseif p >= 1.0 then
                    -- à plat : crevé (pas sur la jante), fuite terminée
                    SetVehicleTyreBurst(vehicle, tyre, false, 1000.0)
                    applied[id] = nil
                    TriggerServerEvent('rp_vehiclecontrol:leakEnd', net, tyre, 'flat')
                else
                    -- se dégonfle lentement : la santé du pneu baisse ; le pneu s'affaisse peu à peu
                    local health = math.max(T.MinHealth or 50.0, 1000.0 * (1.0 - p))
                    SetTyreHealth(vehicle, wheel, health)
                    if T.Sag ~= false and p >= (T.SagFrom or 0.15) then
                        SetVehicleTyreBurst(vehicle, tyre, false, math.min(999.0, 1000.0 * p))
                    end
                    applied[id] = health
                end
            end
        end
    end
    return next(leaking) ~= nil
end

local function start()
    if running then return end
    running = true
    CreateThread(function()
        while tick() do Wait(T.Interval or 500) end
        running = false
    end)
end

-- Fuite ajoutée / retirée (état du véhicule, reçu par tous les joueurs proches)
AddStateBagChangeHandler('rpLeaks', nil, function(bagName, _, value)
    local net = tonumber(bagName:match('^entity:(%d+)$'))
    if not net then return end
    if type(value) == 'table' and next(value) then
        leaking[net] = true
        SetTimeout(0, start)
    else
        leaking[net] = nil
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then leaking = {} end
end)
