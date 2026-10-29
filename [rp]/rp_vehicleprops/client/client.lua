--[[
    RP VehicleProps - client
    ------------------------
    OBJETS POSÉS (chez tous les joueurs) : chaque véhicule garde sa liste dans son état "rpProps" (écrit par le
      serveur). Chaque joueur pose ses propres objets (locaux, sans collision) collés au véhicule ; ils suivent ses
      changements et disparaissent avec lui.
    ŒIL (rp_interact, Config.TargetProviders) : sur un véhicule, à pied, à moins de VPConfig.Distance m :
      « Ajouter un objet » (il apparaît là où l'on regarde), « Déplacer un objet », « Retirer un objet ».
    ÉDITEUR (NUI) : position (X, Y, Z) et rotation (tangage, roulis, lacet) au curseur, sensibilité ; aperçu en
      direct (seulement chez soi) ; Enregistrer l'envoie au serveur, Échap / Annuler le laisse tel quel. La dernière
      rotation choisie pour un objet est gardée (KVP) pour le suivant.
    Performance : une vérification toutes les 2,5 s (véhicules proches portant des objets) ; rien d'autre à pied.
]]

local Config = VPConfig
local E = Config.Editor or {}
local RANGE = E.Range or 3.0

local byId = {}
for _, p in ipairs(Config.Props or {}) do byId[p.id] = p end

local posed = {}      -- [véhicule] = { sig, objects = { [id] = objet } }
local editor = nil    -- { vehicle, netId, id, key, offsets, preview, hidden }
local KVP = 'rp_vehicleprops:rot:'

local function notify(text)
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started'
        and pcall(function() exports[chat]:addPrivate({ title = 'Objets', text = text }) end) then
        return
    end
    TriggerEvent('chat:addMessage', { args = { 'Objets', text }, color = { 140, 200, 255 } })
end

local function loadModel(model)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local untilTime = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < untilTime do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function attach(obj, vehicle, o)
    AttachEntityToEntity(obj, vehicle, 0, o.x + 0.0, o.y + 0.0, o.z + 0.0, o.rx + 0.0, o.ry + 0.0, o.rz + 0.0,
        false, false, false, false, 2, true)
end

--- Objet local (sans collision, indestructible) collé au véhicule ; nil si le modèle n'existe pas
local function spawn(vehicle, key, o)
    local prop = byId[key]
    local hash = prop and loadModel(prop.model)
    if not hash then return nil end
    local c = GetEntityCoords(vehicle)
    local obj = CreateObjectNoOffset(hash, c.x, c.y, c.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not obj or obj == 0 then return nil end
    SetEntityCollision(obj, false, false)
    SetEntityInvincible(obj, true)
    SetEntityCanBeDamaged(obj, false)
    SetEntityDynamic(obj, false)
    attach(obj, vehicle, o)
    return obj
end

local function clearVehicle(vehicle)
    local entry = posed[vehicle]
    if not entry then return end
    for _, obj in pairs(entry.objects) do
        if DoesEntityExist(obj) then DeleteObject(obj) end
    end
    posed[vehicle] = nil
end

--- Liste de l'état du véhicule -> signature (refaire les objets seulement si elle change)
local function signature(list)
    local parts = {}
    for _, p in ipairs(list) do
        parts[#parts + 1] = ('%s:%s:%.3f:%.3f:%.3f:%.1f:%.1f:%.1f'):format(p.id, p.key, p.x, p.y, p.z, p.rx, p.ry, p.rz)
    end
    return table.concat(parts, '|')
end

local function propsOf(vehicle)
    local list = Entity(vehicle).state.rpProps
    local out = {}
    if type(list) == 'table' then
        for _, p in ipairs(list) do
            if type(p) == 'table' and byId[p.key] and type(p.id) == 'string' then
                out[#out + 1] = { id = p.id, key = p.key, x = tonumber(p.x) or 0.0, y = tonumber(p.y) or 0.0,
                    z = tonumber(p.z) or 0.0, rx = tonumber(p.rx) or 0.0, ry = tonumber(p.ry) or 0.0, rz = tonumber(p.rz) or 0.0 }
            end
        end
    end
    return out
end
VPClient = { propsOf = propsOf, signature = signature } -- pour les tests

--- Objets du véhicule remis à jour d'après son état (posés, déplacés, retirés)
local function refresh(vehicle)
    if not DoesEntityExist(vehicle) then return clearVehicle(vehicle) end
    local list = propsOf(vehicle)
    local sig = signature(list)
    local entry = posed[vehicle]
    if entry and entry.sig == sig then return end
    clearVehicle(vehicle)
    if #list == 0 then return end
    entry = { sig = sig, objects = {} }
    posed[vehicle] = entry
    for _, p in ipairs(list) do
        entry.objects[p.id] = spawn(vehicle, p.key, p)
        -- objet en cours de réglage : caché (l'aperçu le remplace)
        if editor and editor.vehicle == vehicle and editor.id == p.id and entry.objects[p.id] then
            SetEntityVisible(entry.objects[p.id], false, false)
        end
    end
end
VPClient.refresh = refresh

-- Changement de l'état d'un véhicule (objet posé, déplacé, retiré, véhicule qui arrive près de soi)
AddStateBagChangeHandler('rpProps', nil, function(bagName)
    CreateThread(function()
        local untilTime = GetGameTimer() + 3000
        local vehicle = GetEntityFromStateBagName(bagName)
        while (vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < untilTime do
            Wait(100)
            vehicle = GetEntityFromStateBagName(bagName)
        end
        if vehicle ~= 0 then Wait(0); refresh(vehicle) end -- Wait(0) : nouvel état lu, pas l'ancien
    end)
end)

-- Toutes les 2,5 s : véhicules proches qui portent des objets (arrivés près de soi), véhicules disparus
CreateThread(function()
    while true do
        Wait(2500)
        for vehicle in pairs(posed) do
            if not DoesEntityExist(vehicle) then clearVehicle(vehicle) end
        end
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if posed[vehicle] or Entity(vehicle).state.rpProps then refresh(vehicle) end
        end
    end
end)

-- =========================================================================
-- ÉDITEUR
-- =========================================================================
local function savedRotation(key)
    local raw = GetResourceKvpString(KVP .. key)
    local ok, r = pcall(json.decode, raw or '')
    if ok and type(r) == 'table' then return tonumber(r.rx) or 0.0, tonumber(r.ry) or 0.0, tonumber(r.rz) or 0.0 end
    return 0.0, 0.0, 0.0
end

local function clampOffsets(o)
    local function c(v, m) v = tonumber(v) or 0.0; return math.max(-m, math.min(m, v)) + 0.0 end
    return { x = c(o.x, RANGE), y = c(o.y, RANGE), z = c(o.z, RANGE), rx = c(o.rx, 180.0), ry = c(o.ry, 180.0), rz = c(o.rz, 180.0) }
end
VPClient.clampOffsets = clampOffsets

local function closeUi()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function stopEditor()
    if not editor then return end
    if editor.preview and DoesEntityExist(editor.preview) then DeleteObject(editor.preview) end
    local entry = posed[editor.vehicle]
    if editor.id and entry and entry.objects[editor.id] and DoesEntityExist(entry.objects[editor.id]) then
        SetEntityVisible(entry.objects[editor.id], true, false)
    end
    editor = nil
end

local function vehicleInfo(vehicle)
    return { plate = (GetVehicleNumberPlateText(vehicle) or ''):gsub('^%s+', ''):gsub('%s+$', ''),
        name = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))) }
end

--- Ouvre l'éditeur sur un objet (nouveau : key ; posé : id)
local function startEditor(vehicle, key, offsets, id)
    stopEditor()
    local preview = spawn(vehicle, key, offsets)
    if not preview then return notify('Modèle introuvable dans le jeu : ' .. (byId[key] and byId[key].model or key) .. '.') end
    SetEntityAlpha(preview, 215, false)
    editor = { vehicle = vehicle, netId = VehToNet(vehicle), id = id, key = key, offsets = offsets, preview = preview }
    local entry = posed[vehicle]
    if id and entry and entry.objects[id] then SetEntityVisible(entry.objects[id], false, false) end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'editor', data = {
        title = byId[key].label, mode = id and 'edit' or 'add', offsets = offsets, vehicle = vehicleInfo(vehicle),
        range = RANGE, step = E.Step or 0.01, rotStep = E.RotStep or 1.0, sensitivity = E.Sensitivity,
    } })
end

--- Menu : liste des objets à ajouter, ou de ceux posés (déplacer / retirer)
local function openList(vehicle, mode, hit)
    local data = { mode = mode, vehicle = vehicleInfo(vehicle) }
    if mode == 'add' then
        data.props = {}
        for _, p in ipairs(Config.Props or {}) do data.props[#data.props + 1] = { id = p.id, label = p.label, category = p.category or 'Objets' } end
    else
        data.placed = {}
        for _, p in ipairs(propsOf(vehicle)) do data.placed[#data.placed + 1] = { id = p.id, label = byId[p.key].label, category = byId[p.key].category } end
    end
    editor = { vehicle = vehicle, netId = VehToNet(vehicle), hit = hit, list = true }
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'list', data = data })
end

RegisterNUICallback('choose', function(data, cb)
    cb({ ok = true })
    local ctx = editor
    if not ctx or not DoesEntityExist(ctx.vehicle) then return closeUi() end
    local vehicle = ctx.vehicle
    if data.mode == 'add' and byId[data.id] then
        -- là où l'on regardait avec l'œil, rotation de la dernière fois pour cet objet
        local o = { x = 0.0, y = 0.0, z = 0.5 }
        if ctx.hit then
            local off = GetOffsetFromEntityGivenWorldCoords(vehicle, ctx.hit.x, ctx.hit.y, ctx.hit.z)
            o = { x = off.x, y = off.y, z = off.z + 0.05 }
        end
        o.rx, o.ry, o.rz = savedRotation(data.id)
        editor = nil
        startEditor(vehicle, data.id, clampOffsets(o), nil)
    elseif data.mode == 'edit' then
        for _, p in ipairs(propsOf(vehicle)) do
            if p.id == data.id then editor = nil; return startEditor(vehicle, p.key, clampOffsets(p), p.id) end
        end
        closeUi(); editor = nil
        notify('Cet objet n\'est plus sur le véhicule.')
    elseif data.mode == 'remove' and type(data.id) == 'string' then
        TriggerServerEvent('rp_vehicleprops:remove', VehToNet(vehicle), data.id)
        closeUi(); editor = nil
    end
end)

RegisterNUICallback('offsets', function(data, cb)
    cb({ ok = true })
    if not editor or not editor.preview or not DoesEntityExist(editor.preview) or not DoesEntityExist(editor.vehicle) then return end
    editor.offsets = clampOffsets(data)
    attach(editor.preview, editor.vehicle, editor.offsets)
end)

RegisterNUICallback('save', function(_, cb)
    cb({ ok = true })
    if not editor or not editor.preview then return end
    local o = editor.offsets
    SetResourceKvp(KVP .. editor.key, json.encode({ rx = o.rx, ry = o.ry, rz = o.rz }))
    TriggerServerEvent('rp_vehicleprops:save', editor.netId, { id = editor.id, key = editor.key, offsets = o })
    closeUi()
    stopEditor()
end)

RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    closeUi()
    if editor and editor.list then editor = nil else stopEditor() end
end)

RegisterNetEvent('rp_vehicleprops:result', function(ok, text)
    if not ok and type(text) == 'string' then notify(text) end -- seulement ce qui n'a pas marché
end)

-- =========================================================================
-- ŒIL (rp_interact : Config.TargetProviders) : exports targetOptions / targetSelect
-- =========================================================================
local function vehicleFromInfo(info)
    if type(info) ~= 'table' or info.type ~= 'vehicle' or not info.entity or not DoesEntityExist(info.entity) then return nil end
    if (tonumber(info.distance) or 99.0) > (Config.Distance or 3.0) then return nil end
    if IsPedInAnyVehicle(PlayerPedId(), false) or not NetworkGetEntityIsNetworked(info.entity) then return nil end
    return info.entity
end

exports('targetOptions', function(info)
    if editor then return nil end
    local vehicle = vehicleFromInfo(info)
    if not vehicle then return nil end
    local count = #propsOf(vehicle)
    local options = { { id = 'add', icon = 'hand', label = 'Ajouter un objet' } }
    if count > 0 then
        options[#options + 1] = { id = 'edit', icon = 'move', label = ('Déplacer un objet (%d)'):format(count) }
        options[#options + 1] = { id = 'remove', icon = 'trash', label = 'Retirer un objet' }
    end
    return { label = 'Véhicule', options = options }
end)

exports('targetSelect', function(id, info)
    local vehicle = vehicleFromInfo(info)
    if not vehicle then return notify('Rapprochez-vous du véhicule.') end
    if id == 'add' or id == 'edit' or id == 'remove' then openList(vehicle, id, info.hit) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopEditor()
    for vehicle in pairs(posed) do clearVehicle(vehicle) end
end)
