--[[
    RP Interact - Actions de police et véhicules d'urgence
    ------------------------------------------------------
    POLICIER (joueur dans une unité du MDC), par l'œil ou par le menu d'interactions :
      - Menotter (2 m autour du policier, 7 s) / Retirer les menottes (3 s)
      - Prendre par le bras (individu le plus proche, 2 m) : le policier fait "/e tenirlebras",
        l'individu est placé devant à droite et marche quand le policier marche
      - Placer l'individu tenu à l'arrière d'un véhicule : le policier ouvre la portière arrière la plus
        proche et lâche le bras ; l'individu y monte lui-même (sans téléportation)
      - Faire sortir l'individu (places arrière)
    Tout fonctionne aussi sur les PNJ (tests en solo) : le client du policier les pilote directement.

    CIVIL menotté : emote "/e menotté1" + menottes aux poignets ; si l'emote s'arrête (bousculé,
    monté dans un véhicule, touche…), elle est relancée automatiquement.

    VÉHICULES D'URGENCE (/policeon, /policeoff) : seuls les policiers montent dans un véhicule de
    classe 18 (portière déjà ouverte : tout le monde).

    Performance : boucles actives uniquement pendant qu'on est menotté, tenu par le bras, qu'on tient
    quelqu'un, que des PNJ sont menottés, ou que la règle des véhicules d'urgence est activée.
]]

local Config = InteractConfig
local CUFF = Config.CuffAnim
local WALK = { 'move_m@generic', 'walk' } -- marche de l'individu tenu par le bras
local CUFF_ANIM_POLICE = { 'mp_arresting', 'a_uncuff', 49 }
local PELVIS = 11816
local LEFT_HAND = 60309

local Police = {}
RPI.Police = Police

-- =========================================================================
-- OUTILS
-- =========================================================================
local function isPlayingCuff(ped)
    return IsEntityPlayingAnim(ped, CUFF.dict, CUFF.clip, 3)
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
-- =========================================================================
local function attachToPolice(ped, policePed)
    local o = Config.DragOffset
    AttachEntityToEntity(ped, policePed, GetPedBoneIndex(policePed, PELVIS), o.x, o.y, o.z, 0.0, 0.0, 0.0,
        false, false, false, false, 2, true)
end

local dragWalking = false -- civil local tenu par le bras en train de marcher (pas de relance des menottes)

--- Fait marcher `ped` quand le policier marche, et s'arrêter quand il s'arrête
local function followLoop(ped, getPolicePed, isActive, onEnd, isSelf)
    CreateThread(function()
        local walking = false
        while isActive() do
            Wait(100)
            local policePed = getPolicePed()
            if not policePed or policePed == 0 or not DoesEntityExist(ped) or IsEntityDead(policePed)
                or IsPedInAnyVehicle(policePed, false) then
                break
            end
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
        if walking and DoesEntityExist(ped) then StopAnimTask(ped, WALK[1], WALK[2], 1.0) end
        if isSelf then dragWalking = false end
        if DoesEntityExist(ped) and IsEntityAttached(ped) then DetachEntity(ped, true, false) end
        if onEnd then onEnd() end
    end)
end

-- =========================================================================
-- PNJ (tests en solo) : menottés / tenus par ce policier
-- =========================================================================
local npcCuffed = {} -- [ped] = prop des menottes (false en attendant)
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
                elseif not isPlayingCuff(ped) and not IsPedRagdoll(ped) and not IsPedGettingIntoAVehicle(ped)
                    and not IsEntityAttached(ped) then
                    if NetworkHasControlOfEntity(ped) then
                        RPI.playAnimNow(ped, CUFF.dict, CUFF.clip, -1, 49)
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
            RPI.playAnimNow(ped, CUFF.dict, CUFF.clip, -1, 49)
            local prop = attachCuffs(ped)
            if npcCuffed[ped] == false then npcCuffed[ped] = prop or false else deleteProp(prop) end
        end)
        startNpcLoop()
    else
        deleteProp(npcCuffed[ped])
        npcCuffed[ped] = nil
        if DoesEntityExist(ped) then
            StopAnimTask(ped, CUFF.dict, CUFF.clip, 1.0)
            SetBlockingOfNonTemporaryEvents(ped, false)
        end
    end
    if NetworkGetEntityIsNetworked(ped) then Entity(ped).state:set('rpiCuffed', cuffed, true) end
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
local dragging = nil -- { ped, serverId } : individu tenu par le bras

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
        attachToPolice(ped, PlayerPedId())
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
        ExecuteCommand(Config.Emotes.drag)
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
    dragging = nil -- arrête aussi la boucle de marche du PNJ (qui le détache)
    ExecuteCommand(Config.Emotes.cancel)
    if d.serverId then RPI.request('drag', { target = d.serverId, drag = false }, function() end) end
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
    ExecuteCommand(Config.Emotes.cancel)
    if d.serverId then
        RPI.request('putInVehicle', { target = d.serverId, netId = VehToNet(vehicle), seat = rear.seat }, feedback(nil))
    else
        RPI.withControl(d.ped, function()
            if IsEntityAttached(d.ped) then DetachEntity(d.ped, true, false) end
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
local draggedBy = nil
local entryAllowedUntil = 0 -- portière ouverte par un policier : montée autorisée (véhicule d'urgence)
local CUFF_BLOCKED = { 21, 22, 23, 24, 25, 37, 44, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264 }

function RPI.isCuffed() return cuffed end

--- Relance l'emote "menotté" : commande d'emote à pied, animation directe en véhicule / tenu par
--- le bras, ou si l'emote n'a rien donné (script d'emotes absent, autre animation)
local function reapplyCuffEmote(ped)
    local now = GetGameTimer()
    if IsPedInAnyVehicle(ped, false) or draggedBy then
        RPI.playAnimNow(ped, CUFF.dict, CUFF.clip, -1, 49)
    elseif now - lastEmote > 4000 then
        ExecuteCommand(Config.Emotes.cuffed)
        lastEmote = now
    elseif now - lastEmote > 1500 then
        RPI.playAnimNow(ped, CUFF.dict, CUFF.clip, -1, 49)
    end
end

local function cuffLoop()
    CreateThread(function()
        local nextCheck = 0
        while cuffed do
            Wait(0)
            DisablePlayerFiring(PlayerId(), true)
            for _, control in ipairs(CUFF_BLOCKED) do DisableControlAction(0, control, true) end
            local now = GetGameTimer()
            if now >= nextCheck then
                nextCheck = now + 1000
                local ped = PlayerPedId()
                if not isPlayingCuff(ped) and not dragWalking and not IsPedRagdoll(ped)
                    and not IsPedGettingIntoAVehicle(ped) and not IsEntityDead(ped) then
                    reapplyCuffEmote(ped)
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
        deleteProp(cuffProp)
        cuffProp = nil
        ExecuteCommand(Config.Emotes.cancel)
        StopAnimTask(ped, CUFF.dict, CUFF.clip, 1.0)
    end
end

RegisterNetEvent('rp_interact:client:setCuffed', setCuffed)

RegisterNetEvent('rp_interact:client:drag', function(policeSrc)
    local ped = PlayerPedId()
    if not policeSrc then
        draggedBy = nil
        if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
        return
    end
    local player = GetPlayerFromServerId(policeSrc)
    if player == -1 then return end
    draggedBy = policeSrc
    attachToPolice(ped, GetPlayerPed(player))
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
    draggedBy = nil
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    entryAllowedUntil = GetGameTimer() + 15000
    ClearPedTasks(ped)
    TaskEnterVehicle(ped, vehicle, 15000, seat, 1.0, 1, 0)
end)

RegisterNetEvent('rp_interact:client:leaveVehicle', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then TaskLeaveVehicle(ped, vehicle, 0) end
end)

-- Ressource redémarrée alors que le joueur était menotté
if LocalPlayer.state.rpiCuffed == true then setCuffed(true) end

-- =========================================================================
-- VÉHICULES D'URGENCE (classe 18) : /policeon, /policeoff
-- Non-policier qui essaie de monter par une portière fermée : refusé. Policier : toujours autorisé
-- (déverrouillé pour lui seul). Boucle (100 ms) uniquement quand la règle est activée.
-- =========================================================================
local EMERGENCY_CLASS = 18
local restriction = GlobalState.rpiPoliceVehicles == true
local restrictionRunning = false
local lastRefusal = 0

local function doorForSeat(seat) return seat + 1 end -- siège -1 (conducteur) -> portière 0…

local function startRestriction()
    if restrictionRunning then return end
    restrictionRunning = true
    CreateThread(function()
        local attempt = nil -- véhicule de la tentative en cours (décision prise au début)
        while restriction do
            Wait(100)
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsTryingToEnter(ped)
            if vehicle == 0 or not DoesEntityExist(vehicle) then
                attempt = nil
            elseif attempt ~= vehicle and GetVehicleClass(vehicle) == EMERGENCY_CLASS then
                attempt = vehicle
                if RPI.isPolice() then
                    SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false)
                elseif GetGameTimer() > entryAllowedUntil then
                    local door = doorForSeat(GetSeatPedIsTryingToEnter(ped))
                    if GetVehicleDoorAngleRatio(vehicle, door) < 0.1 then
                        ClearPedTasks(ped)
                        attempt = nil
                        if GetGameTimer() - lastRefusal > 3000 then
                            lastRefusal = GetGameTimer()
                            RPI.notify('Véhicule de police : réservé aux policiers.', 'error')
                        end
                    end
                end
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

-- =========================================================================
-- SUPPRIMER DES ÉLÉMENTS AMBIANTS
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

--- Élément ambiant supprimable ? (jamais un joueur, ni un véhicule occupé par un joueur)
function Police.deletable(ctx)
    if ctx.isSelf then return false end
    if ctx.type == 'ped' then return not ctx.isPlayer end
    if ctx.type == 'vehicle' then return not playerInside(ctx.entity) end
    return ctx.type == 'object'
end

local function deleteLocally(entity)
    RPI.withControl(entity, function()
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end)
end

function Police.delete(ctx)
    local entity = ctx.entity
    if ctx.netId then
        RPI.request('deleteEntity', { netId = ctx.netId }, function(res)
            if res and res.ok then return end
            if res and res.fallback then return deleteLocally(entity) end
            RPI.notify(res and res.error or 'Suppression impossible.', 'error')
        end)
    elseif ctx.type == 'object' then
        -- Objet de la carte : masqué chez tous les joueurs
        local c = GetEntityCoords(entity)
        RPI.request('hideProp', { model = ctx.model, x = c.x, y = c.y, z = c.z }, function(res)
            if not res or not res.ok then RPI.notify(res and res.error or 'Suppression impossible.', 'error') end
        end)
    else
        deleteLocally(entity)
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
    end
end)
