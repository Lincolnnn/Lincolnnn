--[[
    RP Interact - Actions de police et véhicules d'urgence
    ------------------------------------------------------
    POLICIER (joueur dans une unité du MDC), par l'œil ou par le menu d'interactions :
      - Menotter (2 m autour du policier, 7 s) / Retirer les menottes (3 s)
      - Prendre par le bras (individu le plus proche, 2 m) : le policier fait "/e tenirlebras",
        l'individu est tenu de force à sa droite (accroché à son centre : il reste droit) et le suit
        (marcher, trottiner, gauche, droite) ; le policier ne peut pas sprinter ; X : lâcher le bras
      - Placer l'individu tenu à l'arrière d'un véhicule : le policier va ouvrir lui-même la portière
        arrière la plus proche et lâche le bras ; l'individu y monte lui-même (sans téléportation) et
        laisse la portière ouverte (le policier la referme avec l'œil)
      - Faire sortir l'individu (places arrière) : le policier ouvre la portière, l'individu descend et
        la laisse ouverte
      - Faire s'asseoir l'individu MENOTTÉ au sol ("/e menotté2") / le faire se relever
    Tout fonctionne aussi sur les PNJ (tests en solo) : le client du policier les pilote directement.

    CIVIL menotté : comportement de base de GTA 5 (aucune emote) : menottes du jeu (SetEnableHandcuffs)
    + animation "mains dans le dos" (CuffAnim) + menottes aux poignets ; si l'animation s'arrête
    (bousculé, monté dans un véhicule…), elle est relancée automatiquement. Assis au sol : emote
    "/e menotté2" du mode d'emotes du serveur (RPEMOTES), dont l'animation exacte y est lue
    (server/emotes.lua), pour ne jamais rejouer une autre animation que celle de l'emote.


    Performance : boucles actives uniquement pendant qu'on est menotté, tenu par le bras, qu'on tient
    quelqu'un ou que des PNJ sont menottés.
]]

local Config = InteractConfig
local CUFF_ANIM_POLICE = { 'mp_arresting', 'a_uncuff', 49 }
local LEFT_HAND = 60309

local Police = {}
RPI.Police = Police

-- =========================================================================
-- OUTILS
-- =========================================================================
-- Postures de l'individu menotté : debout (animation de base du jeu, CuffAnim, jamais d'emote) ou
-- assis au sol ("/e menotté2")
local function poseCommand() return Config.Emotes.seated end
local function poseFallback(sit) return sit and Config.SeatedAnim or Config.CuffAnim end

--- Animation de la posture. Debout : toujours CuffAnim. Assis : celle de l'emote (lue dans RPEMOTES) ;
--- `direct` (PNJ : pas de commande d'emote possible) : toujours une animation, au besoin celle de secours.
local function poseAnim(sit, direct)
    if not sit then
        local a = Config.CuffAnim
        return { dict = a.dict, clip = a.clip, flag = a.flag or 49 }
    end
    local anim = RPI.emoteAnim(poseCommand(), poseFallback(sit))
    if anim and anim.scenario and direct then anim = nil end
    if not anim and direct then
        local fb = poseFallback(sit)
        anim = { dict = fb.dict, clip = fb.clip, flag = fb.flag }
    end
    return anim
end

local function isPlayingPose(ped, sit, direct)
    if direct or not sit then
        local anim = poseAnim(sit, true)
        return IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3)
    end
    return RPI.isPlayingEmote(ped, poseCommand(), poseFallback(sit))
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
--- Position / orientation des menottes sur le poignet (Config.CuffPropPlacement)
local CUFF_PLACE = Config.CuffPropPlacement or { bone = LEFT_HAND, x = -0.055, y = 0.06, z = 0.04, rx = 265.0, ry = 155.0, rz = 80.0 }

local function attachCuffs(ped)
    local model = GetHashKey(Config.CuffProp)
    if not IsModelInCdimage(model) or not RPI.loadModel(model) then return nil end
    local c = GetEntityCoords(ped)
    local prop = CreateObject(model, c.x, c.y, c.z, true, true, false)
    local p = CUFF_PLACE
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, p.bone or LEFT_HAND), p.x, p.y, p.z, p.rx, p.ry, p.rz,
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

--- Menottes du jeu (comportement de base de GTA 5 d'un personnage menotté). Retirées le temps de
--- monter / descendre d'un véhicule (le jeu l'empêcherait), remises ensuite par la boucle.
local function handcuffs(ped, on)
    if DoesEntityExist(ped) then SetEnableHandcuffs(ped, on == true) end
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
-- INDIVIDU TENU PAR LE BRAS : tenu DE FORCE, accroché au policier au même endroit qu'avant (DragOffset : à sa
-- droite, un peu devant ; accroche synchronisée par le jeu, sans à-coups chez tout le monde). Il est accroché au
-- CENTRE du policier (index d'os -1), jamais à un os : il garde son propre axe, toujours droit, et ne suit ni le
-- tronc ni les animations du policier (avant : accroché à l'os racine, il basculait dans le policier quand celui-ci
-- se penchait). Il suit ses déplacements : marcher, trottiner (le policier ne peut pas sprinter en le tenant),
-- aller à gauche, à droite, reculer ; ses jambes jouent l'animation qui correspond à SON déplacement réel
-- (DragMoves). Menotté : mains dans le dos (animation des menottes, haut du corps). Pas menotté : rien d'autre.
-- Le civil (joueur) ne peut pas se déplacer lui-même pendant ce temps (il peut se débattre, voir plus bas).
-- Policier au sol (ragdoll) : décroché le temps qu'il se relève, puis raccroché.
-- Boucle UNIQUEMENT pendant qu'il est tenu (à chaque image pour le civil lui-même, 100 ms pour un PNJ).
-- =========================================================================
local DRAG_BLOCKED = { 21, 22, 23, 30, 31, 32, 33, 34, 35, 36, 44, 75 } -- sprint, saut, véhicule, déplacements, couvert
local HOLDER_BLOCKED = { 21, 22, 44 } -- le policier qui tient quelqu'un : ni sprint, ni saut, ni couvert
local ATTACH_CENTRE = -1 -- pas un os : le centre du policier (matrice toujours droite)

--- Lâché : décroché, collisions et position rendues
local function holdPed(ped, held)
    if not DoesEntityExist(ped) or held then return end
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
end

--- Déplacement (m/s) dans le repère de l'individu -> allure ('walk' / 'trot') et sens, ou nil à l'arrêt.
--- Sens : avant, gauche, droite, arrière (le sens actuel est gardé près des limites : pas de clignotement).
local function pickMove(lx, ly, current)
    local M = Config.DragMove or {}
    local speed = math.sqrt(lx * lx + ly * ly)
    if speed < (M.Idle or 0.35) then return nil end
    local angle = math.deg(math.atan(-lx, ly)) -- 0 : devant, positif : à gauche
    local keep = current and 12 or 0
    local dir
    if current == 'forward' and math.abs(angle) <= 50 + keep then dir = 'forward'
    elseif current == 'back' and math.abs(angle) >= 130 - keep then dir = 'back'
    elseif current == 'left' and angle > 50 - keep and angle < 130 + keep then dir = 'left'
    elseif current == 'right' and angle < -50 + keep and angle > -130 - keep then dir = 'right'
    elseif math.abs(angle) <= 50 then dir = 'forward'
    elseif math.abs(angle) >= 130 then dir = 'back'
    elseif angle > 0 then dir = 'left'
    else dir = 'right' end
    return speed >= (M.Trot or 2.6) and 'trot' or 'walk', dir
end

--- Animation des jambes pour une allure et un sens (menotté vers l'avant : la marche menottée du jeu)
local function moveAnim(gait, dir, cuffedNow)
    local moves = Config.DragMoves or {}
    if cuffedNow and dir == 'forward' and moves.cuffed and moves.cuffed[gait] then return moves.cuffed[gait] end
    return moves[gait] and moves[gait][dir]
end

--- `ped` est accroché au policier et ses jambes suivent ses déplacements
local function holdLoop(ped, getPolicePed, isActive, onEnd, isSelf, isCuffedFn)
    CreateThread(function()
        local o = Config.DragOffset
        local cuffAnim = Config.CuffAnim
        local attachedTo, playing, moveKey = nil, nil, nil
        local lastPos, lastAt, nextMove = nil, 0, 0
        local function stopMove()
            if playing and DoesEntityExist(ped) then StopAnimTask(ped, playing[1], playing[2], 2.0) end
            playing, moveKey = nil, nil
        end
        while isActive() do
            local policePed = getPolicePed()
            if not policePed or policePed == 0 or not DoesEntityExist(ped) or IsEntityDead(policePed)
                or IsPedInAnyVehicle(policePed, false) or IsPedInAnyVehicle(ped, false) then
                break
            end
            if isSelf then
                for _, control in ipairs(DRAG_BLOCKED) do DisableControlAction(0, control, true) end
            end
            if not isSelf and not NetworkHasControlOfEntity(ped) then
                NetworkRequestControlOfEntity(ped)
            elseif IsPedRagdoll(policePed) or IsPedRagdoll(ped) then
                -- policier (ou individu) au sol : décroché le temps de se relever, puis raccroché
                if attachedTo then
                    stopMove()
                    holdPed(ped, false)
                    attachedTo = nil
                end
            else
                if attachedTo ~= policePed or not IsEntityAttachedToEntity(ped, policePed) then
                    if IsEntityAttached(ped) then DetachEntity(ped, false, false) end
                    FreezeEntityPosition(ped, false)
                    ClearPedTasks(ped)
                    AttachEntityToEntity(ped, policePed, ATTACH_CENTRE, o.x, o.y, o.z, 0.0, 0.0, 0.0,
                        false, false, false, false, 2, true)
                    attachedTo, lastPos = policePed, nil
                    stopMove()
                end
                local now = GetGameTimer()
                if now >= nextMove then
                    nextMove = now + 100
                    -- son déplacement réel (le policier avance, recule, va de côté ou tourne) dans son propre repère
                    local pos = GetEntityCoords(ped)
                    local gait, dir
                    if lastPos and now > lastAt then
                        local dt = (now - lastAt) / 1000.0
                        local dx, dy = (pos.x - lastPos.x) / dt, (pos.y - lastPos.y) / dt
                        local h = math.rad(GetEntityHeading(ped))
                        local fx, fy = -math.sin(h), math.cos(h)
                        gait, dir = pickMove(dx * fy - dy * fx, dx * fx + dy * fy, moveKey and moveKey.dir)
                    end
                    lastPos, lastAt = pos, now
                    local cuffedNow = isCuffedFn and isCuffedFn() or false
                    local anim = gait and moveAnim(gait, dir, cuffedNow)
                    if not anim then
                        stopMove()
                    elseif not playing or playing[1] ~= anim[1] or playing[2] ~= anim[2]
                        or not IsEntityPlayingAnim(ped, anim[1], anim[2], 3) then
                        if RPI.loadAnim(anim[1]) then
                            TaskPlayAnim(ped, anim[1], anim[2], 3.0, -3.0, -1, 1, 0.0, false, false, false)
                            playing = anim
                        end
                    end
                    moveKey = gait and { gait = gait, dir = dir } or nil
                    -- menotté : mains dans le dos (haut du corps) ; sinon rien d'imposé
                    if cuffedNow and not IsEntityPlayingAnim(ped, cuffAnim.dict, cuffAnim.clip, 3) then
                        RPI.playAnimNow(ped, cuffAnim.dict, cuffAnim.clip, -1, cuffAnim.flag or 49)
                    end
                end
            end
            Wait(isSelf and 0 or 100)
        end
        stopMove()
        holdPed(ped, false)
        if onEnd then onEnd() end
    end)
end

--- Le policier qui tient quelqu'un : ni sprint (il trottine au plus), ni saut, ni couvert. Seulement pendant ce temps.
local holderLoopOn = false
local function holderLoop(isHolding)
    if holderLoopOn then return end
    holderLoopOn = true
    CreateThread(function()
        while isHolding() do
            for _, control in ipairs(HOLDER_BLOCKED) do DisableControlAction(0, control, true) end
            Wait(0)
        end
        holderLoopOn = false
    end)
end

-- =========================================================================
-- PNJ (tests en solo) : menottés / tenus par ce policier
-- =========================================================================
local npcCuffed = {} -- [ped] = prop des menottes (false en attendant)
local npcSeated = {} -- [ped] = true : PNJ assis par ce policier
local npcMoving = {} -- [ped] = heure de fin : PNJ qui monte / descend d'un véhicule (menottes du jeu retirées)
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
                    npcCuffed[ped], npcMoving[ped] = nil, nil
                elseif (npcMoving[ped] or 0) < GetGameTimer()
                    and not isPlayingPose(ped, npcSeated[ped], true) and not IsPedRagdoll(ped) and not IsPedGettingIntoAVehicle(ped)
                    and not Police.isDragged(ped) and not IsPedInAnyVehicle(ped, false) then
                    if NetworkHasControlOfEntity(ped) then
                        handcuffs(ped, true)
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
        handcuffs(ped, true)
        CreateThread(function()
            playPose(ped, false, true)
            local prop = attachCuffs(ped)
            if npcCuffed[ped] == false then npcCuffed[ped] = prop or false else deleteProp(prop) end
        end)
        startNpcLoop()
    else
        deleteProp(npcCuffed[ped])
        npcCuffed[ped] = nil
        npcSeated[ped], npcMoving[ped] = nil, nil
        handcuffs(ped, false)
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
        holdLoop(ped, PlayerPedId, function() return dragging ~= nil and dragging.ped == ped end, function()
            if dragging and dragging.ped == ped then dragging = nil end
        end, false, function() return npcCuffed[ped] ~= nil end)
    end)
end

function Police.drag(ped)
    if not RPI.isPolice() or not DoesEntityExist(ped) then return end
    if dragging then return Police.release() end
    local target = { ped = ped, serverId = serverIdOf(ped) }
    local function start()
        dragging = target
        RPI.playEmote(Config.Emotes.drag)
        holderLoop(function() return dragging ~= nil end)
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

-- Flags de TaskEnterVehicle / TaskLeaveVehicle : 1 = reprendre si interrompu, 256 = ne pas refermer la
-- portière (le policier la referme lui-même avec l'œil)
local ENTER_FLAGS, LEAVE_FLAGS = 1 | 256, 256

--- Le policier va ouvrir lui-même la portière (animation du jeu) ; à appeler dans un thread.
--- Portière déjà ouverte : rien à faire. Échec (véhicule verrouillé, bloqué…) : ouverte directement.
local function officerOpenDoor(vehicle, seat, door)
    if GetVehicleDoorAngleRatio(vehicle, door) < 0.5 then
        local ped = PlayerPedId()
        TaskOpenVehicleDoor(ped, vehicle, 8000, seat, 1.0)
        local timeout = GetGameTimer() + 8000
        while GetGameTimer() < timeout and GetVehicleDoorAngleRatio(vehicle, door) < 0.5 do Wait(100) end
        if GetVehicleDoorAngleRatio(vehicle, door) < 0.5 then
            RPI.withControl(vehicle, function() SetVehicleDoorOpen(vehicle, door, false, false) end)
            Wait(300)
        end
    end
end

--- Le policier ouvre lui-même la portière arrière la plus proche, lâche le bras, l'individu monte
--- seul (sans téléportation) et laisse la portière ouverte : le policier la referme avec l'œil
function Police.placeInVehicle(vehicle)
    local d = dragging
    if not d or not RPI.isPolice() then return end
    local rear = Police.rearSeat(vehicle)
    if not rear then return RPI.notify('Aucune place libre à l\'arrière de ce véhicule.', 'error') end
    if d.serverId and not NetworkGetEntityIsNetworked(vehicle) then
        return RPI.notify('Ce véhicule n\'est pas synchronisé avec le serveur.', 'error')
    end
    CreateThread(function()
        RPI.cancelEmote() -- "tenir le bras" arrêté pendant qu'il ouvre (l'individu le suit toujours)
        officerOpenDoor(vehicle, rear.seat, rear.door)
        if dragging ~= d then return end -- lâché entre-temps
        dragging = nil
        if d.serverId then
            RPI.request('putInVehicle', { target = d.serverId, netId = VehToNet(vehicle), seat = rear.seat }, feedback(nil))
        else
            npcSeated[d.ped] = nil
            RPI.withControl(d.ped, function()
                holdPed(d.ped, false)
                npcMoving[d.ped] = GetGameTimer() + 15000
                handcuffs(d.ped, false) -- le jeu empêche un personnage menotté de monter
                TaskEnterVehicle(d.ped, vehicle, 15000, rear.seat, 1.0, ENTER_FLAGS, 0)
            end)
        end
    end)
end

--- Faire sortir : le policier ouvre lui-même chaque portière arrière occupée, l'individu descend et
--- laisse la portière ouverte (le policier la referme avec l'œil)
function Police.takeOut(vehicle)
    if not RPI.isPolice() then return end
    CreateThread(function()
        for _, occupant in ipairs(Police.rearOccupants(vehicle)) do
            officerOpenDoor(vehicle, occupant.rear.seat, occupant.rear.door)
            local serverId = serverIdOf(occupant.ped)
            if serverId then
                RPI.request('takeOut', { target = serverId }, feedback(nil))
            else
                RPI.withControl(occupant.ped, function()
                    npcMoving[occupant.ped] = GetGameTimer() + 5000
                    handcuffs(occupant.ped, false) -- remises par la boucle des PNJ une fois descendu
                    TaskLeaveVehicle(occupant.ped, vehicle, LEAVE_FLAGS)
                end)
            end
        end
    end)
end

-- =========================================================================
-- CIVIL (joueur) : menotté / tenu par le bras / placé dans un véhicule
-- =========================================================================
local cuffed, cuffProp, lastEmote = false, nil, 0
local seated = false -- assis au sol par un policier ("/e menotté2")
local draggedBy = nil
-- Monte ('enter') / descend ('leave') d'un véhicule : menottes du jeu retirées le temps du mouvement
local vehicleMove = { kind = nil, untilTime = 0 }
local CUFF_BLOCKED = { 21, 22, 23, 24, 25, 37, 44, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264 }
local SEATED_BLOCKED = { 30, 31, 32, 33, 34, 35 } -- assis : pas de déplacement (il reste assis)

function RPI.isCuffed() return cuffed end
function RPI.isSeated() return seated end

--- Relance la posture : debout (ou en véhicule, tenu par le bras), l'animation de base du jeu ; assis,
--- l'emote "menotté2" et, si elle n'a rien donné, la MÊME animation (lue dans RPEMOTES), jamais une autre.
local function reapplyCuffEmote(ped, sit, direct)
    local now = GetGameTimer()
    if direct or not sit then
        playPose(ped, false, true)
    elseif now - lastEmote > 4000 then
        RPI.playEmote(poseCommand())
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
                local posed = isPlayingPose(ped, sit, direct)
                -- Menottes du jeu, sauf pendant qu'il monte / descend d'un véhicule (placé, sorti)
                if vehicleMove.kind then
                    local arrived = (vehicleMove.kind == 'enter' and inVehicle and not IsPedGettingIntoAVehicle(ped))
                        or (vehicleMove.kind == 'leave' and not inVehicle)
                    if arrived or now > vehicleMove.untilTime then vehicleMove.kind = nil end
                end
                handcuffs(ped, vehicleMove.kind == nil)
                if not posed and not IsPedRagdoll(ped)
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
        handcuffs(ped, true)
        if not seated then CreateThread(function() playPose(ped, false, true) end) end -- sans attendre la boucle
        cuffLoop()
    else
        if seated then RPI.cancelEmote() end -- emote assise ; debout : aucune emote à arrêter
        seated = false
        vehicleMove.kind = nil
        handcuffs(ped, false)
        deleteProp(cuffProp)
        cuffProp = nil
        stopPose(ped, false)
    end
end

RegisterNetEvent('rp_interact:client:setCuffed', setCuffed)

--- Assis au sol par un policier ("/e menotté2", menotté uniquement) / relevé (posture menotté du jeu)
local function setSeated(state)
    state = state == true and cuffed
    local ped = PlayerPedId()
    if state and IsPedInAnyVehicle(ped, false) then return end
    if state == seated then return end
    seated = state
    lastEmote = GetGameTimer()
    if seated then
        stopPose(ped, false)
        RPI.playEmote(Config.Emotes.seated)
    else
        RPI.cancelEmote() -- arrête l'emote assise : debout, toujours menotté
        CreateThread(function() playPose(ped, false, true) end)
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
    if seated then RPI.cancelEmote() end
    seated = false -- relevé par le policier qui le prend par le bras
    draggedBy = policeSrc
    holdLoop(ped, function()
        local p = GetPlayerFromServerId(policeSrc)
        return p ~= -1 and GetPlayerPed(p) or 0
    end, function() return draggedBy == policeSrc end, function()
        if draggedBy == policeSrc then draggedBy = nil end
    end, true, function() return cuffed end)
    Police.struggleWatch(policeSrc)
end)

-- =========================================================================
-- SE DÉBATTRE (civil tenu par le bras SANS menottes) : touche Struggle.Key (Espace) à marteler. Chaque appui
-- remplit la jauge (qui redescend toute seule) et fait trembler l'écran du civil et du policier ; jauge pleine :
-- le serveur décide (seul face au policier : il se dégage ; un autre policier déjà là : 85 % de chances de
-- perdre ; un autre policier qui arrive pendant qu'il se débat : perdu). Perdu : plus possible tant qu'il est tenu.
-- Boucle de 50 ms seulement pendant qu'il est tenu sans menottes.
-- =========================================================================
local ST = Config.Struggle or {}
local struggle = nil -- { police, gauge, lost, sentAt, done }

local function shake(amount)
    ShakeGameplayCam(ST.Shake or 'JOLT_SHAKE', amount or ST.ShakeAmount or 0.35)
end

local function struggleUi(data)
    SendNUIMessage({ action = 'struggle', data = data })
end

function Police.struggleWatch(policeSrc)
    if ST.Enabled == false then return end
    local s = { police = policeSrc, gauge = 0.0, lost = false, sentAt = 0, done = false }
    struggle = s
    CreateThread(function()
        local shown = nil
        while struggle == s and draggedBy == policeSrc do
            local can = not cuffed and not s.lost and not s.done
            if can then
                s.gauge = math.max(0.0, s.gauge - (ST.Decay or 22.0) * 0.05)
                local key = ST.KeyLabel or 'ESPACE'
                struggleUi({ show = true, role = 'civil', value = s.gauge, key = key })
                shown = true
            elseif shown then
                struggleUi({ show = false })
                shown = nil
            end
            Wait(50)
        end
        if struggle == s then struggle = nil end
        struggleUi({ show = false })
    end)
end

RegisterCommand('rpi_struggle', function()
    local s = struggle
    if not s or s.lost or s.done or cuffed or draggedBy ~= s.police then return end
    s.gauge = math.min(100.0, s.gauge + (ST.Gain or 9.0))
    shake()
    local now = GetGameTimer()
    if now - s.sentAt >= 150 then
        s.sentAt = now
        RPI.request('struggle', {}, function(res)
            if res and res.lost then s.lost = true end
        end)
    end
    if s.gauge >= 100.0 and not s.done then
        s.done = true
        RPI.request('struggleEscape', {}, function(res)
            if not (res and res.ok) then
                s.lost = s.lost or (res and res.lost) or false
                if not s.lost then s.done, s.gauge = false, 60.0 end -- refus sans verdict : il peut continuer
            end
        end)
    end
end, false)
RegisterKeyMapping('rpi_struggle', 'Civil : se débattre (tenu par le bras, sans menottes)', 'keyboard', ST.Key or 'SPACE')

-- Policier : l'individu qu'il tient se débat (écran qui tremble, message)
RegisterNetEvent('rp_interact:client:struggleShake', function()
    shake(ST.PoliceShakeAmount or 0.25)
    struggleUi({ show = true, role = 'police', until_ = 1200 })
end)

-- Fin du débattement : 'escaped' (dégagé), 'lost' (civil : perdu), 'held' (policier : il a cessé)
RegisterNetEvent('rp_interact:client:struggleEnd', function(result, role)
    struggleUi({ show = false })
    if result == 'escaped' then
        if role == 'police' then
            if dragging then
                dragging = nil
                RPI.cancelEmote()
            end
            RPI.notify('L\'individu s\'est dégagé !', 'error')
        else
            shake(0.5)
            RPI.notify('Vous vous êtes dégagé !', 'success')
        end
    elseif result == 'lost' then
        if struggle then struggle.lost = true end
        shake(0.6)
        RPI.notify('Vous n\'arrivez pas à vous dégager.', 'error')
    elseif result == 'held' then
        RPI.notify('L\'individu a cessé de se débattre.', 'success')
    end
end)

-- Placé à l'arrière par un policier (qui a ouvert la portière) : il y monte lui-même
RegisterNetEvent('rp_interact:client:enterVehicle', function(netId, seat)
    local vehicle = NetToVeh(netId)
    if not vehicle or vehicle == 0 then return end
    local ped = PlayerPedId()
    draggedBy, seated = nil, false
    holdPed(ped, false)
    ClearPedTasks(ped)
    vehicleMove.kind, vehicleMove.untilTime = 'enter', GetGameTimer() + 15000
    handcuffs(ped, false) -- le jeu empêche un personnage menotté de monter : remises une fois à bord
    TaskEnterVehicle(ped, vehicle, 15000, seat, 1.0, ENTER_FLAGS, 0) -- sans refermer la portière
end)

-- Le policier a ouvert la portière : l'individu descend sans la refermer
RegisterNetEvent('rp_interact:client:leaveVehicle', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        vehicleMove.kind, vehicleMove.untilTime = 'leave', GetGameTimer() + 5000
        handcuffs(ped, false) -- remises une fois descendu
        TaskLeaveVehicle(ped, vehicle, LEAVE_FLAGS)
    end
end)

-- Ressource redémarrée alors que le joueur était menotté
if LocalPlayer.state.rpiCuffed == true then
    seated = LocalPlayer.state.rpiSeated == true
    setCuffed(true)
end

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
