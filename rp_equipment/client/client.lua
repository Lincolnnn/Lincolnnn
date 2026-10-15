--[[
    RP Equipment - client
    ---------------------
    À pied, près d'une PORTIÈRE AVANT ou du COFFRE d'un véhicule équipé (type de config.lua) : proposition à
    l'écran, la touche (Key) ouvre le menu "Équipement". Le joueur peut marcher menu ouvert (souris pour
    cliquer, caméra et armes bloquées) ; au-delà de CloseDistance m du véhicule, le menu se ferme.
      - Équipement : pièces EUP de la catégorie du véhicule (equipment.json : casque, gilet…), à mettre et
        retirer de sa tenue ; en les retirant, ce qu'il portait avant revient.
      - Armes longues : "Ranger l'arme longue" range l'arme TENUE EN MAIN dans son emplacement (fusil à pompe /
        fusil d'assaut) avec ses accessoires et teintes ; "Sortir" la rend à l'identique.
    Performance : à pied et en service, une recherche toutes les 500 ms (~0.01 ms) ; à chaque image
    seulement près d'une portière avant / du coffre (proposition) ou menu ouvert ; rien en véhicule.
]]

local Config = EquipConfig
local RESOURCE = GetCurrentResourceName()

-- =========================================================================
-- OUTILS
-- =========================================================================
local function notify(text)
    local chat = Config.ChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started'
        and pcall(function() exports[chat]:addPrivate({ title = 'Équipement', text = text }) end) then
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end

local pending, nextId = {}, 0
local function request(action, data, cb)
    nextId = nextId + 1
    pending[nextId] = cb
    TriggerServerEvent('rp_equipment:request', nextId, action, data)
end
RegisterNetEvent('rp_equipment:response', function(id, result)
    local cb = pending[id]
    pending[id] = nil
    if cb then cb(result or {}) end
end)

local function onDuty()
    if not Config.PoliceOnly then return true end
    local unit = LocalPlayer.state.mdcUnit
    return unit ~= nil and unit ~= false and unit ~= ''
end

-- =========================================================================
-- TYPES DE VÉHICULES (modèles publiés par le serveur, classes ici)
-- =========================================================================
local function vehicleType(vehicle)
    local models = GlobalState.rpEquipModels or {}
    local model = GetEntityModel(vehicle)
    local kind = models[model] or models[tostring(model)]
    if kind and Config.Types[kind] then return kind end
    local class = GetVehicleClass(vehicle)
    for key, t in pairs(Config.Types) do
        for _, c in ipairs(t.Classes or {}) do
            if c == class then return key end
        end
    end
    return nil
end


-- =========================================================================
-- POINTS D'ACCÈS : portières avant et coffre
-- =========================================================================
local function bonePos(vehicle, name)
    local index = GetEntityBoneIndexByName(vehicle, name)
    if index == -1 then return nil end
    return GetWorldPositionOfEntityBone(vehicle, index)
end

--- { { where = 'front' | 'trunk', pos } } : portières avant (un peu à l'extérieur) et coffre (derrière)
local function accessPoints(vehicle)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local points = {}
    for _, side in ipairs({ { bone = 'door_dside_f', x = min.x - 0.5 }, { bone = 'door_pside_f', x = max.x + 0.5 } }) do
        local door = bonePos(vehicle, side.bone)
        local y = door and GetOffsetFromEntityGivenWorldCoords(vehicle, door.x, door.y, door.z).y or max.y * 0.25
        points[#points + 1] = { where = 'front', pos = GetOffsetFromEntityInWorldCoords(vehicle, side.x, y - 0.4, 0.0) }
    end
    points[#points + 1] = { where = 'trunk', pos = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, min.y - 0.5, 0.0) }
    return points
end

--- Distance (m) du joueur à la carrosserie du véhicule (0 : contre / dedans)
local function distanceToBody(vehicle, pos)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local p = GetOffsetFromEntityGivenWorldCoords(vehicle, pos.x, pos.y, pos.z)
    local dx = math.max(min.x - p.x, 0.0, p.x - max.x)
    local dy = math.max(min.y - p.y, 0.0, p.y - max.y)
    local dz = math.max(min.z - p.z, 0.0, p.z - max.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Point d'accès le plus proche à portée : { vehicle, kind, where } ou nil
local function findAccess(ped)
    local pos = GetEntityCoords(ped)
    local best, bestDist = nil, Config.InteractDistance or 1.6
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(vehicle) - pos) < 9.0 then
            local kind = vehicleType(vehicle)
            if kind then
                for _, point in ipairs(accessPoints(vehicle)) do
                    local d = #(point.pos - pos)
                    if d < bestDist then best, bestDist = { vehicle = vehicle, kind = kind, where = point.where }, d end
                end
            end
        end
    end
    return best
end

-- =========================================================================
-- ARMES : lecture et remise à l'identique (accessoires, teintes, munitions)
-- =========================================================================
local NAMES = {
    WEAPON_PUMPSHOTGUN = 'Fusil à pompe', WEAPON_PUMPSHOTGUN_MK2 = 'Fusil à pompe Mk II',
    WEAPON_SAWNOFFSHOTGUN = 'Fusil à canon scié', WEAPON_ASSAULTSHOTGUN = 'Fusil à pompe d\'assaut',
    WEAPON_BULLPUPSHOTGUN = 'Fusil à pompe bullpup', WEAPON_HEAVYSHOTGUN = 'Fusil à pompe lourd',
    WEAPON_COMBATSHOTGUN = 'Fusil à pompe de combat', WEAPON_DBSHOTGUN = 'Fusil double canon',
    WEAPON_AUTOSHOTGUN = 'Fusil à pompe automatique',
    WEAPON_CARBINERIFLE = 'Carabine', WEAPON_CARBINERIFLE_MK2 = 'Carabine Mk II',
    WEAPON_ASSAULTRIFLE = 'Fusil d\'assaut', WEAPON_ASSAULTRIFLE_MK2 = 'Fusil d\'assaut Mk II',
    WEAPON_ADVANCEDRIFLE = 'Fusil avancé', WEAPON_SPECIALCARBINE = 'Carabine spéciale',
    WEAPON_SPECIALCARBINE_MK2 = 'Carabine spéciale Mk II', WEAPON_BULLPUPRIFLE = 'Fusil bullpup',
    WEAPON_BULLPUPRIFLE_MK2 = 'Fusil bullpup Mk II', WEAPON_COMPACTRIFLE = 'Fusil compact',
    WEAPON_MILITARYRIFLE = 'Fusil militaire', WEAPON_HEAVYRIFLE = 'Fusil lourd', WEAPON_TACTICALRIFLE = 'Carabine de service',
}
for name, label in pairs(Config.LongGuns.Names or {}) do NAMES[name] = label end
local NAME_OF = {}
for name in pairs(NAMES) do NAME_OF[GetHashKey(name)] = name end

-- Accessoires connus (armes du jeu) : testés un par un, seuls ceux que l'arme accepte comptent
local COMPONENTS = {
    'COMPONENT_AT_AR_FLSH', 'COMPONENT_AT_AR_AFGRIP', 'COMPONENT_AT_AR_AFGRIP_02', 'COMPONENT_AT_AR_SUPP',
    'COMPONENT_AT_AR_SUPP_02', 'COMPONENT_AT_SR_SUPP', 'COMPONENT_AT_SR_SUPP_03', 'COMPONENT_AT_RAILCOVER_01',
    'COMPONENT_AT_SCOPE_MACRO', 'COMPONENT_AT_SCOPE_MACRO_02', 'COMPONENT_AT_SCOPE_SMALL', 'COMPONENT_AT_SCOPE_MEDIUM',
    'COMPONENT_AT_SIGHTS', 'COMPONENT_AT_SCOPE_MACRO_MK2', 'COMPONENT_AT_SCOPE_MACRO_02_MK2', 'COMPONENT_AT_SCOPE_SMALL_MK2',
    'COMPONENT_AT_SCOPE_MEDIUM_MK2', 'COMPONENT_AT_AR_BARREL_01', 'COMPONENT_AT_AR_BARREL_02', 'COMPONENT_AT_CR_BARREL_01',
    'COMPONENT_AT_CR_BARREL_02', 'COMPONENT_AT_SC_BARREL_01', 'COMPONENT_AT_SC_BARREL_02', 'COMPONENT_AT_BP_BARREL_01',
    'COMPONENT_AT_BP_BARREL_02',
    'COMPONENT_CARBINERIFLE_VARMOD_LUXE', 'COMPONENT_ASSAULTRIFLE_VARMOD_LUXE', 'COMPONENT_ADVANCEDRIFLE_VARMOD_LUXE',
    'COMPONENT_SPECIALCARBINE_VARMOD_LOWRIDER', 'COMPONENT_BULLPUPRIFLE_VARMOD_LOW', 'COMPONENT_PUMPSHOTGUN_VARMOD_LOWRIDER',
    'COMPONENT_SAWNOFFSHOTGUN_VARMOD_LUXE', 'COMPONENT_ASSAULTSHOTGUN_VARMOD_LUXE', 'COMPONENT_HEAVYSHOTGUN_VARMOD_LUXE',
}
for i = 1, 8 do COMPONENTS[#COMPONENTS + 1] = ('COMPONENT_AT_MUZZLE_%02d'):format(i) end
for _, w in ipairs({ 'CARBINERIFLE', 'ASSAULTRIFLE', 'ADVANCEDRIFLE', 'SPECIALCARBINE', 'BULLPUPRIFLE', 'COMPACTRIFLE',
                     'MILITARYRIFLE', 'HEAVYRIFLE', 'TACTICALRIFLE', 'ASSAULTSHOTGUN', 'HEAVYSHOTGUN', 'COMBATSHOTGUN' }) do
    for i = 1, 3 do COMPONENTS[#COMPONENTS + 1] = ('COMPONENT_%s_CLIP_%02d'):format(w, i) end
end
for _, w in ipairs({ 'CARBINERIFLE_MK2', 'ASSAULTRIFLE_MK2', 'SPECIALCARBINE_MK2', 'BULLPUPRIFLE_MK2', 'PUMPSHOTGUN_MK2' }) do
    for _, c in ipairs({ 'CLIP_01', 'CLIP_02', 'CLIP_TRACER', 'CLIP_INCENDIARY', 'CLIP_ARMORPIERCING', 'CLIP_FMJ',
                         'CLIP_HOLLOWPOINT', 'CLIP_EXPLOSIVE', 'CAMO', 'CAMO_IND_01' }) do
        COMPONENTS[#COMPONENTS + 1] = ('COMPONENT_%s_%s'):format(w, c)
    end
    for i = 2, 10 do COMPONENTS[#COMPONENTS + 1] = ('COMPONENT_%s_CAMO_%02d'):format(w, i) end
end
for _, c in ipairs(Config.LongGuns.ExtraComponents or {}) do COMPONENTS[#COMPONENTS + 1] = c end

local function weaponLabel(hash)
    local name = NAME_OF[hash]
    return name and NAMES[name] or 'Arme longue', name
end

--- Emplacement du râtelier qui accepte cette arme (groupe d'arme), ou nil
local function slotFor(hash)
    local group = GetWeapontypeGroup(hash)
    for _, slot in ipairs(Config.LongGuns.Slots) do
        for _, g in ipairs(slot.Groups or {}) do
            if GetHashKey(g) == group then return slot end
        end
    end
    return nil
end

--- Arme tenue en main, telle quelle : modèle, accessoires, teintes
local function capture(ped, hash)
    local components, tints = {}, {}
    for _, name in ipairs(COMPONENTS) do
        local c = GetHashKey(name)
        if DoesWeaponTakeWeaponComponent(hash, c) and HasPedGotWeaponComponent(ped, hash, c) then
            components[#components + 1] = name
            local ok, tint = pcall(GetPedWeaponComponentTintIndex, ped, hash, c)
            if ok and type(tint) == 'number' and tint >= 0 then tints[name] = tint end
        end
    end
    local label, name = weaponLabel(hash)
    return {
        hash = hash, name = name, label = label,
        tint = GetPedWeaponTintIndex(ped, hash),
        components = components, componentTints = tints,
    }
end

--- Rend l'arme à l'identique (avec GiveAmmo munitions) et la met en main
local function giveStored(ped, w)
    local hash = w.hash
    GiveWeaponToPed(ped, hash, Config.LongGuns.GiveAmmo or 250, false, true)
    for _, name in ipairs(w.components or {}) do
        local c = GetHashKey(name)
        GiveWeaponComponentToPed(ped, hash, c)
        local tint = (w.componentTints or {})[name]
        if tint then pcall(SetPedWeaponComponentTintIndex, ped, hash, c, tint) end
    end
    if w.tint and w.tint >= 0 then SetPedWeaponTintIndex(ped, hash, w.tint) end
    SetCurrentPedWeapon(ped, hash, true)
end

--- Arme tenue : { slot, label } si elle peut aller au râtelier, sinon nil
local function heldLongGun(ped)
    local hash = GetSelectedPedWeapon(ped)
    if hash == 0 or hash == GetHashKey('WEAPON_UNARMED') then return nil end
    local slot = slotFor(hash)
    if not slot then return nil end
    return { hash = hash, slot = slot.Id, label = (weaponLabel(hash)) }
end

-- =========================================================================
-- MENU
-- =========================================================================
local open = nil          -- { vehicle, kind, where, plate, trunk = true si ouvert par le menu }
local near = nil          -- point d'accès à portée (proposition)
local lastHeld = nil

-- =========================================================================
-- ÉQUIPEMENT EUP : pièces mises / retirées de la tenue
-- =========================================================================
local MALE, FEMALE = GetHashKey('mp_m_freemode_01'), GetHashKey('mp_f_freemode_01')
local previous = {}   -- [id de la pièce] = ce que le joueur portait avant de la mettre
local assets = {}     -- pièces du véhicule ouvert, pour ce personnage

local function gender(ped)
    local model = GetEntityModel(ped)
    if model == MALE then return 'male' end
    if model == FEMALE then return 'female' end
    return nil
end

--- La pièce est-elle portée (toutes ses parties identiques sur le personnage) ?
local function isWorn(ped, a)
    for _, c in ipairs(a.components or {}) do
        if GetPedDrawableVariation(ped, c[1]) ~= c[2] or GetPedTextureVariation(ped, c[1]) ~= c[3] then return false end
    end
    for _, p in ipairs(a.props or {}) do
        if p[2] < 0 then
            if GetPedPropIndex(ped, p[1]) ~= -1 then return false end
        elseif GetPedPropIndex(ped, p[1]) ~= p[2] or GetPedPropTextureIndex(ped, p[1]) ~= p[3] then
            return false
        end
    end
    return true
end

local function putOn(ped, a)
    local saved = { components = {}, props = {} }
    for _, c in ipairs(a.components or {}) do
        saved.components[#saved.components + 1] = { c[1], GetPedDrawableVariation(ped, c[1]), GetPedTextureVariation(ped, c[1]) }
        SetPedComponentVariation(ped, c[1], c[2], c[3], 0)
    end
    for _, p in ipairs(a.props or {}) do
        saved.props[#saved.props + 1] = { p[1], GetPedPropIndex(ped, p[1]), GetPedPropTextureIndex(ped, p[1]) }
        if p[2] < 0 then ClearPedProp(ped, p[1]) else SetPedPropIndex(ped, p[1], p[2], p[3], true) end
    end
    previous[a.id] = saved
end

--- Retire la pièce : ce qu'il portait avant revient (sinon : rien à cet emplacement)
local function takeOff(ped, a)
    local saved = previous[a.id]
    previous[a.id] = nil
    if saved then
        for _, c in ipairs(saved.components) do SetPedComponentVariation(ped, c[1], c[2], c[3], 0) end
        for _, p in ipairs(saved.props) do
            if p[2] < 0 then ClearPedProp(ped, p[1]) else SetPedPropIndex(ped, p[1], p[2], p[3], true) end
        end
        return
    end
    for _, c in ipairs(a.components or {}) do SetPedComponentVariation(ped, c[1], 0, 0, 0) end
    for _, p in ipairs(a.props or {}) do ClearPedProp(ped, p[1]) end
end

local function assetsView()
    local ped = PlayerPedId()
    local list = {}
    for _, a in ipairs(assets) do list[#list + 1] = { id = a.id, name = a.name, worn = isWorn(ped, a) } end
    return list
end

local function setAssets(all)
    local sex = gender(PlayerPedId())
    assets = {}
    for _, a in ipairs(all or {}) do
        if a.gender == nil or a.gender == sex then assets[#assets + 1] = a end
    end
end

local function slotsView()
    local list = {}
    for _, slot in ipairs(Config.LongGuns.Slots) do list[#list + 1] = { id = slot.Id, label = slot.Label } end
    return list
end

local function sendHeld()
    if not open then return end
    local held = heldLongGun(PlayerPedId())
    local key = held and (held.hash .. held.slot) or ''
    if key == lastHeld then return end
    lastHeld = key
    SendNUIMessage({ action = 'held', data = held and { slot = held.slot, label = held.label } or false })
end

local function controlled(vehicle)
    return not NetworkGetEntityIsNetworked(vehicle) or NetworkHasControlOfEntity(vehicle)
end

local function closeMenu()
    if not open then return end
    local state = open
    open = nil
    lastHeld = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    if state.trunk and DoesEntityExist(state.vehicle) and controlled(state.vehicle) then
        SetVehicleDoorShut(state.vehicle, 5, false)
    end
end

local DISABLED = { 1, 2, 24, 25, 37, 44, 45, 140, 141, 142, 143, 199, 200, 257, 263, 264, 322, 12, 13, 14, 15, 16, 17, 106 }

local function menuLoop()
    CreateThread(function()
        local nextCheck = 0
        while open do
            for _, c in ipairs(DISABLED) do DisableControlAction(0, c, true) end
            local now = GetGameTimer()
            if now >= nextCheck then
                nextCheck = now + 200
                local ped = PlayerPedId()
                local vehicle = open.vehicle
                if not DoesEntityExist(vehicle) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, true)
                    or distanceToBody(vehicle, GetEntityCoords(ped)) > (Config.CloseDistance or 4.0)
                    or not onDuty() then
                    closeMenu()
                else
                    sendHeld()
                end
            end
            Wait(0)
        end
    end)
end

local function openMenu(access)
    if open then return end
    local vehicle = access.vehicle
    request('open', { net = VehToNet(vehicle), type = access.kind, where = access.where }, function(res)
        if not res.ok then return notify(res.error or 'Équipement indisponible.') end
        if open or not DoesEntityExist(vehicle) then return end
        local kind = res.type or access.kind
        local t = Config.Types[kind] or {}
        open = { vehicle = vehicle, kind = kind, where = access.where, plate = res.plate }
        if access.where == 'trunk' and Config.OpenTrunk and controlled(vehicle) and GetVehicleDoorAngleRatio(vehicle, 5) < 0.1 then
            SetVehicleDoorOpen(vehicle, 5, false, false)
            open.trunk = true
        end
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(true) -- le joueur peut marcher, menu ouvert
        SendNUIMessage({ action = 'open', data = {
            type = { short = t.Short or kind:upper(), label = t.Label or kind, color = t.Color },
            where = access.where, plate = res.plate,
            assets = (function() setAssets(res.assets) return assetsView() end)(),
            freemode = gender(PlayerPedId()) ~= nil,
            slots = res.rack and slotsView() or {}, rack = res.rack or {},
            closeDistance = Config.CloseDistance or 4.0,
        } })
        lastHeld = nil
        sendHeld()
        menuLoop()
    end)
end

-- Râtelier changé (par lui ou un collègue) : menu ouvert sur ce véhicule mis à jour
RegisterNetEvent('rp_equipment:rack', function(plate, rack)
    if open and open.plate == plate then SendNUIMessage({ action = 'rack', data = rack }) end
end)

-- =========================================================================
-- ACTIONS DU MENU
-- =========================================================================
local function context()
    return { net = VehToNet(open.vehicle), type = open.kind, where = open.where }
end

RegisterNUICallback('wear', function(data, cb)
    cb({ ok = true })
    if not open or type(data) ~= 'table' then return end
    local payload = context()
    payload.asset = data.id
    request('wear', payload, function(res)
        if not res.ok then return SendNUIMessage({ action = 'message', data = { text = res.error, error = true } }) end
        local ped = PlayerPedId()
        local a = res.asset
        if isWorn(ped, a) then
            takeOff(ped, a)
            SendNUIMessage({ action = 'message', data = { text = ('%s : retiré.'):format(a.name) } })
        else
            putOn(ped, a)
            SendNUIMessage({ action = 'message', data = { text = ('%s : mis.'):format(a.name) } })
        end
        SendNUIMessage({ action = 'assets', data = assetsView() })
    end)
end)

RegisterNUICallback('store', function(_, cb)
    cb({ ok = true })
    if not open then return end
    local ped = PlayerPedId()
    local held = heldLongGun(ped)
    if not held then
        return SendNUIMessage({ action = 'message', data = { error = true,
            text = 'Tenez dans les mains l\'arme longue à ranger (fusil à pompe ou fusil d\'assaut).' } })
    end
    local payload = context()
    payload.slot, payload.weapon = held.slot, capture(ped, held.hash)
    request('store', payload, function(res)
        if not res.ok then return SendNUIMessage({ action = 'message', data = { text = res.error, error = true } }) end
        RemoveWeaponFromPed(PlayerPedId(), held.hash)
        SetCurrentPedWeapon(PlayerPedId(), GetHashKey('WEAPON_UNARMED'), true)
        SendNUIMessage({ action = 'rack', data = res.rack })
        SendNUIMessage({ action = 'message', data = { text = ('%s rangé.'):format(payload.weapon.label) } })
        lastHeld = nil
    end)
end)

RegisterNUICallback('retrieve', function(data, cb)
    cb({ ok = true })
    if not open or type(data) ~= 'table' then return end
    local payload = context()
    payload.slot = data.slot
    request('retrieve', payload, function(res)
        if not res.ok then return SendNUIMessage({ action = 'message', data = { text = res.error, error = true } }) end
        giveStored(PlayerPedId(), res.weapon)
        SendNUIMessage({ action = 'rack', data = res.rack })
        SendNUIMessage({ action = 'message', data = { text = ('%s sorti.'):format(res.weapon.label or 'Arme') } })
        lastHeld = nil
    end)
end)

RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    closeMenu()
end)

-- =========================================================================
-- TOUCHE ET PROPOSITION
-- =========================================================================
RegisterCommand('rp_equipment', function()
    if open then return closeMenu() end
    if not near or IsPauseMenuActive() then return end
    openMenu(near)
end, false)
RegisterKeyMapping('rp_equipment', 'Véhicule de police : menu Équipement', 'keyboard', Config.Key or 'E')

local HELP = {
    front = 'Équipement du véhicule (portière)',
    trunk = 'Équipement du véhicule (coffre)',
}

--- Proposition à l'écran tant que le joueur est près d'un point d'accès (et que le menu est fermé)
local promptRunning = false
local function promptLoop()
    if promptRunning then return end
    promptRunning = true
    CreateThread(function()
        local key = ('~INPUT_%X~'):format((GetHashKey('rp_equipment') | 0x80000000) & 0xFFFFFFFF)
        while near do
            if not open then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName(('%s %s'):format(key, HELP[near.where] or HELP.front))
                EndTextCommandDisplayHelp(0, false, false, -1)
            end
            Wait(0)
        end
        promptRunning = false
    end)
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if onDuty() and not IsPedInAnyVehicle(ped, true) and not IsEntityDead(ped) then
            near = findAccess(ped)
            if near then promptLoop() end
        else
            near = nil
        end
        Wait(near and 250 or 500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    if open then closeMenu() end
end)
