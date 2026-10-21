--[[
    RP PlateColors - Client : éditeur en jeu (/plaqueedit, ace rp_platecolors.edit)
    -------------------------------------------------------------------------------
    POSITION : pour le modèle du véhicule (celui où l'on est assis, sinon le plus proche), place le texte sur la
      plaque arrière / avant (cadre bleu = plaque), aperçu en direct, enregistré pour tous les joueurs.
    COULEURS : couleur du texte et contour par type de plaque (comme <FontColor> d'un carcols), aperçu en direct.
    Tab : libère la souris pour tourner la caméra (le panneau reste affiché), Tab à nouveau pour reprendre.
]]

local C = PlateConfig
local edit = nil          -- { veh, model, label, side, data = { rear = {on, x, y, z, pitch, yaw, scale}, front = ... } }
local looking = false
local KEYS = { 'x', 'y', 'z', 'pitch', 'yaw', 'scale' }

local function hex(rgb) return ('#%02x%02x%02x'):format(rgb[1], rgb[2], rgb[3]) end

local function copySide(p, fallback)
    local src = p or fallback
    local s = { on = p and true or false }
    for _, k in ipairs(KEYS) do s[k] = src[k] or (k == 'scale' and 1.0 or 0.0) end
    return s
end

--- Placement en cours de réglage -> format utilisé par le dessin / le serveur (côté désactivé = false)
local function packed()
    local out = { label = edit.label }
    for _, side in ipairs({ 'rear', 'front' }) do
        local s = edit.data[side]
        if s.on then
            out[side] = {}
            for _, k in ipairs(KEYS) do out[side][k] = s[k] end
        else
            out[side] = false
        end
    end
    return out
end

local function refreshPreview()
    Plates.preview = { model = edit.model, data = packed() }
    Plates.editSide = edit.side
end

local function colorsList()
    local list = {}
    local count = GetNumberOfVehicleNumberPlates()
    for i = 0, math.max(count, 6) - 1 do
        local c = Plates.colorFor(i)
        local def = C.Plates[i]
        list[#list + 1] = {
            index = i, label = def and def.label or ('Plaque ' .. i),
            text = hex(c.text), outline = c.outline and hex(c.outline) or false,
        }
    end
    return list
end

local function state()
    return {
        label = edit.label, side = edit.side, data = edit.data,
        saved = Plates.positions[tostring(edit.model)] ~= nil,
        plateIndex = GetVehicleNumberPlateTextIndex(edit.veh),
        plateText = GetVehicleNumberPlateText(edit.veh),
    }
end

local function close()
    if not edit then return end
    edit, looking = nil, false
    Plates.preview, Plates.editVeh, Plates.editSide = nil, nil, nil
    Plates.previewColors = {}
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function targetVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then return veh end
    local pos, best, bestD = GetEntityCoords(ped), nil, C.EditRange
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(v) - pos)
        if d < bestD then best, bestD = v, d end
    end
    return best
end

local function open()
    local veh = targetVehicle()
    if not veh then
        return TriggerEvent('chat:addMessage', { args = { 'Plaques', ('Aucun véhicule à moins de %d m.'):format(math.floor(C.EditRange)) } })
    end
    local model = GetEntityModel(veh)
    local current = Plates.positions[tostring(model)] or Plates.autoOf(model) or Plates.placementOf(veh, model) or {}
    local mn, mx = GetModelDimensions(model)
    edit = {
        veh = veh, model = model, side = current.rear ~= false and 'rear' or 'front',
        label = GetLabelText(GetDisplayNameFromVehicleModel(model)),
        data = {
            rear = copySide(current.rear, { x = 0.0, y = mn.y, z = mn.z + 0.4 }),
            front = copySide(current.front, { x = 0.0, y = mx.y, z = mn.z + 0.4 }),
        },
    }
    if edit.label == 'NULL' then edit.label = GetDisplayNameFromVehicleModel(model) end
    if current.rear == nil and current.front == nil then edit.data.rear.on = true end   -- estimation pas encore prête
    Plates.editVeh = veh
    refreshPreview()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = { state = state(), colors = colorsList() } })
end

RegisterNetEvent('rp_platecolors:editAllowed', function(allowed)
    if not allowed then
        return TriggerEvent('chat:addMessage', { args = { 'Plaques', 'Vous n\'avez pas la permission de régler les plaques.' } })
    end
    open()
end)

RegisterCommand(C.EditCommand, function()
    if edit then return close() end
    TriggerServerEvent('rp_platecolors:canEdit')
end, false)

-- Mode « regarder » : souris rendue au jeu, Tab pour reprendre le panneau ; véhicule disparu : fermeture
CreateThread(function()
    while true do
        if edit then
            if not DoesEntityExist(edit.veh) then close() end
            if looking then
                DisableControlAction(0, 37, true)   -- Tab : pas de roue des armes
                if IsDisabledControlJustPressed(0, 37) then
                    looking = false
                    SetNuiFocus(true, true)
                    SendNUIMessage({ action = 'looking', data = false })
                end
            end
            Wait(0)
        else
            Wait(300)
        end
    end
end)

-- =========================================================================
-- NUI
-- =========================================================================
RegisterNUICallback('close', function(_, cb) close(); cb({}) end)

RegisterNUICallback('look', function(_, cb)
    looking = true
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback('side', function(data, cb)
    if edit and (data.side == 'rear' or data.side == 'front') then
        edit.side = data.side
        refreshPreview()
    end
    cb(edit and state() or {})
end)

RegisterNUICallback('set', function(data, cb)
    local s = edit and edit.data[data.side]
    if s then
        if data.key == 'on' then
            s.on = data.value == true
        elseif s[data.key] and tonumber(data.value) then
            s[data.key] = tonumber(data.value) + 0.0
        end
        refreshPreview()
    end
    cb(edit and state() or {})
end)

RegisterNUICallback('auto', function(_, cb)
    if edit then
        local a = Plates.autoOf(edit.model)
        if a then
            for _, side in ipairs({ 'rear', 'front' }) do edit.data[side] = copySide(a[side], edit.data[side]) end
            refreshPreview()
        end
    end
    cb(edit and state() or {})
end)

RegisterNUICallback('save', function(_, cb)
    if edit then TriggerServerEvent('rp_platecolors:savePosition', edit.model, packed()) end
    cb({})
end)

RegisterNUICallback('reset', function(_, cb)
    if edit then TriggerServerEvent('rp_platecolors:savePosition', edit.model, nil) end
    cb({})
end)

RegisterNUICallback('plateIndex', function(data, cb)
    local i = tonumber(data.index)
    if edit and i then
        NetworkRequestControlOfEntity(edit.veh)
        SetVehicleNumberPlateTextIndex(edit.veh, math.floor(i))
    end
    cb(edit and state() or {})
end)

local function rgb(h)
    if type(h) ~= 'string' or not h:match('^#%x%x%x%x%x%x$') then return nil end
    return { tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16) }
end

RegisterNUICallback('color', function(data, cb)
    local i, text = tonumber(data.index), rgb(data.text)
    if edit and i and text then
        Plates.previewColors[tostring(math.floor(i))] = { text = text, outline = rgb(data.outline) or false }
    end
    cb({})
end)

RegisterNUICallback('saveColors', function(_, cb)
    local all = {}
    for _, c in ipairs(colorsList()) do
        all[tostring(c.index)] = { text = rgb(c.text), outline = rgb(c.outline) or false }
    end
    TriggerServerEvent('rp_platecolors:saveColors', all)
    cb({})
end)

RegisterNUICallback('resetColors', function(_, cb)
    Plates.previewColors = {}
    TriggerServerEvent('rp_platecolors:saveColors', {})
    cb({})
end)

-- Réponse du serveur après un enregistrement
RegisterNetEvent('rp_platecolors:saved', function(text, isError)
    if not edit then return end
    if not isError then
        Plates.previewColors = {}
        -- les réglages enregistrés arrivent par rp_platecolors:position / :colors, rafraîchir le panneau ensuite
        SetTimeout(200, function()
            if edit then SendNUIMessage({ action = 'refresh', data = { state = state(), colors = colorsList() } }) end
        end)
    end
    SendNUIMessage({ action = 'message', data = { text = text, error = isError } })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and edit then SetNuiFocus(false, false) end
end)
