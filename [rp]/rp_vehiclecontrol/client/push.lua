--[[
    Vehicle Control - pousser un véhicule (client)
    ----------------------------------------------
    À pied, devant le capot ou derrière le coffre d'un véhicule (avec ou sans quelqu'un au volant) : ŒIL (Alt) sur le
    véhicule > « Pousser le véhicule » (tout en bas de la liste ; option de rp_interact, Config.TargetProviders).
      - Le personnage se met en position contre le pare-chocs ; il pousse en AVANÇANT (sa touche habituelle, Z / W),
        tout droit uniquement. Devant le capot, le véhicule recule ; derrière le coffre, il avance.
      - Quelqu'un au volant : il SUIT la poussée, ses pédales sont coupées (seulement le volant) et le véhicule avance au
        pas chez lui (état du véhicule "vcPushed" : sens et poussée en cours ; une petite pression de pédale est
        simulée pour que le jeu ne freine pas).
      - FREIN DE PARKING de Riven serré : l'option reste proposée et le joueur pousse (position, animation), mais le
        véhicule NE BOUGE PAS (ni sans conducteur, ni au volant) tant que le frein est serré.
      - Pendant la poussée, une notification rappelle « S / X : arrêter de pousser » ; reculer (S) ou X : arrêt.
      - Arrêt automatique : personnage tombé, véhicule disparu ou parti trop vite.
    Performance : aucune boucle hors de la poussée ; à chaque image seulement pendant la poussée (et, au volant,
    pendant qu'on est poussé).
]]

local Config = VCConfig.Push
local pushing = nil   -- { vehicle, side } : poussée en cours
local shown = nil     -- message affiché : nil ou 'pushing'

local function controlled(vehicle)
    return not NetworkGetEntityIsNetworked(vehicle) or NetworkHasControlOfEntity(vehicle)
end

--- Message à l'écran (NUI de ce script) : 'pushing' (rappel pour arrêter), nil
local function show(mode)
    if mode == shown then return end
    shown = mode
    SendNUIMessage({ action = 'push', data = { mode = mode, key = 'S / X' } })
end

function VC.pushable(vehicle)
    return vehicle ~= 0 and DoesEntityExist(vehicle) and Config.Classes[GetVehicleClass(vehicle)] == true
        and GetEntitySpeed(vehicle) < 3.0 and IsVehicleOnAllWheels(vehicle)
end

--- Le joueur est-il devant le capot ('front') ou derrière le coffre ('rear') du véhicule ?
function VC.pushSide(ped, vehicle)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local p = GetOffsetFromEntityGivenWorldCoords(vehicle, GetEntityCoords(ped))
    if math.abs(p.x) > math.max(math.abs(min.x), math.abs(max.x)) + 0.2 then return nil end
    if p.y > max.y - 0.4 and p.y < max.y + Config.Reach then return 'front' end
    if p.y < min.y + 0.4 and p.y > min.y - Config.Reach then return 'rear' end
    return nil
end

--- Poussée en cours sur ce véhicule (par un autre joueur, encore à côté) : { dir, active } ou nil
function VC.pushInfo(vehicle)
    if pushing and pushing.vehicle == vehicle then return pushing.info end
    local p = VC.state(vehicle, 'vcPushed')
    if type(p) ~= 'table' or not p.by then return nil end
    local player = GetPlayerFromServerId(p.by)
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 8.0 then return nil end
    return p
end

--- Frein de parking de Riven serré sur ce véhicule : poussée sans effet
local function parked(vehicle)
    return VC.riven and VC.rivenPark ~= nil and VC.rivenPark(vehicle) == true
end
VC.pushBlocked = parked -- pour les tests

local function loadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function startPush(vehicle, side)
    local ped = PlayerPedId()
    local front = side == 'front'
    local push = { vehicle = vehicle, side = side, info = { dir = front and -1.0 or 1.0, active = false } }
    pushing = push
    show('pushing')
    VC.setState(vehicle, 'vcPushed', { dir = push.info.dir, active = false }) -- le conducteur éventuel le sait
    CreateThread(function()
        local min, max = GetModelDimensions(GetEntityModel(vehicle))
        -- En position : contre le pare-chocs, face au véhicule
        AttachEntityToEntity(ped, vehicle, 0, 0.0, front and (max.y + Config.Gap) or (min.y - Config.Gap),
            min.z + Config.Height, 0.0, 0.0, front and 180.0 or 0.0, false, false, false, true, 2, true)
        local anim = Config.Anim
        local hasAnim = loadDict(anim.dict)
        while pushing == push do
            if not DoesEntityExist(vehicle) or IsEntityDead(ped) or IsPedRagdoll(ped)
                or GetEntitySpeed(vehicle) > 6.0 then
                break
            end
            -- reculer (S) ou X : arrêter de pousser
            if IsControlJustPressed(0, 33) or IsControlJustPressed(0, 73) then break end
            if hasAnim and not IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then
                TaskPlayAnim(ped, anim.dict, anim.clip, 2.0, -8.0, -1, 35, 0, false, false, false)
            end
            -- avancer (sa touche habituelle) ; pas de direction ; frein de parking serré : il pousse, rien ne bouge
            local forward = IsControlPressed(0, 32) and not parked(vehicle)
            if forward ~= push.info.active then
                push.info.active = forward
                VC.setState(vehicle, 'vcPushed', { dir = push.info.dir, active = forward })
            end
            if forward and GetPedInVehicleSeat(vehicle, -1) == 0 then
                -- Personne au volant : ce client fait avancer le véhicule (frein à main du jeu desserré)
                if controlled(vehicle) then
                    SetVehicleHandbrake(vehicle, false)
                    SetVehicleForwardSpeed(vehicle, push.info.dir * Config.Speed)
                else
                    NetworkRequestControlOfEntity(vehicle)
                end
            end
            -- Quelqu'un au volant : c'est son jeu qui fait avancer le véhicule (voir plus bas)
            Wait(0)
        end
        if pushing == push then pushing = nil end
        if DoesEntityExist(vehicle) then VC.setState(vehicle, 'vcPushed', false) end
        if DoesEntityExist(ped) then
            DetachEntity(ped, true, false)
            StopAnimTask(ped, anim.dict, anim.clip, 2.0)
        end
        show(nil)
    end)
end

--- Herse de Riven (riven_spikes) en main ou son cordon tenu : ses touches (E, G, X, Q, molette) ont la priorité
local SPIKE_MODES = { holding = true, cord = true, throwing = true, busy = true }
local function spikesBusy()
    if LocalPlayer.state.rivenSpikeHand ~= nil then return true end
    if GetResourceState('riven_spikes') ~= 'started' then return false end
    local ok, mode = pcall(function() return exports.riven_spikes:getMode() end)
    return ok and SPIKE_MODES[mode] == true
end

-- ŒIL : « Pousser le véhicule », tout en bas de la liste (à pied, devant le capot ou derrière le coffre)
VC.addTarget({
    options = function(info)
        if pushing or type(info) ~= 'table' or info.type ~= 'vehicle' then return nil end
        local ped = PlayerPedId()
        local vehicle = info.entity
        if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) or not VC.pushable(vehicle) or not VC.pushSide(ped, vehicle) then
            return nil
        end
        return { options = { { id = 'push', icon = 'hand', label = 'Pousser le véhicule', last = true } } }
    end,
    select = function(id, info)
        if id ~= 'push' then return false end
        local ped, vehicle = PlayerPedId(), info and info.entity
        if pushing or spikesBusy() or not vehicle or not VC.pushable(vehicle) then return true end
        local side = VC.pushSide(ped, vehicle)
        if side then startPush(vehicle, side) end
        return true
    end,
})

-- Au volant d'un véhicule poussé par un autre joueur : pas d'accélération à soi (seulement le volant) ; quand il
-- pousse, ce client (propriétaire du véhicule) le fait avancer au pas. Un véhicule à l'arrêt avec un joueur au
-- volant et aucune pédale est freiné automatiquement par le jeu : une petite pression de pédale dans le sens de
-- la poussée est donc simulée (le jeu ne freine plus), et la vitesse est tenue à celle de la poussée.
VC.pushedNow = false -- (lu par gear.lua : pas de blocage marche avant / arrière pendant une poussée)
VC.on('frame', function(_, vehicle)
    VC.pushedNow = false
    if VC.seat ~= -1 then return end
    local p = VC.pushInfo(vehicle)
    if not p then return end
    VC.pushedNow = true
    -- ses pédales sont coupées (seulement le volant) ; la pédale simulée passe par les commandes coupées
    DisableControlAction(0, 71, true) -- accélérer
    DisableControlAction(0, 72, true) -- freiner / reculer
    local dir = (tonumber(p.dir) or 1.0) >= 0 and 1.0 or -1.0
    if not p.active or parked(vehicle) then
        SetControlNormal(0, 71, 0.0) -- accélérer
        SetControlNormal(0, 72, 0.0) -- freiner / reculer
        return
    end
    local pedal = Config.Pedal or 0.25
    SetControlNormal(0, 71, dir > 0 and pedal or 0.0)
    SetControlNormal(0, 72, dir < 0 and pedal or 0.0)
    SetVehicleHandbrake(vehicle, false)
    SetVehicleBrakeLights(vehicle, false)
    local forward = GetEntitySpeedVector(vehicle, true).y
    if math.abs(forward - dir * Config.Speed) > 0.15 then SetVehicleForwardSpeed(vehicle, dir * Config.Speed) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if pushing then
        local ped = PlayerPedId()
        DetachEntity(ped, true, false)
        StopAnimTask(ped, Config.Anim.dict, Config.Anim.clip, 2.0)
    end
end)
