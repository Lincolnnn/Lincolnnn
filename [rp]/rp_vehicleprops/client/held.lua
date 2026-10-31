--[[
    RP VehicleProps - arme / lampe tenue en main (client)
    -----------------------------------------------------
    ŒIL (rp_interact), arme ou lampe en main :
      - sur un véhicule : « Poser l'arme / la lampe sur le véhicule » : l'objet tombe sur la surface visée (capot,
        toit, coffre…) et s'y pose grâce à la collision du véhicule (surface dure), puis il est collé au véhicule chez
        tous les joueurs, avec ses accessoires (lus par rp_interact : exports captureWeapon), sa teinte, ses munitions
        et sa lampe allumée si elle l'était. « Reprendre : … » : rendue telle quelle (exports giveWeapon) ;
      - n'importe où (sol, mur, personne…), une lampe en main : « Poser la lampe au sol » (allumée si elle l'était).
    Le Taser relié à un suspect (sondes tirées) ne se pose pas sur un véhicule : rp_taser10 le pose au sol sans couper.
    Lumière : arme avec une lampe allumée : vraie lampe du jeu sur l'arme posée ; lampes : faisceau dessiné ici (vu par
    tous à moins de Held.Beam.Range m).
    Performance : vérifications toutes les 1 à 2,5 s ; faisceaux dessinés à chaque image seulement s'il y a une lampe
    allumée posée à portée.
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
local EXCLUDED, EXCLUDED_GROUPS = {}, {}
for _, n in ipairs(H.Excluded or {}) do EXCLUDED[u32(GetHashKey(n))] = true end
for _, g in ipairs(H.ExcludedGroups or {}) do EXCLUDED_GROUPS[u32(GetHashKey(g))] = true end

local busy = false     -- pose en cours (jusqu'à la réponse du serveur)
local pending = nil    -- arme partie des mains, rendue si le serveur refuse
local probe = nil      -- objet qui tombe (vu par soi), retiré à la réponse du serveur

local function notify(text)
    if VPClient and VPClient.notify then return VPClient.notify(text) end
    TriggerEvent('chat:addMessage', { args = { 'Objets', text } })
end

-- =========================================================================
-- ARME EN MAIN
-- =========================================================================
--- Arme tenue pouvant être posée (empreinte non signée) ou nil
local function heldHash(ped)
    local h = u32(GetSelectedPedWeapon(ped))
    if h == 0 or h == UNARMED or EXCLUDED[h] or EXCLUDED_GROUPS[u32(GetWeapontypeGroup(signed(h)))] then return nil end
    if not TORCHES[h] and (GetWeapontypeModel(signed(h)) or 0) == 0 then return nil end
    return h
end

--- Taser relié à un suspect (rp_taser10 : sondes tirées) : il ne quitte pas la main pour un véhicule
local function taserConnected(h)
    if u32(GetWeapontypeGroup(signed(h))) ~= STUNGUN or GetResourceState('rp_taser10') ~= 'started' then return false end
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

--- L'arme quitte les mains tout de suite (rendue si le serveur refuse)
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

-- =========================================================================
-- OBJETS : arme (accessoires, teinte) ou lampe
-- =========================================================================
local function loadModel(name)
    local hash = type(name) == 'number' and name or GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local untilTime = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < untilTime do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

--- Objet de l'arme ou de la lampe, à ce point (sans réseau : chacun a le sien)
local function spawnObject(w, x, y, z)
    local obj
    if TORCHES[w.hash] then
        local model = loadModel(TORCHES[w.hash])
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
    return obj
end

--- Rotation « couchée » (le plus petit côté vers le haut), si l'objet ne s'est pas posé tout seul
local function lyingRotation(obj, heading)
    local min, max = GetModelDimensions(GetEntityModel(obj))
    local size = max - min
    local rx, ry = 0.0, 0.0
    if size.x <= size.y and size.x <= size.z then ry = 90.0 elseif size.y <= size.z then rx = 90.0 end
    return vector3(rx, ry, heading)
end

--- L'objet tombe et se pose (collision : surface dure du véhicule, sol) ; true s'il est immobile
local function settle(obj)
    SetEntityCollision(obj, true, true)
    FreezeEntityPosition(obj, false)
    SetEntityDynamic(obj, true)
    ActivatePhysics(obj)
    Wait(200)
    local still, untilTime = 0, GetGameTimer() + (H.SettleTime or 2500)
    while GetGameTimer() < untilTime do
        if not DoesEntityExist(obj) then return false end
        if #(GetEntityVelocity(obj)) < 0.03 then
            still = still + 1
            if still >= 4 then return true end
        else
            still = 0
        end
        Wait(60)
    end
    return false
end

local function angle(a)
    a = (a + 180.0) % 360.0 - 180.0
    return a
end

-- =========================================================================
-- POSER
-- =========================================================================
local function finishProbe()
    if probe and DoesEntityExist(probe) then DeleteObject(probe) end
    probe = nil
end

local function placeOnVehicle(info, vehicle)
    local ped = PlayerPedId()
    local w = capture()
    if not w or heldHash(ped) ~= w.hash then return end
    if taserConnected(w.hash) then return notify('Taser relié au suspect : posez-le au sol.') end
    busy = true
    CreateThread(function()
        local hit = info.hit and vector3(info.hit.x, info.hit.y, info.hit.z) or GetEntityCoords(vehicle)
        if loadAnim('mp_common') then
            TaskPlayAnim(ped, 'mp_common', 'givetake1_a', 8.0, -8.0, 1100, 48, 0.0, false, false, false)
        end
        Wait(450)
        local obj = spawnObject(w, hit.x, hit.y, hit.z + 0.25)
        if not obj then busy = false return notify('Impossible de poser cet objet.') end
        probe = obj
        local heading = GetEntityHeading(ped) + 90.0
        SetEntityRotation(obj, 0.0, 0.0, heading, 2, true)
        release(ped, w)
        local ok = settle(obj)
        local pos, rot = GetEntityCoords(obj), GetEntityRotation(obj, 2)
        -- tombée à côté (bord du véhicule, trou) : posée au point visé, couchée
        if not ok or #(pos - hit) > 1.2 then
            pos, rot = vector3(hit.x, hit.y, hit.z + 0.04), lyingRotation(obj, heading)
            FreezeEntityPosition(obj, true)
            SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z, false, false, false)
            SetEntityRotation(obj, rot.x, rot.y, rot.z, 2, true)
        else
            FreezeEntityPosition(obj, true)
        end
        if not DoesEntityExist(vehicle) then
            finishProbe(); busy = false
            local p = pending; pending = nil
            if p then give(p) end
            return
        end
        local vrot = GetEntityRotation(vehicle, 2)
        local off = GetOffsetFromEntityGivenWorldCoords(vehicle, pos.x, pos.y, pos.z)
        w.offsets = { x = off.x, y = off.y, z = off.z,
            rx = angle(rot.x - vrot.x), ry = angle(rot.y - vrot.y), rz = angle(rot.z - vrot.z) }
        TriggerServerEvent('rp_vehicleprops:placeWeapon', VehToNet(vehicle), w)
    end)
end

local function placeOnGround(info)
    local ped = PlayerPedId()
    local w = capture()
    if not w or not w.torch or heldHash(ped) ~= w.hash then return end
    busy = true
    CreateThread(function()
        local origin = GetEntityCoords(ped)
        local spot
        if info.type == 'world' and info.hit and #(vector3(info.hit.x, info.hit.y, info.hit.z) - origin) <= (H.GroundDistance or 3.0) then
            spot = vector3(info.hit.x, info.hit.y, info.hit.z)
        else
            spot = GetOffsetFromEntityInWorldCoords(ped, 0.1, 0.6, 0.0)
            local found, ground = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 1.0, false)
            spot = vector3(spot.x, spot.y, found and ground or spot.z - 0.98)
        end
        if loadAnim('pickup_object') then
            TaskPlayAnim(ped, 'pickup_object', 'putdown_low', 8.0, -8.0, 900, 0, 0.0, false, false, false)
        end
        Wait(450)
        local obj = spawnObject(w, spot.x, spot.y, spot.z + 0.3)
        if not obj then busy = false return notify('Impossible de poser la lampe.') end
        probe = obj
        local heading = GetEntityHeading(ped)
        SetEntityRotation(obj, 0.0, 0.0, heading, 2, true)
        release(ped, w)
        local ok = settle(obj)
        local pos, rot = GetEntityCoords(obj), GetEntityRotation(obj, 2)
        if not ok or #(pos - spot) > 1.5 then
            rot = lyingRotation(obj, heading)
            pos = vector3(spot.x, spot.y, spot.z + 0.05)
        end
        FreezeEntityPosition(obj, true)
        w.x, w.y, w.z, w.rx, w.ry, w.rz = pos.x, pos.y, pos.z, rot.x, rot.y, rot.z
        TriggerServerEvent('rp_vehicleprops:placeTorch', w)
    end)
end

-- Réponse du serveur : posée (l'objet collé / au sol prend le relais) ou refusée (l'arme est rendue)
RegisterNetEvent('rp_vehicleprops:held', function(ok, text)
    local p = pending
    pending = nil
    SetTimeout(ok and 400 or 0, finishProbe) -- le temps que l'objet posé apparaisse
    busy = false
    if not ok then
        if p then give(p) end
        if type(text) == 'string' then notify(text) end
    end
end)

-- Reprise (véhicule) ou ramassée (lampe au sol) : rendue telle quelle, lampe comprise
RegisterNetEvent('rp_vehicleprops:heldGive', function(w)
    if type(w) ~= 'table' then return end
    local ped = PlayerPedId()
    if loadAnim('pickup_object') then
        TaskPlayAnim(ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 900, 48, 0.0, false, false, false)
    end
    give(w)
end)

-- =========================================================================
-- ARMES COLLÉES AUX VÉHICULES (chez tous les joueurs)
-- =========================================================================
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
            SetEntityCollision(obj, false, false)
            SetEntityInvincible(obj, true)
            AttachEntityToEntity(obj, vehicle, 0, (tonumber(w.x) or 0.0) + 0.0, (tonumber(w.y) or 0.0) + 0.0,
                (tonumber(w.z) or 0.0) + 0.0, (tonumber(w.rx) or 0.0) + 0.0, (tonumber(w.ry) or 0.0) + 0.0,
                (tonumber(w.rz) or 0.0) + 0.0, false, false, false, false, 2, true)
            -- arme avec sa lampe allumée : la vraie lampe du jeu (accessoire lampe nécessaire)
            if w.light == true and not TORCHES[w.hash] then pcall(SetCreateWeaponObjectLightSource, obj, true) end
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

CreateThread(function()
    while true do
        Wait(2500)
        for vehicle in pairs(placed) do if not DoesEntityExist(vehicle) then clearVehicle(vehicle) end end
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if placed[vehicle] or Entity(vehicle).state.rpWeapons then refresh(vehicle) end
        end
    end
end)

-- =========================================================================
-- FAISCEAU DES LAMPES POSÉES (véhicule, sol) : vu par tous à moins de Beam.Range m
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

--- Faisceau d'une arme posée : du bout du canon (os « gun_muzzle »), dans l'axe du canon
local function muzzleAxis(obj)
    local bone = GetEntityBoneIndexByName(obj, 'gun_muzzle')
    if bone == -1 then return nil end
    local local_ = GetOffsetFromEntityGivenWorldCoords(obj, GetWorldPositionOfEntityBone(obj, bone))
    local len = #local_
    if len < 0.01 then return nil end
    return { x = local_.x / len, y = local_.y / len, z = local_.z / len, ext = len }
end

local lights = {} -- { { obj, ax } } : lampes allumées à portée

local function addLight(obj, weapon)
    local ax = weapon and muzzleAxis(obj) or beamAxis(obj)
    if ax then lights[#lights + 1] = { obj = obj, ax = ax } end
end

local function collectLights()
    lights = {}
    local me = GetEntityCoords(PlayerPedId())
    local range = B.Range or 60.0
    for _, entry in pairs(placed) do
        for _, o in pairs(entry.objects) do
            if o.w.light == true and DoesEntityExist(o.obj) and #(GetEntityCoords(o.obj) - me) <= range then
                if TORCHES[o.w.hash] then addLight(o.obj, false) elseif B.Weapons then addLight(o.obj, true) end
            end
        end
    end
    for _, obj in ipairs(GetGamePool('CObject')) do
        if NetworkGetEntityIsNetworked(obj) then
            local t = Entity(obj).state.rpPlacedTorch
            if type(t) == 'table' and t.light == true and #(GetEntityCoords(obj) - me) <= range then addLight(obj, false) end
        end
    end
end
VPHeld.collectLights = collectLights
VPHeld.lights = function() return lights end

local function drawBeam(l)
    local ax = l.ax
    local front = GetOffsetFromEntityInWorldCoords(l.obj, ax.x * ax.ext, ax.y * ax.ext, ax.z * ax.ext)
    local far = GetOffsetFromEntityInWorldCoords(l.obj, ax.x * (ax.ext + 1.0), ax.y * (ax.ext + 1.0), ax.z * (ax.ext + 1.0))
    local c = B.Color or { 255, 246, 228 }
    DrawSpotLight(front.x, front.y, front.z, far.x - front.x, far.y - front.y, far.z - front.z, c[1], c[2], c[3],
        (B.Distance or 22.0) + 0.0, (B.Brightness or 5.0) + 0.0, (B.Hardness or 2.0) + 0.0, (B.Radius or 13.0) + 0.0,
        (B.Falloff or 30.0) + 0.0)
end

CreateThread(function()
    while true do
        collectLights()
        if #lights == 0 then
            Wait(1500)
        else
            local untilTime = GetGameTimer() + 1000
            repeat
                for _, l in ipairs(lights) do if DoesEntityExist(l.obj) then drawBeam(l) end end
                Wait(0)
            until GetGameTimer() >= untilTime
        end
    end
end)

-- =========================================================================
-- ŒIL : options ajoutées à celles de client/client.lua (exports targetOptions / targetSelect)
-- =========================================================================
function VPHeld.options(info, vehicle, out)
    local ped = PlayerPedId()
    if busy or IsPedInAnyVehicle(ped, false) then return end
    local h = heldHash(ped)
    if vehicle then
        if h and not taserConnected(h) then
            out[#out + 1] = { id = 'held:place', icon = 'hand', primary = true,
                label = TORCHES[h] and 'Poser la lampe sur le véhicule' or 'Poser l\'arme sur le véhicule' }
        end
        for _, w in ipairs(weaponsOf(vehicle)) do
            out[#out + 1] = { id = 'held:take:' .. w.id, icon = 'hand', primary = true,
                label = ('Reprendre : %s'):format(type(w.label) == 'string' and w.label or 'arme') }
        end
    elseif h and TORCHES[h] then
        out[#out + 1] = { id = 'held:ground', icon = 'hand', primary = true, label = 'Poser la lampe au sol' }
    end
end

function VPHeld.select(id, info, vehicle)
    if type(id) ~= 'string' or id:sub(1, 5) ~= 'held:' then return false end
    if busy then return true end
    if id == 'held:place' then
        if vehicle then placeOnVehicle(info, vehicle) end
    elseif id == 'held:ground' then
        placeOnGround(info)
    elseif id:sub(1, 10) == 'held:take:' and vehicle then
        TriggerServerEvent('rp_vehicleprops:takeWeapon', VehToNet(vehicle), id:sub(11))
    end
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    finishProbe()
    for vehicle in pairs(placed) do clearVehicle(vehicle) end
    if pending then give(pending) end
end)
