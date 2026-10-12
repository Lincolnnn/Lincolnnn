--[[
    Vehicle Control - pousser un véhicule (client)
    ----------------------------------------------
    À pied, devant le capot ou derrière le coffre d'un véhicule (frein de parcage serré ou non, avec ou
    sans quelqu'un au volant) : un petit message (fond noir légèrement transparent, NUI de ce script)
    propose la touche K (Raccourcis clavier > FiveM > "Véhicule : pousser / arrêter de pousser").
      - K : le personnage se met en position contre le pare-chocs ; il pousse en AVANÇANT (sa touche
        habituelle, Z / W), tout droit uniquement. Devant le capot, le véhicule recule ; derrière le
        coffre, il avance.
      - Quelqu'un au volant : il ne peut plus accélérer ni reculer, seulement tourner le volant ; c'est
        son jeu qui fait avancer le véhicule (état du véhicule "vcPushed" : sens et poussée en cours).
      - Pendant la poussée, une notification rappelle "K : arrêter de pousser" ; K de nouveau : arrêt.
      - Arrêt automatique : personnage tombé, véhicule disparu ou parti trop vite.
    Tant que le message est affiché (ou pendant la poussée), K n'ouvre pas le MDC (état du joueur
    "vcPushPrompt", lu par le MDC).
    Performance : recherche à pied toutes les 500 ms ; à moins de 6 m d'un véhicule poussable,
    vérification toutes les 100 ms ; boucle à chaque image seulement pendant la poussée (et, au volant,
    pendant qu'on est poussé).
]]

local Config = VCConfig.Push
local KEY = VCConfig.Keys.push
local SCAN_RANGE = 6.0

local candidate = nil -- { vehicle, side } : véhicule devant / derrière lequel se trouve le joueur
local pushing = nil   -- { vehicle, side } : poussée en cours
local watching = false
local shown = nil     -- message affiché : nil, 'prompt' ou 'pushing'

local function controlled(vehicle)
    return not NetworkGetEntityIsNetworked(vehicle) or NetworkHasControlOfEntity(vehicle)
end

--- Message à l'écran (NUI de ce script) : 'prompt' (proposer), 'pushing' (rappel pour arrêter), nil
local function show(mode)
    if mode == shown then return end
    shown = mode
    LocalPlayer.state:set('vcPushPrompt', mode ~= nil, false) -- le MDC n'ouvre pas sur K pendant ce temps
    SendNUIMessage({ action = 'push', data = { mode = mode, key = VC.keyLabel('vc_push', KEY) } })
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

local function nearestPushable(pos)
    local best, bestDistance = nil, SCAN_RANGE
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(vehicle) - pos)
        if d <= bestDistance and VC.pushable(vehicle) then best, bestDistance = vehicle, d end
    end
    return best
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function stopPush()
    pushing = nil -- la boucle de poussée se termine et remet le personnage sur ses pieds
end

local function startPush(vehicle, side)
    local ped = PlayerPedId()
    local front = side == 'front'
    local push = { vehicle = vehicle, side = side, info = { dir = front and -1.0 or 1.0, active = false } }
    pushing, candidate = push, nil
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
            if hasAnim and not IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then
                TaskPlayAnim(ped, anim.dict, anim.clip, 2.0, -8.0, -1, 35, 0, false, false, false)
            end
            local forward = IsControlPressed(0, 32) -- avancer (sa touche habituelle) ; pas de direction
            if forward ~= push.info.active then
                push.info.active = forward
                VC.setState(vehicle, 'vcPushed', { dir = push.info.dir, active = forward })
            end
            if forward and GetPedInVehicleSeat(vehicle, -1) == 0 then
                -- Personne au volant : ce client fait avancer le véhicule (même frein de parcage serré)
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

RegisterCommand('vc_push', function()
    if pushing then return stopPush() end
    if IsPauseMenuActive() or not candidate or not VC.pushable(candidate.vehicle) then return end
    startPush(candidate.vehicle, candidate.side)
end, false)
RegisterKeyMapping('vc_push', 'Véhicule : pousser / arrêter de pousser', 'keyboard', KEY)

-- Au volant d'un véhicule poussé par un autre joueur : pas d'accélération (seulement le volant) ;
-- quand il pousse, ce client (propriétaire du véhicule) le fait avancer tout droit
VC.on('frame', function(_, vehicle)
    if VC.seat ~= -1 then return end
    local p = VC.pushInfo(vehicle)
    if not p then return end
    DisableControlAction(0, 71, true) -- accélérer
    DisableControlAction(0, 72, true) -- freiner / reculer
    if p.active then
        SetVehicleHandbrake(vehicle, false)
        SetVehicleForwardSpeed(vehicle, (tonumber(p.dir) or 1.0) * Config.Speed)
    end
end)

--- Près d'un véhicule poussable : message tant que le joueur est devant le capot / derrière le coffre
local function watchLoop()
    watching = true
    CreateThread(function()
        while not pushing do
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then break end
            local vehicle = nearestPushable(GetEntityCoords(ped))
            if not vehicle then break end
            local side = VC.pushSide(ped, vehicle)
            candidate = side and { vehicle = vehicle, side = side } or nil
            show(candidate and 'prompt' or nil)
            Wait(100)
        end
        if not pushing then
            candidate = nil
            show(nil)
        end
        watching = false
    end)
end

VC.on('idle', function(ped)
    if watching or pushing or IsEntityDead(ped) then return end
    if nearestPushable(GetEntityCoords(ped)) then watchLoop() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    LocalPlayer.state:set('vcPushPrompt', false, false)
    if pushing then
        local ped = PlayerPedId()
        DetachEntity(ped, true, false)
        StopAnimTask(ped, Config.Anim.dict, Config.Anim.clip, 2.0)
    end
end)
