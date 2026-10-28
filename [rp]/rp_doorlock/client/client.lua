--[[
    RP Doorlock - client
    --------------------
    Avec l'œil de rp_interact (Alt), en visant une porte du jeu (ou d'une map ajoutée) à moins de Distance m :
      - joueur CIVIL (mode civil ou sans rôle) : « Verrouiller la porte » ; porte verrouillée : « Déverrouiller la
        porte » (tout civil) ;
      - POLICIER en service (unité du MDC) : ne verrouille ni ne déverrouille jamais ;
      - porte verrouillée, TOUT LE MONDE : « Frapper à la porte » ou « Enfoncer la porte » : barre de réussite en bas
        de l'écran (ESPACE quand le curseur passe dans la zone verte ; 3 à 6 coups réussis, tirés au hasard par le
        serveur ; un raté ne compte pas mais n'arrête rien ; RETOUR ARRIÈRE pour arrêter), un coup de pied (animation
        + bruit, entendu autour) à chaque essai ; la porte cède d'un coup sec (bruit, secousse pour celui qui
        l'enfonce) ;
      - porte enfoncée : cassée, elle ne se verrouille plus ; description « Elle a été forcée. » affichée au-dessus
        (comme la description visuelle d'une scène de /scene) ; un admin peut la réparer ;
      - porte ouverte : tout le monde peut y frapper ; un admin peut déverrouiller toute porte.
    Une porte double (deux battants côte à côte) est verrouillée / déverrouillée / enfoncée en entier.
    Verrous : système de portes du jeu (porte fermée et bloquée chez tout le monde), ré-appliqué quand la porte se
    charge près du joueur ; la porte est refermée d'un coup puis FIGÉE avec ses collisions (elle ne bouge plus du
    tout et bloque les joueurs, même une porte de bâtiment du jeu de base).
    Les portes ne peuvent pas être supprimées avec l'œil (rp_interact : export isDoor).
    Performance : aucune boucle sans verrou ni porte forcée ; sinon une vérification par seconde (0,5 s près d'une
    porte), et l'affichage de la description seulement quand elle est visible à moins de 10 m.
]]

local Config = DoorlockConfig

local DOOR_MODELS = {}
for _, name in ipairs(DoorlockModels or {}) do DOOR_MODELS[GetHashKey(name)] = true end
for _, m in ipairs(Config.ExtraModels or {}) do DOOR_MODELS[type(m) == 'number' and m or GetHashKey(m)] = true end
local IGNORED = {}
for _, m in ipairs(Config.IgnoredModels or {}) do IGNORED[type(m) == 'number' and m or GetHashKey(m)] = true end

local locks = {}        -- [id] = { id, model, x, y, z, tag, group } (du serveur)
local broken = {}       -- [id] = { id, model, x, y, z, group } : portes enfoncées (du serveur)
local applied = {}      -- [id] = { hash, loaded, object } : porte inscrite dans le système de portes du jeu
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
-- APPLIQUER LES VERROUS (système de portes du jeu + porte figée une fois fermée)
-- =========================================================================
--- Nombres reçus du serveur : modèle en ENTIER (un nombre à virgule passé à une native attendant un entier serait
--- lu de travers : la porte ne serait jamais reconnue), position en nombres à virgule
local function toInt(v) return math.tointeger(v) or math.floor(tonumber(v) or 0) end

--- La porte (objet) d'un verrou, si elle est chargée près du joueur
local function doorObject(l)
    local obj = GetClosestObjectOfType(l.x + 0.0, l.y + 0.0, l.z + 0.0, 1.0, toInt(l.model), false, false, false)
    return obj ~= 0 and obj or nil
end

--- Verrouillée dans le système de portes : la porte se referme et reste bloquée. Le jeu n'applique un état qu'une
--- fois la porte chargée (physique) : `lockState` est donc rappelé quand elle se charge près du joueur.
local function lockState(a)
    DoorSystemSetDoorState(a.hash, 4, false, false) -- remise à zéro de l'état, puis :
    DoorSystemSetDoorState(a.hash, 1, false, true)  -- verrouillée, appliqué tout de suite
end

local holdLocked -- (plus bas)

local function apply(l)
    local a = applied[l.id]
    if not a then
        -- toujours NOTRE inscription dans le système de portes (comme les scripts de portes éprouvés) : une porte
        -- déjà gérée par le jeu ou un autre script garderait sinon l'état qu'ils lui donnent
        a = { hash = GetHashKey('rp_doorlock:' .. l.id) }
        applied[l.id] = a
    end
    if not IsDoorRegisteredWithSystem(a.hash) then
        AddDoorToSystem(a.hash, toInt(l.model), l.x + 0.0, l.y + 0.0, l.z + 0.0, false, false, false)
    end
    lockState(a)
    a.loaded = DoorSystemGetIsPhysicsLoaded(a.hash) == true or DoorSystemGetIsPhysicsLoaded(a.hash) == 1
    if locks[l.id] then holdLocked(l) end -- porte proche : refermée et figée tout de suite
end

--- Porte figée : immobile, collisions actives (elle bloque les joueurs comme un mur)
local function freeze(a, obj)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, true, true)
    a.object = obj
    a.rotation = GetEntityRotation(obj, 2) -- position fermée : remise en place si quelque chose la décale
end

local function unfreeze(a)
    if a.object and DoesEntityExist(a.object) then FreezeEntityPosition(a.object, false) end
    a.object, a.rotation = nil, nil
end

local function release(id, keepOpen)
    local a = applied[id]
    if not a then return end
    applied[id] = nil
    unfreeze(a)
    DoorSystemSetDoorState(a.hash, 0, false, true) -- déverrouillée
    if keepOpen then
        -- enfoncée : la porte reste libre de battre un instant, puis rendue au jeu
        SetTimeout(3000, function() if not applied[id] and IsDoorRegisteredWithSystem(a.hash) then RemoveDoorFromSystem(a.hash) end end)
    else
        RemoveDoorFromSystem(a.hash)
    end
end

--- Une porte verrouillée proche : état ré-appliqué quand elle se charge ; ouverte, elle est refermée d'un coup
--- (sans attendre qu'elle batte), puis FIGÉE avec ses collisions : elle ne bouge plus du tout.
function holdLocked(l)
    local a = applied[l.id]
    if not a then return end
    if not IsDoorRegisteredWithSystem(a.hash) then
        AddDoorToSystem(a.hash, toInt(l.model), l.x + 0.0, l.y + 0.0, l.z + 0.0, false, false, false)
        a.loaded = false
    end
    local loaded = DoorSystemGetIsPhysicsLoaded(a.hash)
    loaded = loaded == true or loaded == 1
    if loaded and (not a.loaded or DoorSystemGetDoorState(a.hash) ~= 1) then lockState(a) end
    a.loaded = loaded
    local obj = doorObject(l)
    if a.object and a.object ~= obj then unfreeze(a) end
    if not obj then return end
    if a.object then
        -- déjà figée : remise en place si elle a été décalée (autre script, véhicule…)
        local r = GetEntityRotation(obj, 2)
        if a.rotation and math.abs(r.z - a.rotation.z) > 0.5 then SetEntityRotation(obj, a.rotation.x, a.rotation.y, a.rotation.z, 2, true) end
        if not IsEntityPositionFrozen(obj) then FreezeEntityPosition(obj, true) end
        return
    end
    if math.abs(DoorSystemGetOpenRatio(a.hash)) < 0.02 then
        freeze(a, obj)
    else
        -- ouverte : refermée tout de suite ; figée à la vérification suivante (quelques images plus tard)
        DoorSystemSetOpenRatio(a.hash, 0.0, false, true)
        a.closing = (a.closing or 0) + 1
        if a.closing > 6 then freeze(a, obj) end -- le jeu ne la referme pas (porte sans physique…) : figée là
        if not a.pending then
            a.pending = true
            SetTimeout(150, function()
                a.pending = nil
                if applied[l.id] == a and locks[l.id] then holdLocked(l) end
            end)
        end
        return
    end
    a.closing = nil
end
DL.holdLocked = holdLocked -- pour les tests

-- =========================================================================
-- PORTE FORCÉE : description au-dessus de la porte (même rendu que la description visuelle de /scene)
-- =========================================================================
local B = Config.Broken or {}
local looks = {}         -- [id] = { anchor, entity, visible, lines }
local lookRunning = false

--- Texte coupé en lignes de ~38 caractères
local function wrap(text, width)
    local lines = {}
    for paragraph in (tostring(text) .. '\n'):gmatch('(.-)\n') do
        local line = ''
        for word in paragraph:gmatch('%S+') do
            if #line + #word + 1 > width and line ~= '' then lines[#lines + 1] = line; line = word
            else line = line == '' and word or (line .. ' ' .. word) end
        end
        if line ~= '' then lines[#lines + 1] = line end
    end
    return lines
end

--- Point au-dessus duquel la description s'affiche : au milieu du battant, juste au-dessus
local function lookAnchor(l)
    local obj = doorObject(l)
    if obj then
        local min, max = GetModelDimensions(GetEntityModel(obj))
        return GetOffsetFromEntityInWorldCoords(obj, (min.x + max.x) / 2, (min.y + max.y) / 2, max.z + 0.25), obj
    end
    return vector3(l.x, l.y, l.z + 2.35), nil
end

--- Visible : rien entre la caméra et le point (un mur…), la porte elle-même mise à part
local function inSight(anchor, entity)
    local cam = GetFinalRenderedCamCoord()
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, anchor.x, anchor.y, anchor.z,
        1 + 2 + 16, PlayerPedId(), 7)
    local _, hit, coords, _, hitEntity = GetShapeTestResult(ray)
    if hit ~= 1 and hit ~= true then return true end
    if entity and hitEntity == entity then return true end
    return #(coords - anchor) <= 0.6
end

local function drawLook(anchor, lines, distance)
    local scale = (B.Scale or 0.34) * math.max(0.75, math.min(1.15, 6.0 / math.max(distance, 1.0)))
    local color = B.Color or { 245, 238, 215 }
    local lineH = 0.028 * scale / 0.34
    local longest = 0
    for _, l in ipairs(lines) do if #l > longest then longest = #l end end
    SetDrawOrigin(anchor.x, anchor.y, anchor.z, 0)
    DrawRect(0.0, (#lines - 1) * lineH / 2 + lineH * 0.45, longest * 0.0052 * scale / 0.34 + 0.016, #lines * lineH + 0.012, 0, 0, 0, 140)
    for i, l in ipairs(lines) do
        SetTextFont(4)
        SetTextScale(0.0, scale)
        SetTextColour(color[1], color[2], color[3], 235)
        SetTextCentre(true)
        SetTextOutline()
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(l)
        EndTextCommandDisplayText(0.0, (i - 1) * lineH)
    end
    ClearDrawOrigin()
end

local function lookLoop()
    if lookRunning then return end
    lookRunning = true
    CreateThread(function()
        while next(looks) do
            if not IsPauseMenuActive() then
                local me = GetEntityCoords(PlayerPedId())
                for _, look in pairs(looks) do
                    if look.visible then drawLook(look.anchor, look.lines, #(me - look.anchor)) end
                end
            end
            Wait(0)
        end
        lookRunning = false
    end)
end

--- Descriptions des portes forcées proches (depuis la boucle des portes)
local function updateLooks(me)
    if B.Text == false or B.Text == '' then return end
    local range = B.Distance or 10.0
    for id, l in pairs(broken) do
        local close = #(me - vector3(l.x, l.y, l.z)) <= range + 3.0
        if close then
            local look = looks[id] or { lines = wrap(B.Text or 'Elle a été forcée.', 38) }
            look.anchor, look.entity = lookAnchor(l)
            look.visible = #(me - look.anchor) <= range + 0.5 and inSight(look.anchor, look.entity)
            looks[id] = look
        else
            looks[id] = nil
        end
    end
    for id in pairs(looks) do if not broken[id] then looks[id] = nil end end
    if next(looks) then lookLoop() end
end

-- =========================================================================
-- BOUCLE DES PORTES : seulement s'il y a des verrous ou des portes forcées ; plus rapide près de l'une d'elles
-- =========================================================================
local watching = false
local function watch()
    if watching then return end
    watching = true
    CreateThread(function()
        while next(locks) or next(broken) do
            local me = GetEntityCoords(PlayerPedId())
            local close = false
            for id, l in pairs(locks) do
                if #(me - vector3(l.x, l.y, l.z)) <= (Config.HoldDistance or 40.0) then
                    close = true
                    holdLocked(l)
                elseif applied[id] and applied[id].object then
                    unfreeze(applied[id]) -- hors de portée : l'objet peut disparaître
                    applied[id].loaded = false
                end
            end
            updateLooks(me)
            if next(looks) then close = true end
            Wait(close and 500 or 1000)
        end
        looks = {}
        watching = false
    end)
end

RegisterNetEvent('rp_doorlock:all', function(list, tag, isAdmin, brokenList)
    myTag, admin = tag, isAdmin == true
    for id in pairs(locks) do release(id) end
    locks, broken = {}, {}
    for _, l in ipairs(type(list) == 'table' and list or {}) do
        locks[l.id] = l
        apply(l)
    end
    for _, l in ipairs(type(brokenList) == 'table' and brokenList or {}) do broken[l.id] = l end
    watch()
end)

RegisterNetEvent('rp_doorlock:set', function(list)
    for _, l in ipairs(type(list) == 'table' and list or {}) do
        locks[l.id] = l
        apply(l)
    end
    watch()
end)

RegisterNetEvent('rp_doorlock:unset', function(ids)
    for _, id in ipairs(type(ids) == 'table' and ids or {}) do
        locks[id] = nil
        release(id)
    end
end)

--- Enfoncée : déverrouillée, cassée (description), et le battant est projeté loin de celui qui l'a enfoncée
local stopBreach -- barre de réussite (plus bas)

--- Bruit d'une porte (coup de pied réussi / raté, porte qui cède), plus faible avec la distance (html/ : généré)
local function soundAt(p, kind)
    local S = (Config.Kick or {}).Sound or {}
    local range = S.Range or 25.0
    local d = #(GetEntityCoords(PlayerPedId()) - vector3(p.x, p.y, p.z))
    if d > range then return end
    local volume = (S.Volume or 0.8) * (1.0 - d / range) ^ 1.3
    SendNUIMessage({ action = 'sound', data = { kind = kind, volume = volume } })
end
DL.soundAt = soundAt

local function myServerId() return GetPlayerServerId(PlayerId()) end

-- Coup de pied d'un autre joueur (le mien est joué tout de suite chez moi)
RegisterNetEvent('rp_doorlock:kickFx', function(p, hit, src)
    if type(p) ~= 'table' or src == myServerId() then return end
    soundAt(p, hit and 'hit' or 'miss')
end)

--- Enfoncée (les deux battants d'une porte double) : déverrouillée, cassée (description), ouverte d'un coup sec loin
--- de celui qui l'a enfoncée, bruit chez tout le monde autour ; secousse pour lui. Elle reste battante.
RegisterNetEvent('rp_doorlock:breach', function(doors, from, by)
    local K = Config.Kick or {}
    if stopBreach then stopBreach() end
    local list = type(doors) == 'table' and doors or {}
    for _, l in ipairs(list) do
        locks[l.id] = nil
        broken[l.id] = l
        release(l.id, true) -- libérée (plus figée) : elle bat de nouveau
    end
    if list[1] then soundAt(list[1], 'break') end
    if by == myServerId() and K.BreakShake then ShakeGameplayCam(K.BreakShake[1] or 'JOLT_SHAKE', K.BreakShake[2] or 1.2) end
    CreateThread(function()
        Wait(0) -- une image après l'avoir libérée : la poussée s'applique
        for _ = 1, 3 do
            for _, l in ipairs(list) do
                local obj = doorObject(l)
                if obj and type(from) == 'table' then
                    local c = GetEntityCoords(obj)
                    local dx, dy = c.x - from.x, c.y - from.y
                    local len = math.sqrt(dx * dx + dy * dy)
                    if len > 0.01 then
                        local f = K.Force or 30.0
                        ApplyForceToEntity(obj, 1, dx / len * f, dy / len * f, 0.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
                    end
                end
            end
            Wait(0)
        end
    end)
    watch()
end)

--- Porte réparée (admin, ou après Broken.Duration minutes) : elle se verrouille de nouveau
RegisterNetEvent('rp_doorlock:repaired', function(ids)
    for _, id in ipairs(type(ids) == 'table' and ids or {}) do
        broken[id] = nil
        looks[id] = nil
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

--- Joue une animation (dict, clip, durée) ; renvoie tout de suite
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

--- Un coup de pied dans la porte : le personnage joue l'animation à CHAQUE essai (réussi ou raté) ; secousse si
--- réussi. Renvoie quand le pied touche la porte, avec le temps restant de l'animation.
local function kickAnim(door, hit)
    local K = Config.Kick or {}
    local ped = PlayerPedId()
    faceDoor(door)
    ClearPedTasks(ped) -- l'animation précédente (coup d'avant) ne bloque pas la nouvelle
    local played
    for _, anim in ipairs(K.Anims or {}) do
        if playAnim(anim, 0) then played = anim break end
    end
    Wait(played and played[4] or 600) -- moment où le pied touche la porte
    soundAt(door, hit and 'hit' or 'miss')
    if hit and K.Shake and K.Shake > 0 then ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', K.Shake) end
    return math.max(0, (played and played[3] or 1600) - (played and played[4] or 600))
end

-- =========================================================================
-- ENFONCER : BARRE DE RÉUSSITE (en bas de l'écran, html/) - ESPACE quand le curseur est dans la zone verte
-- =========================================================================
local breach = nil -- { door, step, need, waiting }
local BREACH_DISABLED = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 44, 140, 141, 142, 143, 177, 194, 199, 200, 257, 263, 322 }

local function stepData(b)
    local K = Config.Kick or {}
    local zones, speeds = K.Zone or { 0.2, 0.15, 0.11 }, K.Speed or { 0.9, 1.15, 1.4 }
    local step = b.step
    return { show = true, steps = b.need, step = step,
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
    breach = { door = door, step = 0, need = nil, waiting = true } -- en attente du serveur (coups nécessaires)
    local mine = breach
    TriggerServerEvent('rp_doorlock:breachStart', door.id)
    -- animations chargées dès le début : le premier coup de pied part sans attendre
    for _, anim in ipairs((Config.Kick or {}).Anims or {}) do
        if DoesAnimDictExist(anim[1]) then RequestAnimDict(anim[1]) end
    end
    faceDoor(door)
    SetTimeout(3000, function() if breach == mine and not mine.need then stopBreach() end end) -- serveur muet
    CreateThread(function()
        while breach == mine do
            for _, control in ipairs(BREACH_DISABLED) do DisableControlAction(0, control, true) end
            if not mine.waiting and IsDisabledControlJustPressed(0, 22) then -- ESPACE
                mine.waiting = true
                SendNUIMessage({ action = 'breachKey' })
            elseif IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194)
                or IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322) then
                stopBreach('Vous arrêtez d\'enfoncer la porte.') -- à tout moment
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

-- Le serveur dit combien de coups réussis il faut (3 à 6, le même pour toute la porte) : la barre s'affiche
RegisterNetEvent('rp_doorlock:breachInfo', function(id, need)
    local b = breach
    if not b or b.door.id ~= id or b.need then return end
    if not need then return stopBreach('Cette porte ne peut pas être enfoncée.') end
    b.need, b.waiting = math.floor(need), false
    SendNUIMessage({ action = 'breach', data = stepData(b) })
end)

-- Résultat d'un essai (le NUI sait où était le curseur) : coup de pied (animation + bruit), puis essai suivant.
-- Raté : ne compte pas, la tentative continue (seuls RETOUR ARRIÈRE, s'éloigner ou la porte ouverte l'arrêtent).
RegisterNUICallback('breachResult', function(data, cb)
    cb({ ok = true })
    local b = breach
    if not b or not b.waiting or not b.need then return end
    local hit = type(data) == 'table' and data.hit == true
    CreateThread(function()
        local rest = kickAnim(b.door, hit)
        if breach ~= b then return end
        TriggerServerEvent('rp_doorlock:kick', b.door.id, hit)
        if hit then b.step = b.step + 1 end
        if b.step >= b.need then
            SetTimeout(3000, function() if breach == b then stopBreach() end end) -- le serveur fait céder la porte
            return
        end
        Wait(rest)
        if breach ~= b then return end
        SendNUIMessage({ action = 'breach', data = stepData(b) })
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
    local lock, forced = locks[door.id], broken[door.id]
    local police = info.police == true -- policier en service (unité du MDC) ; sinon : civil
    local K = Config.Knock or {}
    local options = {}
    if forced then
        if admin then options[#options + 1] = { id = 'repair', icon = 'tool', label = 'Réparer la porte', primary = true } end
    elseif not lock then
        if not police then options[#options + 1] = { id = 'lock', icon = 'lock', label = 'Verrouiller la porte', primary = true } end
    elseif not police or admin then
        options[#options + 1] = { id = 'unlock', icon = 'unlock', label = 'Déverrouiller la porte', primary = true }
    end
    if K.Enabled ~= false then options[#options + 1] = { id = 'knock', icon = 'hand', label = 'Frapper à la porte' } end
    if lock and (Config.Kick or {}).Enabled ~= false then -- tout le monde (civil ou policier)
        options[#options + 1] = { id = 'kick', icon = 'door', label = 'Enfoncer la porte', primary = true }
    end
    if #options == 0 then return nil end
    return { label = forced and 'Porte forcée' or (lock and 'Porte verrouillée' or 'Porte'), options = options }
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
        elseif id == 'repair' then
            TriggerServerEvent('rp_doorlock:repair', door.id)
        elseif id == 'knock' then
            knock(door)
        end
        busy = false
    end)
end)

--- rp_interact : une porte ne peut pas être supprimée avec l'œil
exports('isDoor', function(entity) return DL.isDoor(entity) end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(applied) do release(id) end
    if breach then stopBreach() end
end)
