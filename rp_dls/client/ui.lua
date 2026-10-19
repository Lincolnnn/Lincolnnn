--[[
    RP DLS - panneau de commande (NUI)
    ----------------------------------
    Affiché au conducteur d'un véhicule DLS (ou d'urgence) : stages, Traffic Advisor, Steady Burn, sirène…
    Touche « DLS : afficher / masquer le panneau » (gardé d'une session à l'autre). /dls : panneau cliquable à
    la souris (boutons, déplacement en glissant le titre, position gardée) ; Échap ou /dls pour en sortir.
]]

local Config = DLSConfig
local visible = GetResourceKvpInt('dls_panel_hidden') ~= 1
local focus = false

local STAGE_LABELS = { 'S1', 'S2', 'S3', 'C1', 'C2' }
local TONE_LABELS = { 'T1', 'T2', 'T3', 'T4' }

local function vehicleName(vehicle, model)
    local label = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
    if label and label ~= 'NULL' then return label end
    return model.name:upper()
end

-- Touche réellement attribuée par le joueur à une commande (affichée sur les boutons)
local BOUND = {
    stage1 = 'dls_stage1', stage2 = 'dls_stage2', stage3 = 'dls_stage3',
    tone1 = 'dls_tone1', tone2 = 'dls_tone2', tone3 = 'dls_tone3', tone4 = 'dls_tone4',
}
local function boundKeys()
    local keys = {}
    for name, command in pairs(BOUND) do
        local label = GetControlInstructionalButton(2, GetHashKey(command) | 0x80000000, true)
        if type(label) == 'string' and label:sub(1, 2) == 't_' then
            keys[name] = label:sub(3):gsub('^NUMPAD', 'N')
        end
    end
    return keys
end

local function setFocus(on)
    focus = on
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(false)
end

local function push()
    local vehicle, model = DLSC.driving()
    if vehicle == 0 or not model then
        if focus then setFocus(false) end
        SendNUIMessage({ action = 'hide' })
        return
    end
    local state = DLSC.copy(vehicle)
    local stages = {}
    for _, n in ipairs(model.available) do
        stages[#stages + 1] = { n = n, label = STAGE_LABELS[n], native = model.native[n] == true }
    end
    local tones = {}
    for n = 1, 4 do
        if model.tones[n] then tones[#tones + 1] = { n = n, label = TONE_LABELS[n] } end
    end
    local ta = nil
    if model.ta then
        local pattern, index, count = DLS.taPattern(model, state.tap ~= 0 and state.tap or nil)
        ta = {
            type = model.ta.type, divergeOnly = model.ta.divergeOnly,
            pattern = pattern and pattern.name or '', index = index or 0, count = count or 0,
        }
    end
    SendNUIMessage({
        action = 'update',
        show = visible or focus,
        focus = focus,
        name = vehicleName(vehicle, model),
        generic = model.generic == true,
        stages = stages,
        tones = tones,
        ta = ta,
        steady = model.steady ~= nil,
        state = state,
        locked = DLSC.locked,
        scan = DLSC.scan,
        manual = select(2, DLSC.inputs()),
        keys = boundKeys(),
    })
end
DLSC.pushUi = push

DLSC.onChange(function(vehicle)
    if vehicle == (DLSC.driving()) then push() end
end)

RegisterCommand('dls_panel', function()
    visible = not visible
    SetResourceKvpInt('dls_panel_hidden', visible and 0 or 1)
    push()
end, false)
RegisterKeyMapping('dls_panel', 'DLS : afficher / masquer le panneau', 'keyboard', Config.Keys.panel)

RegisterCommand(Config.Command or 'dls', function()
    if focus then setFocus(false) push() return end
    local vehicle = DLSC.driving()
    if vehicle == 0 then
        TriggerEvent('chat:addMessage', { args = { 'DLS', 'Au volant d\'un véhicule d\'urgence seulement.' }, color = { 255, 120, 90 } })
        return
    end
    setFocus(true)
    push()
end, false)

RegisterNUICallback('action', function(data, cb)
    if type(data) == 'table' and type(data.name) == 'string' then DLSC.action(data.name, data.arg) end
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    setFocus(false)
    push()
    cb('ok')
end)

-- Scan, verrou, manuelle… (pas dans l'état du véhicule) : panneau tenu à jour
CreateThread(function()
    local last = ''
    while true do
        local vehicle = DLSC.driving()
        local _, manual = DLSC.inputs()
        local mark = ('%d|%s|%s|%s'):format(vehicle, tostring(DLSC.scan), tostring(DLSC.locked), tostring(manual))
        if mark ~= last then
            last = mark
            push()
        end
        Wait(vehicle ~= 0 and 100 or 1000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and focus then SetNuiFocus(false, false) end
end)
