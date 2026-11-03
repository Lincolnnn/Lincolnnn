--[[
    RP VehicleProps - chapeau / lunettes tombés (client)
    ----------------------------------------------------
    Le jeu fait tomber le chapeau (ancre 0 : casquette, casque, chapeau EUP…) ou les lunettes (ancre 1) d'un personnage
    qui chute, prend un coup ou une balle, ragdoll (rp_adrenaline)… Ici, côté du joueur à qui ils appartiennent :
      - la tenue portée (modèle + texture) est relevée toutes les CheckMs ms ;
      - quand le chapeau / les lunettes disparaissent PENDANT une chute, un ragdoll ou juste après une blessure (pas
        quand le joueur les retire avec un menu), ils sont retenus avec l'endroit de la chute ; l'objet que le jeu a
        fait tomber est cherché autour de la tête (objet du jeu, non attaché, en mouvement juste après la chute) et
        suivi jusqu'à ce qu'il s'arrête ;
      - œil (rp_interact) sur l'objet ou à côté : « Ramasser : chapeau » / « Ramasser : lunettes » -> petit geste,
        objet retiré du sol, chapeau / lunettes remis tels quels (même modèle EUP, même texture).
    Remis par un menu entre-temps (EUP, vMenu…) : plus rien à ramasser. Oublié après Expire s, ou si le personnage
    change de modèle. Si l'objet du jeu n'a pas été retrouvé, un petit repère est dessiné à l'endroit (Marker) tant que
    le joueur est à moins de 15 m.
    Performance : deux lectures de la tenue toutes les 300 ms ; recherche de l'objet 1,5 s après une chute seulement ;
    repère : seulement à moins de 15 m d'un objet non retrouvé.
]]

local Config = VPConfig
local LP = Config.LostProps or {}
VPLost = {}
if LP.Enabled == false then return end

local NAMES = { [0] = 'chapeau', [1] = 'lunettes' }
local HEAD = 31086 -- SKEL_Head

local worn = {}   -- [ancre] = { drawable, texture }
local lost = {}   -- [ancre] = { drawable, texture, model, pos, obj, at }
local hurtAt = -100000
local markerRunning = false

local function notify(text)
    if VPClient and VPClient.notify then return VPClient.notify(text) end
    TriggerEvent('chat:addMessage', { args = { 'Tenue', text } })
end

-- Blessé (balle, coup, chute, véhicule) : un chapeau qui tombe juste après est « tombé », pas retiré
AddEventHandler('gameEventTriggered', function(name, args)
    if name == 'CEventNetworkEntityDamage' and type(args) == 'table' and args[1] == PlayerPedId() then
        hurtAt = GetGameTimer()
    end
end)

--- Le chapeau / les lunettes viennent-ils de tomber (et pas d'être retirés par un menu) ?
local function knocked(ped, now)
    if IsPedInAnyVehicle(ped, true) then return false end -- casque de moto : géré par le jeu
    return IsPedRagdoll(ped) or IsPedFalling(ped) or IsEntityDead(ped) or now - hurtAt <= 2000
end

local function forget(anchor, keepObject)
    local item = lost[anchor]
    lost[anchor] = nil
    if item and item.obj and not keepObject and DoesEntityExist(item.obj) then
        SetEntityAsMissionEntity(item.obj, true, true)
        DeleteObject(item.obj)
    end
end

--- Position d'un objet tombé (l'objet du jeu s'il a été retrouvé)
local function itemPos(item)
    if item.obj and DoesEntityExist(item.obj) then return GetEntityCoords(item.obj) end
    return item.pos
end

local function startMarker()
    if markerRunning or LP.Marker == false then return end
    markerRunning = true
    CreateThread(function()
        while next(lost) do
            local me = GetEntityCoords(PlayerPedId())
            local drawn = false
            for _, item in pairs(lost) do
                if not (item.obj and DoesEntityExist(item.obj)) and #(item.pos - me) <= 15.0 then
                    DrawMarker(2, item.pos.x, item.pos.y, item.pos.z + 0.25, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0,
                        0.12, 0.12, 0.12, 255, 255, 255, 160, false, true, 2, false, nil, nil, false)
                    drawn = true
                end
            end
            Wait(drawn and 0 or 500)
        end
        markerRunning = false
    end)
end

--- Cherche l'objet que le jeu vient de faire tomber : objet du jeu (pas d'un script), non attaché, en mouvement,
--- près de la tête ; puis le suit jusqu'à ce qu'il s'arrête (position de la chute)
local function findObject(anchor, item, head)
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
        if lost[anchor] ~= item then return end
        if found then
            SetEntityAsMissionEntity(found, true, true) -- pas nettoyé par le jeu tant qu'il n'est pas ramassé
            item.obj = found
            local settle = GetGameTimer() + 5000
            while DoesEntityExist(found) and #(GetEntityVelocity(found)) > 0.05 and GetGameTimer() < settle do Wait(200) end
            if DoesEntityExist(found) then item.pos = GetEntityCoords(found) end
        else
            startMarker()
        end
    end)
end

--- Position au sol sous un point (repli si l'objet du jeu n'est pas retrouvé)
local function groundUnder(pos)
    local ok, z = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 0.5, false)
    if ok then return vector3(pos.x, pos.y, z) end
    return vector3(pos.x, pos.y, pos.z - 1.0)
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
                if lost[anchor] then forget(anchor) end -- remis (ramassé ou par un menu) : plus rien au sol
            elseif worn[anchor] then
                local w = worn[anchor]
                worn[anchor] = nil
                if w.model == model and knocked(ped, now) then
                    local head = GetPedBoneCoords(ped, HEAD, 0.0, 0.0, 0.0)
                    forget(anchor)
                    local item = { drawable = w.drawable, texture = w.texture, model = model, at = now,
                        pos = groundUnder(GetEntityCoords(ped)) }
                    lost[anchor] = item
                    findObject(anchor, item, head)
                end
            end
            local item = lost[anchor]
            if item and (now - item.at > (LP.Expire or 900) * 1000 or item.model ~= model) then forget(anchor) end
        end
        Wait(LP.CheckMs or 300)
    end
end)

-- =========================================================================
-- ŒIL : « Ramasser : chapeau / lunettes » (options ajoutées par client/client.lua, exports targetOptions)
-- =========================================================================
function VPLost.options(info, vehicle, out)
    if vehicle or not next(lost) or type(info) ~= 'table' then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    local me = GetEntityCoords(ped)
    local hit = info.hit and vector3(info.hit.x + 0.0, info.hit.y + 0.0, info.hit.z + 0.0)
    for anchor, item in pairs(lost) do
        local pos = itemPos(item)
        local aimed = (item.obj and info.entity == item.obj) or (hit and #(pos - hit) <= (LP.Snap or 1.2))
        if aimed and #(pos - me) <= (LP.Distance or 2.5) then
            out[#out + 1] = { id = 'lost:' .. anchor, icon = 'hand', primary = true, label = 'Ramasser : ' .. NAMES[anchor] }
        end
    end
end

function VPLost.select(id, info)
    if type(id) ~= 'string' or id:sub(1, 5) ~= 'lost:' then return false end
    local anchor = tonumber(id:sub(6))
    local item = anchor and lost[anchor]
    if not item then return true end
    local ped = PlayerPedId()
    if #(itemPos(item) - GetEntityCoords(ped)) > (LP.Distance or 2.5) + 0.5 then notify('Rapprochez-vous.') return true end
    if GetEntityModel(ped) ~= item.model then forget(anchor) notify('Cette tenue ne va plus avec votre personnage.') return true end
    CreateThread(function()
        local anim = LP.Anim
        if anim and anim[1] then
            RequestAnimDict(anim[1])
            local deadline = GetGameTimer() + 1500
            while not HasAnimDictLoaded(anim[1]) and GetGameTimer() < deadline do Wait(0) end
            if HasAnimDictLoaded(anim[1]) then
                TaskPlayAnim(ped, anim[1], anim[2], 8.0, -8.0, anim[3] or 900, 48, 0.0, false, false, false)
                Wait(math.floor((anim[3] or 900) * 0.6))
                RemoveAnimDict(anim[1])
            end
        end
        if lost[anchor] ~= item then return end
        SetPedPropIndex(ped, anchor, item.drawable, item.texture, true)
        forget(anchor)
        worn[anchor] = { drawable = item.drawable, texture = item.texture, model = item.model }
    end)
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for anchor in pairs(lost) do forget(anchor) end
end)

VPLost.lost = function() return lost end -- tests
