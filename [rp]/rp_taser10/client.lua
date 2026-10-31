local armed = false
local stealth = false
local stealthReady = false
local functionTestState = 'inactive'
local cartridges = Config.Cartridges
local battery = 100.0
local deployed = 0
local dischargeLogged = false
local connection = { state = 'DISCONNECTED', probes = {} }
local persistentProngs = {}
local activeConnections = {}
local remoteArmedPlayers = {}
local remoteFlashlights = {}
local victimProngCounts = {}
local canRemoveProngs = false
local lastShot = 0
local lastReactivation = -Config.Prongs.ReactivationCooldown
local reactivationSafeAt
local safeAt
local warningUntil = 0
local selectorDownAt
local downPresses = 0
local lastDownPress = 0
local stunEnds = 0
local ragdollEnds = 0

print('AXON TASER 10 v1.0.0PRE')

local function debugLog(message, ...)
    if not Config.DebugMode then return end
    print(('[axon_taser10] ' .. message):format(...))
end

local function playTaserSound(sound)
    SendNUIMessage({ action = 'sound', sound = sound, volume = Config.SoundVolume })
    TriggerServerEvent('axon_taser10:sound', sound)
end

local function usingTaser(ped)
    local weapon = GetSelectedPedWeapon(ped or PlayerPedId())

    for _, taser in ipairs(Config.Weapons) do
        if weapon == taser then return true end
    end

    return false
end

local function hasConnection()
    return connection.state == 'CONNECTED'
end

local function updateCid()
    local equipped = usingTaser()

    SendNUIMessage({
        action = 'update',
        visible = equipped,
        armed = armed,
        cartridges = cartridges,
        battery = battery,
        shotsSpent = deployed,
        batteryDisplay = Config.BatteryDisplay,
        functionTestState = functionTestState,
        connected = hasConnection(),
        stealth = stealth,
        syncing = false
    })
end

local function playerFromPed(ped)
    if not IsPedAPlayer(ped) then return nil end

    local player = NetworkGetPlayerIndexFromPed(ped)
    if player == -1 then return nil end
    return GetPlayerServerId(player)
end

local function getCameraAimPosition(start, range)
    local ped = PlayerPedId()
    local camera = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local pitch = math.rad(rotation.x)
    local yaw = math.rad(rotation.z)
    local forward = vector3(
        -math.sin(yaw) * math.abs(math.cos(pitch)),
        math.cos(yaw) * math.abs(math.cos(pitch)),
        math.sin(pitch)
    )

    local finish = camera + forward * (range + #(camera - start))
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        camera.x, camera.y, camera.z,
        finish.x, finish.y, finish.z,
        511, ped, 7
    )
    local _, cameraHit, aimPosition = GetShapeTestResult(ray)

    if cameraHit ~= 1 then
        aimPosition = finish
    end

    return aimPosition
end

local function taserRaycast()
    local ped = PlayerPedId()
    local start = GetPedBoneCoords(ped, 57005, 0.0, 0.0, 0.0)
    local aimPosition = getCameraAimPosition(start, Config.MaxRange)
    local direction = aimPosition - start

    if #direction < 0.001 then
        return false, 0, start, start
    end

    local finish = start + direction / #direction * Config.MaxRange
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        start.x, start.y, start.z,
        finish.x, finish.y, finish.z,
        511, ped, 7
    )
    local _, hit, hitPosition, _, entity = GetShapeTestResult(ray)

    if hit ~= 1 then
        hitPosition = finish
    end

    return hit == 1, entity, hitPosition, start
end

local function vecLength(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function normalizeVector(v)
    local length = vecLength(v)
    if length < 0.001 then return nil end

    return vector3(
        v.x / length,
        v.y / length,
        v.z / length
    )
end

local function dotVector(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function crossVector(a, b)
    return vector3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
end

local function scaleVector(v, amount)
    return vector3(
        v.x * amount,
        v.y * amount,
        v.z * amount
    )
end

local function addVectors(a, b)
    return vector3(
        a.x + b.x,
        a.y + b.y,
        a.z + b.z
    )
end

local function subtractVectors(a, b)
    return vector3(
        a.x - b.x,
        a.y - b.y,
        a.z - b.z
    )
end

--- Bout du canon et axes (avant, droite, haut) d'un objet d'arme : arme en main, ou Taser posé au sol (pas d'os
--- du canon sur ce modèle : son centre et ses axes)
local function entityBasis(weaponEntity, fallback)
    if weaponEntity == 0 or not DoesEntityExist(weaponEntity) then
        return nil, nil, nil, nil
    end

    local muzzleBone = GetEntityBoneIndexByName(weaponEntity, Config.Laser.MuzzleBone)
    if muzzleBone == -1 then
        if not fallback then return nil, nil, nil, nil end
        local f, r, u, origin = GetEntityMatrix(weaponEntity)
        return origin, f, r, u
    end

    local muzzle = GetWorldPositionOfEntityBone(weaponEntity, muzzleBone)
    local origin = GetEntityCoords(weaponEntity)
    local towardMuzzle = normalizeVector(subtractVectors(muzzle, origin))

    if not towardMuzzle then
        return nil, nil, nil, nil
    end

    local entityForward, entityRight, entityUp = GetEntityMatrix(weaponEntity)
    local candidates = {
        entityForward,
        scaleVector(entityForward, -1.0),
        entityRight,
        scaleVector(entityRight, -1.0),
        entityUp,
        scaleVector(entityUp, -1.0)
    }

    local barrelDirection
    local bestAlignment = -2.0

    for _, candidate in ipairs(candidates) do
        local normalized = normalizeVector(candidate)
        if normalized then
            local alignment = dotVector(normalized, towardMuzzle)
            if alignment > bestAlignment then
                bestAlignment = alignment
                barrelDirection = normalized
            end
        end
    end

    if not barrelDirection then
        return nil, nil, nil, nil
    end

    local referenceUp = normalizeVector(entityUp) or vector3(0.0, 0.0, 1.0)
    if math.abs(dotVector(barrelDirection, referenceUp)) > 0.95 then
        referenceUp = normalizeVector(entityForward) or vector3(0.0, 1.0, 0.0)
    end

    local barrelRight = normalizeVector(crossVector(barrelDirection, referenceUp))
    if not barrelRight then
        barrelRight = vector3(1.0, 0.0, 0.0)
    end

    local barrelUp = normalizeVector(crossVector(barrelRight, barrelDirection))
    if not barrelUp then
        barrelUp = vector3(0.0, 0.0, 1.0)
    end

    return muzzle, barrelDirection, barrelRight, barrelUp
end

local function getWeaponLightBasis(ped)
    ped = ped or PlayerPedId()
    return entityBasis(GetCurrentPedWeaponEntityIndex(ped), false)
end

-- =========================================================================
-- TASER POSÉ AU SOL (œil de rp_interact) : les sondes restent dans le suspect, le fil part du Taser posé ; repris,
-- il marche comme avant (réactivation des sondes déjà tirées). État du joueur "taserDropped" (réseau de l'objet).
-- =========================================================================
local dropping = false -- posé, en attente du serveur
-- Réseau de son propre Taser posé : gardé ici dès la réponse du serveur (l'état du joueur "taserDropped" peut arriver
-- quelques images APRÈS la réponse : entre les deux, le Taser n'était ni en main ni « posé » -> sondes coupées)
local droppedNet = nil
local rearmAfterPickup = false -- repris du sol, sondes reliées : le prochain passage en ARMÉ relance la décharge
local pickupGrace = 0 -- repris : le Taser met une image ou deux à revenir en main (sans couper les sondes entre-temps)
local myServerId = GetPlayerServerId(PlayerId())
local function droppedObject(serverId)
    local netId
    if not serverId or serverId == myServerId then netId = droppedNet or LocalPlayer.state.taserDropped
    else netId = Player(serverId).state.taserDropped end
    if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
    local obj = NetworkGetEntityFromNetworkId(netId)
    if obj == 0 or not DoesEntityExist(obj) then return nil end
    return obj
end

local function taserOnGround()
    return dropping or droppedNet ~= nil or LocalPlayer.state.taserDropped ~= nil or GetGameTimer() < pickupGrace
end

--- Origine du fil d'un tireur : son Taser posé au sol, sinon l'arme dans sa main
local function shooterBasis(serverId)
    local obj = droppedObject(serverId)
    if obj then return entityBasis(obj, true) end
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then return nil, nil, nil, nil end
    return getWeaponLightBasis(GetPlayerPed(player))
end

local function correctedWeaponDirection(baseDirection, right, up, rightCorrection, upCorrection)
    rightCorrection = tonumber(rightCorrection) or 0.0
    upCorrection = tonumber(upCorrection) or 0.0

    local direction = addVectors(
        baseDirection,
        addVectors(
            scaleVector(right, rightCorrection),
            scaleVector(up, upCorrection)
        )
    )

    return normalizeVector(direction) or baseDirection
end

local function getLaserDotPosition(ped)
    ped = ped or PlayerPedId()
    local muzzle, baseDirection, right, up = getWeaponLightBasis(ped)

    if not muzzle or not baseDirection then
        return nil, nil, nil, nil, nil
    end

    local start = muzzle
    start = addVectors(start, scaleVector(right, tonumber(Config.Laser.StartRightOffset) or 0.0))
    start = addVectors(start, scaleVector(up, tonumber(Config.Laser.StartUpOffset) or 0.0))
    start = addVectors(start, scaleVector(baseDirection, tonumber(Config.Laser.StartForwardOffset) or 0.0))

    local range = tonumber(Config.Laser.Range) or 12.192
    local finish = addVectors(start, scaleVector(baseDirection, range))
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        start.x, start.y, start.z,
        finish.x, finish.y, finish.z,
        511, ped, 7
    )
    local _, hit, hitPosition = GetShapeTestResult(ray)

    if hit ~= 1 then
        hitPosition = finish
    end

    local flashlightDirection = correctedWeaponDirection(
        baseDirection,
        right,
        up,
        Config.Flashlight.DirectionRight,
        Config.Flashlight.DirectionUp
    )

    return hitPosition, start, flashlightDirection, right, up
end

local function drawLaserDot(position)
    local alpha = math.floor(255 * (1.0 - math.max(0.0, math.min(1.0, Config.Laser.Transparency))))
    local size = math.max(0.001, tonumber(Config.Laser.DotSize) or 0.035)

    DrawMarker(
        28,
        position.x, position.y, position.z,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        size, size, size,
        Config.Laser.Color.r,
        Config.Laser.Color.g,
        Config.Laser.Color.b,
        alpha,
        false,
        false,
        2,
        nil,
        nil,
        false
    )
end

local function drawFlashlight(start, direction, right, up, strobeUntil, lowBattery)
    local now = GetGameTimer()
    local strobeInterval = math.max(1, Config.Flashlight.StrobeInterval)
    local strobeOnTime = math.max(0, math.min(strobeInterval, Config.Flashlight.StrobeOnTime))
    local strobing = now < strobeUntil and now % strobeInterval < strobeOnTime
    local brightness = lowBattery and Config.Flashlight.LowBatteryBrightness or Config.Flashlight.Brightness

    if strobing then
        brightness = Config.Flashlight.StrobeBrightness
    elseif now < strobeUntil then
        return
    end

    local flashlightStart = start
        + right * (tonumber(Config.Flashlight.StartRightOffset) or 0.0)
        + up * (tonumber(Config.Flashlight.StartUpOffset) or 0.0)
        + direction * (tonumber(Config.Flashlight.StartForwardOffset) or 0.0)

    DrawSpotLight(
        flashlightStart.x, flashlightStart.y, flashlightStart.z,
        direction.x, direction.y, direction.z,
        Config.Flashlight.Color.r,
        Config.Flashlight.Color.g,
        Config.Flashlight.Color.b,
        Config.Flashlight.Distance,
        brightness,
        Config.Flashlight.Hardness,
        Config.Flashlight.Radius,
        Config.Flashlight.Falloff
    )
end

local function closestProngBone(ped, hitPosition)
    local closest = Config.Prongs.BoneIds[1]
    local closestDistance

    for _, boneId in ipairs(Config.Prongs.BoneIds) do
        local bonePosition = GetPedBoneCoords(ped, boneId, 0.0, 0.0, 0.0)
        local boneDistance = #(bonePosition - hitPosition)
        if not closestDistance or boneDistance < closestDistance then
            closest = boneId
            closestDistance = boneDistance
        end
    end

    return closest
end

local function victimKey(victimType, victimId)
    return ('%s:%s'):format(victimType, victimId)
end

local function victimPed(victimType, victimId)
    if victimType == 'player' then
        local player = GetPlayerFromServerId(victimId)
        if player == -1 then return 0 end
        return GetPlayerPed(player)
    end

    if victimType == 'npc' and NetworkDoesEntityExistWithNetworkId(victimId) then
        local ped = NetworkGetEntityFromNetworkId(victimId)
        if ped ~= 0 and DoesEntityExist(ped) and IsEntityAPed(ped) and not IsPedAPlayer(ped) then
            return ped
        end
    end

    return 0
end

local function prongVictimPed(data)
    if data.victimNetworkId and data.victimNetworkId > 0 then
        if NetworkDoesEntityExistWithNetworkId(data.victimNetworkId) then
            local ped = NetworkGetEntityFromNetworkId(data.victimNetworkId)
            if ped ~= 0 and DoesEntityExist(ped) and IsEntityAPed(ped) then
                return ped
            end
        end

        return 0
    end

    return victimPed(data.victimType, data.victimId)
end

local function victimDetails(ped, makeNetworked)
    if ped == 0 or not DoesEntityExist(ped) or not IsEntityAPed(ped) then return end

    local player = playerFromPed(ped)
    if player then
        return 'player', player
    end

    if makeNetworked and not NetworkGetEntityIsNetworked(ped) then
        NetworkRequestControlOfEntity(ped)
        NetworkRegisterEntityAsNetworked(ped)

        local timeout = GetGameTimer() + 500
        while not NetworkGetEntityIsNetworked(ped) and GetGameTimer() < timeout do
            Wait(0)
        end
    end

    if not NetworkGetEntityIsNetworked(ped) then return end

    local networkId = NetworkGetNetworkIdFromEntity(ped)
    if networkId and networkId > 0 then
        return 'npc', networkId
    end
end

local function trackedProngCount(ped)
    local targetType, targetId = victimDetails(ped)
    if not targetType then return 0 end
    return victimProngCounts[victimKey(targetType, targetId)] or 0
end

local function cleanupProng(prong)
    if not prong then return end

    local prongEntity = prong.entity
    local targetPed = prongVictimPed(prong.data)
    debugLog(
        'prong cleanup id=%s entity=%s victimNetId=%s',
        prong.data.id,
        prongEntity or 0,
        prong.data.victimNetworkId or 0
    )

    if not prongEntity or prongEntity == 0 or not DoesEntityExist(prongEntity) then
        prong.entity = 0
        return
    end
    if prongEntity == targetPed or not IsEntityAnObject(prongEntity) then
        debugLog('ERROR blocked invalid prong cleanup id=%s entity=%s victimPed=%s', prong.data.id, prongEntity, targetPed)
        prong.entity = 0
        return
    end
    if GetEntityModel(prongEntity) ~= GetHashKey(prong.data.model) then
        debugLog('ERROR blocked prong cleanup id=%s because model changed', prong.data.id)
        prong.entity = 0
        return
    end

    DetachEntity(prongEntity, true, true)
    SetEntityAsMissionEntity(prongEntity, true, true)
    DeleteObject(prongEntity)
    prong.entity = 0
end

local function removePersistentProng(prongId)
    local prong = persistentProngs[prongId]
    if not prong then return end

    cleanupProng(prong)
    local key = victimKey(prong.data.victimType, prong.data.victimId)
    victimProngCounts[key] = math.max(0, (victimProngCounts[key] or 1) - 1)
    if victimProngCounts[key] == 0 then
        victimProngCounts[key] = nil
    end
    persistentProngs[prongId] = nil
end

local function spawnPersistentProng(prong)
    if prong.loading or (prong.entity and DoesEntityExist(prong.entity)) then return end

    local targetPed = prongVictimPed(prong.data)
    if targetPed == 0 then return end
    prong.loading = true

    CreateThread(function()
        local model = GetHashKey(prong.data.model)
        RequestModel(model)

        local timeout = GetGameTimer() + Config.Prongs.ModelLoadTimeout
        while not HasModelLoaded(model) and GetGameTimer() < timeout do
            Wait(0)
        end

        local current = persistentProngs[prong.data.id]
        targetPed = prongVictimPed(prong.data)
        if current ~= prong or not HasModelLoaded(model) or targetPed == 0 then
            prong.loading = false
            if HasModelLoaded(model) then SetModelAsNoLongerNeeded(model) end
            return
        end

        local boneIndex = GetPedBoneIndex(targetPed, prong.data.bone)
        local position = GetPedBoneCoords(targetPed, prong.data.bone, 0.0, 0.0, 0.0)
        local prongEntity = CreateObjectNoOffset(model, position.x, position.y, position.z, false, false, false)

        if prongEntity ~= 0 and prongEntity ~= targetPed and IsEntityAnObject(prongEntity) then
            local offset = prong.data.offset
            local rotation = prong.data.rotation
            SetEntityAsMissionEntity(prongEntity, true, true)
            SetEntityCollision(prongEntity, false, false)
            SetEntityInvincible(prongEntity, true)
            AttachEntityToEntity(
                prongEntity,
                targetPed,
                boneIndex,
                offset.x, offset.y, offset.z,
                rotation.x, rotation.y, rotation.z,
                false, false, false, true, 2, true
            )
            prong.entity = prongEntity
            debugLog(
                'persistent prong attached id=%s entity=%s victimNetId=%s bone=%s',
                prong.data.id,
                prongEntity,
                prong.data.victimNetworkId or 0,
                prong.data.bone
            )
        end

        prong.loading = false
        SetModelAsNoLongerNeeded(model)
    end)
end

local function addPersistentProng(data)
    if persistentProngs[data.id] then return end

    persistentProngs[data.id] = { data = data, entity = 0, loading = false }
    local key = victimKey(data.victimType, data.victimId)
    victimProngCounts[key] = (victimProngCounts[key] or 0) + 1
    debugLog(
        'persistent prong received id=%s victimNetId=%s bone=%s count=%s',
        data.id,
        data.victimNetworkId or 0,
        data.bone,
        victimProngCounts[key]
    )
    spawnPersistentProng(persistentProngs[data.id])
end

local function createActiveConnection(data)
    data.smooth = {}
    data.lastDistanceLog = 0
    activeConnections[data.id] = data
    debugLog(
        'cord created connectionId=%s shooter=%s victimNetId=%s prongs=%s,%s',
        data.id,
        data.shooter,
        data.targetType == 'npc' and data.targetId or 0,
        data.prongIds[1] or 0,
        data.prongIds[2] or 0
    )
end

local function removeActiveConnection(connectionId, reason)
    local active = activeConnections[connectionId]
    if not active then return end

    activeConnections[connectionId] = nil
    debugLog(
        'cord destroyed connectionId=%s reason=%s persistentProngsPreserved=true',
        connectionId,
        reason or 'removed'
    )
end

local function clearOwnedConnection(reason, notifyServer)
    local connectionId = connection.connectionId
    if connectionId then
        removeActiveConnection(connectionId, reason)
    end

    connection = { state = reason and 'BROKEN' or 'DISCONNECTED', probes = {} }
    reactivationSafeAt = nil
    if notifyServer then
        TriggerServerEvent('axon_taser10:breakConnection', reason, connectionId)
    end
    updateCid()
end

local function smoothVector(current, target)
    if not current then return target end

    local damping = math.max(0.01, math.min(1.0, tonumber(Config.Wire.Damping) or 0.22))
    return vector3(
        current.x + (target.x - current.x) * damping,
        current.y + (target.y - current.y) * damping,
        current.z + (target.z - current.z) * damping
    )
end

local function wirePoint(start, finish, amount, wireDistance, curlSide, curlUp)
    local stiffness = math.max(0.1, tonumber(Config.Wire.Stiffness) or 1.0)
    local sag = ((tonumber(Config.Wire.Sag) or 0.035) + wireDistance * (tonumber(Config.Wire.Gravity) or 0.018)) / stiffness
    local drop = 4.0 * amount * (1.0 - amount) * sag
    local curlSize = math.max(0.0, tonumber(Config.Wire.CurlSize) or 0.0)
    local curlCount = math.max(0.0, tonumber(Config.Wire.CurlCount) or 0.0)
    local curlFade = math.sin(math.pi * amount)
    local curlAngle = amount * curlCount * math.pi * 2.0
    local sideCurl = math.sin(curlAngle) * curlSize * curlFade
    local upCurl = math.cos(curlAngle) * curlSize * curlFade

    return vector3(
        start.x + (finish.x - start.x) * amount + curlSide.x * sideCurl + curlUp.x * upCurl,
        start.y + (finish.y - start.y) * amount + curlSide.y * sideCurl + curlUp.y * upCurl,
        start.z + (finish.z - start.z) * amount - drop + curlSide.z * sideCurl + curlUp.z * upCurl
    )
end

local function drawWire(start, finish)
    local wireDistance = #(finish - start)
    local segments = math.max(2, math.floor(Config.Wire.Segments))
    local thickness = math.max(0.001, Config.Wire.Thickness)
    local color = Config.Wire.Color
    local alpha = color.a or 255
    local camera = GetGameplayCamCoord()
    local wireDirection = normalizeVector(subtractVectors(finish, start))
    local curlSide = wireDirection and normalizeVector(crossVector(wireDirection, vector3(0.0, 0.0, 1.0)))
    if not curlSide then
        curlSide = vector3(1.0, 0.0, 0.0)
    end
    local curlUp = wireDirection and normalizeVector(crossVector(curlSide, wireDirection)) or vector3(0.0, 0.0, 1.0)
    local previous = start

    for segment = 1, segments do
        local current = wirePoint(start, finish, segment / segments, wireDistance, curlSide, curlUp)
        local middle = scaleVector(addVectors(previous, current), 0.5)
        local direction = subtractVectors(current, previous)
        local towardCamera = subtractVectors(camera, middle)
        local side = normalizeVector(crossVector(direction, towardCamera))

        if side then
            side = scaleVector(side, thickness * 0.5)
            local firstLeft = subtractVectors(previous, side)
            local firstRight = addVectors(previous, side)
            local secondLeft = subtractVectors(current, side)
            local secondRight = addVectors(current, side)

            DrawPoly(
                firstLeft.x, firstLeft.y, firstLeft.z,
                firstRight.x, firstRight.y, firstRight.z,
                secondRight.x, secondRight.y, secondRight.z,
                color.r, color.g, color.b, alpha
            )
            DrawPoly(
                firstLeft.x, firstLeft.y, firstLeft.z,
                secondRight.x, secondRight.y, secondRight.z,
                secondLeft.x, secondLeft.y, secondLeft.z,
                color.r, color.g, color.b, alpha
            )
        end

        DrawLine(previous.x, previous.y, previous.z, current.x, current.y, current.z, color.r, color.g, color.b, alpha)

        previous = current
    end
end

local function connectionWireDistance(active)
    local muzzle, forward, right, up = shooterBasis(active.shooter)
    if not muzzle then return nil end

    local wireStart = addVectors(muzzle, scaleVector(forward, Config.Wire.WeaponForwardOffset))
    wireStart = addVectors(wireStart, scaleVector(right, Config.Wire.WeaponRightOffset))
    wireStart = addVectors(wireStart, scaleVector(up, Config.Wire.WeaponUpOffset))

    local longest = 0.0
    for probe, prongId in ipairs(active.prongIds or {}) do
        local prong = persistentProngs[prongId]
        if not prong or not prong.entity or not DoesEntityExist(prong.entity) then return nil end
        local start = addVectors(wireStart, scaleVector(right, (probe - 1) * Config.Wire.ProbeSpacing))
        longest = math.max(longest, #(GetEntityCoords(prong.entity) - start))
    end

    return longest
end

CreateThread(function()
    while true do
        local drawing = false
        local now = GetGameTimer()

        for _, prong in pairs(persistentProngs) do
            if prong.entity ~= 0 then
                local targetPed = prongVictimPed(prong.data)
                if not DoesEntityExist(prong.entity)
                    or targetPed == 0
                    or not IsEntityAttachedToEntity(prong.entity, targetPed)
                then
                    cleanupProng(prong)
                end
            end
            if prong.entity == 0 then
                spawnPersistentProng(prong)
            end
        end

        for _, active in pairs(activeConnections) do
            local muzzle, forward, right, up = shooterBasis(active.shooter)
            if muzzle then
                local currentDistance = connectionWireDistance(active)

                if muzzle and currentDistance and currentDistance < active.maxDistance then
                    local wireStart = addVectors(muzzle, scaleVector(forward, Config.Wire.WeaponForwardOffset))
                    wireStart = addVectors(wireStart, scaleVector(right, Config.Wire.WeaponRightOffset))
                    wireStart = addVectors(wireStart, scaleVector(up, Config.Wire.WeaponUpOffset))

                    for probe, prongId in ipairs(active.prongIds or {}) do
                        local prong = persistentProngs[prongId]
                        if prong and prong.entity and DoesEntityExist(prong.entity) then
                            local rawStart = addVectors(wireStart, scaleVector(right, (probe - 1) * Config.Wire.ProbeSpacing))
                            local rawFinish = GetEntityCoords(prong.entity)
                            active.smooth[probe] = active.smooth[probe] or {}
                            active.smooth[probe].start = smoothVector(active.smooth[probe].start, rawStart)
                            active.smooth[probe].finish = smoothVector(active.smooth[probe].finish, rawFinish)

                            if #(active.smooth[probe].finish - active.smooth[probe].start) >= active.maxDistance then
                                active.smooth[probe].start = rawStart
                                active.smooth[probe].finish = rawFinish
                            end

                            drawWire(active.smooth[probe].start, active.smooth[probe].finish)
                            drawing = true
                        end
                    end

                    if Config.DebugMode and now - active.lastDistanceLog >= 1000 then
                        active.lastDistanceLog = now
                        debugLog(
                            'connection distance id=%s distance=%.3f maximum=%.3f',
                            active.id,
                            currentDistance or -1.0,
                            active.maxDistance
                        )
                    end
                end
            end
        end

        Wait(drawing and math.max(0, Config.Wire.UpdateRate) or 250)
    end
end)

local function fireTaser()
    if GetGameTimer() - lastShot < 350 then return end
    lastShot = GetGameTimer()

    if stealth then
        stealth = false
    end

    if connection.state == 'CONNECTED' then
        clearOwnedConnection('new_deployment', true)
    end

    local hit, hitEntity, hitPosition = taserRaycast()
    playTaserSound('fire')
    cartridges = cartridges - 1
    deployed = deployed + 1
    if deployed >= Config.BatteryDisplay.DepletedThresholdShotsSpent then
        battery = 0.0
        if not dischargeLogged then
            dischargeLogged = true
            TriggerServerEvent('axon_taser10:discharge')
        end
    end

    if hit and DoesEntityExist(hitEntity) and IsEntityAPed(hitEntity) then
        local targetType, targetId = victimDetails(hitEntity, true)
        if targetType then
            TriggerServerEvent('axon_taser10:shot', targetType, targetId, closestProngBone(hitEntity, hitPosition))
        else
            debugLog('shot rejected because victim ped=%s has no network identity', hitEntity)
        end
    end

    updateCid()
end

local function attachedProngs()
    if not connection.connectionId then return false end

    local active = activeConnections[connection.connectionId]
    if not active or #active.prongIds < 2 then return false end

    local targetPed = victimPed(active.targetType, active.targetId)
    if targetPed == 0 then return false end

    for probe = 1, 2 do
        local prong = persistentProngs[active.prongIds[probe]]
        if not prong or not prong.entity or not DoesEntityExist(prong.entity) then return false end
        if not IsEntityAttachedToEntity(prong.entity, targetPed) then return false end
    end

    return true
end

local function reactivateConnection()
    if not usingTaser() or not armed or battery <= 0 then return end
    if connection.state ~= 'CONNECTED' or not attachedProngs() then return end

    local active = activeConnections[connection.connectionId]
    local wireDistance = active and connectionWireDistance(active)
    if not wireDistance or wireDistance >= Config.Prongs.MaxWireDistance then
        clearOwnedConnection('distance', true)
        return
    end

    local now = GetGameTimer()
    if now - lastReactivation < Config.Prongs.ReactivationCooldown then return end
    lastReactivation = now
    TriggerServerEvent('axon_taser10:reactivate')
end

local function setSafe()
    reactivationSafeAt = nil
    playTaserSound('switch')
    armed = false
    stealth = false
    safeAt = GetGameTimer()
    if functionTestState == 'running' then
        functionTestState = 'passed'
    end
    TriggerServerEvent('axon_taser10:safe')
    updateCid()
end

RegisterCommand('+axonSafety', function()
    if not usingTaser() then return end

    if armed then
        local canReactivate = connection.state == 'CONNECTED' and attachedProngs()
        setSafe()
        if canReactivate then
            reactivationSafeAt = GetGameTimer()
        end
    else
        if functionTestState == 'passed' then
            reactivationSafeAt = nil
            functionTestState = 'inactive'
            updateCid()
            return
        end
        local reactivate = (reactivationSafeAt
            and GetGameTimer() - reactivationSafeAt <= Config.Prongs.SelectorReactivationWindow) or rearmAfterPickup
        reactivationSafeAt = nil
        rearmAfterPickup = false
        playTaserSound('switch')
        armed = true
        stealth = stealthReady
        stealthReady = false
        safeAt = nil
        playTaserSound('arming')
        TriggerServerEvent('axon_taser10:armed', not stealth)
        updateCid()
        if reactivate then
            reactivateConnection()
        end
    end
end, false)
RegisterCommand('-axonSafety', function() end, false)
RegisterKeyMapping('+axonSafety', 'TASER 10 : sélecteur ARMÉ / SÉCURITÉ', 'keyboard', Config.Keys.safety)

RegisterCommand('+axonSelectorUp', function()
    if not usingTaser() or not armed or battery <= 0 then return end

    playTaserSound('switch')
    playTaserSound('warning')
    warningUntil = GetGameTimer() + Config.Flashlight.StrobeDuration
end, false)
RegisterCommand('-axonSelectorUp', function() end, false)
RegisterKeyMapping('+axonSelectorUp', 'TASER 10 : alerte sonore et lampe stroboscopique', 'keyboard', Config.Keys.selectorUp)

RegisterCommand('+axonSelectorDown', function()
    if not usingTaser() or armed then return end

    if functionTestState == 'passed' then
        functionTestState = 'inactive'
        updateCid()
        return
    end

    playTaserSound('switch')
    selectorDownAt = GetGameTimer()
end, false)

RegisterCommand('-axonSelectorDown', function()
    if not selectorDownAt then return end

    local now = GetGameTimer()
    local held = now - selectorDownAt
    selectorDownAt = nil

    if held >= 3000 then
        if functionTestState == 'inactive' then
            functionTestState = 'running'
        else
            functionTestState = 'inactive'
        end
        downPresses = 0
        updateCid()
        return
    end

    if now - lastDownPress > 1200 then
        downPresses = 0
    end

    lastDownPress = now
    downPresses = downPresses + 1

    if downPresses == 3 then
        stealthReady = true
        downPresses = 0
    end
end, false)
RegisterKeyMapping('+axonSelectorDown', 'TASER 10 : sélecteur vers le bas (discret, test)', 'keyboard', Config.Keys.selectorDown)

local function removalTarget(serverId)
    if serverId then
        local player = GetPlayerFromServerId(serverId)
        if player ~= -1 then
            return 'player', serverId
        end
    end

    local camera = GetGameplayCamCoord()
    local finish = getCameraAimPosition(camera, Config.RemoveProngs.Distance)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        camera.x, camera.y, camera.z,
        finish.x, finish.y, finish.z,
        511,
        PlayerPedId(),
        7
    )
    local _, hit, _, _, entity = GetShapeTestResult(ray)

    if hit == 1 and IsEntityAPed(entity) and trackedProngCount(entity) > 0 then
        return victimDetails(entity)
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local nearestType, nearestId
    local nearestDistance = Config.RemoveProngs.Distance + 0.001
    local checked = {}

    for _, prong in pairs(persistentProngs) do
        local data = prong.data
        local key = victimKey(data.victimType, data.victimId)
        if not checked[key] then
            checked[key] = true
            local ped = victimPed(data.victimType, data.victimId)
            if ped ~= 0 then
                local currentDistance = #(GetEntityCoords(ped) - playerCoords)
                if currentDistance < nearestDistance then
                    nearestType = data.victimType
                    nearestId = data.victimId
                    nearestDistance = currentDistance
                end
            end
        end
    end

    return nearestType, nearestId
end

local function requestProngRemoval(ped, removalSource)
    local targetType, targetId = victimDetails(ped)
    if not targetType or trackedProngCount(ped) == 0 then return end
    TriggerServerEvent('axon_taser10:removeProngs', targetType, targetId, removalSource)
end

RegisterCommand(Config.RemoveProngs.Command, function(_, args)
    local targetType, targetId = removalTarget(tonumber(args[1]))
    if targetType then
        TriggerServerEvent('axon_taser10:removeProngs', targetType, targetId, 'command')
    end
end, false)

RegisterCommand(Config.ReloadCommand, function()
    if not usingTaser() then return end
    if armed then setSafe() end

    cartridges = Config.Cartridges
    if deployed >= Config.BatteryDisplay.DepletedThresholdShotsSpent then
        battery = 100.0
        deployed = 0
        dischargeLogged = false
    end
    clearOwnedConnection(nil, true)
    functionTestState = 'inactive'
    TriggerServerEvent('axon_taser10:sleep')
    updateCid()
end, false)

RegisterNetEvent('axon_taser10:shotResult', function(targetType, targetId, state, probeCount, connectionId, prongIds)
    local wasConnected = connection.state == 'CONNECTED'
    connection = {
        state = state,
        targetType = targetType,
        targetId = targetId,
        probeCount = probeCount,
        connectionId = connectionId,
        prongIds = prongIds
    }

    if state == 'CONNECTED' and not wasConnected then
        playTaserSound('connect')
        battery = math.max(0.0, battery - Config.BatteryDrain)
    end

    updateCid()
end)

RegisterNetEvent('axon_taser10:connectionBroken', function(connectionId, reason)
    if not connection.connectionId or connection.connectionId == connectionId then
        clearOwnedConnection(reason or 'server', false)
    end
end)

RegisterNetEvent('axon_taser10:persistentProngAdded', function(data)
    addPersistentProng(data)
end)

RegisterNetEvent('axon_taser10:persistentProngsRemoved', function(prongIds)
    for _, prongId in ipairs(prongIds) do
        removePersistentProng(prongId)
    end
end)

RegisterNetEvent('axon_taser10:activeConnectionCreated', function(data)
    createActiveConnection(data)
end)

RegisterNetEvent('axon_taser10:activeConnectionRemoved', function(connectionId, reason)
    removeActiveConnection(connectionId, reason)
end)

RegisterNetEvent('axon_taser10:syncState', function(prongs, connections, removalAllowed, ownedConnection)
    canRemoveProngs = removalAllowed == true
    local synced = {}
    for _, data in ipairs(prongs) do
        synced[data.id] = true
        addPersistentProng(data)
    end

    local stale = {}
    for prongId in pairs(persistentProngs) do
        if not synced[prongId] then
            stale[#stale + 1] = prongId
        end
    end
    for _, prongId in ipairs(stale) do
        removePersistentProng(prongId)
    end

    activeConnections = {}
    for _, data in ipairs(connections) do
        createActiveConnection(data)
    end

    if ownedConnection then
        connection = {
            state = ownedConnection.state,
            targetType = ownedConnection.targetType,
            targetId = ownedConnection.targetId,
            probeCount = #ownedConnection.prongIds,
            connectionId = ownedConnection.id,
            prongIds = ownedConnection.prongIds
        }
        updateCid()
    end
end)

RegisterNetEvent('axon_taser10:cycle', function(_, cycleDuration, ragdollDuration, extend)
    local now = GetGameTimer()
    if extend and stunEnds > now then
        stunEnds = stunEnds + cycleDuration
    else
        stunEnds = now + cycleDuration
    end

    if extend and ragdollEnds > now then
        ragdollEnds = ragdollEnds + ragdollDuration
    else
        ragdollEnds = now + ragdollDuration
    end
end)

RegisterNetEvent('axon_taser10:cycleNpc', function(networkId, ragdollDuration)
    local ped = victimPed('npc', networkId)
    if ped ~= 0 and not IsEntityDead(ped) then
        SetPedToRagdoll(ped, ragdollDuration, ragdollDuration, 0, false, false, false)
    end
end)

RegisterNetEvent('axon_taser10:stopCycle', function()
    stunEnds = 0
    ragdollEnds = 0
end)

RegisterNetEvent('axon_taser10:reactivationResult', function()
    battery = math.max(0.0, battery - Config.BatteryDrain)
    updateCid()
end)

RegisterNetEvent('axon_taser10:playSound', function(sound, volume)
    SendNUIMessage({ action = 'sound', sound = sound, volume = volume })
end)

RegisterNetEvent('axon_taser10:flashlightState', function(serverId, enabled)
    if serverId == GetPlayerServerId(PlayerId()) then return end

    if enabled then
        remoteFlashlights[serverId] = remoteFlashlights[serverId] or { strobeUntil = 0 }
    else
        remoteFlashlights[serverId] = nil
    end
end)

RegisterNetEvent('axon_taser10:armedState', function(serverId, enabled)
    if serverId == GetPlayerServerId(PlayerId()) then return end
    remoteArmedPlayers[serverId] = enabled and true or nil
end)

RegisterNetEvent('axon_taser10:remoteStrobe', function(serverId, duration)
    local flashlight = remoteFlashlights[serverId]
    if not flashlight or serverId == GetPlayerServerId(PlayerId()) then return end
    flashlight.strobeUntil = GetGameTimer() + duration
end)

CreateThread(function()
    while true do
        local drawing = false

        if Config.Laser.Enabled or Config.Flashlight.Enabled then
            for serverId in pairs(remoteArmedPlayers) do
                local player = GetPlayerFromServerId(serverId)
                if player ~= -1 then
                    local ped = GetPlayerPed(player)
                    if ped ~= 0 and not IsEntityDead(ped) and usingTaser(ped) then
                        local hitPosition, start, direction, right, up = getLaserDotPosition(ped)
                        if hitPosition and start then
                            if Config.Laser.Enabled then
                                drawLaserDot(hitPosition)
                            end

                            local flashlight = remoteFlashlights[serverId]
                            if Config.Flashlight.Enabled and flashlight then
                                drawFlashlight(start, direction, right, up, flashlight.strobeUntil, false)
                            end

                            drawing = true
                        end
                    end
                end
            end
        end

        Wait(drawing and 0 or 250)
    end
end)

local function connectionTargetPed()
    if not connection.targetType then return 0 end
    return victimPed(connection.targetType, connection.targetId)
end

local function connectionBreakReason()
    if connection.state ~= 'PARTIAL' and connection.state ~= 'CONNECTED' then return nil end
    local onGround = taserOnGround()
    if Config.Prongs.BreakOnWeaponSwitch and not usingTaser() and not onGround then return 'weapon_switch' end

    local shooter = PlayerPedId()
    local target = connectionTargetPed()
    if target == 0 or not DoesEntityExist(target) then return 'target_missing' end

    if Config.Prongs.BreakOnDeath and (IsEntityDead(shooter) or IsEntityDead(target)) then
        return 'death'
    end

    if connection.state == 'CONNECTED' and connection.connectionId then
        local active = activeConnections[connection.connectionId]
        local wireDistance = active and connectionWireDistance(active)
        if wireDistance and wireDistance >= Config.Prongs.MaxWireDistance then
            return 'distance'
        end
    elseif #(GetEntityCoords(droppedObject() or shooter) - GetEntityCoords(target)) > Config.Prongs.MaxWireDistance then
        return 'distance'
    end

    if Config.Prongs.BreakOnLineOfSight and not onGround and not HasEntityClearLosToEntity(shooter, target, 17) then
        return 'line_of_sight'
    end

    return nil
end

RPTaser = { breakReason = connectionBreakReason, onGround = taserOnGround } -- pour les tests

-- =========================================================================
-- ŒIL de rp_interact (rp_interact/config.lua : TargetProviders) : remplace ox_target
--   exports targetOptions(info) -> { label, options = { { id, label, icon } } } ; targetSelect(id, info)
-- =========================================================================
local TargetConfig = Config.Target or {}

--- Rotation « couchée » (le plus petit côté vers le haut) et hauteur pour poser l'objet à plat sur le sol
local function lyingPlacement(model, x, y, ground, heading)
    local min, max = GetModelDimensions(model)
    local size = max - min
    local rx, ry = 0.0, 0.0
    if size.x <= size.y and size.x <= size.z then ry = 90.0 elseif size.y <= size.z then rx = 90.0 end
    local probe = CreateObjectNoOffset(model, x, y, ground + 1.0, false, false, false)
    SetEntityVisible(probe, false, false)
    SetEntityCollision(probe, false, false)
    FreezeEntityPosition(probe, true)
    SetEntityRotation(probe, rx, ry, heading, 2, true)
    local lowest = math.huge
    for _, cx in ipairs({ min.x, max.x }) do
        for _, cy in ipairs({ min.y, max.y }) do
            for _, cz in ipairs({ min.z, max.z }) do
                local w = GetOffsetFromEntityInWorldCoords(probe, cx, cy, cz)
                if w.z < lowest then lowest = w.z end
            end
        end
    end
    local origin = GetEntityCoords(probe)
    DeleteEntity(probe)
    return vector3(origin.x, origin.y, origin.z + (ground + 0.01 - lowest)), rx, ry
end

local droppedWeapon = nil -- { weapon, ammo } : rendu si le serveur refuse

--- Poser le Taser au sol devant soi : il quitte la main, les sondes restent reliées (fil depuis le Taser posé)
local function dropTaser()
    local ped = PlayerPedId()
    if taserOnGround() or not usingTaser(ped) or IsPedInAnyVehicle(ped, false) then return end
    local weapon = GetSelectedPedWeapon(ped)
    local model = GetWeapontypeModel(weapon)
    if not model or model == 0 or not IsModelInCdimage(model) then return end
    dropping = true
    CreateThread(function()
        RequestModel(model)
        RequestAnimDict('pickup_object')
        local untilTime = GetGameTimer() + 2000
        while (not HasModelLoaded(model) or not HasAnimDictLoaded('pickup_object')) and GetGameTimer() < untilTime do Wait(0) end
        if HasAnimDictLoaded('pickup_object') then
            TaskPlayAnim(ped, 'pickup_object', 'putdown_low', 8.0, -8.0, 900, 0, 0.0, false, false, false)
        end
        Wait(450)
        local spot = GetOffsetFromEntityInWorldCoords(ped, 0.15, 0.55, 0.0)
        local found, ground = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 1.0, false)
        if not found then ground = spot.z - 0.98 end
        local heading = (GetEntityHeading(ped) + 90.0) % 360.0
        local pos, rx, ry = lyingPlacement(model, spot.x, spot.y, ground, heading)
        SetModelAsNoLongerNeeded(model)
        droppedWeapon = { weapon = weapon, ammo = GetAmmoInPedWeapon(ped, weapon) }
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        RemoveWeaponFromPed(ped, weapon)
        TriggerServerEvent('axon_taser10:dropTaser', { weapon = weapon, model = model, ammo = droppedWeapon.ammo,
            x = pos.x, y = pos.y, z = pos.z, rx = rx, ry = ry, rz = heading })
    end)
end

-- Posé (le serveur a créé l'objet) ou refusé (le Taser est rendu)
RegisterNetEvent('axon_taser10:dropResult', function(ok, message, netId)
    if ok then droppedNet = netId end
    dropping = false
    if not ok and droppedWeapon then
        GiveWeaponToPed(PlayerPedId(), droppedWeapon.weapon, droppedWeapon.ammo or 0, false, true)
        droppedWeapon = nil
    end
    if message then TriggerEvent('chat:addMessage', { args = { 'TASER 10', message } }) end
end)

-- Repris (œil de rp_interact, ExternalObjects) : en main, les sondes toujours reliées
RegisterNetEvent('axon_taser10:pickedUp', function(weapon, ammo)
    local ped = PlayerPedId()
    RequestAnimDict('pickup_object')
    local untilTime = GetGameTimer() + 1000
    while not HasAnimDictLoaded('pickup_object') and GetGameTimer() < untilTime do Wait(0) end
    if HasAnimDictLoaded('pickup_object') then
        TaskPlayAnim(ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 900, 48, 0.0, false, false, false)
    end
    GiveWeaponToPed(ped, weapon, tonumber(ammo) or 0, false, true)
    SetCurrentPedWeapon(ped, weapon, true)
    droppedWeapon = nil
    droppedNet = nil
    pickupGrace = GetGameTimer() + 1500
    rearmAfterPickup = connection.state == 'CONNECTED'
    if safeAt then safeAt = GetGameTimer() end
end)

exports('targetOptions', function(info)
    if type(info) ~= 'table' then return nil end
    local options = {}
    local ped = PlayerPedId()
    -- Taser en main, n'importe où (sol, mur, véhicule, personne) : le poser au sol, sondes gardées
    if TargetConfig.Drop ~= false and usingTaser(ped) and not taserOnGround() and not IsPedInAnyVehicle(ped, false) then
        options[#options + 1] = { id = 'drop', icon = 'hand',
            label = hasConnection() and 'Poser le Taser au sol (sondes gardées)' or 'Poser le Taser au sol' }
    end
    if info.type ~= 'ped' or not info.entity or not DoesEntityExist(info.entity) then
        if #options == 0 then return nil end
        return { label = 'TASER 10', options = options }
    end
    if info.entity == ped then
        -- sur soi-même, Taser en main : recharger (comme /reloadtaser)
        if TargetConfig.Reload ~= false and usingTaser(ped) then
            options[#options + 1] = { id = 'reload', icon = 'hand', label = TargetConfig.ReloadLabel or 'Recharger le Taser' }
        end
    else
        local count = trackedProngCount(info.entity)
        if canRemoveProngs and count > 0 and (tonumber(info.distance) or 99.0) <= (Config.RemoveProngs.TargetDistance or 2.0) then
            options[#options + 1] = { id = 'removeProngs', icon = 'hand',
                label = ('%s (%d)'):format(TargetConfig.RemoveLabel or 'Retirer les sondes du Taser', count) }
        end
    end
    if #options == 0 then return nil end
    return { label = 'TASER 10', options = options }
end)

exports('targetSelect', function(id, info)
    if id == 'drop' then
        dropTaser()
    elseif id == 'reload' then
        ExecuteCommand(Config.ReloadCommand)
    elseif id == 'removeProngs' and type(info) == 'table' and info.entity and DoesEntityExist(info.entity) then
        requestProngRemoval(info.entity, 'target')
    end
end)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('axon_taser10:requestSync')
end)
CreateThread(function()
    while true do
        local now = GetGameTimer()
        local stunned = stunEnds > now
        local ragdolling = ragdollEnds > now

        if ragdolling then
            SetPedToRagdoll(PlayerPedId(), 500, 500, 0, false, false, false)
        end

        if stunned then
            DisableAllControlActions(0)
            EnableControlAction(0, 1, true)
            EnableControlAction(0, 2, true)
        end

        if stunned or ragdolling then
            Wait(0)
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        if usingTaser() then
            DisablePlayerFiring(PlayerId(), true)

            if armed then
                local hitPosition, laserStart, flashlightDirection, weaponRight, weaponUp = getLaserDotPosition()

                if hitPosition and laserStart then
                    if Config.Laser.Enabled then
                        drawLaserDot(hitPosition)
                    end

                    if Config.Flashlight.Enabled and not stealth then
                        drawFlashlight(
                            laserStart,
                            flashlightDirection,
                            weaponRight,
                            weaponUp,
                            warningUntil,
                            battery < Config.Flashlight.LowBatteryThreshold
                        )
                    end
                end

                if cartridges > 0
                    and battery > 0
                    and deployed < Config.BatteryDisplay.DepletedThresholdShotsSpent
                    and (not Config.RequireAiming or IsPlayerFreeAiming(PlayerId()))
                    and (IsControlJustPressed(0, 24) or IsDisabledControlJustPressed(0, 24)) then
                    fireTaser()
                end
            end
        elseif armed then
            setSafe()
        end

        local breakReason = connectionBreakReason()
        if breakReason then
            clearOwnedConnection(breakReason, true)
        end

        if safeAt and taserOnGround() then safeAt = GetGameTimer() end -- posé : pas de mise en veille
        if safeAt and GetGameTimer() - safeAt >= 180000 then
            safeAt = nil
            clearOwnedConnection('sleep', false)
            TriggerServerEvent('axon_taser10:sleep')
        end

        Wait(0)
    end
end)

CreateThread(function()
    while true do
        updateCid()
        Wait(100)
    end
end)

exports('toggleSafety', function()
    ExecuteCommand('+axonSafety')
end)

exports('pressSelectorUp', function()
    ExecuteCommand('+axonSelectorUp')
end)

exports('getTaserState', function()
    return {
        armed = armed,
        stealth = stealth,
        cartridges = cartridges,
        battery = battery,
        deployed = deployed,
        connected = hasConnection(),
        connectionState = connection.state
    }
end)

exports('isNpcTaserTarget', function(ped)
    return trackedProngCount(ped) > 0
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for _, prong in pairs(persistentProngs) do
        cleanupProng(prong)
    end

    persistentProngs = {}
    activeConnections = {}
    victimProngCounts = {}
end)
