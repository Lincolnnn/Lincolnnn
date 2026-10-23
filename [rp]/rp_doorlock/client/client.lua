--[[
    RP Doorlock - client
    --------------------
    Avec l'œil de rp_interact (Alt), en visant une porte du jeu (ou d'une map ajoutée) à moins de Distance m :
      - porte ouverte à tous : « Verrouiller la porte » (et « Frapper à la porte ») ;
      - porte verrouillée : « Déverrouiller la porte » pour son propriétaire, « Frapper à la porte » pour tous,
        « Enfoncer la porte » pour les policiers en service (coups de pied).
    Une porte double (deux battants côte à côte) est verrouillée / déverrouillée / enfoncée en entier.
    Les verrous viennent du serveur et sont appliqués avec le système de portes du jeu (porte bloquée fermée chez
    tout le monde, même loin d'elle).
    Performance : aucune boucle ; rien ne tourne en dehors des actions (œil, animations).
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
local function apply(l)
    local a = applied[l.id]
    if not a then
        local found, existing = DoorSystemFindExistingDoor(l.x, l.y, l.z, l.model)
        if found and existing and existing ~= 0 then
            a = { hash = existing, own = false } -- porte déjà gérée par le jeu : on change seulement son état
        else
            a = { hash = GetHashKey('rp_doorlock:' .. l.id), own = true }
            AddDoorToSystem(a.hash, l.model, l.x, l.y, l.z, false, false, false)
        end
        applied[l.id] = a
    end
    DoorSystemSetOpenRatio(a.hash, 0.0, false, false)
    DoorSystemSetDoorState(a.hash, 1, false, true) -- verrouillée
end

local function release(id, keepOpen)
    local a = applied[id]
    if not a then return end
    applied[id] = nil
    DoorSystemSetDoorState(a.hash, 0, false, true) -- déverrouillée
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
RegisterNetEvent('rp_doorlock:breach', function(doors, from)
    local K = Config.Kick or {}
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

RegisterNetEvent('rp_doorlock:kicked', function(n, max)
    notify(('La porte tient bon (%d / %d).'):format(n, max))
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

local function kickDoor(door)
    local K = Config.Kick or {}
    faceDoor(door)
    local played
    for _, anim in ipairs(K.Anims or {}) do
        if playAnim(anim, 0) then played = anim break end
    end
    Wait(played and played[4] or 600) -- moment où le pied touche la porte
    if K.Shake and K.Shake > 0 then ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', K.Shake) end
    if near(door) then TriggerServerEvent('rp_doorlock:kick', door.id) end
    Wait(math.max(0, (played and played[3] or 1600) - (played and played[4] or 600)))
end

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
    if busy then return nil end
    local door = doorFromInfo(info)
    if not door then return nil end
    local lock = locks[door.id]
    local police = info.police == true
    local options = {}
    if not lock then
        if not police or Config.PoliceCanLock ~= false then
            options[#options + 1] = { id = 'lock', icon = 'lock', label = 'Verrouiller la porte' }
        end
    else
        if lock.tag == myTag or admin then
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
            kickDoor(door)
        elseif id == 'knock' then
            knock(door)
        end
        busy = false
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(applied) do release(id) end
end)
