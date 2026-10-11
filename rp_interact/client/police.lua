--[[
    RP Interact - Actions de police et véhicules d'urgence
    ------------------------------------------------------
    POLICIER (joueur dans une unité du MDC), par l'œil ou par le menu d'interactions :
      - Menotter (2 m autour du policier, 7 s) / Retirer les menottes (3 s)
      - Prendre par le bras (individu le plus proche, 2 m) : le policier fait "/e tenirlebras",
        l'individu est placé à sa droite et marche quand le policier marche ; X : lâcher le bras
      - Placer l'individu tenu à l'arrière d'un véhicule : le policier ouvre la portière arrière la plus
        proche et lâche le bras ; l'individu y monte lui-même (sans téléportation)
      - Faire sortir l'individu (places arrière)
      - Faire s'asseoir l'individu MENOTTÉ au sol ("/e menotté2") / le faire se relever
    Tout fonctionne aussi sur les PNJ (tests en solo) : le client du policier les pilote directement.

    CIVIL menotté : emote "/e menotté1" + menottes aux poignets ; si l'emote s'arrête (bousculé,
    monté dans un véhicule, touche…), elle est relancée automatiquement. Les emotes viennent du mode
    d'emotes du serveur (RPEMOTES) : leur animation exacte y est lue (server/emotes.lua), pour ne
    jamais rejouer une autre animation que celle de l'emote.

    VÉHICULES D'URGENCE (/policeon, /policeoff) : un non-policier qui essaie d'ouvrir une portière
    fermée d'un véhicule de classe 18 tire sur la poignée sans l'ouvrir (aucun verrou réseau : les
    policiers et les individus placés par un policier montent normalement).

    Performance : boucles actives uniquement pendant qu'on est menotté, tenu par le bras, qu'on tient
    quelqu'un, que des PNJ sont menottés, ou que la règle des véhicules d'urgence est activée.
]]

local Config = InteractConfig
local WALK = { 'move_m@generic', 'walk' } -- marche de l'individu tenu par le bras
local CUFF_ANIM_POLICE = { 'mp_arresting', 'a_uncuff', 49 }
local LEFT_HAND = 60309

local Police = {}
RPI.Police = Police

-- =========================================================================
-- OUTILS
-- =========================================================================
-- Postures de l'individu menotté : debout ("/e menotté1") ou assis au sol ("/e menotté2")
local function poseCommand(sit) return sit and Config.Emotes.seated or Config.Emotes.cuffed end
local function poseFallback(sit) return sit and Config.SeatedAnim or Config.CuffAnim end

--- Animation de la posture : celle de l'emote (lue dans RPEMOTES). `direct` (PNJ, en véhicule, tenu
--- par le bras : pas de commande d'emote possible) : toujours une animation, au besoin celle de secours.
local function poseAnim(sit, direct)
    local anim = RPI.emoteAnim(poseCommand(sit), poseFallback(sit))
    if anim and anim.scenario and direct then anim = nil end
    if not anim and direct then
        local fb = poseFallback(sit)
        anim = { dict = fb.dict, clip = fb.clip, flag = fb.flag }
    end
    return anim
end

local function isPlayingPose(ped, sit, direct)
    if direct then
        local anim = poseAnim(sit, true)
        return IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3)
    end
    return RPI.isPlayingEmote(ped, poseCommand(sit), poseFallback(sit))
end

--- Joue directement l'animation de la posture (à appeler dans un thread)
local function playPose(ped, sit, direct)
    local anim = poseAnim(sit, direct)
    if not anim or anim.scenario then return false end
    return RPI.playAnimNow(ped, anim.dict, anim.clip, -1, anim.flag or (sit and 1 or 49))
end

local function stopPose(ped, sit)
    local anim = poseAnim(sit, true)
    StopAnimTask(ped, anim.dict, anim.clip, 1.0)
end

--- Menottes aux poignets (modèle Config.CuffProp). À appeler dans un thread.
local function attachCuffs(ped)
    local model = GetHashKey(Config.CuffProp)
    if not IsModelInCdimage(model) or not RPI.loadModel(model) then return nil end
    local c = GetEntityCoords(ped)
    local prop = CreateObject(model, c.x, c.y, c.z, true, true, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, LEFT_HAND), -0.055, 0.06, 0.04, 265.0, 155.0, 80.0,
        true, false, false, false, 0, true)
    SetModelAsNoLongerNeeded(model)
    return prop
end

local function deleteProp(prop)
    if prop and DoesEntityExist(prop) then
        DetachEntity(prop, true, false)
        DeleteEntity(prop)
    end
end

local function serverIdOf(ped)
    if not IsPedAPlayer(ped) then return nil end
    return GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
end

--- Individu le plus proche du joueur (joueurs ET PNJ), à pied, dans le rayon donné
function Police.closestPed(range)
    local me = PlayerPedId()
    local origin = GetEntityCoords(me)
    local best, bestDistance = nil, range
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
            local d = #(GetEntityCoords(ped) - origin)
            if d <= bestDistance then best, bestDistance = ped, d end
        end
    end
    return best, bestDistance
end

function Police.closestVehicle(range)
    local origin = GetEntityCoords(PlayerPedId())
    local best, bestDistance = nil, range
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(vehicle) - origin)
        if d <= bestDistance then best, bestDistance = vehicle, d end
    end
    return best
end

-- =========================================================================
-- INDIVIDU TENU PAR LE BRAS : position et marche (policier pour un PNJ, civil pour lui-même)
-- Il n'est PAS accroché au policier (accroché, il pivotait avec le tronc du policier) : à chaque
-- image il est replacé à DragOffset du policier (à sa droite, un peu devant) et tourne sur lui-même
-- vers l'orientation du policier (DragTurnSpeed). Collisions supprimées et position figée (pas de
-- chute) tant qu'il est tenu. Boucle à chaque image UNIQUEMENT pendant qu'il est tenu.
-- =========================================================================
local dragWalking = false -- civil local tenu par le bras en train de marcher (pas de relance des menottes)

--- Tenu : figé et sans collisions ; lâché : retour à la normale
local function holdPed(ped, held)
    if not DoesEntityExist(ped) then return end
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    FreezeEntityPosition(ped, held)
    SetEntityCollision(ped, not held, not held)
end

--- Rotation de `current` vers `target` (degrés), limitée à `maxStep`
local function turnTowards(current, target, maxStep)
    local diff = (target - current + 540.0) % 360.0 - 180.0
    if diff > maxStep then diff = maxStep elseif diff < -maxStep then diff = -maxStep end
    return (current + diff) % 360.0
end

--- `ped` suit le policier et marche quand il marche
local function followLoop(ped, getPolicePed, isActive, onEnd, isSelf)
    CreateThread(function()
        local o = Config.DragOffset
        local walking, nextWalkCheck = false, 0
        local heading = GetEntityHeading(ped)
        holdPed(ped, true)
        while isActive() do
            Wait(0)
            local policePed = getPolicePed()
            if not policePed or policePed == 0 or not DoesEntityExist(ped) or IsEntityDead(policePed)
                or IsPedInAnyVehicle(policePed, false) then
                break
            end
            if not isSelf and not NetworkHasControlOfEntity(ped) then NetworkRequestControlOfEntity(ped) end
            local dt = GetFrameTime()
            local target = GetOffsetFromEntityInWorldCoords(policePed, o.x, o.y, o.z)
            local pos = GetEntityCoords(ped)
            if #(target - pos) > 3.0 then
                pos = target -- trop loin (téléportation, gros décalage réseau) : replacé directement
            else
                pos = pos + (target - pos) * math.min(1.0, dt * 15.0) -- suivi fluide
            end
            heading = turnTowards(heading, GetEntityHeading(policePed), Config.DragTurnSpeed * dt)
            SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z, false, false, false)
            SetEntityHeading(ped, heading)

            local now = GetGameTimer()
            if now >= nextWalkCheck then
                nextWalkCheck = now + 100
                local moving = GetEntitySpeed(policePed) > 0.6
                if moving and not walking then
                    RPI.playAnimNow(ped, WALK[1], WALK[2], -1, 1)
                    walking = true
                elseif not moving and walking then
                    StopAnimTask(ped, WALK[1], WALK[2], 1.0)
                    walking = false
                end
                if isSelf then dragWalking = walking end
            end
        end
        if walking and DoesEntityExist(ped) then StopAnimTask(ped, WALK[1], WALK[2], 1.0) end
        if isSelf then dragWalking = false end
        holdPed(ped, false)
        if onEnd then onEnd() end
    end)
end

-- =========================================================================
-- PNJ (tests en solo) : menottés / tenus par ce policier
-- =========================================================================
local npcCuffed = {} -- [ped] = prop des menottes (false en attendant)
local npcSeated = {} -- [ped] = true : PNJ assis par ce policier
local npcLoopRunning = false

local function startNpcLoop()
    if npcLoopRunning then return end
    npcLoopRunning = true
    CreateThread(function()
        -- Relance l'animation des PNJ menottés si elle s'arrête (boucle tant qu'il y en a)
        while next(npcCuffed) do
            Wait(1000)
            for ped, prop in pairs(npcCuffed) do
                if not DoesEntityExist(ped) or IsEntityDead(ped) then
                    deleteProp(prop)
                    npcCuffed[ped] = nil
                elseif not isPlayingPose(ped, npcSeated[ped], true) and not IsPedRagdoll(ped) and not IsPedGettingIntoAVehicle(ped)
                    and not Police.isDragged(ped) and not IsPedInAnyVehicle(ped, false) then
                    if NetworkHasControlOfEntity(ped) then
                        playPose(ped, npcSeated[ped], true)
                    else
                        NetworkRequestControlOfEntity(ped)
                    end
                end
            end
        end
        npcLoopRunning = false
    end)
end

local function prepareNpc(ped)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
end

local function setNpcCuffed(ped, cuffed)
    if cuffed then
        if npcCuffed[ped] ~= nil then return end
        prepareNpc(ped)
        ClearPedTasksImmediately(ped)
        npcCuffed[ped] = false
        CreateThread(function()
            playPose(ped, false, true)
            local prop = attachCuffs(ped)
            if npcCuffed[ped] == false then npcCuffed[ped] = prop or false else deleteProp(prop) end
        end)
        startNpcLoop()
    else
        deleteProp(npcCuffed[ped])
        npcCuffed[ped] = nil
        npcSeated[ped] = nil
        if DoesEntityExist(ped) then
            stopPose(ped, true)
            stopPose(ped, false)
            SetBlockingOfNonTemporaryEvents(ped, false)
        end
    end
    if NetworkGetEntityIsNetworked(ped) then Entity(ped).state:set('rpiCuffed', cuffed, true) end
end

function Police.isSeated(ped)
    local id = serverIdOf(ped)
    if id then return Player(id).state.rpiSeated == true end
    return npcSeated[ped] == true
end

local dragging = nil -- { ped, serverId } : individu tenu par le bras par ce policier

--- Individu tenu par le bras (joueur : par n'importe quel policier ; PNJ : par ce policier) ?
function Police.isDragged(ped)
    local id = serverIdOf(ped)
    if id then
        local by = Player(id).state.rpiDraggedBy
        return by ~= nil and by ~= false
    end
    return dragging ~= nil and dragging.ped == ped
end

function Police.isCuffed(ped)
    local id = serverIdOf(ped)
    if id then return Player(id).state.rpiCuffed == true end
    if npcCuffed[ped] ~= nil then return true end
    return NetworkGetEntityIsNetworked(ped) and Entity(ped).state.rpiCuffed == true
end

-- =========================================================================
-- POLICIER : MENOTTER / PRENDRE PAR LE BRAS / VÉHICULE
-- =========================================================================

function Police.dragging() return dragging end

local function feedback(okText)
    return function(res)
        if res and res.ok then
            if okText then RPI.notify(okText, 'success') end
        else
            RPI.notify(res and res.error or 'Action impossible.', 'error')
        end
    end
end

function Police.cuff(ped, cuffed)
    if not RPI.isPolice() or RPI.busy() or not DoesEntityExist(ped) then return end
    local serverId = serverIdOf(ped)
    TaskTurnPedToFaceEntity(PlayerPedId(), ped, 600)
    RPI.progress({
        label = cuffed and 'Menottage' or 'Retrait des menottes',
        duration = cuffed and Config.CuffDuration or Config.UncuffDuration,
        anim = CUFF_ANIM_POLICE,
        keep = function()
            return DoesEntityExist(ped) and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped)) <= Config.ActionDistance + 1.0
        end,
    }, function()
        local okText = cuffed and 'Individu menotté.' or 'Menottes retirées.'
        if serverId then
            RPI.request('cuff', { target = serverId, cuffed = cuffed }, feedback(okText))
        else
            RPI.withControl(ped, function() setNpcCuffed(ped, cuffed) end)
            RPI.notify(okText, 'success')
        end
        if not cuffed and dragging and dragging.ped == ped then Police.release() end
    end, function()
        RPI.notify(cuffed and 'Menottage interrompu.' or 'Retrait des menottes interrompu.', 'error')
    end)
end

local function startNpcDrag(ped)
    RPI.withControl(ped, function()
        prepareNpc(ped)
        if npcSeated[ped] then
            npcSeated[ped] = nil
            stopPose(ped, true)
        end
        followLoop(ped, PlayerPedId, function() return dragging ~= nil and dragging.ped == ped end, function()
            if dragging and dragging.ped == ped then dragging = nil end
        end)
    end)
end

function Police.drag(ped)
    if not RPI.isPolice() or not DoesEntityExist(ped) then return end
    if dragging then return Police.release() end
    local target = { ped = ped, serverId = serverIdOf(ped) }
    local function start()
        dragging = target
        RPI.playEmote(Config.Emotes.drag)
        if not target.serverId then startNpcDrag(ped) end
    end
    if target.serverId then
        RPI.request('drag', { target = target.serverId, drag = true }, function(res)
            if res and res.ok then start() else RPI.notify(res and res.error or 'Action impossible.', 'error') end
        end)
    else
        start()
    end
end

function Police.release()
    local d = dragging
    if not d then return end
    dragging = nil -- arrête aussi la boucle de suivi du PNJ (qui le relâche)
    RPI.cancelEmote()
    if d.serverId then RPI.request('drag', { target = d.serverId, drag = false }, function() end) end
end

-- Touche X (modifiable : Raccourcis clavier > FiveM) : lâcher le bras. Raccourci FiveM : aucune boucle.
RegisterCommand('rpi_release', function()
    if dragging and not RPI.busy() and not RPI.uiOpen() then Police.release() end
end, false)
RegisterKeyMapping('rpi_release', 'Police : lâcher le bras de l\'individu', 'keyboard', Config.DragReleaseKey or 'X')

--- Faire s'asseoir l'individu MENOTTÉ au sol ("/e menotté2") ou le faire se relever (à pied, pas tenu par le bras)
function Police.seat(ped, seated)
    if not RPI.isPolice() or not DoesEntityExist(ped) then return end
    if IsPedInAnyVehicle(ped, false) then return RPI.notify('L\'individu est dans un véhicule.', 'error') end
    if seated and not Police.isCuffed(ped) then return RPI.notify('L\'individu doit d\'abord être menotté.', 'error') end
    if seated and Police.isDragged(ped) then return RPI.notify('Lâchez d\'abord le bras de l\'individu.', 'error') end
    local serverId = serverIdOf(ped)
    if serverId then
        return RPI.request('seat', { target = serverId, seated = seated }, feedback(nil))
    end
    RPI.withControl(ped, function()
        if seated then
            prepareNpc(ped)
            npcSeated[ped] = true
            ClearPedTasks(ped)
            playPose(ped, true, true)
        else
            npcSeated[ped] = nil
            stopPose(ped, true)
            if npcCuffed[ped] ~= nil then playPose(ped, false, true) end
        end
    end)
end

-- Places arrière uniquement : siège 1 (portière arrière gauche), siège 2 (arrière droite)
local REAR = {
    { seat = 1, door = 2, bone = 'door_dside_r' },
    { seat = 2, door = 3, bone = 'door_pside_r' },
}

--- Place arrière libre la plus proche du policier (nil si aucune)
function Police.rearSeat(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) or GetVehicleMaxNumberOfPassengers(vehicle) < 3 then return nil end
    local origin = GetEntityCoords(PlayerPedId())
    local best, bestDistance
    for _, rear in ipairs(REAR) do
        if IsVehicleSeatFree(vehicle, rear.seat) then
            local bone = GetEntityBoneIndexByName(vehicle, rear.bone)
            local pos = bone ~= -1 and GetWorldPositionOfEntityBone(vehicle, bone) or GetEntityCoords(vehicle)
            local d = #(pos - origin)
            if not best or d < bestDistance then best, bestDistance = rear, d end
        end
    end
    return best
end

--- Individus assis à l'arrière
function Police.rearOccupants(vehicle)
    local list = {}
    for _, rear in ipairs(REAR) do
        local ped = GetPedInVehicleSeat(vehicle, rear.seat)
        if ped and ped ~= 0 then list[#list + 1] = { ped = ped, rear = rear } end
    end
    return list
end

--- Le policier ouvre la portière arrière la plus proche, lâche le bras, l'individu monte lui-même
function Police.placeInVehicle(vehicle)
    local d = dragging
    if not d or not RPI.isPolice() then return end
    local rear = Police.rearSeat(vehicle)
    if not rear then return RPI.notify('Aucune place libre à l\'arrière de ce véhicule.', 'error') end
    if d.serverId and not NetworkGetEntityIsNetworked(vehicle) then
        return RPI.notify('Ce véhicule n\'est pas synchronisé avec le serveur.', 'error')
    end
    RPI.withControl(vehicle, function() SetVehicleDoorOpen(vehicle, rear.door, false, false) end)
    dragging = nil
    RPI.cancelEmote()
    if d.serverId then
        RPI.request('putInVehicle', { target = d.serverId, netId = VehToNet(vehicle), seat = rear.seat }, feedback(nil))
    else
        npcSeated[d.ped] = nil
        RPI.withControl(d.ped, function()
            holdPed(d.ped, false)
            TaskEnterVehicle(d.ped, vehicle, 15000, rear.seat, 1.0, 1, 0)
        end)
    end
end

function Police.takeOut(vehicle)
    if not RPI.isPolice() then return end
    for _, occupant in ipairs(Police.rearOccupants(vehicle)) do
        RPI.withControl(vehicle, function() SetVehicleDoorOpen(vehicle, occupant.rear.door, false, false) end)
        local serverId = serverIdOf(occupant.ped)
        if serverId then
            RPI.request('takeOut', { target = serverId }, feedback(nil))
        else
            RPI.withControl(occupant.ped, function() TaskLeaveVehicle(occupant.ped, vehicle, 0) end)
        end
    end
end

-- =========================================================================
-- CIVIL (joueur) : menotté / tenu par le bras / placé dans un véhicule
-- =========================================================================
local cuffed, cuffProp, lastEmote = false, nil, 0
local seated = false -- assis au sol par un policier ("/e menotté2")
local draggedBy = nil
local entryAllowedUntil, entryAllowedVehicle = 0, nil -- portière ouverte par un policier (véhicule d'urgence)
local CUFF_BLOCKED = { 21, 22, 23, 24, 25, 37, 44, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264 }
local SEATED_BLOCKED = { 30, 31, 32, 33, 34, 35 } -- assis : pas de déplacement (il reste assis)

function RPI.isCuffed() return cuffed end
function RPI.isSeated() return seated end

--- Relance l'emote "menotté1" (ou "menotté2" si assis) : commande d'emote à pied ; animation directe
--- en véhicule / tenu par le bras ; si l'emote n'a rien donné, la MÊME animation (lue dans RPEMOTES),
--- jamais une autre.
local function reapplyCuffEmote(ped, sit, direct)
    local now = GetGameTimer()
    if direct then
        playPose(ped, false, true)
    elseif now - lastEmote > 4000 then
        RPI.playEmote(poseCommand(sit))
        lastEmote = now
    elseif now - lastEmote > 2500 then
        playPose(ped, sit, false)
    end
end

local function cuffLoop()
    CreateThread(function()
        local nextCheck = 0
        while cuffed do
            Wait(0)
            DisablePlayerFiring(PlayerId(), true)
            for _, control in ipairs(CUFF_BLOCKED) do DisableControlAction(0, control, true) end
            if seated then
                for _, control in ipairs(SEATED_BLOCKED) do DisableControlAction(0, control, true) end
            end
            local now = GetGameTimer()
            if now >= nextCheck then
                nextCheck = now + 1000
                local ped = PlayerPedId()
                local inVehicle = IsPedInAnyVehicle(ped, false)
                local direct = inVehicle or draggedBy ~= nil
                local sit = seated and not direct
                if not isPlayingPose(ped, sit, direct) and not dragWalking and not IsPedRagdoll(ped)
                    and not IsPedGettingIntoAVehicle(ped) and not IsEntityDead(ped) then
                    reapplyCuffEmote(ped, sit, direct)
                end
            end
        end
    end)
end

local function setCuffed(state)
    state = state == true
    if state == cuffed then return end
    cuffed = state
    local ped = PlayerPedId()
    if cuffed then
        lastEmote = 0
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
        CreateThread(function()
            local prop = attachCuffs(ped)
            if cuffed then cuffProp = prop else deleteProp(prop) end
        end)
        cuffLoop()
    else
        seated = false
        deleteProp(cuffProp)
        cuffProp = nil
        RPI.cancelEmote()
        stopPose(ped, false)
    end
end

RegisterNetEvent('rp_interact:client:setCuffed', setCuffed)

--- Assis au sol par un policier ("/e menotté2", menotté uniquement) / relevé ("/e menotté1")
local function setSeated(state)
    state = state == true and cuffed
    local ped = PlayerPedId()
    if state and IsPedInAnyVehicle(ped, false) then return end
    if state == seated then return end
    seated = state
    lastEmote = GetGameTimer()
    if seated then
        RPI.playEmote(Config.Emotes.seated)
    else
        RPI.playEmote(Config.Emotes.cuffed) -- debout, toujours menotté (remplace l'emote assise)
    end
end
RegisterNetEvent('rp_interact:client:setSeated', setSeated)

RegisterNetEvent('rp_interact:client:drag', function(policeSrc)
    local ped = PlayerPedId()
    if not policeSrc then
        draggedBy = nil
        holdPed(ped, false)
        return
    end
    local player = GetPlayerFromServerId(policeSrc)
    if player == -1 then return end
    seated = false -- relevé par le policier qui le prend par le bras
    draggedBy = policeSrc
    followLoop(ped, function()
        local p = GetPlayerFromServerId(policeSrc)
        return p ~= -1 and GetPlayerPed(p) or 0
    end, function() return draggedBy == policeSrc end, function()
        if draggedBy == policeSrc then draggedBy = nil end
    end, true)
end)

-- Placé à l'arrière par un policier (qui a ouvert la portière) : il y monte lui-même
RegisterNetEvent('rp_interact:client:enterVehicle', function(netId, seat)
    local vehicle = NetToVeh(netId)
    if not vehicle or vehicle == 0 then return end
    local ped = PlayerPedId()
    draggedBy, seated = nil, false
    holdPed(ped, false)
    entryAllowedUntil, entryAllowedVehicle = GetGameTimer() + 15000, vehicle -- /policeon : autorisé
    ClearPedTasks(ped)
    TaskEnterVehicle(ped, vehicle, 15000, seat, 1.0, 1, 0)
end)

RegisterNetEvent('rp_interact:client:leaveVehicle', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then TaskLeaveVehicle(ped, vehicle, 0) end
end)

-- Ressource redémarrée alors que le joueur était menotté
if LocalPlayer.state.rpiCuffed == true then
    seated = LocalPlayer.state.rpiSeated == true
    setCuffed(true)
end

-- =========================================================================
-- VÉHICULES D'URGENCE (classe 18) : /policeon, /policeoff
-- Règle activée, joueur NON policier qui essaie d'ouvrir une portière FERMÉE d'un véhicule d'urgence :
-- il va jusqu'à la portière, tire sur la poignée (LockedDoorAnim) et la portière reste fermée ;
-- aucun message. Rien n'est verrouillé sur le véhicule lui-même (un verrou est partagé par le réseau
-- et bloquait aussi les policiers) : seul le client du civil l'empêche de monter.
-- Autorisé : policier en service, portière déjà ouverte, individu placé par un policier (15 s).
-- Boucle (250 ms ; à chaque image pendant une tentative de montée) uniquement quand la règle est activée.
-- =========================================================================
local EMERGENCY_CLASS = 18
local DOOR_BONES = { [-1] = 'door_dside_f', [0] = 'door_pside_f', [1] = 'door_dside_r', [2] = 'door_pside_r' }
local HANDLE_RANGE = 1.4 -- m : le civil est arrêté à la poignée
local restriction = GlobalState.rpiPoliceVehicles == true
local restrictionRunning = false

local function doorForSeat(seat) return seat + 1 end -- siège -1 (conducteur) -> portière 0…

--- Véhicule d'urgence interdit à ce joueur (règle activée, pas policier) ?
function Police.restricted(vehicle)
    return restriction and not RPI.isPolice() and GetVehicleClass(vehicle) == EMERGENCY_CLASS
end

local function entryAllowed(vehicle)
    return vehicle == entryAllowedVehicle and GetGameTimer() <= entryAllowedUntil
end

--- Le civil tire sur la poignée : tentative arrêtée, portière refermée s'il avait commencé à l'ouvrir
local function refuseEntry(ped, vehicle, door)
    ClearPedTasks(ped)
    if GetVehicleDoorAngleRatio(vehicle, door) > 0.0 then
        RPI.withControl(vehicle, function() SetVehicleDoorShut(vehicle, door, false) end)
    end
    local anim = Config.LockedDoorAnim
    if anim then
        CreateThread(function() RPI.playAnimNow(ped, anim.dict, anim.clip, 1800, 0) end)
    end
end

local function startRestriction()
    if restrictionRunning then return end
    restrictionRunning = true
    CreateThread(function()
        local attempt, door, wasOpen = nil, nil, false
        while restriction do
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsTryingToEnter(ped)
            if vehicle == 0 or not DoesEntityExist(vehicle) or RPI.isPolice()
                or GetVehicleClass(vehicle) ~= EMERGENCY_CLASS or entryAllowed(vehicle) then
                attempt = nil
                Wait(250)
            else
                if attempt ~= vehicle then
                    -- Début de la tentative : portière déjà ouverte -> montée autorisée
                    local seat = GetSeatPedIsTryingToEnter(ped)
                    attempt = vehicle
                    door = { index = doorForSeat(seat), bone = DOOR_BONES[seat] or 'door_dside_f' }
                    wasOpen = GetVehicleDoorAngleRatio(vehicle, door.index) >= 0.1
                end
                if not wasOpen then
                    local bone = GetEntityBoneIndexByName(vehicle, door.bone)
                    local handle = bone ~= -1 and GetWorldPositionOfEntityBone(vehicle, bone) or GetEntityCoords(vehicle)
                    if #(GetEntityCoords(ped) - handle) <= HANDLE_RANGE or GetVehicleDoorAngleRatio(vehicle, door.index) > 0.02 then
                        refuseEntry(ped, vehicle, door.index)
                        attempt = nil
                        Wait(500)
                    end
                end
                Wait(0)
            end
        end
        restrictionRunning = false
    end)
end

AddStateBagChangeHandler('rpiPoliceVehicles', 'global', function(_, _, value)
    restriction = value == true
    if restriction then startRestriction() end
end)
if restriction then startRestriction() end

-- Version 1.3 : des véhicules d'urgence ont pu rester verrouillés pour ce joueur -> déverrouillés
CreateThread(function()
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if GetVehicleClass(vehicle) == EMERGENCY_CLASS then SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false) end
    end
end)

-- =========================================================================
-- SUPPRIMER (PNJ, véhicules sans joueur, objets ; y compris créés par des joueurs), jusqu'à 50 m
-- =========================================================================
function Police.canDelete()
    if LocalPlayer.state.rpiCanDelete == true or Config.DeleteAccess == 'everyone' then return true end
    return Config.DeleteAccess == 'police' and RPI.isPolice()
end

local function playerInside(vehicle)
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and IsPedAPlayer(ped) then return true end
    end
    return false
end

--- Élément supprimable ? (jamais un joueur, ni un véhicule occupé par un joueur ; les véhicules et
--- objets créés par des joueurs ou des scripts le sont)
function Police.deletable(ctx)
    if ctx.isSelf then return false end
    if ctx.type == 'ped' then return not ctx.isPlayer end
    if ctx.type == 'vehicle' then return not playerInside(ctx.entity) end
    return ctx.type == 'object'
end

--- Suppression par ce client : il prend le contrôle de l'entité (si elle est en réseau), puis la
--- supprime. done(true) si elle a disparu.
local function deleteLocally(entity, done)
    RPI.withControl(entity, function()
        local networked = NetworkGetEntityIsNetworked(entity)
        if DoesEntityExist(entity) and (not networked or NetworkHasControlOfEntity(entity)) then
            if IsEntityAttached(entity) then DetachEntity(entity, true, false) end
            SetEntityAsMissionEntity(entity, true, true)
            DeleteEntity(entity)
            if DoesEntityExist(entity) then
                local kind = GetEntityType(entity)
                if kind == 2 then DeleteVehicle(entity) elseif kind == 3 then DeleteObject(entity) else DeletePed(entity) end
            end
        end
        if done then done(not DoesEntityExist(entity)) end
    end)
end

local function deleted(ok)
    if ok then
        RPI.notify('Élément supprimé.', 'success')
    else
        RPI.notify('Suppression impossible : l\'élément est protégé par le script qui l\'a créé.', 'error')
    end
end

--- Entité en réseau : le serveur la supprime pour tout le monde (OneSync), même si elle a été créée
--- par un autre joueur ; vérification, puis suppression par ce client si elle est encore là.
--- Objet de la carte (pas en réseau, pas créé par un script) : masqué chez tous les joueurs.
function Police.delete(ctx)
    local entity = ctx.entity
    if ctx.netId then
        RPI.request('deleteEntity', { netId = ctx.netId }, function(res)
            if res and not res.ok and not res.fallback then
                return RPI.notify(res.error or 'Suppression impossible.', 'error')
            end
            SetTimeout(res and res.ok and 1000 or 0, function() -- suppression serveur reçue par ce client
                if not DoesEntityExist(entity) then return deleted(true) end
                deleteLocally(entity, deleted)
            end)
        end)
    elseif ctx.type == 'object' and not IsEntityAMissionEntity(entity) then
        local c = GetEntityCoords(entity)
        RPI.request('hideProp', { model = ctx.model, x = c.x, y = c.y, z = c.z }, function(res)
            if res and res.ok then return deleted(true) end
            RPI.notify(res and res.error or 'Suppression impossible.', 'error')
        end)
    else
        deleteLocally(entity, deleted) -- entité propre à ce client
    end
end

local function hideProp(prop)
    CreateModelHideExcludingScriptObjects(prop.x, prop.y, prop.z, 1.0, prop.model, true)
end
RegisterNetEvent('rp_interact:client:hideProp', hideProp)
RegisterNetEvent('rp_interact:client:showProps', function(list)
    for _, prop in ipairs(list or {}) do RemoveModelHide(prop.x, prop.y, prop.z, 1.0, prop.model, false) end
end)
-- Objets déjà masqués (connexion / redémarrage de la ressource)
CreateThread(function()
    Wait(2000)
    RPI.request('getHiddenProps', {}, function(res)
        for _, prop in ipairs(res and res.props or {}) do hideProp(prop) end
    end)
end)

-- =========================================================================
-- MENU D'INTERACTIONS > POLICE : actions toujours affichées, grisées si personne n'est assez proche.
-- État envoyé au menu toutes les 300 ms, uniquement pendant que la vue Police est ouverte.
-- =========================================================================
local menuView = nil

local function menuState()
    local onDuty = RPI.isPolice()
    local ped = Police.closestPed(Config.ActionDistance)
    local vehicle = dragging and Police.closestVehicle(Config.PlaceVehicleDistance) or nil
    local pedCuffed = ped and Police.isCuffed(ped) or false
    return {
        onDuty = onDuty,
        cuff = { enabled = onDuty and ped ~= nil, label = pedCuffed and 'Retirer les menottes' or 'Menotter' },
        drag = { enabled = onDuty and (dragging ~= nil or ped ~= nil), label = dragging and 'Lâcher le bras' or 'Prendre par le bras' },
        place = { enabled = onDuty and vehicle ~= nil and Police.rearSeat(vehicle) ~= nil },
        seat = { enabled = onDuty and ped ~= nil and pedCuffed and not Police.isDragged(ped),
                 label = ped and Police.isSeated(ped) and 'Faire se relever l\'individu' or 'Faire s\'asseoir l\'individu' },
    }
end

local function startMenuLoop()
    CreateThread(function()
        local last = ''
        while menuView == 'police' and RPI.uiOpen('menu') do
            local state = menuState()
            local key = json.encode(state)
            if key ~= last then
                last = key
                SendNUIMessage({ action = 'menuActions', data = state })
            end
            Wait(300)
        end
    end)
end

RegisterNUICallback('menuView', function(data, cb)
    local view = type(data) == 'table' and data.view or nil
    local wasPolice = menuView == 'police'
    menuView = view
    if view == 'police' and not wasPolice then startMenuLoop() end
    cb({ ok = true })
end)

RegisterNUICallback('policeAction', function(data, cb)
    cb({ ok = true })
    local action = type(data) == 'table' and data.action or nil
    if not RPI.isPolice() then return RPI.notify('Réservé à la police : rejoignez une unité dans le MDC.', 'error') end
    menuView = nil
    RPI.closeMenu()
    if action == 'drag' and dragging then return Police.release() end
    if action == 'place' then
        local vehicle = Police.closestVehicle(Config.PlaceVehicleDistance)
        if not vehicle then return RPI.notify('Aucun véhicule à proximité.', 'error') end
        return Police.placeInVehicle(vehicle)
    end
    local ped = Police.closestPed(Config.ActionDistance)
    if not ped then return RPI.notify('Personne à moins de 2 m.', 'error') end
    if action == 'cuff' then
        Police.cuff(ped, not Police.isCuffed(ped))
    elseif action == 'drag' then
        Police.drag(ped)
    elseif action == 'seat' then
        Police.seat(ped, not Police.isSeated(ped))
    end
end)
