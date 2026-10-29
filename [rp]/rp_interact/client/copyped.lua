--[[
    RP Interact - /copyped : copie du personnage, pour les photos (client)
    ----------------------------------------------------------------------
    /copyped : un double du personnage apparaît EXACTEMENT à sa place (position, orientation, tenue), avec :
      - l'arme tenue en main, ses accessoires (ceux de l'arme dans equipment_services.json, armes addon comprises :
        GlobalState.rpiWeaponComponents) et ses teintes ; en train de viser : il vise aussi, dans la même direction ;
      - l'animation en cours : l'emote du mode d'emotes (RPEMOTES / rpemotes, index complet lu par le serveur), au même
        moment de l'animation, avec ses props ; ou un scénario (WORLD_HUMAN_…) ; ou une animation de ce script ;
      - les objets accrochés au personnage qui ne viennent pas de l'emote (menottes…).
    Le double ne bouge pas (figé, invulnérable) ; pose figée à l'instant de la copie (CopyPed.FreezePose).
    /copyped suppr : supprime vos doubles (CopyPed.Max au plus, le plus ancien est remplacé).
    Performance : rien en dehors de la commande.
]]

local Config = InteractConfig
local C = Config.CopyPed or {}
if C.Enabled == false then return end

local clones = {} -- { ped, objects = {} }

-- =========================================================================
-- INDEX DES EMOTES (serveur : server/emotes.lua), demandé une fois
-- =========================================================================
local index, waiting = nil, nil

local function withIndex(cb)
    if index then return cb(index) end
    if waiting then waiting[#waiting + 1] = cb return end
    waiting = { cb }
    TriggerServerEvent('rp_interact:emoteIndex')
    SetTimeout(8000, function() -- pas de réponse (pas de mode d'emotes) : sans emote
        if waiting then
            local list = waiting
            waiting, index = nil, index or {}
            for _, fn in ipairs(list) do fn(index) end
        end
    end)
end

RegisterNetEvent('rp_interact:emoteIndex', function(list)
    index = type(list) == 'table' and list or {}
    local pending = waiting or {}
    waiting = nil
    for _, fn in ipairs(pending) do fn(index) end
end)

--- Animations de ce script (menotté, assis…) reconnues aussi
local function ownAnims()
    local list = {}
    local function add(a, loop)
        if type(a) == 'table' and a.dict and a.clip then list[#list + 1] = { n = a.clip, d = a.dict, c = a.clip, l = loop } end
    end
    add(Config.CuffAnim, true)
    add(Config.SeatedAnim, true)
    return list
end

--- Emote / scénario / animation joué par `ped` : entrée de l'index, ou nil
local function currentEmote(ped, list)
    if IsPedUsingAnyScenario(ped) then
        for _, e in ipairs(list) do
            if e.s and IsPedUsingScenario(ped, e.c) then return e end
        end
    end
    for _, e in ipairs(list) do
        if not e.s and IsEntityPlayingAnim(ped, e.d, e.c, 3) then return e end
    end
    for _, e in ipairs(ownAnims()) do
        if IsEntityPlayingAnim(ped, e.d, e.c, 3) then return e end
    end
    return nil
end

-- =========================================================================
-- COPIE
-- =========================================================================
local function loadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local stopAt = GetGameTimer() + 3000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > stopAt then return nil end
        Wait(0)
    end
    return hash
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local stopAt = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > stopAt then return false end
        Wait(0)
    end
    return true
end

local function makeObject(model, at)
    local hash = loadModel(model)
    if not hash then return nil end
    local obj = CreateObject(hash, at.x, at.y, at.z, C.Networked ~= false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not obj or obj == 0 then return nil end
    SetEntityCollision(obj, false, false)
    return obj
end

--- Arme en main (accessoires de equipment_services.json, teinte, lampe) ; en train de viser : vise pareil
local function copyWeapon(ped, clone)
    local hash = GetSelectedPedWeapon(ped)
    if not hash or hash == 0 or hash == GetHashKey('WEAPON_UNARMED') then return end
    GiveWeaponToPed(clone, hash, 1, false, true)
    local list = GlobalState.rpiWeaponComponents
    for name, w in pairs(type(list) == 'table' and list or {}) do
        if GetHashKey(name) == hash then
            for _, component in ipairs(w.components or {}) do
                local c = GetHashKey(component)
                if HasPedGotWeaponComponent(ped, hash, c) then GiveWeaponComponentToPed(clone, hash, c) end
            end
        end
    end
    for _, component in ipairs(C.ExtraComponents or {}) do
        local c = GetHashKey(component)
        if HasPedGotWeaponComponent(ped, hash, c) then GiveWeaponComponentToPed(clone, hash, c) end
    end
    SetPedWeaponTintIndex(clone, hash, GetPedWeaponTintIndex(ped, hash))
    SetCurrentPedWeapon(clone, hash, true)
    pcall(function() SetFlashLightEnabled(clone, IsFlashLightOn(ped)) end)
    if IsPlayerFreeAiming(PlayerId()) then
        local cam, rot = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2)
        local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
        local t = cam + vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)) * 25.0
        TaskAimGunAtCoord(clone, t.x, t.y, t.z, -1, false, false)
        return true
    end
end

--- Emote : animation au même moment (figée si FreezePose), props de l'emote ; scénario : lancé sur place
local function copyEmote(ped, clone, emote, objects)
    if emote.s then
        TaskStartScenarioInPlace(clone, emote.c, 0, false)
        return {}
    end
    if not loadDict(emote.d) then return {} end
    local flag = emote.m and 49 or 1
    local time = GetEntityAnimCurrentTime(ped, emote.d, emote.c)
    TaskPlayAnim(clone, emote.d, emote.c, 8.0, 8.0, -1, flag, time or 0.0, false, false, false)
    Wait(50)
    if time then SetEntityAnimCurrentTime(clone, emote.d, emote.c, time) end
    if C.FreezePose ~= false then SetEntityAnimSpeed(clone, emote.d, emote.c, 0.0) end
    local models = {}
    for _, p in ipairs(emote.p or {}) do
        local obj = makeObject(p[1], GetEntityCoords(clone))
        if obj then
            local o = p[3] or {}
            AttachEntityToEntity(obj, clone, GetPedBoneIndex(clone, p[2]), o[1] or 0.0, o[2] or 0.0, o[3] or 0.0,
                o[4] or 0.0, o[5] or 0.0, o[6] or 0.0, true, true, false, true, 1, true)
            objects[#objects + 1] = obj
            models[GetHashKey(p[1])] = true
        end
    end
    return models
end

--- Objets accrochés au personnage (menottes…), hors arme et props de l'emote : même place sur le double
local function copyAttached(ped, clone, skipModels, objects)
    local weapon = GetCurrentPedWeaponEntityIndex(ped)
    for _, obj in ipairs(GetGamePool('CObject')) do
        if obj ~= weapon and GetEntityAttachedTo(obj) == ped and not skipModels[GetEntityModel(obj)] then
            local copy = makeObject(GetEntityModel(obj), GetEntityCoords(obj))
            if copy then
                local wp = GetEntityCoords(obj)
                local at = GetOffsetFromEntityGivenWorldCoords(ped, wp.x, wp.y, wp.z)
                local r, pr = GetEntityRotation(obj, 2), GetEntityRotation(ped, 2)
                AttachEntityToEntity(copy, clone, 0, at.x, at.y, at.z, r.x - pr.x, r.y - pr.y, r.z - pr.z,
                    false, false, false, false, 2, true)
                objects[#objects + 1] = copy
            end
        end
    end
end

local function deleteClone(c)
    for _, obj in ipairs(c.objects or {}) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    if DoesEntityExist(c.ped) then DeleteEntity(c.ped) end
end

local function clearClones()
    for _, c in ipairs(clones) do deleteClone(c) end
    clones = {}
end

local busy = false
local function copyPed()
    if busy then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, true) then return RPI.notify('Descendez du véhicule pour copier votre personnage.', 'error') end
    if IsEntityDead(ped) then return end
    busy = true
    withIndex(function(list)
        CreateThread(function()
            local emote = currentEmote(ped, list)
            local pos, heading = GetEntityCoords(ped), GetEntityHeading(ped)
            local clone = ClonePed(ped, C.Networked ~= false, false, true)
            if not clone or clone == 0 then
                busy = false
                return RPI.notify('Copie impossible.', 'error')
            end
            SetEntityAsMissionEntity(clone, true, true)
            SetEntityCoordsNoOffset(clone, pos.x, pos.y, pos.z, false, false, false)
            SetEntityHeading(clone, heading)
            FreezeEntityPosition(clone, true)
            SetEntityInvincible(clone, true)
            SetBlockingOfNonTemporaryEvents(clone, true)
            SetPedCanRagdoll(clone, false)
            SetPedFleeAttributes(clone, 0, false)
            SetPedKeepTask(clone, true)
            local objects = {}
            local aiming = copyWeapon(ped, clone)
            local emoteModels = (emote and not aiming) and copyEmote(ped, clone, emote, objects) or {}
            copyAttached(ped, clone, emoteModels, objects)
            clones[#clones + 1] = { ped = clone, objects = objects }
            while #clones > (C.Max or 5) do deleteClone(table.remove(clones, 1)) end
            RPI.notify(emote and ('Personnage copié (animation : %s).'):format(emote.n) or 'Personnage copié.', 'success')
            busy = false
        end)
    end)
end

RegisterCommand(C.Command or 'copyped', function(_, args)
    local sub = args[1] and args[1]:lower() or ''
    if sub == 'suppr' or sub == 'clear' or sub == 'delete' then
        local n = #clones
        clearClones()
        return RPI.notify(n > 0 and ('%d copie(s) supprimée(s).'):format(n) or 'Aucune copie à supprimer.', n > 0 and 'success' or 'info')
    end
    copyPed()
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearClones() end
end)

RPICopyPed = { current = currentEmote, clones = clones } -- pour les tests
