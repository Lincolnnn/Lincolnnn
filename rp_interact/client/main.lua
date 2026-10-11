--[[
    RP Interact - Client principal
    ------------------------------
    - Menu d'interactions (touche F1 par défaut) : cases "Police" et "Civil"
    - Fiche civile (interface séparée du MDC, même style) : profils permanents et profil du véhicule
    - Affichage des résultats d'inspection (à l'écran + copie dans le chat écrit)

    Performance : aucune boucle dans ce fichier. L'œil (client/target.lua) ne tourne que pendant
    que la touche Alt est maintenue ; s'asseoir (client/options.lua) seulement pendant qu'on est assis.
]]

local Config = InteractConfig

RPI = {}

-- =========================================================================
-- REQUÊTES SERVEUR (requête -> réponse)
-- =========================================================================
local pending, requestId = {}, 0

function RPI.request(name, payload, cb)
    requestId = requestId + 1
    local id = requestId
    pending[id] = cb
    TriggerServerEvent('rp_interact:server:request', name, id, payload or {})
    SetTimeout(5000, function()
        local waiting = pending[id]
        if waiting then
            pending[id] = nil
            waiting({ ok = false, error = 'Le serveur ne répond pas.' })
        end
    end)
end

RegisterNetEvent('rp_interact:client:response', function(id, result)
    local cb = pending[id]
    if not cb then return end
    pending[id] = nil
    cb(result)
end)

-- =========================================================================
-- FOCUS NUI : menu, fiche civile et liste d'options de l'œil
-- =========================================================================
local ui = { menu = false, editor = false, options = false }

function RPI.setUi(name, open)
    ui[name] = open and true or false
    local any = ui.menu or ui.editor or ui.options
    SetNuiFocus(any, any)
end

function RPI.uiOpen(name)
    if name then return ui[name] end
    return ui.menu or ui.editor or ui.options
end

function RPI.notify(text, kind)
    SendNUIMessage({ action = 'notify', data = { text = text, type = kind or 'info' } })
end

--- Policier = dans une unité du MDC (état publié par le MDC ; le serveur revérifie)
function RPI.isPolice()
    local unit = LocalPlayer.state.mdcUnit
    return type(unit) == 'string' and unit ~= ''
end

-- =========================================================================
-- RÉSULTATS D'INSPECTION
-- =========================================================================
function RPI.showResult(result)
    SendNUIMessage({ action = 'result', data = {
        title = result.title, subject = result.subject, text = result.text, duration = Config.ResultDuration,
    } })
    -- Copie privée dans le chat écrit (relisible plus tard)
    if Config.ResultsInChat and GetResourceState(Config.ChatResource) == 'started' then
        pcall(function()
            exports[Config.ChatResource]:addMessage({
                args = { ('%s (%s)'):format(result.title, result.subject), result.text },
                color = { 140, 200, 255 },
            })
        end)
    end
end

-- =========================================================================
-- VÉHICULE DU JOUEUR (pour "Créer un véhicule")
-- =========================================================================
local function gameLabel(key)
    if not key or key == '' then return '' end
    local label = GetLabelText(key)
    if label == 'NULL' or label == '' then return (key:lower():gsub('^%l', string.upper)) end
    return label
end

function RPI.vehicleLabel(vehicle)
    local model = GetEntityModel(vehicle)
    local okMake, makeKey = pcall(GetMakeNameFromVehicleModel, model)
    local make = okMake and gameLabel(makeKey) or ''
    local name = gameLabel(GetDisplayNameFromVehicleModel(model))
    return make ~= '' and (make .. ' ' .. name) or name
end

function RPI.vehiclePlate(vehicle)
    return (GetVehicleNumberPlateText(vehicle) or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

--- Véhicule dans lequel se trouve le joueur, sinon le plus proche (6 m)
local function findVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        local coords = GetEntityCoords(ped)
        local best = 6.0
        for _, candidate in ipairs(GetGamePool('CVehicle')) do
            local d = #(GetEntityCoords(candidate) - coords)
            if d < best then vehicle, best = candidate, d end
        end
    end
    if vehicle == 0 then return nil, 'Montez dans le véhicule ou placez-vous juste à côté.' end
    if not NetworkGetEntityIsNetworked(vehicle) then return nil, 'Ce véhicule n\'est pas synchronisé avec le serveur.' end
    return { netId = VehToNet(vehicle), label = RPI.vehicleLabel(vehicle), plate = RPI.vehiclePlate(vehicle) }
end

-- =========================================================================
-- MENU D'INTERACTIONS
-- =========================================================================
local function openMenu()
    if RPI.uiOpen() or IsPauseMenuActive() or (RPI.targetActive and RPI.targetActive()) then return end
    RPI.request('getMenuState', {}, function(res)
        if RPI.uiOpen() then return end
        RPI.setUi('menu', true)
        SendNUIMessage({ action = 'menu', data = {
            open = true,
            activeName = res and res.activeName or nil,
            police = res and res.police or nil,
            targetKey = Config.TargetKey == 'LMENU' and 'Alt' or Config.TargetKey,
        } })
    end)
end

local function closeMenu()
    if not ui.menu then return end
    RPI.setUi('menu', false)
    SendNUIMessage({ action = 'menu', data = { open = false } })
end

RegisterCommand('interactions', function()
    if ui.menu then closeMenu() else openMenu() end
end, false)
RegisterKeyMapping('interactions', 'Menu d\'interactions', 'keyboard', Config.MenuKey)

RegisterNUICallback('closeMenu', function(_, cb)
    closeMenu()
    cb({ ok = true })
end)

-- =========================================================================
-- FICHE CIVILE (profils et véhicule)
-- =========================================================================
local function openEditor(view, vehicle, cb)
    RPI.request('getProfiles', {}, function(profiles)
        local function show(vehicleData)
            closeMenu()
            RPI.setUi('editor', true)
            SendNUIMessage({ action = 'editor', data = {
                open = true, view = view, profiles = profiles, vehicle = vehicleData,
            } })
            if cb then cb({ ok = true }) end
        end
        if view ~= 'vehicle' then return show(nil) end
        RPI.request('getVehicleProfile', { netId = vehicle.netId }, function(res)
            if not res or not res.ok then
                if cb then cb({ ok = false, error = res and res.error or 'Véhicule introuvable.' }) end
                return
            end
            vehicle.profile, vehicle.taken = res.profile, res.taken
            show(vehicle)
        end)
    end)
end

-- Boutons "Créer un profil" / "Créer un véhicule" du menu (le menu se ferme)
RegisterNUICallback('openEditor', function(data, cb)
    local view = type(data) == 'table' and data.view == 'vehicle' and 'vehicle' or 'profiles'
    if view == 'vehicle' then
        local vehicle, err = findVehicle()
        if not vehicle then return cb({ ok = false, error = err }) end
        return openEditor(view, vehicle, cb)
    end
    openEditor(view, nil, cb)
end)

-- Onglet "Véhicule" de la fiche : cherche le véhicule actuel / le plus proche
RegisterNUICallback('findVehicle', function(_, cb)
    local vehicle, err = findVehicle()
    if not vehicle then return cb({ ok = false, error = err }) end
    RPI.request('getVehicleProfile', { netId = vehicle.netId }, function(res)
        if not res or not res.ok then return cb({ ok = false, error = res and res.error or 'Véhicule introuvable.' }) end
        vehicle.profile, vehicle.taken = res.profile, res.taken
        cb({ ok = true, vehicle = vehicle })
    end)
end)

RegisterNUICallback('closeEditor', function(_, cb)
    RPI.setUi('editor', false)
    SendNUIMessage({ action = 'editor', data = { open = false } })
    cb({ ok = true })
end)

-- Relais vers le serveur (les vérifications sont faites côté serveur)
for _, name in ipairs({ 'getProfiles', 'saveProfile', 'deleteProfile', 'setActive', 'saveVehicleProfile', 'deleteVehicleProfile' }) do
    RegisterNUICallback(name, function(data, cb)
        RPI.request(name, type(data) == 'table' and data or {}, cb)
    end)
end

-- =========================================================================
-- SÉCURITÉ : relâche le focus si la ressource est arrêtée
-- =========================================================================
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and RPI.uiOpen() then SetNuiFocus(false, false) end
end)
