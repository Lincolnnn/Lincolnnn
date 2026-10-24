--[[
    RP Doorlock - client
    --------------------
    Avec l'œil de rp_interact (Alt), en visant une porte du jeu (ou d'une map ajoutée) à moins de Distance m :
      - MODE CIVIL seulement (rp_interact : Menu F1 > Civil > Mode civil ; jamais un policier en service) :
        « Verrouiller la porte », et « Déverrouiller la porte » pour son propriétaire ;
      - porte verrouillée, policier en service : « Enfoncer la porte » : barre de réussite en bas de l'écran (ESPACE
        quand le curseur passe dans la zone verte, Steps fois ; RETOUR ARRIÈRE pour arrêter), un coup de pied à
        chaque essai ;
      - tout le monde : « Frapper à la porte ».
    Une porte double (deux battants côte à côte) est verrouillée / déverrouillée / enfoncée en entier.
    Les verrous viennent du serveur et sont appliqués avec le système de portes du jeu (porte bloquée fermée chez
    tout le monde, même loin d'elle). Les portes ne peuvent pas être supprimées avec l'œil (rp_interact : export isDoor).
    Performance : aucune boucle, sauf pendant la barre de réussite (lecture des touches, à chaque image).
]]

local Config = DoorlockConfig

local DOOR_MODELS = {}
for _, name in ipairs(DoorlockModels or {}) do DOOR_MODELS[GetHashKey(name)] = true end
for _, m in ipairs(Config.ExtraModels or {}) do DOOR_MODELS[type(m) == 'number' and m or GetHashKey(m)] = true end
local IGNORED = {}
for _, m in ipairs(Config.IgnoredModels or {}) do IGNORED[type(m) == 'number' and m or GetHashKey(m)] = true end

local locks = {}        -- [id] = { id, model, x, y, z, tag, group } (du serveur)
local applied = {}      -- [id] = { hash, own } : porte inscrite dans le système de portes du jeu
local myTag, admin = nil, false
local busy = false

DL = {} -- pour les tests

local function notify(text)
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started'
        and pcall(function() exports[chat]:addPrivate({ title = 'Porte', text = text }) end) then
        return
    end
    TriggerEvent('chat:addMessage', { args = { 'Porte', text }, color = { 200, 200, 200 } })
end
RegisterNetEvent('rp_doorlock:notify', notify)

-- =========================================================================
-- RECONNAÎTRE UNE PORTE
-- =========================================================================
local sizeCache = {}
local function doorSized(model)
    local cached = sizeCache[model]
    if cached ~= nil then return cached end
    local min, max = GetModelDimensions(model)
    local h, w, t = max.z - min.z, max.x - min.x, max.y - min.y
    if t > w then w, t = t, w end -- certaines portes sont modélisées dans l'autre sens
    local ok = h >= (Config.MinHeight or 1.6) and h <= (Config.MaxHeight or 7.0) and w >= (Config.MinWidth or 0.5)
    if ok and not DOOR_MODELS[model] then ok = Config.DetectBySize == true and t <= (Config.MaxThickness or 0.4) end
    sizeCache[model] = ok
    return ok
end

function DL.isDoor(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 3 then return false end
    local model = GetEntityModel(entity)
    if IGNORED[model] then return false end
    if not DOOR_MODELS[model] and Config.DetectBySize ~= true then return false end
    return doorSized(model)
end

local function describe(entity)
    local c = GetEntityCoords(entity)
    local model = GetEntityModel(entity)
    return { id = DoorlockId(model, c.x, c.y, c.z), model = model, x = c.x, y = c.y, z = c.z, entity = entity }
end

--- Second battant d'une porte double : une autre porte tout à côté, au même niveau
function DL.pairOf(entity)
    local c = GetEntityCoords(entity)
    local best, bestD
    for _, obj in ipairs(GetGamePool('CObject')) do
        if obj ~= entity and DL.isDoor(obj) then
            local o = GetEntityCoords(obj)
            local d = #(o - c)
            if d <= (Config.PairDistance or 2.6) and math.abs(o.z - c.z) < 0.8 and (not bestD or d < bestD) then
                best, bestD = obj, d
            end
        end
    end
    return best
end

-- =========================================================================
-- APPLIQUER LES VERROUS (système de portes du jeu)
-- =========================================================================
--- Nombres reçus du serveur : modèle en ENTIER (un nombre à virgule passé à une native attendant un entier serait
--- lu de travers : la porte ne serait jamais reconnue), position en nombres à virgule
local function toInt(v) return math.tointeger(v) or math.floor(tonumber(v) or 0) end

local function apply(l)
    local a = applied[l.id]
    if not a then
        -- toujours NOTRE inscription dans le système de portes (comme les scripts de portes éprouvés) : une porte
        -- déjà gérée par le jeu ou un autre script garderait sinon l'état qu'ils lui donnent
        a = { hash = GetHashKey('rp_doorlock:' .. l.id), own = true }
        AddDoorToSystem(a.hash, toInt(l.model), l.x + 0.0, l.y + 0.0, l.z + 0.0, false, false, false)
        applied[l.id] = a
    end
    DoorSystemSetDoorState(a.hash, 4, false, false) -- remise à zéro de l'état, puis :
    DoorSystemSetDoorState(a.hash, 1, false, false) -- verrouillée (elle se referme et reste bloquée)
end

local function release(id, keepOpen)
    local a = applied[id]
    if not a then return end
    applied[id] = nil
    DoorSystemSetDoorState(a.hash, 0, false, false) -- déverrouillée
    if a.own then
        if keepOpen then
            -- enfoncée : la porte reste libre de battre un instant, puis rendue au jeu
            SetTimeout(3000, function() if not applied[id] and IsDoorRegisteredWithSystem(a.hash) then RemoveDoorFromSystem(a.hash) end end)
        else
            RemoveDoorFromSystem(a.hash)
        end
    end
end

RegisterNetEvent('rp_doorlock:all', function(list, tag, isAdmin)
    myTag, admin = tag, isAdmin == true
    for id in pairs(locks) do release(id) end
    locks = {}
    for _, l in ipairs(type(list) == 'table' and list or {}) do
        locks[l.id] = l
        apply(l)
    end
end)

RegisterNetEvent('rp_doorlock:set', function(list)
    for _, l in ipairs(type(list) == 'table' and list or {}) do
        locks[l.id] = l
        apply(l)
    end
end)

RegisterNetEvent('rp_doorlock:unset', function(ids)
    for _, id in ipairs(type(ids) == 'table' and ids or {}) do
        locks[id] = nil
        release(id)
    end
end)

--- Enfoncée : déverrouillée, et le battant est projeté loin du policier
local stopBreach -- barre de réussite (plus bas)

RegisterNetEvent('rp_doorlock:breach', function(doors, from)
    local K = Config.Kick or {}
    if stopBreach then stopBreach() end
    for _, l in ipairs(type(doors) == 'table' and doors or {}) do
        locks[l.id] = nil
        release(l.id, true)
        local obj = GetClosestObjectOfType(l.x, l.y, l.z, 1.5, l.model, false, false, false)
        if obj and obj ~= 0 and type(from) == 'table' then
            local c = GetEntityCoords(obj)
            local dx, dy = c.x - from.x, c.y - from.y
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0.01 then
                local f = K.Force or 22.0
                ApplyForceToEntity(obj, 1, dx / len * f, dy / len * f, 0.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
            end
        end
    end
end)


RegisterNetEvent('rp_doorlock:knock', function(p)
    local K = Config.Knock or {}
    if type(p) ~= 'table' or not K.Sound then return end
    if #(GetEntityCoords(PlayerPedId()) - vector3(p.x, p.y, p.z)) > (K.Range or 15.0) then return end
    PlaySoundFromCoord(-1, K.Sound[1], p.x, p.y, p.z, K.Sound[2], false, K.Range or 15.0, false)
end)

CreateThread(function() TriggerServerEvent('rp_doorlock:sync') end)

-- =========================================================================
-- ACTIONS (animations)
-- =========================================================================
local function loadAnim(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local untilTime = GetGameTimer() + 1500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < untilTime do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function faceDoor(door)
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    SetEntityHeading(ped, GetHeadingFromVector_2d(door.x - p.x, door.y - p.y))
end

--- Joue une animation (dict, clip, durée) ; renvoie une fois terminée
local function playAnim(anim, flag)
    if not anim or not loadAnim(anim[1]) then return false end
    TaskPlayAnim(PlayerPedId(), anim[1], anim[2], 4.0, -4.0, anim[3] or 1500, flag or 48, 0.0, false, false, false)
    return true
end

local function near(door)
    return #(GetEntityCoords(PlayerPedId()) - vector3(door.x, door.y, door.z)) <= (Config.Distance or 2.0) + 0.5
end

local function lockDoor(door)
    local list = { { model = door.model, x = door.x, y = door.y, z = door.z } }
    local pair = DL.pairOf(door.entity)
    if pair then
        local p = describe(pair)
        list[2] = { model = p.model, x = p.x, y = p.y, z = p.z }
    end
    faceDoor(door)
    playAnim(Config.LockAnim)
    Wait((Config.LockAnim or {})[3] or 1200)
    if near(door) then TriggerServerEvent('rp_doorlock:lock', list) end
end

local function unlockDoor(door)
    faceDoor(door)
    playAnim(Config.LockAnim)
    Wait((Config.LockAnim or {})[3] or 1200)
    if near(door) then TriggerServerEvent('rp_doorlock:unlock', door.id) end
end

local function knock(door)
    faceDoor(door)
    playAnim(Config.KnockAnim)
    TriggerServerEvent('rp_doorlock:knock', door.x, door.y, door.z)
    Wait((Config.KnockAnim or {})[3] or 2500)
end

--- Un coup de pied (animation, secousse si réussi) ; renvoie quand le pied touche la porte, puis la fin
local function kickAnim(door, hit)
    local K = Config.Kick or {}
    faceDoor(door)
    local played
    for _, anim in ipairs(K.Anims or {}) do
        if playAnim(anim, 0) then played = anim break end
    end
    Wait(played and played[4] or 600) -- moment où le pied touche la porte
    if hit and K.Shake and K.Shake > 0 then ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', K.Shake) end
    return math.max(0, (played and played[3] or 1600) - (played and played[4] or 600))
end

-- =========================================================================
-- ENFONCER : BARRE DE RÉUSSITE (en bas de l'écran, html/) - ESPACE quand le curseur est dans la zone verte
-- =========================================================================
local breach = nil -- { door, step, misses, waiting, session }
local BREACH_DISABLED = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 44, 140, 141, 142, 143, 177, 194, 199, 200, 257, 263, 322 }

local function stepData(step)
    local K = Config.Kick or {}
    local zones, speeds = K.Zone or { 0.2, 0.15, 0.11 }, K.Speed or { 0.9, 1.15, 1.4 }
    return { show = true, steps = K.Steps or 3, step = step,
        zone = zones[math.min(step + 1, #zones)], speed = speeds[math.min(step + 1, #speeds)] }
end

stopBreach = function(text)
    if not breach then return end
    breach = nil
    SendNUIMessage({ action = 'breach', data = { show = false } })
    if text then notify(text) end
end

local function startBreach(door)
    if breach then return end
    breach = { door = door, step = 0, misses = 0, waiting = false }
    local mine = breach
    TriggerServerEvent('rp_doorlock:breachStart', door.id)
    faceDoor(door)
    SendNUIMessage({ action = 'breach', data = stepData(0) })
    CreateThread(function()
        while breach == mine do
            for _, control in ipairs(BREACH_DISABLED) do DisableControlAction(0, control, true) end
            if not mine.waiting then
                if IsDisabledControlJustPressed(0, 22) then -- ESPACE
                    mine.waiting = true
                    SendNUIMessage({ action = 'breachKey' })
                elseif IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194)
                    or IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322) then
                    stopBreach('Vous arrêtez d\'enfoncer la porte.')
                end
            end
            if breach == mine then
                if IsEntityDead(PlayerPedId()) or not locks[door.id] then
                    stopBreach()
                elseif #(GetEntityCoords(PlayerPedId()) - vector3(door.x, door.y, door.z)) > (Config.Distance or 2.0) + 1.0 then
                    stopBreach('Trop loin de la porte.')
                end
            end
            Wait(0)
        end
    end)
end

-- Résultat d'un essai (le NUI sait où était le curseur) : coup de pied, puis étape suivante
RegisterNUICallback('breachResult', function(data, cb)
    cb({ ok = true })
    local b = breach
    if not b or not b.waiting then return end
    local hit = type(data) == 'table' and data.hit == true
    local K = Config.Kick or {}
    CreateThread(function()
        local rest = kickAnim(b.door, hit)
        if breach ~= b then return end
        TriggerServerEvent('rp_doorlock:kick', b.door.id, hit)
        if hit then b.step = b.step + 1 else b.misses = b.misses + 1 end
        if not hit and b.misses >= (K.MaxMisses or 3) then
            Wait(rest)
            return stopBreach('Vous n\'arrivez pas à enfoncer la porte. Reprenez votre souffle et réessayez.')
        end
        if hit and b.step >= (K.Steps or 3) then
            SetTimeout(3000, function() if breach == b then stopBreach() end end) -- le serveur fait céder la porte
            return
        end
        Wait(rest)
        if breach ~= b then return end
        if not hit then notify('La porte tient bon.') end
        SendNUIMessage({ action = 'breach', data = stepData(b.step) })
        b.waiting = false
    end)
end)

-- =========================================================================
-- ŒIL (rp_interact : Config.TargetProviders) : exports targetOptions / targetSelect
-- =========================================================================
local function doorFromInfo(info)
    if type(info) ~= 'table' or info.type ~= 'object' or not DL.isDoor(info.entity) then return nil end
    local door = describe(info.entity)
    if #(GetEntityCoords(PlayerPedId()) - vector3(door.x, door.y, door.z)) > (Config.Distance or 2.0) + 0.5 then return nil end
    return door
end

exports('targetOptions', function(info)
    if busy or breach then return nil end
    local door = doorFromInfo(info)
    if not door then return nil end
    local lock = locks[door.id]
    local police = info.police == true
    local civil = DL.civilMode() and not police -- verrouiller / déverrouiller : mode civil seulement
    local options = {}
    if not lock then
        if civil then
            options[#options + 1] = { id = 'lock', icon = 'lock', label = 'Verrouiller la porte' }
        end
    else
        if (civil and lock.tag == myTag) or admin then
            options[#options + 1] = { id = 'unlock', icon = 'unlock', label = 'Déverrouiller la porte' }
        end
        if police and (Config.Kick or {}).Enabled ~= false then
            options[#options + 1] = { id = 'kick', icon = 'door', label = 'Enfoncer la porte', police = true }
        end
    end
    if (Config.Knock or {}).Enabled ~= false then
        options[#options + 1] = { id = 'knock', icon = 'hand', label = 'Frapper à la porte' }
    end
    return { label = lock and 'Porte verrouillée' or 'Porte', options = options }
end)

exports('targetSelect', function(id, info)
    if busy then return end
    local door = doorFromInfo(info)
    if not door then return notify('Rapprochez-vous de la porte.') end
    busy = true
    CreateThread(function()
        if id == 'lock' then
            lockDoor(door)
        elseif id == 'unlock' then
            unlockDoor(door)
        elseif id == 'kick' then
            startBreach(door)
        elseif id == 'knock' then
            knock(door)
        end
        busy = false
    end)
end)

--- Mode civil de rp_interact (Menu F1 > Civil) ; sans rp_interact : tout le monde est civil
function DL.civilMode()
    if GetResourceState(Config.InteractResource or 'rp_interact') ~= 'started' then return true end
    return LocalPlayer.state.rpiCivilMode == true
end

--- rp_interact : une porte ne peut pas être supprimée avec l'œil
exports('isDoor', function(entity) return DL.isDoor(entity) end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(applied) do release(id) end
    if breach then stopBreach() end
end)
