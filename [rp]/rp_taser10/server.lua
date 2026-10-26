local connections = {}
local persistentProngs = {}
local victimProngs = {}
local lastShots = {}
local armedPlayers = {}
local flashlightPlayers = {}
local nextProngId = 1
local nextConnectionId = 1
local sounds = { arming = true, switch = true, fire = true, connect = true, warning = true }
local validBones = {}
local removeProngIds

local function debugLog(message, ...)
    if not Config.DebugMode then return end
    print(('[axon_taser10] ' .. message):format(...))
end

local function logDischarge(player)
    local webhook = Config.DischargeWebhook
    if not webhook or webhook.Url == '' then return end

    local playerName = GetPlayerName(player) or ('Player ' .. player)
    local payload = json.encode({
        username = webhook.Username or 'Axon Ecosystem',
        embeds = {{
            title = 'TASER battery discharged',
            description = ('%s fully discharged their AXON TASER 10 battery.'):format(playerName),
            color = 16711680
        }}
    })

    PerformHttpRequest(webhook.Url, function() end, 'POST', payload, {
        ['Content-Type'] = 'application/json'
    })
end

local function stopConflictingTaser(resource)
    for _, name in ipairs(Config.ConflictingTaserResources or {}) do
        if resource == name and GetResourceState(name) == 'started' then
            print(('[axon_taser10] Stopping conflicting taser resource: %s'):format(name))
            StopResource(name)
            return
        end
    end
end

CreateThread(function()
    Wait(0)
    for _, resource in ipairs(Config.ConflictingTaserResources or {}) do
        stopConflictingTaser(resource)
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        print('AXON TASER 10 1.5.0 Pre Release')
        return
    end

    stopConflictingTaser(resource)
end)

for _, boneId in ipairs(Config.Prongs.BoneIds) do
    validBones[boneId] = true
end

local function distance(first, second)
    local offset = first - second
    return math.sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
end

local function victimKey(targetType, targetId)
    return ('%s:%s'):format(targetType, targetId)
end

local function playerFromPed(ped)
    for _, player in ipairs(GetPlayers()) do
        if GetPlayerPed(player) == ped then
            return tonumber(player)
        end
    end
end

local function victimEntity(targetType, targetId)
    if targetType == 'player' then
        if not GetPlayerName(targetId) then return 0 end
        return GetPlayerPed(targetId)
    end

    if targetType == 'npc' then
        local ped = NetworkGetEntityFromNetworkId(targetId)
        if ped == 0 or GetEntityType(ped) ~= 1 or playerFromPed(ped) then return 0 end
        return ped
    end

    return 0
end

local function validPair(shooter, targetType, targetId, maxDistance)
    if not GetPlayerName(shooter) then return false end

    local shooterPed = GetPlayerPed(shooter)
    local targetPed = victimEntity(targetType, targetId)
    if shooterPed == 0 or targetPed == 0 or shooterPed == targetPed then return false end
    if GetEntityHealth(shooterPed) <= 0 or GetEntityHealth(targetPed) <= 0 then return false end

    if targetType == 'player' then
        if GetPlayerRoutingBucket(shooter) ~= GetPlayerRoutingBucket(targetId) then return false end
    elseif GetPlayerRoutingBucket(shooter) ~= GetEntityRoutingBucket(targetPed) then
        return false
    end

    return distance(GetEntityCoords(shooterPed), GetEntityCoords(targetPed)) <= maxDistance
end

local function validRemovalTarget(requester, targetType, targetId)
    local requesterPed = GetPlayerPed(requester)
    local targetPed = victimEntity(targetType, targetId)
    if requesterPed == 0 or targetPed == 0 then return false end

    if targetType == 'player' then
        if GetPlayerRoutingBucket(requester) ~= GetPlayerRoutingBucket(targetId) then return false end
    elseif GetPlayerRoutingBucket(requester) ~= GetEntityRoutingBucket(targetPed) then
        return false
    end

    return distance(GetEntityCoords(requesterPed), GetEntityCoords(targetPed)) <= Config.RemoveProngs.Distance
end

local function prongCount(key)
    local ids = victimProngs[key]
    return ids and #ids or 0
end

local function setConnectionProngsInactive(connection)
    for _, prongId in ipairs(connection.prongIds or {}) do
        local prong = persistentProngs[prongId]
        if prong then
            prong.activeConnectionId = nil
        end
    end
end

local function connectionVictimMatches(connection)
    local firstProng = persistentProngs[connection.prongIds[1]]
    local targetPed = victimEntity(connection.targetType, connection.targetId)
    if not firstProng or targetPed == 0 then return false end
    if firstProng.victimNetworkId == 0 then return true end
    return NetworkGetNetworkIdFromEntity(targetPed) == firstProng.victimNetworkId
end

local function stopVictimCycle(connection)
    if connection.targetType == 'player' then
        TriggerClientEvent('axon_taser10:stopCycle', connection.targetId)
    end
end

local function breakConnection(shooter, reason)
    local connection = connections[shooter]
    if not connection then return end

    setConnectionProngsInactive(connection)
    stopVictimCycle(connection)
    connections[shooter] = nil

    TriggerClientEvent('axon_taser10:connectionBroken', shooter, connection.id, reason or 'removed')
    TriggerClientEvent('axon_taser10:activeConnectionRemoved', -1, connection.id, reason or 'removed')

    local preserveProngs = Config.Prongs.KeepAfterConnectionBreak
    if reason == 'weapon_switch' then
        preserveProngs = Config.Prongs.KeepAfterWeaponSwitch
    elseif reason == 'new_deployment' then
        preserveProngs = Config.Prongs.KeepAfterNewShot
    end

    if not preserveProngs then
        removeProngIds(connection.prongIds)
    end

    debugLog(
        'connection destroyed id=%s shooter=%s reason=%s persistentProngsPreserved=%s',
        connection.id,
        shooter,
        reason or 'removed',
        preserveProngs
    )
end

local function addPersistentProng(shooter, targetType, targetId, boneId, probe)
    local key = victimKey(targetType, targetId)
    local targetPed = victimEntity(targetType, targetId)
    local offset = Config.Prongs.AttachmentOffsets[probe] or Config.Prongs.AttachmentOffsets[1]
    local rotation = Config.Prongs.AttachmentRotation
    local model = Config.Prongs.Models and Config.Prongs.Models[probe] or Config.Prongs.Model
    local prongId = nextProngId
    nextProngId = nextProngId + 1

    local prong = {
        id = prongId,
        model = model,
        victimType = targetType,
        victimId = targetId,
        victimNetworkId = targetPed ~= 0 and NetworkGetNetworkIdFromEntity(targetPed) or 0,
        bone = boneId,
        offset = { x = offset.x, y = offset.y, z = offset.z },
        rotation = { x = rotation.x, y = rotation.y, z = rotation.z },
        shooter = shooter,
        createdAt = os.time()
    }

    persistentProngs[prongId] = prong
    victimProngs[key] = victimProngs[key] or {}
    victimProngs[key][#victimProngs[key] + 1] = prongId

    TriggerClientEvent('axon_taser10:persistentProngAdded', -1, prong)
    debugLog(
        'persistent prong created id=%s victimNetId=%s bone=%s shooter=%s count=%s',
        prongId,
        prong.victimNetworkId,
        boneId,
        shooter,
        prongCount(key)
    )

    return prongId
end

local function cycleVictim(connection, extend)
    if connection.targetType == 'player' then
        TriggerClientEvent(
            'axon_taser10:cycle',
            connection.targetId,
            connection.shooter,
            Config.CycleTime,
            Config.RagdollTime,
            extend
        )
        return
    end

    local victimPed = victimEntity(connection.targetType, connection.targetId)
    if victimPed == 0 then return end

    local owner = NetworkGetEntityOwner(victimPed)
    TriggerClientEvent(
        'axon_taser10:cycleNpc',
        owner and owner > 0 and owner or -1,
        connection.targetId,
        Config.RagdollTime
    )
end

local function allowedJob(source)
    local allowed = Config.RemoveProngs.AllowedJobs or {}
    if #allowed == 0 then return false end

    local state = Player(source).state
    local job = state.job
    if type(job) == 'table' then job = job.name end
    if type(job) ~= 'string' then return false end

    for _, name in ipairs(allowed) do
        if job == name then return true end
    end

    return false
end

local function canRemoveProngs(source)
    if not Config.RemoveProngs.RequirePermission then return true end
    if IsPlayerAceAllowed(source, Config.RemoveProngs.PermissionAce) then return true end
    return allowedJob(source)
end

removeProngIds = function(ids)
    local removed = {}

    for _, prongId in ipairs(ids or {}) do
        local prong = persistentProngs[prongId]
        if prong then
            local key = victimKey(prong.victimType, prong.victimId)
            local stored = victimProngs[key] or {}

            for index = #stored, 1, -1 do
                if stored[index] == prongId then
                    table.remove(stored, index)
                    break
                end
            end

            if #stored == 0 then
                victimProngs[key] = nil
            end

            persistentProngs[prongId] = nil
            removed[#removed + 1] = prongId
        end
    end

    if #removed > 0 then
        TriggerClientEvent('axon_taser10:persistentProngsRemoved', -1, removed)
    end
end

local function removePersistentProngs(key, source, removalSource)
    local storedIds = victimProngs[key]
    if not storedIds or #storedIds == 0 then return false end

    local ids = {}
    for _, prongId in ipairs(storedIds) do
        ids[#ids + 1] = prongId
    end

    local removing = {}
    for _, prongId in ipairs(ids) do
        removing[prongId] = true
    end

    local breaking = {}
    for shooter, connection in pairs(connections) do
        for _, prongId in ipairs(connection.prongIds or {}) do
            if removing[prongId] then
                breaking[#breaking + 1] = shooter
                break
            end
        end
    end

    for _, shooter in ipairs(breaking) do
        breakConnection(shooter, 'prongs_removed')
    end

    removeProngIds(ids)
    debugLog(
        'persistent prongs removed source=%s requester=%s victim=%s count=%s',
        removalSource or 'cleanup',
        source or 0,
        key,
        #ids
    )
    return true
end

RegisterNetEvent('axon_taser10:sound', function(sound)
    if not sounds[sound] then return end

    local shooter = source
    local ped = GetPlayerPed(shooter)
    if ped == 0 then return end

    if sound == 'warning' and armedPlayers[shooter] and flashlightPlayers[shooter] then
        TriggerClientEvent('axon_taser10:remoteStrobe', -1, shooter, Config.Flashlight.StrobeDuration)
    end

    local maxDistance = math.max(0.1, tonumber(Config.SoundDistance) or 15.0)
    local baseVolume = math.max(0.0, math.min(1.0, tonumber(Config.SoundVolume) or 0.6))
    if baseVolume <= 0.0 then return end

    local position = GetEntityCoords(ped)
    local bucket = GetPlayerRoutingBucket(shooter)

    for _, player in ipairs(GetPlayers()) do
        local target = tonumber(player)
        local targetPed = GetPlayerPed(target)
        if target ~= shooter and targetPed ~= 0 and GetPlayerRoutingBucket(target) == bucket then
            local playerDistance = distance(GetEntityCoords(targetPed), position)
            if playerDistance <= maxDistance then
                local volume = baseVolume * (1.0 - playerDistance / maxDistance)
                TriggerClientEvent('axon_taser10:playSound', target, sound, volume)
            end
        end
    end
end)

RegisterNetEvent('axon_taser10:shot', function(targetType, targetId, boneId)
    local shooter = source
    local now = GetGameTimer()
    if lastShots[shooter] and now - lastShots[shooter] < 300 then return end
    lastShots[shooter] = now

    targetId = tonumber(targetId)
    if (targetType ~= 'player' and targetType ~= 'npc') or not targetId then return end
    if type(boneId) ~= 'number' or not validBones[boneId] then return end
    if not armedPlayers[shooter] or not validPair(shooter, targetType, targetId, Config.MaxRange + 2.0) then return end

    local previous = connections[shooter]
    if previous and previous.state == 'CONNECTED' then
        breakConnection(shooter, 'new_deployment')
        previous = nil
    elseif previous and (previous.targetType ~= targetType or previous.targetId ~= targetId) then
        breakConnection(shooter, 'different_target')
        previous = nil
    end

    local connection = previous or {
        id = nextConnectionId,
        shooter = shooter,
        targetType = targetType,
        targetId = targetId,
        prongIds = {},
        state = 'PARTIAL',
        lastReactivation = now - Config.Prongs.ReactivationCooldown,
        maxDistance = Config.Prongs.MaxWireDistance
    }

    if not previous then
        nextConnectionId = nextConnectionId + 1
    end

    local probe = #connection.prongIds + 1
    local prongId = addPersistentProng(shooter, targetType, targetId, boneId, probe)
    connection.prongIds[#connection.prongIds + 1] = prongId
    persistentProngs[prongId].activeConnectionId = connection.id
    connection.state = #connection.prongIds >= 2 and 'CONNECTED' or 'PARTIAL'
    connections[shooter] = connection

    TriggerClientEvent(
        'axon_taser10:shotResult',
        shooter,
        targetType,
        targetId,
        connection.state,
        #connection.prongIds,
        connection.id,
        connection.prongIds
    )

    TriggerClientEvent('axon_taser10:activeConnectionCreated', -1, connection)

    if connection.state == 'CONNECTED' then
        cycleVictim(connection, true)
        debugLog(
            'connection created id=%s shooter=%s victim=%s:%s prongs=%s,%s maxDistance=%.2f',
            connection.id,
            shooter,
            targetType,
            targetId,
            connection.prongIds[1],
            connection.prongIds[2],
            connection.maxDistance
        )
    end
end)

RegisterNetEvent('axon_taser10:discharge', function()
    if armedPlayers[source] then
        logDischarge(source)
    end
end)

RegisterNetEvent('axon_taser10:reactivate', function()
    local shooter = source
    local connection = connections[shooter]
    if not connection or connection.state ~= 'CONNECTED' or #connection.prongIds < 2 then return end
    if not connectionVictimMatches(connection) then
        breakConnection(shooter, 'target_changed')
        return
    end
    if not armedPlayers[shooter] or not validPair(
        shooter,
        connection.targetType,
        connection.targetId,
        Config.Prongs.MaxWireDistance + Config.Prongs.CordBreakTolerance
    ) then
        breakConnection(shooter, 'invalid')
        return
    end

    local now = GetGameTimer()
    if now - connection.lastReactivation < Config.Prongs.ReactivationCooldown then return end
    connection.lastReactivation = now

    cycleVictim(connection, false)
    TriggerClientEvent('axon_taser10:reactivationResult', shooter)
end)

RegisterNetEvent('axon_taser10:breakConnection', function(reason, connectionId)
    local connection = connections[source]
    if not connection then return end
    if connectionId and connection.id ~= connectionId then return end
    breakConnection(source, type(reason) == 'string' and reason or 'removed')
end)

RegisterNetEvent('axon_taser10:removeProngs', function(targetType, targetId, removalSource)
    local requester = source
    targetId = tonumber(targetId)
    if (targetType ~= 'player' and targetType ~= 'npc') or not targetId then return end
    if not canRemoveProngs(requester) then return end

    local key = victimKey(targetType, targetId)
    if not victimProngs[key] or victimEntity(targetType, targetId) == 0 then return end
    if not validRemovalTarget(requester, targetType, targetId) then return end

    removePersistentProngs(key, requester, removalSource == 'target' and 'target' or 'command')
end)

RegisterNetEvent('axon_taser10:requestSync', function()
    local prongs = {}
    local active = {}

    for _, prong in pairs(persistentProngs) do
        prongs[#prongs + 1] = prong
    end
    for _, connection in pairs(connections) do
        active[#active + 1] = connection
    end

    TriggerClientEvent('axon_taser10:syncState', source, prongs, active, canRemoveProngs(source), connections[source])

    for shooter, isArmed in pairs(armedPlayers) do
        if isArmed then
            TriggerClientEvent('axon_taser10:armedState', source, shooter, true)
        end
    end

    for shooter in pairs(flashlightPlayers) do
        TriggerClientEvent('axon_taser10:flashlightState', source, shooter, true)
    end
end)

RegisterNetEvent('axon_taser10:armed', function(flashlightEnabled)
    local ped = GetPlayerPed(source)
    armedPlayers[source] = ped ~= 0 and GetEntityHealth(ped) > 0
    flashlightPlayers[source] = armedPlayers[source] and Config.Flashlight.Enabled and flashlightEnabled == true or nil
    TriggerClientEvent('axon_taser10:armedState', -1, source, armedPlayers[source] == true)
    TriggerClientEvent('axon_taser10:flashlightState', -1, source, flashlightPlayers[source] == true)
end)

RegisterNetEvent('axon_taser10:safe', function()
    armedPlayers[source] = nil
    flashlightPlayers[source] = nil
    TriggerClientEvent('axon_taser10:armedState', -1, source, false)
    TriggerClientEvent('axon_taser10:flashlightState', -1, source, false)
    local connection = connections[source]
    if connection and connection.state == 'CONNECTED' then
        stopVictimCycle(connection)
    end
end)

RegisterNetEvent('axon_taser10:sleep', function()
    armedPlayers[source] = nil
    flashlightPlayers[source] = nil
    TriggerClientEvent('axon_taser10:armedState', -1, source, false)
    TriggerClientEvent('axon_taser10:flashlightState', -1, source, false)
    breakConnection(source, 'sleep')
end)

CreateThread(function()
    while true do
        local broken = {}
        for shooter, connection in pairs(connections) do
            local limit = Config.Prongs.MaxWireDistance + Config.Prongs.CordBreakTolerance
            if not connectionVictimMatches(connection)
                or not validPair(shooter, connection.targetType, connection.targetId, limit)
            then
                broken[#broken + 1] = shooter
            end
        end

        for _, shooter in ipairs(broken) do
            breakConnection(shooter, 'distance_or_entity')
        end

        local missingVictims = {}
        for key, ids in pairs(victimProngs) do
            local first = persistentProngs[ids[1]]
            local targetPed = first and victimEntity(first.victimType, first.victimId) or 0
            if not first
                or targetPed == 0
                or (first.victimNetworkId ~= 0 and NetworkGetNetworkIdFromEntity(targetPed) ~= first.victimNetworkId)
            then
                missingVictims[#missingVictims + 1] = key
            end
        end

        for _, key in ipairs(missingVictims) do
            removePersistentProngs(key, nil, 'entity_removed')
        end

        Wait(500)
    end
end)

AddEventHandler('playerDropped', function()
    local player = source
    breakConnection(player, 'shooter_left')
    lastShots[player] = nil
    armedPlayers[player] = nil
    flashlightPlayers[player] = nil
    TriggerClientEvent('axon_taser10:armedState', -1, player, false)
    TriggerClientEvent('axon_taser10:flashlightState', -1, player, false)

    local key = victimKey('player', player)
    removePersistentProngs(key, nil, 'victim_left')

    local affected = {}
    for shooter, connection in pairs(connections) do
        if connection.targetType == 'player' and connection.targetId == player then
            affected[#affected + 1] = shooter
        end
    end

    for _, shooter in ipairs(affected) do
        breakConnection(shooter, 'target_left')
    end
end)
