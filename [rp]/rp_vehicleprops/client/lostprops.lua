--[[
    RP VehicleProps - chapeaux / lunettes au sol ou sur un véhicule (client)
    ------------------------------------------------------------------------
    VISIBLES ET REPRIS PAR TOUS (synchronisés par le serveur, server/wear.lua ; aucune permission) :
      - TOMBÉS : le jeu fait tomber le chapeau (ancre 0 : casquette, casque, chapeau EUP…) ou les lunettes (ancre 1)
        d'un joueur qui chute, est bousculé, blessé, ragdoll (rp_adrenaline)… Son client le voit tomber, attend qu'il
        s'arrête, retire l'objet local du jeu et l'annonce au serveur : il apparaît chez tous à cet endroit ;
      - POSÉS SUR UN VÉHICULE : œil (rp_interact) sur un véhicule, chapeau / lunettes sur la tête : « Poser son chapeau
        sur le véhicule » (au point visé, sur la carrosserie) ;
      - œil : « Ramasser : chapeau » (au sol) / « Reprendre : chapeau » (sur le véhicule) : n'importe quel joueur dont
        le personnage a le même modèle (homme / femme) ; remis tel quel (même modèle EUP, même texture).
    Objet affiché : un modèle du jeu (LostProps.Models, et Overrides par numéro de chapeau / lunettes), le modèle EUP
    lui-même ne pouvant pas être posé comme objet.
    Performance : deux lectures de la tenue toutes les 300 ms ; objets mis à jour à chaque changement (états
    "rpWearGround" / "rpWear") et toutes les 2,5 s (portée).
]]

local Config = VPConfig
local LP = Config.LostProps or {}
VPLost = {}
if LP.Enabled == false then return end

local NAMES = { [0] = 'chapeau', [1] = 'lunettes' }
local PLACE_LABEL = { [0] = 'Poser son chapeau sur le véhicule', [1] = 'Poser ses lunettes sur le véhicule' }
local HEAD = 31086 -- SKEL_Head
local RANGE = 80.0

local function u32(h) return (math.tointeger(tonumber(h) or 0) or 0) & 0xFFFFFFFF end
local MALE, FEMALE = u32(GetHashKey('mp_m_freemode_01')), u32(GetHashKey('mp_f_freemode_01'))
local offset = LP.OneBased == false and 0 or 1

local function notify(text)
    if VPClient and VPClient.notify then return VPClient.notify(text) end
    TriggerEvent('chat:addMessage', { args = { 'Tenue', text } })
end

--- Modèle d'objet affiché pour une pièce (Overrides par numéro, sinon Models)
local function objectModel(item)
    local gender = u32(item.pedModel) == FEMALE and 'female' or (u32(item.pedModel) == MALE and 'male' or nil)
    for _, o in ipairs(LP.Overrides or {}) do
        if o.anchor == item.anchor and tonumber(o.drawable) and math.floor(o.drawable) - offset == item.drawable
            and (o.gender == nil or o.gender == gender) then
            return o.model
        end
    end
    return (LP.Models or {})[item.anchor] or (item.anchor == 0 and 'prop_cap_01' or 'prop_cs_sol_glasses')
end
VPLost.objectModel = objectModel

local function loadModel(name)
    local model = type(name) == 'number' and name or GetHashKey(name)
    if not IsModelInCdimage(model) then return nil end
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(model) and model or nil
end

local function spawn(item, x, y, z)
    local model = loadModel(objectModel(item))
    if not model then return nil end
    local obj = CreateObjectNoOffset(model, x, y, z, false, false, false)
    SetModelAsNoLongerNeeded(model)
    if not obj or obj == 0 then return nil end
    SetEntityCollision(obj, false, false)
    SetEntityInvincible(obj, true)
    return obj
end

-- =========================================================================
-- AFFICHAGE (chez tous) : au sol (GlobalState "rpWearGround") et sur les véhicules (état "rpWear")
-- =========================================================================
local ground = {} -- [id] = { obj, item }
local onVehicles = {} -- [véhicule] = { sig, objects = { [id] = { obj, item } } }

local function groundItems()
    local list = GlobalState.rpWearGround
    return type(list) == 'table' and list or {}
end

local function vehicleItems(vehicle)
    local list, out = Entity(vehicle).state.rpWear, {}
    if type(list) == 'table' then
        for _, item in ipairs(list) do if type(item) == 'table' and type(item.id) == 'string' then out[#out + 1] = item end end
    end
    return out
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
                if not g or not DoesEntityExist(g.obj) then
                    local obj = spawn(item, pos.x, pos.y, pos.z)
                    if obj then
                        FreezeEntityPosition(obj, true)
                        SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z, false, false, false)
                        SetEntityRotation(obj, (tonumber(item.rx) or 0.0) + 0.0, (tonumber(item.ry) or 0.0) + 0.0,
                            (tonumber(item.rz) or 0.0) + 0.0, 2, true)
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

local function clearVehicle(vehicle)
    local entry = onVehicles[vehicle]
    if not entry then return end
    for _, o in pairs(entry.objects) do if DoesEntityExist(o.obj) then DeleteObject(o.obj) end end
    onVehicles[vehicle] = nil
end

local function refreshVehicle(vehicle)
    if not DoesEntityExist(vehicle) then return clearVehicle(vehicle) end
    local list = vehicleItems(vehicle)
    local ids = {}
    for _, item in ipairs(list) do ids[#ids + 1] = item.id end
    local sig = table.concat(ids, '|')
    if onVehicles[vehicle] and onVehicles[vehicle].sig == sig then return end
    clearVehicle(vehicle)
    if #list == 0 then return end
    local entry = { sig = sig, objects = {} }
    onVehicles[vehicle] = entry
    local c = GetEntityCoords(vehicle)
    for _, item in ipairs(list) do
        local obj = spawn(item, c.x, c.y, c.z - 3.0)
        if obj then
            AttachEntityToEntity(obj, vehicle, 0, (tonumber(item.x) or 0.0) + 0.0, (tonumber(item.y) or 0.0) + 0.0,
                (tonumber(item.z) or 0.0) + 0.0, (tonumber(item.rx) or 0.0) + 0.0, (tonumber(item.ry) or 0.0) + 0.0,
                (tonumber(item.rz) or 0.0) + 0.0, false, false, false, false, 2, true)
            entry.objects[item.id] = { obj = obj, item = item }
        end
    end
end
VPLost.refreshVehicle = refreshVehicle

AddStateBagChangeHandler('rpWearGround', 'global', function() SetTimeout(0, refreshGround) end)
AddStateBagChangeHandler('rpWear', nil, function(bagName)
    CreateThread(function()
        local untilTime = GetGameTimer() + 3000
        local vehicle = GetEntityFromStateBagName(bagName)
        while (vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < untilTime do
            Wait(100)
            vehicle = GetEntityFromStateBagName(bagName)
        end
        if vehicle ~= 0 then Wait(0); refreshVehicle(vehicle) end
    end)
end)

CreateThread(function()
    while true do
        Wait(2500)
        for vehicle in pairs(onVehicles) do if not DoesEntityExist(vehicle) then clearVehicle(vehicle) end end
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if onVehicles[vehicle] or Entity(vehicle).state.rpWear then refreshVehicle(vehicle) end
        end
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
            x = pos.x, y = pos.y, z = math.max(ground.z + 0.03, math.min(pos.z, ground.z + 0.3)), rx = 0.0, ry = 0.0, rz = heading })
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
-- ŒIL : poser sur un véhicule, ramasser au sol, reprendre sur un véhicule (tout le monde)
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

local pendingPlace = nil -- pièce retirée de la tête, rendue si le serveur refuse

RegisterNetEvent('rp_vehicleprops:wearResult', function(ok, text)
    if not ok and pendingPlace then
        SetPedPropIndex(PlayerPedId(), pendingPlace.anchor, pendingPlace.drawable, pendingPlace.texture, true)
    end
    pendingPlace = nil
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
    if IsPedInAnyVehicle(ped, false) or type(info) ~= 'table' then return end
    if vehicle then
        for anchor, label in pairs(PLACE_LABEL) do
            if GetPedPropIndex(ped, anchor) >= 0 then
                out[#out + 1] = { id = 'wear:place:' .. anchor, icon = 'hand', primary = true, label = label }
            end
        end
        for _, item in ipairs(vehicleItems(vehicle)) do
            out[#out + 1] = { id = 'wear:take:' .. item.id, icon = 'hand', primary = true,
                label = 'Reprendre : ' .. (NAMES[item.anchor] or 'objet') }
        end
        return
    end
    for _, item in ipairs(itemsNear(info)) do
        out[#out + 1] = { id = 'wear:pick:' .. item.id, icon = 'hand', primary = true,
            label = 'Ramasser : ' .. (NAMES[item.anchor] or 'objet') }
    end
end

--- Poser la pièce portée sur la carrosserie, au point visé
local function placeOnVehicle(info, vehicle, anchor)
    local ped = PlayerPedId()
    local drawable = GetPedPropIndex(ped, anchor)
    if drawable < 0 then return end
    local point = info.hit and vector3(info.hit.x + 0.0, info.hit.y + 0.0, info.hit.z + 0.0) or GetEntityCoords(vehicle)
    if VPHeld and VPHeld.surfaceAt then
        local hit = VPHeld.surfaceAt(point, 2, vehicle)
        if hit then point = hit end
    end
    local o = GetOffsetFromEntityGivenWorldCoords(vehicle, point.x, point.y, point.z + 0.02)
    local yaw = (GetEntityHeading(ped) - GetEntityHeading(vehicle)) + math.random(-30, 30)
    yaw = ((yaw + 180.0) % 360.0) - 180.0
    local piece = { anchor = anchor, drawable = drawable, texture = GetPedPropTextureIndex(ped, anchor),
        offsets = { x = o.x, y = o.y, z = o.z, rx = 0.0, ry = 0.0, rz = yaw } }
    CreateThread(function()
        playAnim()
        if GetPedPropIndex(PlayerPedId(), anchor) ~= drawable then return end
        pendingPlace = piece
        worn[anchor] = nil -- retiré par le joueur, pas tombé
        ClearPedProp(PlayerPedId(), anchor)
        TriggerServerEvent('rp_vehicleprops:wearPlaceVehicle', VehToNet(vehicle), piece)
    end)
end

function VPLost.select(id, info, vehicle)
    if type(id) ~= 'string' or id:sub(1, 5) ~= 'wear:' then return false end
    local ped = PlayerPedId()
    if id:sub(1, 11) == 'wear:place:' then
        if vehicle then placeOnVehicle(info, vehicle, tonumber(id:sub(12)) or 0) end
        return true
    end
    -- reprendre : l'emplacement doit être libre (chapeau déjà porté : l'enlever d'abord)
    local function free(anchor)
        if GetPedPropIndex(ped, anchor) >= 0 then
            notify(anchor == 0 and 'Vous portez déjà un chapeau : retirez-le d\'abord.' or 'Vous portez déjà des lunettes : retirez-les d\'abord.')
            return false
        end
        return true
    end
    if id:sub(1, 10) == 'wear:take:' and vehicle then
        local wanted = id:sub(11)
        for _, item in ipairs(vehicleItems(vehicle)) do
            if item.id == wanted and free(item.anchor) then TriggerServerEvent('rp_vehicleprops:wearTake', VehToNet(vehicle), wanted) end
        end
    elseif id:sub(1, 10) == 'wear:pick:' then
        local wanted = id:sub(11)
        local g = ground[wanted]
        if g and free(g.item.anchor) then TriggerServerEvent('rp_vehicleprops:wearPickup', wanted) end
    end
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, g in pairs(ground) do if DoesEntityExist(g.obj) then DeleteObject(g.obj) end end
    for vehicle in pairs(onVehicles) do clearVehicle(vehicle) end
end)

VPLost.ground = function() return ground end -- tests
