--[[
    RP VehicleProps - arme / lampe tenue en main (client)
    -----------------------------------------------------
    ŒIL (rp_interact), arme ou lampe en main :
      - sur un véhicule : « Poser l'arme ici » (au point visé), « … sur le toit » (au-dessus de la portière la plus
        proche : 4 endroits), « … sur le coffre » (véhicules à coffre plat : berlines…). L'arme est posée DIRECTEMENT sur la carrosserie, sans physique (elle ne glisse plus) :
        des rayons vers le bas trouvent la surface (collision du véhicule, comme les impacts de balles) et son
        inclinaison ; l'arme est couchée, inclinée comme la surface et posée au ras (son point le plus bas la touche).
        Collée au véhicule chez tous les joueurs, avec ses accessoires (rp_interact : captureWeapon), sa teinte, ses
        munitions et sa lampe allumée si elle l'était. « Reprendre : … » : rendue telle quelle (giveWeapon) ;
      - n'importe où ailleurs (sol, mur, personne…) : « Poser l'arme au sol » (la lampe aussi), de la même façon, sur
        le sol ; « Ramasser : … » avec l'œil. La jeter reste possible avec rp_RoleplayZone (touche G).
    Le Taser se pose au sol avec rp_taser10 (sondes gardées) ; relié à un suspect, il ne va pas sur un véhicule.
    Lumière : arme avec une lampe allumée : vraie lampe du jeu sur l'arme posée ; lampe torche : lumière du modèle
    (comme CartoonFlashlight), faisceau dessiné en plus si Held.Beam.Drawn.
    Performance : vérifications toutes les 1,5 à 2,5 s ; rien à chaque image (sauf faisceaux dessinés, si activés).
]]

local Config = VPConfig
local H = Config.Held or {}
VPHeld = {}
if H.Enabled == false then return end

local B = H.Beam or {}

local function u32(h) return (math.tointeger(tonumber(h) or 0) or 0) & 0xFFFFFFFF end
local function signed(h) h = u32(h) if h > 0x7FFFFFFF then h = h - 0x100000000 end return h end

local UNARMED = u32(GetHashKey('WEAPON_UNARMED'))
local STUNGUN = u32(GetHashKey('GROUP_STUNGUN'))
local TORCHES = {}
for name, model in pairs(H.Torches or {}) do TORCHES[u32(GetHashKey(name))] = model end
local GROUND_TORCHES = {} -- lampe posée au sol : son propre modèle (prop_cs_police_torch_02)
for name, model in pairs(H.GroundTorches or {}) do GROUND_TORCHES[u32(GetHashKey(name))] = model end

--- Modèle d'une lampe : au sol, celui de GroundTorches ; sinon (véhicule) celui de la lampe tenue
local function torchModel(hash, ground)
    hash = u32(hash)
    return ground and GROUND_TORCHES[hash] or TORCHES[hash]
end
local EXCLUDED, EXCLUDED_GROUPS = {}, {}
for _, n in ipairs(H.Excluded or {}) do EXCLUDED[u32(GetHashKey(n))] = true end
for _, g in ipairs(H.ExcludedGroups or {}) do EXCLUDED_GROUPS[u32(GetHashKey(g))] = true end
local NO_SPOTS = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true } -- motos, vélos, bateaux…

local busy = false     -- pose en cours (jusqu'à la réponse du serveur)
local pending = nil    -- arme partie des mains, rendue si le serveur refuse

local function notify(text)
    if VPClient and VPClient.notify then return VPClient.notify(text) end
    TriggerEvent('chat:addMessage', { args = { 'Objets', text } })
end

-- =========================================================================
-- ARME EN MAIN
-- =========================================================================
local function isTaser(h) return u32(GetWeapontypeGroup(signed(h))) == STUNGUN end

--- Arme tenue pouvant être posée (empreinte non signée) ou nil
local function heldHash(ped)
    local h = u32(GetSelectedPedWeapon(ped))
    if h == 0 or h == UNARMED or EXCLUDED[h] or EXCLUDED_GROUPS[u32(GetWeapontypeGroup(signed(h)))] then return nil end
    if not TORCHES[h] and (GetWeapontypeModel(signed(h)) or 0) == 0 then return nil end
    return h
end

--- Taser relié à un suspect (rp_taser10 : sondes tirées) : il ne quitte pas la main pour un véhicule
local function taserConnected(h)
    if not isTaser(h) or GetResourceState('rp_taser10') ~= 'started' then return false end
    local ok, state = pcall(function() return exports.rp_taser10:getTaserState() end)
    return ok and type(state) == 'table' and (state.connectionState == 'CONNECTED' or state.connectionState == 'PARTIAL')
end

local function capture()
    if GetResourceState('rp_interact') ~= 'started' then return nil end
    local ok, w = pcall(function() return exports.rp_interact:captureWeapon() end)
    if not ok or type(w) ~= 'table' then return nil end
    w.hash = u32(w.hash)
    w.torch = TORCHES[w.hash] ~= nil
    return w
end

local function give(w)
    if GetResourceState('rp_interact') == 'started'
        and pcall(function() exports.rp_interact:giveWeapon(w, true) end) then return end
    GiveWeaponToPed(PlayerPedId(), signed(w.hash), tonumber(w.ammo) or 0, false, true)
end

--- L'arme quitte les mains (rendue si le serveur refuse)
local function release(ped, w)
    pending = w
    SetCurrentPedWeapon(ped, UNARMED, true)
    SetPedAmmo(ped, signed(w.hash), 0)
    RemoveWeaponFromPed(ped, signed(w.hash))
end

local function loadAnim(dict)
    RequestAnimDict(dict)
    local untilTime = GetGameTimer() + 1500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < untilTime do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function loadModel(name)
    local hash = type(name) == 'number' and name or GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local untilTime = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < untilTime do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

--- Modèle de l'objet posé : lampe (au sol : prop_cs_police_torch_02 ; véhicule : modèle de la lampe tenue) ou arme
local function modelOf(w, ground)
    if TORCHES[u32(w.hash)] then return GetHashKey(torchModel(w.hash, ground)) end
    return GetWeapontypeModel(signed(w.hash))
end

-- =========================================================================
-- POSE SUR UNE SURFACE : couchée, inclinée comme la surface, au ras (point le plus bas posé dessus)
-- Rotations du jeu « ordre 2 » : R = Rz(z) · Rx(x) · Ry(y) (x tangage, y roulis, z lacet), comme AttachEntityToEntity
-- =========================================================================
local function eulerMatrix(x, y, z)
    x, y, z = math.rad(x), math.rad(y), math.rad(z)
    local cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    return {
        { cz * cy - sz * sx * sy, -sz * cx, cz * sy + sz * sx * cy },
        { sz * cy + cz * sx * sy, cz * cx, sz * sy - cz * sx * cy },
        { -cx * sy, sx, cx * cy },
    }
end

local function matrixEuler(m)
    local x = math.asin(math.max(-1.0, math.min(1.0, m[3][2])))
    return math.deg(x), math.deg(math.atan(-m[3][1], m[3][3])), math.deg(math.atan(-m[1][2], m[2][2]))
end

local function mul(a, b)
    local out = {}
    for i = 1, 3 do
        out[i] = {}
        for j = 1, 3 do out[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end
    end
    return out
end

--- Rotation qui amène le haut (0, 0, 1) sur la normale n de la surface
local function alignUp(n)
    local vx, vy, c = -n.y, n.x, n.z
    local s2 = vx * vx + vy * vy
    if s2 < 1e-9 then return c >= 0 and eulerMatrix(0, 0, 0) or eulerMatrix(180, 0, 0) end
    local k = (1 - c) / s2
    local K = { { 0, 0, vy }, { 0, 0, -vx }, { -vy, vx, 0 } }
    local K2 = mul(K, K)
    local out = {}
    for i = 1, 3 do
        out[i] = {}
        for j = 1, 3 do out[i][j] = (i == j and 1 or 0) + K[i][j] + K2[i][j] * k end
    end
    return out
end

--- Position et rotation de l'objet couché sur la surface (point, normale), dans le repère du point (véhicule ou monde)
local function surfacePose(model, hit, n, yaw)
    local min, max = GetModelDimensions(model)
    local size = max - min
    local bx, by = 0.0, 0.0
    if size.x <= size.y and size.x <= size.z then by = 90.0 elseif size.y <= size.z then bx = 90.0 end
    local m = mul(alignUp(n), eulerMatrix(bx, by, yaw))
    local lowest = math.huge
    for _, cx in ipairs({ min.x, max.x }) do
        for _, cy in ipairs({ min.y, max.y }) do
            for _, cz in ipairs({ min.z, max.z }) do
                local px = m[1][1] * cx + m[1][2] * cy + m[1][3] * cz
                local py = m[2][1] * cx + m[2][2] * cy + m[2][3] * cz
                local pz = m[3][1] * cx + m[3][2] * cy + m[3][3] * cz
                local d = px * n.x + py * n.y + pz * n.z
                if d < lowest then lowest = d end
            end
        end
    end
    local lift = -lowest + (H.Lift or 0.004)
    local rx, ry, rz = matrixEuler(m)
    return vector3(hit.x + n.x * lift, hit.y + n.y * lift, hit.z + n.z * lift), rx, ry, rz
end
VPHeld.surfacePose = surfacePose

local function normalize(v)
    local l = #v
    if l < 1e-6 then return vector3(0.0, 0.0, 1.0) end
    return vector3(v.x / l, v.y / l, v.z / l)
end

--- Rayon vertical au-dessus de ce point : surface touchée (point, normale) ; entity : seulement ce véhicule
local function rayDown(point, flags, entity)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(point.x, point.y, point.z + 1.5, point.x, point.y,
        point.z - 1.5, flags, PlayerPedId(), 7)
    local _, hit, coords, normal, touched = GetShapeTestResult(handle)
    if not (hit == 1 or hit == true) or (entity and touched ~= entity) then return nil end
    return coords, normal
end

--- Surface sous ce point : point au centre, normale moyenne de 5 rayons (les courbes de la carrosserie / du sol)
local function surfaceAt(point, flags, entity)
    local hit, normal = rayDown(point, flags, entity)
    if not hit then return nil end
    local sum = normal
    for _, o in ipairs({ { 0.1, 0.0 }, { -0.1, 0.0 }, { 0.0, 0.1 }, { 0.0, -0.1 } }) do
        local h2, n2 = rayDown(vector3(point.x + o[1], point.y + o[2], point.z), flags, entity)
        if h2 and math.abs(h2.z - hit.z) < 0.12 then sum = sum + n2 end
    end
    return hit, normalize(sum)
end
VPHeld.surfaceAt = surfaceAt

-- =========================================================================
-- EMPLACEMENTS SUR UN VÉHICULE : ici (point visé), toit, coffre plat (berlines…)
-- =========================================================================
local spotsCache = {} -- [modèle] = { roof = bool, trunk = bool }

local function spotPoint(vehicle, spot)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local y = spot == 'trunk' and (min.y + (max.y - min.y) * 0.12) or ((min.y + max.y) * 0.5 - 0.35)
    return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, y, max.z + 0.2)
end

--- Toit : 4 endroits, au-dessus des portières (avant / arrière, gauche / droite) ; celui de la portière la plus
--- proche du joueur. La charnière (os de la portière) est à l'avant de la portière : on recule vers son milieu, puis
--- on garde le premier point où la surface est le toit (presque plat, tout en haut du véhicule)
local DOORS = { { bone = 'door_dside_f', front = true }, { bone = 'door_pside_f', front = true },
    { bone = 'door_dside_r' }, { bone = 'door_pside_r' } }

local function roofPoint(vehicle)
    local me = GetEntityCoords(PlayerPedId())
    local best
    for _, d in ipairs(DOORS) do
        local bone = GetEntityBoneIndexByName(vehicle, d.bone)
        if bone ~= -1 then
            local world = GetWorldPositionOfEntityBone(vehicle, bone)
            local dist = #(world - me)
            if not best or dist < best.dist then best = { dist = dist, world = world, front = d.front } end
        end
    end
    if not best then return spotPoint(vehicle, 'roof') end
    local _, max = GetModelDimensions(GetEntityModel(vehicle))
    local door = GetOffsetFromEntityGivenWorldCoords(vehicle, best.world.x, best.world.y, best.world.z)
    local x = (door.x >= 0 and 1 or -1) * math.min(math.abs(door.x) * 0.4, 0.35)
    for _, back in ipairs(best.front and { 0.45, 0.6, 0.75, 0.3 } or { 0.35, 0.5, 0.2, 0.65 }) do
        local p = GetOffsetFromEntityInWorldCoords(vehicle, x, door.y - back, max.z + 0.2)
        local hit, n = rayDown(p, 2, vehicle)
        if hit then
            local hl = GetOffsetFromEntityGivenWorldCoords(vehicle, hit.x, hit.y, hit.z)
            local up = normalize(GetOffsetFromEntityGivenWorldCoords(vehicle, hit.x + n.x, hit.y + n.y, hit.z + n.z) - hl)
            if up.z > 0.9 and hl.z > max.z - 0.45 then return p end
        end
    end
    return spotPoint(vehicle, 'roof')
end
VPHeld.roofPoint = roofPoint

--- Toit (tous les véhicules à toit) et coffre plat (nettement plus bas que le toit, presque horizontal)
local function vehicleSpots(vehicle)
    local model = GetEntityModel(vehicle)
    if spotsCache[model] then return spotsCache[model] end
    local out = { roof = false, trunk = false }
    if not NO_SPOTS[GetVehicleClass(vehicle)] then
        local roof = rayDown(spotPoint(vehicle, 'roof'), 2, vehicle)
        local trunk, tn = rayDown(spotPoint(vehicle, 'trunk'), 2, vehicle)
        out.roof = roof ~= nil
        if roof and trunk then
            local rl = GetOffsetFromEntityGivenWorldCoords(vehicle, roof.x, roof.y, roof.z)
            local tl = GetOffsetFromEntityGivenWorldCoords(vehicle, trunk.x, trunk.y, trunk.z)
            local up = GetOffsetFromEntityGivenWorldCoords(vehicle, trunk.x + tn.x, trunk.y + tn.y, trunk.z + tn.z) - tl
            out.trunk = rl.z - tl.z > 0.25 and normalize(up).z > 0.85
        end
    end
    spotsCache[model] = out
    return out
end
VPHeld.vehicleSpots = vehicleSpots

-- =========================================================================
-- POSER
-- =========================================================================
local function placeOnVehicle(info, vehicle, spot)
    local ped = PlayerPedId()
    local w = capture()
    if not w or heldHash(ped) ~= w.hash then return end
    if taserConnected(w.hash) then return notify('Taser relié au suspect : posez-le au sol.') end
    local point
    if spot == 'here' and info.hit then point = vector3(info.hit.x, info.hit.y, info.hit.z)
    elseif spot == 'roof' then point = roofPoint(vehicle)
    else point = spotPoint(vehicle, spot) end
    local hit, normal = surfaceAt(point, 2, vehicle)
    if not hit then return notify('Impossible de poser l\'arme à cet endroit.') end
    local model = modelOf(w)
    if not loadModel(model) then return notify('Modèle introuvable.') end
    busy = true
    CreateThread(function()
        if loadAnim('mp_common') then
            TaskPlayAnim(ped, 'mp_common', 'givetake1_a', 8.0, -8.0, 1100, 48, 0.0, false, false, false)
        end
        Wait(450)
        if not DoesEntityExist(vehicle) then busy = false return end
        -- dans le repère du véhicule : point, normale, lacet (canon vers la gauche du joueur)
        local hl = GetOffsetFromEntityGivenWorldCoords(vehicle, hit.x, hit.y, hit.z)
        local nl = normalize(GetOffsetFromEntityGivenWorldCoords(vehicle, hit.x + normal.x, hit.y + normal.y, hit.z + normal.z) - hl)
        local yaw = GetEntityHeading(ped) - GetEntityHeading(vehicle) + 90.0
        local pos, rx, ry, rz = surfacePose(model, hl, nl, yaw)
        SetModelAsNoLongerNeeded(model)
        release(ped, w)
        w.offsets = { x = pos.x, y = pos.y, z = pos.z, rx = rx, ry = ry, rz = rz }
        TriggerServerEvent('rp_vehicleprops:placeWeapon', VehToNet(vehicle), w)
    end)
end

local function placeOnGround(info)
    local ped = PlayerPedId()
    local w = capture()
    if not w or heldHash(ped) ~= w.hash then return end
    local origin = GetEntityCoords(ped)
    local point
    if info.hit and #(vector3(info.hit.x, info.hit.y, info.hit.z) - origin) <= (H.GroundDistance or 3.0) then
        point = vector3(info.hit.x, info.hit.y, info.hit.z)
    else
        point = GetOffsetFromEntityInWorldCoords(ped, 0.1, 0.6, -0.5)
    end
    local hit, normal = surfaceAt(point, 1 | 16, nil)
    if not hit then return notify('Impossible de poser l\'arme ici.') end
    local model = modelOf(w, true)
    if not loadModel(model) then return notify('Modèle introuvable.') end
    busy = true
    CreateThread(function()
        if loadAnim('pickup_object') then
            TaskPlayAnim(ped, 'pickup_object', 'putdown_low', 8.0, -8.0, 900, 0, 0.0, false, false, false)
        end
        Wait(450)
        local pos, rx, ry, rz = surfacePose(model, hit, normal, GetEntityHeading(ped) + 90.0)
        SetModelAsNoLongerNeeded(model)
        release(ped, w)
        w.x, w.y, w.z, w.rx, w.ry, w.rz = pos.x, pos.y, pos.z, rx, ry, rz
        TriggerServerEvent('rp_vehicleprops:placeGround', w)
    end)
end

-- Réponse du serveur : posée (elle apparaît chez tous) ou refusée (l'arme est rendue)
RegisterNetEvent('rp_vehicleprops:held', function(ok, text)
    local p = pending
    pending = nil
    busy = false
    if not ok then
        if p then give(p) end
        if type(text) == 'string' then notify(text) end
    end
end)

-- Reprise (véhicule) ou ramassée (sol) : rendue telle quelle, lampe comprise
RegisterNetEvent('rp_vehicleprops:heldGive', function(w)
    if type(w) ~= 'table' then return end
    local ped = PlayerPedId()
    if loadAnim('pickup_object') then
        TaskPlayAnim(ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 900, 48, 0.0, false, false, false)
    end
    give(w)
end)

-- =========================================================================
-- OBJETS (chez tous les joueurs) : arme (accessoires, teinte) ou lampe, sans collision
-- =========================================================================
local function spawnObject(w, x, y, z, ground)
    local obj
    if TORCHES[u32(w.hash)] then
        local model = loadModel(torchModel(w.hash, ground))
        if not model then return nil end
        obj = CreateObjectNoOffset(model, x, y, z, false, false, false)
        SetModelAsNoLongerNeeded(model)
    else
        local h = signed(w.hash)
        RequestWeaponAsset(h, 31, 0)
        local untilTime = GetGameTimer() + 3000
        while not HasWeaponAssetLoaded(h) and GetGameTimer() < untilTime do Wait(0) end
        if not HasWeaponAssetLoaded(h) then return nil end
        obj = CreateWeaponObject(h, 0, x, y, z, true, 1.0, 0)
        for _, name in ipairs(type(w.components) == 'table' and w.components or {}) do
            local c = GetHashKey(name)
            local model = GetWeaponComponentTypeModel(c)
            if model and model ~= 0 then loadModel(model) end
            GiveWeaponComponentToWeaponObject(obj, c)
        end
        if (tonumber(w.tint) or -1) >= 0 then SetWeaponObjectTintIndex(obj, math.floor(w.tint)) end
    end
    if not obj or obj == 0 then return nil end
    SetEntityCollision(obj, false, false)
    SetEntityInvincible(obj, true)
    -- lampe allumée : vraie lampe du jeu (arme avec accessoire lampe) ou lumière du modèle (lampe torche)
    if w.light == true then
        if TORCHES[u32(w.hash)] then SetEntityLights(obj, false) else pcall(SetCreateWeaponObjectLightSource, obj, true) end
    elseif TORCHES[u32(w.hash)] then
        SetEntityLights(obj, true)
    end
    return obj
end

-- ---- Collées aux véhicules : état du véhicule "rpWeapons" ----
local placed = {} -- [véhicule] = { sig, objects = { [id] = { obj, w } } }

local function weaponsOf(vehicle)
    local list, out = Entity(vehicle).state.rpWeapons, {}
    if type(list) == 'table' then
        for _, w in ipairs(list) do
            if type(w) == 'table' and type(w.id) == 'string' and tonumber(w.hash) then out[#out + 1] = w end
        end
    end
    return out
end
VPHeld.weaponsOf = weaponsOf

local function signature(list)
    local parts = {}
    for _, w in ipairs(list) do parts[#parts + 1] = w.id end
    return table.concat(parts, '|')
end

local function clearVehicle(vehicle)
    local entry = placed[vehicle]
    if not entry then return end
    for _, o in pairs(entry.objects) do if DoesEntityExist(o.obj) then DeleteObject(o.obj) end end
    placed[vehicle] = nil
end

local function refresh(vehicle)
    if not DoesEntityExist(vehicle) then return clearVehicle(vehicle) end
    local list = weaponsOf(vehicle)
    local sig = signature(list)
    if placed[vehicle] and placed[vehicle].sig == sig then return end
    clearVehicle(vehicle)
    if #list == 0 then return end
    local entry = { sig = sig, objects = {} }
    placed[vehicle] = entry
    local c = GetEntityCoords(vehicle)
    for _, w in ipairs(list) do
        w.hash = u32(w.hash)
        local obj = spawnObject(w, c.x, c.y, c.z - 3.0)
        if obj then
            AttachEntityToEntity(obj, vehicle, 0, (tonumber(w.x) or 0.0) + 0.0, (tonumber(w.y) or 0.0) + 0.0,
                (tonumber(w.z) or 0.0) + 0.0, (tonumber(w.rx) or 0.0) + 0.0, (tonumber(w.ry) or 0.0) + 0.0,
                (tonumber(w.rz) or 0.0) + 0.0, false, false, false, false, 2, true)
            entry.objects[w.id] = { obj = obj, w = w }
        end
    end
end
VPHeld.refresh = refresh

AddStateBagChangeHandler('rpWeapons', nil, function(bagName)
    CreateThread(function()
        local untilTime = GetGameTimer() + 3000
        local vehicle = GetEntityFromStateBagName(bagName)
        while (vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < untilTime do
            Wait(100)
            vehicle = GetEntityFromStateBagName(bagName)
        end
        if vehicle ~= 0 then Wait(0); refresh(vehicle) end
    end)
end)

-- ---- Au sol : GlobalState "rpGroundItems" (objets locaux, seulement à portée) ----
local ground = {} -- [id] = { obj, item }
local GROUND_RANGE = 80.0

local function groundItems()
    local list = GlobalState.rpGroundItems
    return type(list) == 'table' and list or {}
end

local function refreshGround()
    local me = GetEntityCoords(PlayerPedId())
    local keep = {}
    for _, item in ipairs(groundItems()) do
        if type(item) == 'table' and type(item.id) == 'string' and tonumber(item.x) then
            local pos = vector3(item.x + 0.0, item.y + 0.0, item.z + 0.0)
            if #(pos - me) <= GROUND_RANGE then
                keep[item.id] = true
                local g = ground[item.id]
                if not g or not DoesEntityExist(g.obj) then
                    item.hash = u32(item.hash)
                    local obj = spawnObject(item, pos.x, pos.y, pos.z, true)
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
VPHeld.refreshGround = refreshGround

AddStateBagChangeHandler('rpGroundItems', 'global', function()
    SetTimeout(0, refreshGround)
end)

CreateThread(function()
    while true do
        Wait(2500)
        for vehicle in pairs(placed) do if not DoesEntityExist(vehicle) then clearVehicle(vehicle) end end
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if placed[vehicle] or Entity(vehicle).state.rpWeapons then refresh(vehicle) end
        end
        refreshGround()
    end
end)

-- =========================================================================
-- LUMIÈRE DES LAMPES POSÉES : lumière du modèle réappliquée (elle ne prend pas toujours du premier coup) ;
-- faisceau dessiné en plus si Held.Beam.Drawn (vu par tous à moins de Beam.Range m)
-- =========================================================================
local axes = {} -- [modèle] = { x, y, z, ext } : axe du faisceau dans le modèle, distance du bout

local function beamAxis(obj)
    local model = GetEntityModel(obj)
    if axes[model] then return axes[model] end
    local min, max = GetModelDimensions(model)
    local spec = H.TorchBeamAxis
    local letter, sign
    if type(spec) == 'string' and spec:match('^%-?[xyz]$') then
        letter, sign = spec:sub(-1), spec:sub(1, 1) == '-' and -1 or 1
    else
        local size = max - min
        letter = (size.x >= size.y and size.x >= size.z) and 'x' or (size.y >= size.z and 'y' or 'z')
        sign = 1
    end
    local ax = { x = 0.0, y = 0.0, z = 0.0, ext = sign > 0 and max[letter] or -min[letter] }
    ax[letter] = sign + 0.0
    axes[model] = ax
    return ax
end

local lights = {} -- lampes torches allumées à portée : { obj }

local function collectLights()
    lights = {}
    local me = GetEntityCoords(PlayerPedId())
    local range = B.Range or 60.0
    local function consider(obj, w)
        if w.light == true and TORCHES[u32(w.hash)] and DoesEntityExist(obj) and #(GetEntityCoords(obj) - me) <= range then
            SetEntityLights(obj, false)
            lights[#lights + 1] = obj
        end
    end
    for _, entry in pairs(placed) do for _, o in pairs(entry.objects) do consider(o.obj, o.w) end end
    for _, g in pairs(ground) do consider(g.obj, g.item) end
end
VPHeld.collectLights = collectLights
VPHeld.lights = function() return lights end

local function drawBeam(obj)
    local ax = beamAxis(obj)
    local front = GetOffsetFromEntityInWorldCoords(obj, ax.x * ax.ext, ax.y * ax.ext, ax.z * ax.ext)
    local far = GetOffsetFromEntityInWorldCoords(obj, ax.x * (ax.ext + 1.0), ax.y * (ax.ext + 1.0), ax.z * (ax.ext + 1.0))
    local c = B.Color or { 255, 246, 228 }
    DrawSpotLight(front.x, front.y, front.z, far.x - front.x, far.y - front.y, far.z - front.z, c[1], c[2], c[3],
        (B.Distance or 22.0) + 0.0, (B.Brightness or 5.0) + 0.0, (B.Hardness or 2.0) + 0.0, (B.Radius or 13.0) + 0.0,
        (B.Falloff or 30.0) + 0.0)
end

CreateThread(function()
    while true do
        collectLights()
        if #lights == 0 or not B.Drawn then
            Wait(1500)
        else
            local untilTime = GetGameTimer() + 1000
            repeat
                for _, obj in ipairs(lights) do if DoesEntityExist(obj) then drawBeam(obj) end end
                Wait(0)
            until GetGameTimer() >= untilTime
        end
    end
end)

-- =========================================================================
-- ŒIL : options ajoutées à celles de client/client.lua (exports targetOptions / targetSelect)
-- =========================================================================
--- Objets au sol près du point visé (et du joueur)
local function groundNear(info)
    if not info.hit then return {} end
    local hit = vector3(info.hit.x, info.hit.y, info.hit.z)
    local me = GetEntityCoords(PlayerPedId())
    local out = {}
    for id, g in pairs(ground) do
        local pos = vector3(g.item.x + 0.0, g.item.y + 0.0, g.item.z + 0.0)
        if #(pos - hit) <= (H.PickupSnap or 0.8) and #(pos - me) <= (H.PickupDistance or 2.5) then
            out[#out + 1] = { id = id, label = g.item.label }
        end
    end
    return out
end

function VPHeld.options(info, vehicle, out)
    local ped = PlayerPedId()
    if busy or IsPedInAnyVehicle(ped, false) then return end
    local h = heldHash(ped)
    local what = h and (TORCHES[h] and 'la lampe' or 'l\'arme')
    if vehicle then
        if h and not taserConnected(h) then
            local spots = vehicleSpots(vehicle)
            out[#out + 1] = { id = 'held:here', icon = 'hand', primary = true, label = ('Poser %s ici'):format(what) }
            if spots.roof then out[#out + 1] = { id = 'held:roof', icon = 'hand', primary = true, label = ('Poser %s sur le toit'):format(what) } end
            if spots.trunk then out[#out + 1] = { id = 'held:trunk', icon = 'hand', primary = true, label = ('Poser %s sur le coffre'):format(what) } end
        end
        for _, w in ipairs(weaponsOf(vehicle)) do
            out[#out + 1] = { id = 'held:take:' .. w.id, icon = 'hand', primary = true,
                label = ('Reprendre : %s'):format(type(w.label) == 'string' and w.label or 'arme') }
        end
        return
    end
    for _, g in ipairs(groundNear(info)) do
        out[#out + 1] = { id = 'held:pick:' .. g.id, icon = 'hand', primary = true,
            label = ('Ramasser : %s'):format(type(g.label) == 'string' and g.label or 'arme') }
    end
    -- Taser : posé au sol par rp_taser10 (sondes gardées)
    if h and not (isTaser(h) and GetResourceState('rp_taser10') == 'started') then
        out[#out + 1] = { id = 'held:ground', icon = 'hand', primary = true, label = ('Poser %s au sol'):format(what) }
    end
end

function VPHeld.select(id, info, vehicle)
    if type(id) ~= 'string' or id:sub(1, 5) ~= 'held:' then return false end
    if busy then return true end
    if id == 'held:here' or id == 'held:roof' or id == 'held:trunk' then
        if vehicle then placeOnVehicle(info, vehicle, id:sub(6)) end
    elseif id == 'held:ground' then
        placeOnGround(info)
    elseif id:sub(1, 10) == 'held:take:' and vehicle then
        TriggerServerEvent('rp_vehicleprops:takeWeapon', VehToNet(vehicle), id:sub(11))
    elseif id:sub(1, 10) == 'held:pick:' then
        TriggerServerEvent('rp_vehicleprops:pickupGround', id:sub(11))
    end
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for vehicle in pairs(placed) do clearVehicle(vehicle) end
    for _, g in pairs(ground) do if DoesEntityExist(g.obj) then DeleteObject(g.obj) end end
    if pending then give(pending) end
end)
