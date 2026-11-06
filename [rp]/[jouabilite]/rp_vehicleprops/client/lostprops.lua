--[[
    RP VehicleProps - chapeaux / lunettes tombés au sol (client)
    -------------------------------------------------------------
    VISIBLES ET REPRIS PAR TOUS (synchronisés par le serveur, server/wear.lua ; aucune permission) :
      - TOMBÉS : le jeu fait tomber le chapeau (ancre 0 : casquette, casque, chapeau EUP…) ou les lunettes (ancre 1)
        d'un joueur qui chute, est bousculé, blessé, ragdoll (rp_adrenaline)… Son client le voit tomber, attend qu'il
        s'arrête, retire l'objet local du jeu et l'annonce au serveur : il apparaît chez tous à cet endroit ;
      - œil : « Ramasser : chapeau » / « Ramasser : lunettes » (au sol) : n'importe quel joueur dont le personnage a le
        même modèle (homme / femme) ; remis tel quel (même modèle EUP, même texture).
    (Poser son chapeau sur un véhicule : retiré, ça ne fonctionnait pas.)
    Objet affiché : LE VRAI chapeau EUP (même modèle, même texture) : un personnage local invisible du même modèle le
    porte un instant, le jeu le lui fait tomber (KnockOffPedProp) et l'objet ainsi créé est gardé, posé à l'endroit.
    Si ça échoue (pièce introuvable…) : un modèle du jeu (LostProps.Models, ou Overrides par numéro).
    Performance : deux lectures de la tenue toutes les 300 ms ; objets mis à jour à chaque changement (état
    "rpWearGround") et toutes les 2,5 s (portée).
]]

local Config = VPConfig
local LP = Config.LostProps or {}
VPLost = {}
if LP.Enabled == false then return end

local NAMES = { [0] = 'chapeau', [1] = 'lunettes' }
local HEAD = 31086 -- SKEL_Head
local RANGE = 80.0

local function u32(h) return (math.tointeger(tonumber(h) or 0) or 0) & 0xFFFFFFFF end
local MALE, FEMALE = u32(GetHashKey('mp_m_freemode_01')), u32(GetHashKey('mp_f_freemode_01'))
local offset = LP.OneBased == false and 0 or 1

local function notify(text)
    if VPClient and VPClient.notify then return VPClient.notify(text) end
    TriggerEvent('chat:addMessage', { args = { 'Tenue', text } })
end

--- Modèle choisi dans la configuration pour une pièce (Overrides par numéro) ; nil : le vrai modèle EUP
local function overrideModel(item)
    local gender = u32(item.pedModel) == FEMALE and 'female' or (u32(item.pedModel) == MALE and 'male' or nil)
    for _, o in ipairs(LP.Overrides or {}) do
        if o.anchor == item.anchor and tonumber(o.drawable) and math.floor(o.drawable) - offset == item.drawable
            and (o.gender == nil or o.gender == gender) then
            return o.model
        end
    end
    return nil
end

--- Modèle de remplacement (Overrides, sinon Models) : utilisé si le vrai objet ne peut pas être créé
local function objectModel(item)
    return overrideModel(item) or (LP.Models or {})[item.anchor] or (item.anchor == 0 and 'prop_cap_01' or 'prop_cs_sol_glasses')
end
VPLost.objectModel = objectModel

local function loadModel(name)
    local model = type(name) == 'number' and name or GetHashKey(name)
    if model >= 0x80000000 then model = model - 0x100000000 end -- hash signé (32 bits)
    if not IsModelInCdimage(model) then return nil end
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(model) and model or nil
end

local creating = false -- un vrai objet à la fois (repéré parmi les nouveaux objets du jeu)

--- LE VRAI OBJET de la pièce EUP : un personnage local (non synchronisé), invisible et figé, du même modèle (homme /
--- femme) la porte ; le jeu la lui fait tomber (KnockOffPedProp) : l'objet créé est celui de la pièce (modèle et
--- texture). Retourne l'objet et sa rotation « portée sur la tête » (pour le poser à l'endroit), ou nil.
local function realObject(item, x, y, z)
    if LP.RealObject == false then return nil end
    local model = loadModel(u32(item.pedModel))
    if not model then return nil end
    while creating do Wait(0) end
    creating = true
    local ok, obj, rot = pcall(function()
        local ped = CreatePed(4, model, x, y, z + 1.0, 0.0, false, false)
        if not ped or ped == 0 then return nil end
        SetEntityVisible(ped, false, false)
        SetEntityCollision(ped, false, false)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedPreloadPropData(ped, item.anchor, item.drawable, item.texture or 0)
        local deadline = GetGameTimer() + 3000
        while not HasPedPreloadPropDataFinished(ped) and GetGameTimer() < deadline do Wait(0) end
        SetPedPropIndex(ped, item.anchor, item.drawable, item.texture or 0, true)
        ReleasePedPreloadPropData(ped)
        Wait(0)
        local found, rot = nil, nil
        if GetPedPropIndex(ped, item.anchor) == item.drawable then
            local before = {}
            for _, o in ipairs(GetGamePool('CObject')) do before[o] = true end
            KnockOffPedProp(ped, true, true, true, true)
            local head = GetEntityCoords(ped)
            local untilTime = GetGameTimer() + 1000
            repeat
                Wait(0)
                local best = 6.0
                for _, o in ipairs(GetGamePool('CObject')) do
                    if not before[o] and not IsEntityAttached(o) then
                        local d = #(GetEntityCoords(o) - head)
                        if d < best then found, best = o, d end
                    end
                end
            until found or GetGameTimer() >= untilTime
            if found then
                SetEntityAsMissionEntity(found, true, true)
                FreezeEntityPosition(found, true)
                SetEntityCollision(found, false, false)
                SetEntityInvincible(found, true)
                -- tombé d'un personnage invisible : l'objet peut l'être aussi -> toujours rendu visible
                SetEntityVisible(found, true, false)
                ResetEntityAlpha(found)
                SetEntityLodDist(found, 100)
                rot = GetEntityRotation(found, 2)
            end
        end
        DeletePed(ped)
        return found, rot
    end)
    creating = false
    SetModelAsNoLongerNeeded(model)
    if not ok then
        print(('^3[rp_vehicleprops] vrai chapeau EUP impossible (modèle de remplacement) : %s^7'):format(tostring(obj)))
        return nil
    end
    return obj, rot
end

--- Objet affiché pour une pièce : le vrai (sauf Overrides), sinon le modèle de remplacement ; et sa rotation de base
local function spawn(item, x, y, z)
    if not overrideModel(item) then
        local obj, rot = realObject(item, x, y, z)
        if obj then return obj, rot end
    end
    local model = loadModel(objectModel(item))
    if not model then return nil end
    local obj = CreateObjectNoOffset(model, x, y, z, false, false, false)
    SetModelAsNoLongerNeeded(model)
    if not obj or obj == 0 then return nil end
    SetEntityCollision(obj, false, false)
    SetEntityInvincible(obj, true)
    return obj, vector3(0.0, 0.0, 0.0)
end

--- Hauteur à ajouter pour que le BAS de l'objet (sa boîte, tournée de rx / ry) soit au point où on le pose.
--- Calculée sur le modèle (pas sur la position de l'objet dans le monde : juste après un AttachEntityToEntity, le jeu
--- ne l'a pas encore mise à jour, et l'ancienne position enfonçait le chapeau de 50 cm dans la carrosserie).
--- Rotation du jeu (ordre 2 : Y, puis X, puis Z ; Z ne change pas la hauteur).
local function bottomLift(obj, rx, ry)
    local mn, mx = GetModelDimensions(GetEntityModel(obj))
    if not mn or not mx then return 0.0 end
    local sx, cx = math.sin(math.rad(rx or 0.0)), math.cos(math.rad(rx or 0.0))
    local sy, cy = math.sin(math.rad(ry or 0.0)), math.cos(math.rad(ry or 0.0))
    local low = nil
    for _, x in ipairs({ mn.x, mx.x }) do
        for _, y in ipairs({ mn.y, mx.y }) do
            for _, z in ipairs({ mn.z, mx.z }) do
                local h = y * sx + (-x * sy + z * cy) * cx
                if not low or h < low then low = h end
            end
        end
    end
    if not low then return 0.0 end
    return math.max(-0.2, math.min(0.5, -low))
end
VPLost.bottomLift = bottomLift

-- =========================================================================
-- AFFICHAGE (chez tous) : au sol (GlobalState "rpWearGround")
-- =========================================================================
local ground = {} -- [id] = { obj, item }
local making = {} -- [id] = true : objet en cours de création (pas deux fois)

local function groundItems()
    local list = GlobalState.rpWearGround
    return type(list) == 'table' and list or {}
end

local function refreshGround()
    local me = GetEntityCoords(PlayerPedId())
    local keep = {}
    for _, item in ipairs(groundItems()) do
        if type(item) == 'table' and type(item.id) == 'string' and tonumber(item.x) then
            local pos = vector3(item.x + 0.0, item.y + 0.0, item.z + 0.0)
            if #(pos - me) <= RANGE then
                keep[item.id] = true
                local g = ground[item.id]
                if (not g or not DoesEntityExist(g.obj)) and not making[item.id] then
                    making[item.id] = true
                    local obj, base = spawn(item, pos.x, pos.y, pos.z)
                    making[item.id] = nil
                    if obj then
                        FreezeEntityPosition(obj, true)
                        local rx, ry = base.x + (tonumber(item.rx) or 0.0), base.y + (tonumber(item.ry) or 0.0)
                        SetEntityRotation(obj, rx, ry, base.z + (tonumber(item.rz) or 0.0), 2, true)
                        local lift = bottomLift(obj, rx, ry) -- posé à plat sur le sol
                        SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z + lift, false, false, false)
                        ground[item.id] = { obj = obj, item = item }
                    end
                end
            end
        end
    end
    for id, g in pairs(ground) do
        if not keep[id] then
            if DoesEntityExist(g.obj) then DeleteObject(g.obj) end
            ground[id] = nil
        end
    end
end
VPLost.refreshGround = refreshGround

AddStateBagChangeHandler('rpWearGround', 'global', function() CreateThread(refreshGround) end)

CreateThread(function()
    while true do
        Wait(2500)
        refreshGround()
    end
end)

-- =========================================================================
-- CHUTE : le chapeau / les lunettes du joueur tombent (pas retirés par un menu)
-- =========================================================================
local worn = {}       -- [ancre] = { drawable, texture, model }
local hurtAt = -100000

AddEventHandler('gameEventTriggered', function(name, args)
    if name == 'CEventNetworkEntityDamage' and type(args) == 'table' and args[1] == PlayerPedId() then
        hurtAt = GetGameTimer()
    end
end)

local function knocked(ped, now)
    if IsPedInAnyVehicle(ped, true) then return false end -- casque de moto : géré par le jeu
    return IsPedRagdoll(ped) or IsPedFalling(ped) or IsEntityDead(ped) or now - hurtAt <= 2000
end

local function groundUnder(pos)
    local ok, z = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 0.5, false)
    if ok then return vector3(pos.x, pos.y, z) end
    return vector3(pos.x, pos.y, pos.z - 1.0)
end

--- Objet que le jeu vient de faire tomber : objet du jeu (pas d'un script), non attaché, en mouvement, près de la
--- tête ; suivi jusqu'à ce qu'il s'arrête, puis retiré (l'objet synchronisé le remplace chez tous)
local function dropped(anchor, w, head, fallback)
    CreateThread(function()
        local found, best = nil, 2.5
        local untilTime = GetGameTimer() + 1500
        repeat
            for _, obj in ipairs(GetGamePool('CObject')) do
                if not IsEntityAMissionEntity(obj) and not IsEntityAttached(obj) then
                    local d = #(GetEntityCoords(obj) - head)
                    if d < best and #(GetEntityVelocity(obj)) > 0.15 then found, best = obj, d end
                end
            end
            if found then break end
            Wait(100)
        until GetGameTimer() >= untilTime
        local pos, heading = fallback, math.random(0, 359) + 0.0
        if found then
            SetEntityAsMissionEntity(found, true, true)
            local settle = GetGameTimer() + 5000
            while DoesEntityExist(found) and #(GetEntityVelocity(found)) > 0.05 and GetGameTimer() < settle do Wait(200) end
            if DoesEntityExist(found) then
                pos = GetEntityCoords(found)
                heading = GetEntityHeading(found)
                DeleteObject(found)
            end
        end
        local ground = groundUnder(pos)
        TriggerServerEvent('rp_vehicleprops:wearDrop', { anchor = anchor, drawable = w.drawable, texture = w.texture,
            x = pos.x, y = pos.y, z = ground.z + 0.01, rx = 0.0, ry = 0.0, rz = heading })
    end)
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local now = GetGameTimer()
        local model = GetEntityModel(ped)
        for anchor in pairs(NAMES) do
            local drawable = GetPedPropIndex(ped, anchor)
            if drawable >= 0 then
                worn[anchor] = { drawable = drawable, texture = GetPedPropTextureIndex(ped, anchor), model = model }
            elseif worn[anchor] then
                local w = worn[anchor]
                worn[anchor] = nil
                if w.model == model and knocked(ped, now) then
                    dropped(anchor, w, GetPedBoneCoords(ped, HEAD, 0.0, 0.0, 0.0), GetEntityCoords(ped))
                end
            end
        end
        Wait(LP.CheckMs or 300)
    end
end)

-- =========================================================================
-- ŒIL : ramasser au sol (tout le monde)
-- =========================================================================
local function playAnim()
    local anim = LP.Anim
    if not (anim and anim[1]) then return end
    RequestAnimDict(anim[1])
    local deadline = GetGameTimer() + 1500
    while not HasAnimDictLoaded(anim[1]) and GetGameTimer() < deadline do Wait(0) end
    if not HasAnimDictLoaded(anim[1]) then return end
    TaskPlayAnim(PlayerPedId(), anim[1], anim[2], 8.0, -8.0, anim[3] or 900, 48, 0.0, false, false, false)
    Wait(math.floor((anim[3] or 900) * 0.6))
    RemoveAnimDict(anim[1])
end

RegisterNetEvent('rp_vehicleprops:wearResult', function(ok, text)
    if not ok and type(text) == 'string' then notify(text) end
end)

RegisterNetEvent('rp_vehicleprops:wearGive', function(item)
    if type(item) ~= 'table' then return end
    CreateThread(function()
        playAnim()
        SetPedPropIndex(PlayerPedId(), item.anchor, item.drawable, item.texture or 0, true)
    end)
end)

local function itemsNear(info)
    local out = {}
    if type(info) ~= 'table' or not info.hit then return out end
    local hit = vector3(info.hit.x + 0.0, info.hit.y + 0.0, info.hit.z + 0.0)
    local me = GetEntityCoords(PlayerPedId())
    for id, g in pairs(ground) do
        local pos = DoesEntityExist(g.obj) and GetEntityCoords(g.obj) or vector3(g.item.x, g.item.y, g.item.z)
        local aimed = info.entity == g.obj or #(pos - hit) <= (LP.Snap or 1.2)
        if aimed and #(pos - me) <= (LP.Distance or 2.5) then out[#out + 1] = g.item end
    end
    return out
end

function VPLost.options(info, vehicle, out)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or type(info) ~= 'table' or vehicle then return end
    for _, item in ipairs(itemsNear(info)) do
        out[#out + 1] = { id = 'wear:pick:' .. item.id, icon = 'hand', primary = true,
            label = 'Ramasser : ' .. (NAMES[item.anchor] or 'objet') }
    end
end

function VPLost.select(id, info, vehicle)
    if type(id) ~= 'string' or id:sub(1, 5) ~= 'wear:' then return false end
    local ped = PlayerPedId()
    -- reprendre : l'emplacement doit être libre (chapeau déjà porté : l'enlever d'abord)
    local function free(anchor)
        if GetPedPropIndex(ped, anchor) >= 0 then
            notify(anchor == 0 and 'Vous portez déjà un chapeau : retirez-le d\'abord.' or 'Vous portez déjà des lunettes : retirez-les d\'abord.')
            return false
        end
        return true
    end
    if id:sub(1, 10) == 'wear:pick:' then
        local wanted = id:sub(11)
        local g = ground[wanted]
        if g and free(g.item.anchor) then TriggerServerEvent('rp_vehicleprops:wearPickup', wanted) end
    end
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, g in pairs(ground) do if DoesEntityExist(g.obj) then DeleteObject(g.obj) end end
end)

VPLost.ground = function() return ground end -- tests
