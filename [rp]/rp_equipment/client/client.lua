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
      - Coffre (inventaire, par plaque) : plots de circulation (pris : PORTÉS dans les mains, G les pose au sol, l'œil
        les ramasse, "Ranger le plot" les remet dans un coffre) et fusées de détresse (prendre / ranger).
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

--- Herse de Riven (riven_spikes) en main ou son cordon tenu : ses touches (E, G, X, Q, molette) ont la priorité
local SPIKE_MODES = { holding = true, cord = true, throwing = true, busy = true }
local function spikesBusy()
    if LocalPlayer.state.rivenSpikeHand ~= nil then return true end
    if GetResourceState('riven_spikes') ~= 'started' then return false end
    local ok, mode = pcall(function() return exports.riven_spikes:getMode() end)
    return ok and SPIKE_MODES[mode] == true
end

EquipNotify = notify -- client/spikes.lua

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

--- { { where = 'front' | 'trunk', pos, door } } : portières avant (un peu à l'extérieur) et coffre (derrière) ;
--- door : porte du jeu à ouvrir (0 conducteur à gauche, 1 passager avant à droite, 5 coffre)
local function accessPoints(vehicle)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local points = {}
    for _, side in ipairs({ { bone = 'door_dside_f', x = min.x - 0.5, door = 0 }, { bone = 'door_pside_f', x = max.x + 0.5, door = 1 } }) do
        local door = bonePos(vehicle, side.bone)
        local y = door and GetOffsetFromEntityGivenWorldCoords(vehicle, door.x, door.y, door.z).y or max.y * 0.25
        points[#points + 1] = { where = 'front', door = side.door, pos = GetOffsetFromEntityInWorldCoords(vehicle, side.x, y - 0.4, 0.0) }
    end
    points[#points + 1] = { where = 'trunk', door = 5, pos = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, min.y - 0.5, 0.0) }
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
                    if d < bestDist then best, bestDist = { vehicle = vehicle, kind = kind, where = point.where, door = point.door }, d end
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

--- Emplacement accessible d'ici (avant : portières avant, coffre : coffre)
local function slotHere(slot, where) return slot.Where == nil or slot.Where == 'both' or slot.Where == where end

--- Emplacement du râtelier, accessible d'ici (`where`), qui accepte cette arme (groupe d'arme), ou nil
local function slotFor(hash, where)
    local group = GetWeapontypeGroup(hash)
    for _, slot in ipairs(Config.LongGuns.Slots) do
        if slotHere(slot, where) then
            for _, g in ipairs(slot.Groups or Config.LongGuns.Groups or {}) do
                if GetHashKey(g) == group then return slot end
            end
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

--- Arme tenue : { slot, label } si elle peut aller au râtelier d'ici (`where`), sinon nil
local function heldLongGun(ped, where)
    local hash = GetSelectedPedWeapon(ped)
    if hash == 0 or hash == GetHashKey('WEAPON_UNARMED') then return nil end
    local slot = slotFor(hash, where)
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

--- La pièce est-elle portée (toutes ses parties identiques sur le personnage) ? Objet (jerrican…) : en sa possession
local function isWorn(ped, a)
    if a.item then return HasPedGotWeapon(ped, GetHashKey(a.weapon), false) end
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
    for _, a in ipairs(assets) do list[#list + 1] = { id = a.id, name = a.name, worn = isWorn(ped, a), item = a.item == true } end
    return list
end

local function setAssets(all)
    local sex = gender(PlayerPedId())
    assets = {}
    for _, a in ipairs(all or {}) do
        if a.gender == nil or a.gender == sex then assets[#assets + 1] = a end
    end
end

--- Emplacements accessibles d'ici seulement (l'avant ou le coffre)
local function slotsView(where)
    local list = {}
    for _, slot in ipairs(Config.LongGuns.Slots) do
        if slotHere(slot, where) then list[#list + 1] = { id = slot.Id, label = slot.Label } end
    end
    return list
end

local function sendHeld()
    if not open then return end
    local held = heldLongGun(PlayerPedId(), open.where)
    local key = held and (held.hash .. held.slot) or ''
    if key == lastHeld then return end
    lastHeld = key
    SendNUIMessage({ action = 'held', data = held and { slot = held.slot, label = held.label } or false })
end

local function controlled(vehicle)
    return not NetworkGetEntityIsNetworked(vehicle) or NetworkHasControlOfEntity(vehicle)
end

-- Échap : le menu pause du jeu s'ouvre au RELÂCHEMENT de la touche ; après la fermeture du menu, les commandes de
-- pause restent bloquées jusqu'à ce qu'Échap soit relâché (+ quelques images, 3 s au plus)
local PAUSE_KEYS = { 199, 200, 322 }
local function blockPauseAfterClose()
    CreateThread(function()
        local untilTime, extra = GetGameTimer() + 3000, 10
        while extra > 0 and GetGameTimer() < untilTime and not open do
            for _, c in ipairs(PAUSE_KEYS) do DisableControlAction(0, c, true) end
            if IsPauseMenuActive() then SetPauseMenuActive(false) end
            if not (IsDisabledControlPressed(0, 200) or IsDisabledControlPressed(0, 322)) then extra = extra - 1 end
            Wait(0)
        end
    end)
end

local function closeMenu()
    if not open then return end
    local state = open
    open = nil
    lastHeld = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    blockPauseAfterClose()
    -- Portière avant / coffre : refermé à la fermeture du menu (même s'il était déjà ouvert avant)
    if state.door and DoesEntityExist(state.vehicle) then
        if not controlled(state.vehicle) then NetworkRequestControlOfEntity(state.vehicle) end
        SetVehicleDoorShut(state.vehicle, state.door, false)
    end
end

local DISABLED = { 1, 2, 24, 25, 37, 44, 45, 140, 141, 142, 143, 199, 200, 257, 263, 264, 322, 12, 13, 14, 15, 16, 17, 106 }
local sendInventory -- (plus bas : coffre) plot porté, fusées sur soi, envoyés au menu quand ils changent

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
                    if sendInventory then sendInventory() end
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
        -- Portière avant la plus proche (gauche : conducteur, droite : passager avant) ou coffre : ouvert s'il ne l'est
        -- pas déjà (jamais rouvert), refermé à la fermeture du menu
        local door = access.door or (access.where == 'trunk' and 5 or nil)
        local wanted = door and ((door == 5 and Config.OpenTrunk) or (door ~= 5 and Config.OpenFrontDoor ~= false))
        if wanted and GetIsDoorValid(vehicle, door) then
            if not controlled(vehicle) then NetworkRequestControlOfEntity(vehicle) end
            if GetVehicleDoorAngleRatio(vehicle, door) < 0.1 then SetVehicleDoorOpen(vehicle, door, false, false) end
            open.door = door
        end
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(true) -- le joueur peut marcher, menu ouvert
        SendNUIMessage({ action = 'open', data = {
            type = { short = t.Short or kind:upper(), label = t.Label or kind, color = t.Color },
            where = access.where, plate = res.plate,
            assets = (function() setAssets(res.assets) return assetsView() end)(),
            freemode = gender(PlayerPedId()) ~= nil,
            slots = res.rack and slotsView(access.where) or {}, rack = res.rack or {},
            stock = res.stock or false,
            closeDistance = Config.CloseDistance or 4.0,
        } })
        lastHeld = nil
        sendHeld()
        if sendInventory then sendInventory(true) end
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
        if a.item then
            -- Objet : pris (dans les mains) ou rangé dans le véhicule
            local hash = GetHashKey(a.weapon)
            if HasPedGotWeapon(ped, hash, false) then
                RemoveWeaponFromPed(ped, hash)
                SendNUIMessage({ action = 'message', data = { text = ('%s : rangé.'):format(a.name) } })
            else
                GiveWeaponToPed(ped, hash, a.ammo or 0, false, true)
                SendNUIMessage({ action = 'message', data = { text = ('%s : pris.'):format(a.name) } })
            end
        elseif isWorn(ped, a) then
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
    local held = heldLongGun(ped, open.where)
    if not held then
        return SendNUIMessage({ action = 'message', data = { error = true,
            text = 'Tenez dans les mains l\'arme longue à ranger (fusil à pompe, fusil d\'assaut…).' } })
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
-- COFFRE COMME UN INVENTAIRE : plots de circulation (portés, posés, ramassés) et fusées de détresse
-- Performance : boucle à chaque image seulement pendant qu'un plot est porté (aide, touches) ; aucune sinon.
-- =========================================================================
local S = Config.Stock or {}
local SC = S.Cones or {}
local FLARE = GetHashKey(S.Flares and S.Flares.Weapon or 'WEAPON_FLARE')
local CONE = GetHashKey(SC.Model or 'prop_roadcone02a')
local UNARMED = GetHashKey('WEAPON_UNARMED')
local MAX_FLARES_HELD = 25 -- fusées qu'un joueur peut avoir sur lui (jeu)
local PICK_ANIM = { 'pickup_object', 'pickup_low' }
local carried = nil       -- plots portés : { count, props = { objet, ... } } (pile de plots dans les mains)
local placingCone = false
local MAX_CARRY = math.max(1, math.floor(tonumber(SC.MaxCarry) or 5))
local lastInventory = nil

local function flaresHeld(ped)
    return HasPedGotWeapon(ped, FLARE, false) and GetAmmoInPedWeapon(ped, FLARE) or 0
end

local PETROLCAN = GetHashKey(S.Jerrycans and S.Jerrycans.Weapon or 'WEAPON_PETROLCAN')
local CAN_AMMO = S.Jerrycans and S.Jerrycans.Ammo or 4500
local RADARGUN = GetHashKey(S.RadarGuns and S.RadarGuns.Weapon or 'WEAPON_RADARGUN')

--- Jerrican sur soi : essence restante (en % d'un jerrican plein), false s'il n'en a pas
local function canHeld(ped)
    if not HasPedGotWeapon(ped, PETROLCAN, false) then return false end
    return math.floor(GetAmmoInPedWeapon(ped, PETROLCAN) / CAN_AMMO * 100 + 0.5)
end

sendInventory = function(force)
    if not open then return end
    local ped = PlayerPedId()
    local cones = carried and carried.count or 0
    local can = canHeld(ped)
    local radar = HasPedGotWeapon(ped, RADARGUN, false)
    local spikes = RPSpikes ~= nil and RPSpikes.available(open) -- (client/spikes.lua)
    local spikeHeld = spikes and RPSpikes.held() or false
    local key = ('%d:%d:%s:%s:%s:%s'):format(cones, flaresHeld(ped), tostring(can), tostring(radar), tostring(spikes), tostring(spikeHeld))
    if key == lastInventory and not force then return end
    lastInventory = key
    SendNUIMessage({ action = 'inventory', data = { carrying = cones, maxCarry = MAX_CARRY, flares = flaresHeld(ped),
        maxHeld = MAX_FLARES_HELD, jerrycan = can, radar = radar, spikes = spikes, spikeHeld = spikeHeld } })
end

local function loadAnim(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 1000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
end

local function playPickup()
    loadAnim(PICK_ANIM[1])
    TaskPlayAnim(PlayerPedId(), PICK_ANIM[1], PICK_ANIM[2], 8.0, -8.0, 900, 0, 0.0, false, false, false)
end

local function playCarry(ped)
    local anim = SC.Carry and SC.Carry.Anim
    if not anim then return end
    loadAnim(anim[1])
    TaskPlayAnim(ped, anim[1], anim[2], 8.0, -8.0, -1, 49, 0.0, false, false, false)
end

--- Aide en haut à gauche pendant `ms` (après avoir posé le dernier plot : comment les reprendre)
local hintUntil = 0
local function showHint(text, ms)
    local running = GetGameTimer() < hintUntil
    hintUntil = GetGameTimer() + ms
    if running then return end
    CreateThread(function()
        while GetGameTimer() < hintUntil and not carried do
            if not open and not IsPauseMenuActive() then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName(text)
                EndTextCommandDisplayHelp(0, false, false, -1)
            end
            Wait(0)
        end
        hintUntil = 0
    end)
end
local TARGET_HINT = 'Utiliser le target pour récupérer les plots posés.'

local function deleteProp(prop)
    if DoesEntityExist(prop) then
        DetachEntity(prop, true, true)
        DeleteEntity(prop)
    end
end

local function stopCarry()
    if not carried then return end
    local ped = PlayerPedId()
    for _, prop in ipairs(carried.props) do deleteProp(prop) end
    local anim = SC.Carry and SC.Carry.Anim
    if anim then StopAnimTask(ped, anim[1], anim[2], 1.0) end
    carried = nil
    LocalPlayer.state:set('rpCarryingCone', false, false)
    if sendInventory then sendInventory() end
end

--- Pile de plots dans les mains : autant d'objets que de plots portés (Carry.MaxProps au plus), empilés
local function updateProps(ped)
    local c = SC.Carry or {}
    local want = math.min(carried.count, c.MaxProps or 5)
    while #carried.props > want do deleteProp(table.remove(carried.props)) end
    if #carried.props >= want then return end
    RequestModel(CONE)
    local timeout = GetGameTimer() + 2000
    while not HasModelLoaded(CONE) and GetGameTimer() < timeout do Wait(10) end
    local o = c.Offset or { 0.0, -0.05, -0.15, 0.0, 0.0, 0.0 }
    local pos = GetEntityCoords(ped)
    while carried and #carried.props < want do
        local i = #carried.props
        local prop = CreateObject(CONE, pos.x, pos.y, pos.z + 0.5, true, true, false)
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, c.Bone or 28422), o[1], o[2], o[3] + i * (c.StackStep or 0.07),
            o[4], o[5], o[6], true, true, false, true, 1, true)
        carried.props[#carried.props + 1] = prop
    end
    SetModelAsNoLongerNeeded(CONE)
end

--- Endroit au sol, devant le joueur (`forward` m, `side` m à droite), plot debout
local function groundSpot(ped, side, forward)
    local spot = GetOffsetFromEntityInWorldCoords(ped, side, forward, 0.0)
    local found, ground = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 1.0, false)
    if not found then ground = GetEntityCoords(ped).z - 0.98 end
    local min = GetModelDimensions(CONE)
    return { x = spot.x, y = spot.y, z = ground - min.z, heading = GetEntityHeading(ped) }
end

--- Un plot porté posé au sol, debout, devant le joueur (créé par le serveur, visible par tous) ;
--- mort (`dropAll`) : tous les plots portés tombent autour de ses pieds
local function placeCone(dropAll)
    if not carried or placingCone then return end
    local ped = PlayerPedId()
    if not dropAll and (IsPauseMenuActive() or IsPedInAnyVehicle(ped, true)) then return end
    placingCone = true
    SetTimeout(2000, function() placingCone = false end)
    local spots = {}
    if dropAll then
        for i = 1, carried.count do
            local angle = (i - 1) / carried.count * 2.0 * math.pi
            spots[i] = groundSpot(ped, math.sin(angle) * 0.6, 0.2 + math.cos(angle) * 0.6)
        end
    else
        spots[1] = groundSpot(ped, 0.0, SC.PlaceDistance or 0.8)
    end
    TriggerServerEvent('rp_equipment:cone:place', { spots = spots })
end

--- Touche de pose choisie par le joueur (raccourci FiveM), "G" par défaut
local function placeKeyName()
    local name = GetControlInstructionalButton(0, (GetHashKey('rp_cone_place') | 0x80000000) & 0xFFFFFFFF, true)
    if type(name) == 'string' and name:sub(1, 2) == 't_' then return name:sub(3) end
    return S.PlaceKey or 'G'
end

--- Texte découpé en morceaux de 90 octets au plus, coupés entre deux mots (limite du jeu : 99 par morceau ;
--- CELL_EMAIL_BCON les met bout à bout)
local function helpParts(text)
    local parts, current = {}, ''
    for word in text:gmatch('%S+%s*') do
        if #current + #word > 90 and current ~= '' then
            parts[#parts + 1] = current
            current = ''
        end
        current = current .. word
    end
    if current ~= '' then parts[#parts + 1] = current end
    return parts
end

local function carryLoop()
    CreateThread(function()
        local parts, partsFor = nil, nil -- texte d'aide, refait seulement quand le nombre de plots change
        while carried do
            local ped = PlayerPedId()
            if IsEntityDead(ped) then
                placeCone(true) -- mort : les plots tombent à ses pieds
            else
                -- Plots dans les mains : ni monter dans un véhicule, ni frapper, ni viser, ni sortir une arme
                for _, c in ipairs({ 23, 24, 25, 37, 140, 141, 142, 257 }) do DisableControlAction(0, c, true) end
                if GetSelectedPedWeapon(ped) ~= UNARMED then SetCurrentPedWeapon(ped, UNARMED, true) end
                local anim = SC.Carry and SC.Carry.Anim
                if anim and not IsEntityPlayingAnim(ped, anim[1], anim[2], 3) and not IsPedRagdoll(ped) then playCarry(ped) end
                if not open and not IsPauseMenuActive() then
                    -- Texte d'aide : 99 caractères au plus par morceau (au-delà, le jeu l'affiche mal) : découpé
                    if partsFor ~= carried.count then
                        partsFor = carried.count
                        parts = helpParts(('"%s" pour poser un plot (%d en mains), utiliser le target pour récupérer les plots posés.'):format(
                            placeKeyName(), carried.count))
                    end
                    BeginTextCommandDisplayHelp('CELL_EMAIL_BCON')
                    for _, part in ipairs(parts) do AddTextComponentSubstringPlayerName(part) end
                    EndTextCommandDisplayHelp(0, false, false, -1)
                end
            end
            Wait(0)
        end
    end)
end

--- Nombre de plots portés (donné par le serveur) : pile mise à jour, port commencé ou arrêté
local function setCarried(count)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return stopCarry() end
    local ped = PlayerPedId()
    if not carried then
        carried = { count = count, props = {} }
        SetCurrentPedWeapon(ped, UNARMED, true)
        LocalPlayer.state:set('rpCarryingCone', true, false) -- (local) la touche G d'autres scripts ne réagit pas
        updateProps(ped)
        playCarry(ped)
        carryLoop()
    else
        carried.count = count
        updateProps(ped)
    end
    if sendInventory then sendInventory() end
end

RegisterCommand('rp_cone_place', function() if not spikesBusy() then placeCone(false) end end, false)
RegisterKeyMapping('rp_cone_place', 'Plot de circulation : poser au sol (plot porté)', 'keyboard', S.PlaceKey or 'G')

-- Le serveur a posé le(s) plot(s) : reste `left` dans les mains
RegisterNetEvent('rp_equipment:cone:placed', function(left)
    placingCone = false
    playPickup()
    setCarried(left)
    if not carried then showHint(TARGET_HINT, 8000) end -- dernier plot posé : comment les reprendre
end)

-- Plot(s) ramassé(s) avec l'œil (rp_interact) : `total` portés, dont `taken` à l'instant
RegisterNetEvent('rp_equipment:cone:carry', function(total, taken)
    playPickup()
    Wait(500)
    setCarried(total)
    -- (pas de message : les plots ramassés sont dans les mains)
end)

RegisterNetEvent('rp_equipment:notify', notify)

-- Coffre changé (par lui ou un collègue) : menu ouvert sur ce véhicule mis à jour
RegisterNetEvent('rp_equipment:stock', function(plate, stock)
    if open and open.plate == plate then SendNUIMessage({ action = 'stock', data = stock }) end
end)

local function stockResult(res, text)
    if not res.ok then return SendNUIMessage({ action = 'message', data = { text = res.error, error = true } }) end
    if res.stock then SendNUIMessage({ action = 'stock', data = res.stock }) end
    if text then SendNUIMessage({ action = 'message', data = { text = text } }) end
    return true
end

-- /restock : remplit le coffre du véhicule de police (celui où l'on est assis, sinon le plus proche à 6 m) à 100 %
RegisterCommand(S.RestockCommand or 'restock', function()
    local ped = PlayerPedId()
    local vehicle, kind = GetVehiclePedIsIn(ped, false), nil
    if vehicle ~= 0 then kind = vehicleType(vehicle) end
    if not kind then
        vehicle = nil
        local pos, best = GetEntityCoords(ped), S.RestockDistance or 6.0
        for _, v in ipairs(GetGamePool('CVehicle')) do
            local d = #(GetEntityCoords(v) - pos)
            if d < best then
                local k = vehicleType(v)
                if k then vehicle, kind, best = v, k, d end
            end
        end
    end
    if not vehicle then return notify('Aucun véhicule de police à côté de vous.') end
    request('restock', { net = VehToNet(vehicle), type = kind, where = 'trunk' }, function(res)
        if not res.ok then return notify(res.error or 'Action impossible.') end
        notify(('Véhicule %s réapprovisionné : %d / %d plots, %d / %d fusées, jerrican et pistolet radar (armes longues : à ranger vous-même).'):format(
            res.plate or '', res.stock.cones, res.stock.maxCones, res.stock.flares, res.stock.maxFlares))
    end)
end, false)

local function plural(n, word) return ('%d %s%s'):format(n, word, n > 1 and 's' or '') end

-- Prendre { count } plots (choisi dans le menu)
RegisterNUICallback('coneTake', function(data, cb)
    cb({ ok = true })
    if not open then return end
    local payload = context()
    payload.count = type(data) == 'table' and tonumber(data.count) or 1
    request('coneTake', payload, function(res)
        if not stockResult(res) then return end
        setCarried(res.carrying)
        SendNUIMessage({ action = 'message', data = { text = ('%s pris : G pour en poser un au sol.'):format(plural(res.count, 'plot')) } })
    end)
end)

-- Ranger : tous les plots portés d'un coup (ce que le coffre peut prendre)
RegisterNUICallback('coneStore', function(_, cb)
    cb({ ok = true })
    if not open then return end
    if not carried then return SendNUIMessage({ action = 'message', data = { text = 'Vous ne portez pas de plot.', error = true } }) end
    request('coneStore', context(), function(res)
        if not stockResult(res) then return end
        setCarried(res.carrying)
        local text = ('%s rangé%s dans le coffre.'):format(plural(res.count, 'plot'), res.count > 1 and 's' or '')
        if (res.carrying or 0) > 0 then text = text .. (' Coffre plein : %d encore en main.'):format(res.carrying) end
        SendNUIMessage({ action = 'message', data = { text = text } })
    end)
end)

-- Jerrican : { mode = 'take' | 'store' } ; rangé avec l'essence qui lui reste
RegisterNUICallback('jerrycan', function(data, cb)
    cb({ ok = true })
    if not open or type(data) ~= 'table' then return end
    local ped = PlayerPedId()
    local payload = context()
    payload.mode = data.mode == 'take' and 'take' or 'store'
    payload.held = HasPedGotWeapon(ped, PETROLCAN, false)
    payload.ammo = payload.held and GetAmmoInPedWeapon(ped, PETROLCAN) or 0
    request('jerrycan', payload, function(res)
        if not stockResult(res) then return end
        local p = PlayerPedId()
        if res.mode == 'take' then
            GiveWeaponToPed(p, PETROLCAN, res.ammo, false, true)
            SetPedAmmo(p, PETROLCAN, res.ammo)
            SendNUIMessage({ action = 'message', data = { text = ('Jerrican pris (%d %%).'):format(math.floor(res.ammo / CAN_AMMO * 100 + 0.5)) } })
        else
            RemoveWeaponFromPed(p, PETROLCAN)
            SendNUIMessage({ action = 'message', data = { text = 'Jerrican rangé dans le coffre.' } })
        end
        sendInventory(true)
    end)
end)

-- Pistolet radar : { mode = 'take' | 'store' }
RegisterNUICallback('radarGun', function(data, cb)
    cb({ ok = true })
    if not open or type(data) ~= 'table' then return end
    local payload = context()
    payload.mode = data.mode == 'take' and 'take' or 'store'
    payload.held = HasPedGotWeapon(PlayerPedId(), RADARGUN, false)
    request('radarGun', payload, function(res)
        if not stockResult(res) then return end
        local p = PlayerPedId()
        if res.mode == 'take' then
            GiveWeaponToPed(p, RADARGUN, 1, false, true)
            SendNUIMessage({ action = 'message', data = { text = 'Pistolet radar pris.' } })
        else
            RemoveWeaponFromPed(p, RADARGUN)
            SendNUIMessage({ action = 'message', data = { text = 'Pistolet radar rangé dans le coffre.' } })
        end
        sendInventory(true)
    end)
end)

-- Herse (riven_spikes) : { mode = 'take' | 'store' } : le menu se ferme, Riven fait la suite (animation au coffre)
RegisterNUICallback('spikes', function(data, cb)
    cb({ ok = true })
    if not open or type(data) ~= 'table' then return end
    local vehicle = open.vehicle
    closeMenu()
    if RPSpikes then RPSpikes.run(data.mode == 'store' and 'store' or 'take', vehicle) end
end)

-- Fusées : { mode = 'take' | 'store', all = true | false }
RegisterNUICallback('flares', function(data, cb)
    cb({ ok = true })
    if not open or type(data) ~= 'table' then return end
    local ped = PlayerPedId()
    local held = flaresHeld(ped)
    local mode = data.mode == 'take' and 'take' or 'store'
    local count
    if mode == 'take' then
        count = data.all and (MAX_FLARES_HELD - held) or 1
        if held >= MAX_FLARES_HELD then
            return SendNUIMessage({ action = 'message', data = { text = ('Vous avez déjà %d fusées sur vous.'):format(MAX_FLARES_HELD), error = true } })
        end
    else
        count = data.all and held or 1
        if held <= 0 then return SendNUIMessage({ action = 'message', data = { text = 'Vous n\'avez pas de fusée sur vous.', error = true } }) end
    end
    local payload = context()
    payload.mode, payload.count = mode, count
    request('flares', payload, function(res)
        if not stockResult(res) then return end
        local p = PlayerPedId()
        local now = flaresHeld(p)
        if res.mode == 'take' then
            if HasPedGotWeapon(p, FLARE, false) then AddAmmoToPed(p, FLARE, res.count) else GiveWeaponToPed(p, FLARE, res.count, false, false) end
            SendNUIMessage({ action = 'message', data = { text = ('%d fusée%s prise%s.'):format(res.count, res.count > 1 and 's' or '', res.count > 1 and 's' or '') } })
        else
            if now - res.count <= 0 then RemoveWeaponFromPed(p, FLARE) else SetPedAmmo(p, FLARE, now - res.count) end
            SendNUIMessage({ action = 'message', data = { text = ('%d fusée%s rangée%s.'):format(res.count, res.count > 1 and 's' or '', res.count > 1 and 's' or '') } })
        end
        sendInventory(true)
    end)
end)

-- =========================================================================
-- TOUCHE ET PROPOSITION
-- =========================================================================
--- Une action d'essence est proposée sur la même touche (pistolet de pompe / jerrican à la trappe, rp_vehiclecontrol) :
--- elle passe en premier, le menu Équipement ne s'ouvre pas
local function fuelPrompt() return LocalPlayer.state.vcFuelPrompt == true end

RegisterCommand('rp_equipment', function()
    if open then return closeMenu() end
    if not near or IsPauseMenuActive() or fuelPrompt() or spikesBusy() then return end -- E : touche de Riven
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
            if not open and not fuelPrompt() then
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
    if carried then for _, prop in ipairs(carried.props) do if DoesEntityExist(prop) then DeleteEntity(prop) end end end
end)
