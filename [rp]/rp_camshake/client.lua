--[[
    RP CamShake - Client
    --------------------
    À PIED : tremblement continu de la caméra (ROAD_VIBRATION_SHAKE, config.lua) qui grandit avec l'allure : marche < course < sprint,
      réduit en visant ; amplitude ajustée en douceur, arrêté à l'arrêt.
    EN VÉHICULE : aucun tremblement, sauf accident (même petit) : secousse selon la violence du choc.
    CHOCS À PIED : chute (réception après une chute), personnage à terre (ragdoll), percuté par un véhicule,
      coup ou balle reçus (événement de dégâts du jeu).
    Le tremblement d'un autre script (ivresse, drogue…) n'est jamais coupé ni remplacé par la marche.
    TIRS : rp_weaponscontrol (ou tout autre script client) envoie TriggerEvent('rp_camshake:pause', ms) juste avant
      sa propre secousse : pendant ce temps (et tant que sa secousse dure) la marche n'y touche plus (sinon son
      amplitude, 0.3 à 2.4, était appliquée à la secousse du tir, 0.03 environ : premiers tirs très brusques).
    /tremblement : chaque joueur l'active ou le coupe (gardé chez lui).

    Performance : une vérification toutes les 100 ms en mouvement (à pied ou véhicule roulant), toutes les
    250 ms à l'arrêt ; quelques natives par vérification. Dégâts : événement du jeu, sans boucle.
]]

local C = CamShakeConfig
local KVP = 'rp_camshake_off'
local enabled = GetResourceKvpString(KVP) ~= '1'

local ours = false        -- la secousse en cours a été lancée par ce script
local move = nil          -- secousse de déplacement en cours : { shake, amp }
local impactUntil, impactPower = 0, 0
local pausedUntil = 0     -- un autre script secoue la caméra (tir) : la marche n'y touche pas jusque-là

-- =========================================================================
-- SECOUSSES
-- =========================================================================
--- Une secousse d'un autre script est en cours : on n'y touche pas
local function foreignShake() return not ours and IsGameplayCamShaking() end

local function stopMove()
    if move and ours and GetGameTimer() >= impactUntil then StopGameplayCamShaking(false); ours = false end
    move = nil
end

--- Secousse ponctuelle (choc) ; une plus faible ne remplace pas une plus forte en cours
local function impact(name)
    local level = C.Impacts[name]
    if not enabled or not level then return end
    local now = GetGameTimer()
    if now < impactUntil and level.power < impactPower then return end
    ShakeGameplayCam(level.shake, level.amp)
    ours, move = true, nil
    impactUntil, impactPower = now + level.duration, level.power
end

--- Tremblement de déplacement voulu (nil : aucun), amplitude rapprochée en douceur
local function setMove(target)
    if not target then return stopMove() end
    local now = GetGameTimer()
    if now < pausedUntil or now < impactUntil or foreignShake() then return end
    if not move or move.shake ~= target.shake or not IsGameplayCamShaking() then
        local amp = move and move.amp or target.amp * C.Smoothing
        ShakeGameplayCam(target.shake, amp)
        move, ours = { shake = target.shake, amp = amp }, true
        return
    end
    local amp = move.amp + (target.amp - move.amp) * C.Smoothing
    if math.abs(amp - move.amp) > 0.01 then
        move.amp = amp
        SetGameplayCamShakeAmplitude(amp)
    end
end

--- Allure du personnage -> tremblement voulu
local function movementTarget(ped)
    if IsPedSwimming(ped) or IsPedClimbing(ped) or IsPedRagdoll(ped) or IsPedFalling(ped) then return nil end
    local step = IsPedSprinting(ped) and C.Sprint or IsPedRunning(ped) and C.Run or IsPedWalking(ped) and C.Walk or nil
    if not step then return nil end
    if IsPlayerFreeAiming(PlayerId()) then
        if (C.AimFactor or 0) <= 0 then return nil end
        return { shake = step.shake, amp = step.amp * C.AimFactor }
    end
    return step
end

-- =========================================================================
-- BOUCLE : allure à pied, chutes / ragdoll, accidents en véhicule
-- =========================================================================
CreateThread(function()
    local lastVeh, lastSpeed, lastBody, lastEngine = 0, 0.0, 0.0, 0.0
    local fallingSince, wasRagdoll = nil, false
    while true do
        local wait = 250
        local ped = PlayerPedId()
        local now = GetGameTimer()
        -- Notre secousse est finie (choc terminé) : la caméra est libre pour les autres scripts
        if ours and now >= impactUntil and not IsGameplayCamShaking() then ours, move = false, nil end
        if not enabled or IsEntityDead(ped) then
            stopMove()
            fallingSince, wasRagdoll, lastVeh = nil, false, 0
        else
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then
                -- EN VÉHICULE : rien, sauf accident
                stopMove()
                fallingSince, wasRagdoll = nil, false
                local speed = GetEntitySpeed(veh)
                local body, engine = GetVehicleBodyHealth(veh), math.max(GetVehicleEngineHealth(veh), 0.0)
                if veh ~= lastVeh then lastVeh, lastSpeed, lastBody, lastEngine = veh, speed, body, engine end
                -- Carrosserie : la moindre perte = choc ; moteur : seulement une vraie perte (un moteur très
                -- abîmé perd un peu de vie tout seul)
                local drop = lastSpeed - speed
                local bodyLost, engineLost = lastBody - body, lastEngine - engine
                local lost = math.max(bodyLost, 0.0) + math.max(engineLost, 0.0)
                if bodyLost > 0.5 or engineLost > 5.0 or drop >= C.Crash.HardDrop then
                    if drop >= C.Crash.Heavy then impact('carHeavy')
                    elseif drop >= C.Crash.Medium or lost >= C.Crash.BigDamage then impact('carMedium')
                    else impact('carLight') end
                end
                lastSpeed, lastBody, lastEngine = speed, body, engine
                if speed > 0.5 then wait = 100 end
            else
                -- À PIED : chute, à terre, allure
                lastVeh = 0
                local ragdoll = IsPedRagdoll(ped)
                if ragdoll and not wasRagdoll then impact('ragdoll') end
                wasRagdoll = ragdoll
                if IsPedFalling(ped) then
                    fallingSince = fallingSince or now
                elseif fallingSince then
                    if now - fallingSince >= C.FallTime then impact('fall') end
                    fallingSince = nil
                end
                local target = movementTarget(ped)
                setMove(target)
                if target or fallingSince or ragdoll then wait = 100 end
            end
        end
        Wait(wait)
    end
end)

-- =========================================================================
-- DÉGÂTS REÇUS À PIED (événement du jeu, sans boucle) : percuté, coup, balle
-- =========================================================================
local RUN_OVER = { [GetHashKey('WEAPON_RUN_OVER_BY_CAR')] = true, [GetHashKey('WEAPON_RAMMED_BY_CAR')] = true }
local FALL = GetHashKey('WEAPON_FALL')

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or type(args) ~= 'table' then return end
    local ped = PlayerPedId()
    if args[1] ~= ped or GetVehiclePedIsIn(ped, false) ~= 0 then return end -- en véhicule : accidents gérés plus haut
    local attacker, weapon = args[2], args[7]
    if RUN_OVER[weapon] or (attacker and attacker ~= 0 and DoesEntityExist(attacker) and GetEntityType(attacker) == 2) then
        impact('hit')
    elseif weapon == FALL then
        impact('fall')
    else
        impact('damage')
    end
end)

-- =========================================================================
-- PAUSE demandée par un autre script client (secousse de tir de rp_weaponscontrol) : sa secousse remplace la
-- nôtre ; on la laisse telle quelle (ni amplitude changée, ni arrêt) et la marche reprend une fois finie
-- =========================================================================
AddEventHandler('rp_camshake:pause', function(ms)
    ms = math.max(0, math.min(tonumber(ms) or 800, 10000))
    pausedUntil = math.max(pausedUntil, GetGameTimer() + ms)
    ours, move = false, nil
    impactUntil, impactPower = 0, 0
end)

-- =========================================================================
-- /tremblement : activer / couper (gardé chez le joueur)
-- =========================================================================
if C.Command then
    RegisterCommand(C.Command, function()
        enabled = not enabled
        SetResourceKvp(KVP, enabled and '0' or '1')
        if not enabled and ours then StopGameplayCamShaking(true); ours, move = false, nil end
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(enabled and 'Tremblement de la caméra : ~g~activé' or 'Tremblement de la caméra : ~r~coupé')
        EndTextCommandThefeedPostTicker(false, false)
    end, false)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and ours then StopGameplayCamShaking(true) end
end)
