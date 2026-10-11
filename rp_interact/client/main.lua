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

-- Notification envoyée par le serveur (ex. confirmation de /policeon, /policeoff)
RegisterNetEvent('rp_interact:client:notify', function(text, kind)
    if type(text) == 'string' then RPI.notify(text, kind) end
end)

-- =========================================================================
-- EN SERVICE (POLICE) = dans une unité du MDC
-- Le MDC publie l'unité du joueur (état "mdcUnit") à chaque entrée / sortie d'unité : le statut
-- change immédiatement (le serveur revérifie de son côté à chaque fouille).
-- =========================================================================
local function unitName(value) return type(value) == 'string' and value ~= '' and value or nil end
local dutyUnit = unitName(LocalPlayer.state.mdcUnit)

function RPI.isPolice() return dutyUnit ~= nil end
function RPI.dutyUnit() return dutyUnit end

-- Appelé AVANT que la nouvelle valeur soit enregistrée : on garde la valeur reçue
AddStateBagChangeHandler('mdcUnit', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    local unit = unitName(value)
    if unit == dutyUnit then return end
    local wasOnDuty = dutyUnit ~= nil
    dutyUnit = unit
    if unit and not wasOnDuty then
        RPI.notify(('En service (unité %s) : fouilles et détails notoires disponibles avec l\'œil.'):format(unit), 'success')
    elseif not unit and wasOnDuty then
        RPI.notify('Hors service : fouilles et détails notoires retirés.', 'info')
    end
    if RPI.onDutyChanged then RPI.onDutyChanged() end
    SendNUIMessage({ action = 'menuPolice', data = { police = unit } })
end)

--- Direction de la caméra (rotation en degrés -> vecteur unitaire)
function RPI.camDirection(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vector3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

-- =========================================================================
-- OUTILS PARTAGÉS (animations, modèles, contrôle réseau)
-- =========================================================================
function RPI.loadAnim(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 1500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

--- Joue une animation sur un ped (le joueur par défaut). À appeler dans un thread si le
--- dictionnaire n'est pas encore chargé (sinon : RPI.playAnim crée son propre thread).
function RPI.playAnimNow(ped, dict, clip, duration, flag)
    if not RPI.loadAnim(dict) then return false end
    TaskPlayAnim(ped, dict, clip, 8.0, -8.0, duration or -1, flag or 49, 0.0, false, false, false)
    return true
end

function RPI.playAnim(dict, clip, duration, flag, ped)
    CreateThread(function() RPI.playAnimNow(ped or PlayerPedId(), dict, clip, duration, flag) end)
end

function RPI.loadModel(model)
    RequestModel(model)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(10) end
    return HasModelLoaded(model)
end

--- Contrôle réseau d'une entité (portières d'un autre véhicule, PNJ), puis action
function RPI.withControl(entity, fn)
    CreateThread(function()
        local timeout = GetGameTimer() + 1000
        NetworkRequestControlOfEntity(entity)
        while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
            Wait(0)
            NetworkRequestControlOfEntity(entity)
        end
        fn()
    end)
end

-- =========================================================================
-- BARRE DE CHARGEMENT (fouilles, menottes)
-- Thème du HUD, barre bleue (même bleu que les résultats privés du chat). Pendant l'action, le
-- joueur ne se déplace pas ; X annule. Boucle active uniquement pendant la barre.
-- opts = { label, duration (ms), anim = { dict, clip, flag }, scenario, keep = function() -> bool }
-- =========================================================================
local progressRunning = false
local CANCEL_KEY = 73 -- X
local PROGRESS_BLOCKED = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 44, 140, 141, 142, 143, 257, 263, 264 }

function RPI.busy() return progressRunning end

function RPI.progress(opts, onDone, onCancel)
    if progressRunning then
        RPI.notify('Une action est déjà en cours.', 'error')
        return false
    end
    progressRunning = true
    local ped = PlayerPedId()
    SendNUIMessage({ action = 'progress', data = { show = true, label = opts.label, duration = opts.duration } })
    if opts.anim then RPI.playAnim(opts.anim[1], opts.anim[2], -1, opts.anim[3] or 49) end
    if opts.scenario then TaskStartScenarioInPlace(ped, opts.scenario, 0, true) end

    CreateThread(function()
        local endsAt = GetGameTimer() + opts.duration
        local nextKeep, reason = 0, nil
        while true do
            Wait(0)
            for _, control in ipairs(PROGRESS_BLOCKED) do DisableControlAction(0, control, true) end
            local now = GetGameTimer()
            if IsControlJustPressed(0, CANCEL_KEY) then reason = 'cancel' break end
            if IsEntityDead(ped) then reason = 'dead' break end
            if opts.keep and now >= nextKeep then
                nextKeep = now + 250
                if not opts.keep() then reason = 'lost' break end
            end
            if now >= endsAt then break end
        end
        progressRunning = false
        SendNUIMessage({ action = 'progress', data = { show = false } })
        if opts.anim then StopAnimTask(ped, opts.anim[1], opts.anim[2], 1.0) end
        if opts.scenario then ClearPedTasks(ped) end
        if reason then
            if onCancel then onCancel(reason) end
        elseif onDone then
            onDone()
        end
    end)
    return true
end

-- =========================================================================
-- RÉSULTATS D'INSPECTION : PRIVÉS (uniquement chez le joueur qui inspecte)
-- La fiche à l'écran et la copie dans le chat ne sont affichées que sur ce client ;
-- seul le /me automatique (envoyé par le serveur) est vu par les joueurs autour.
-- =========================================================================
function RPI.showResult(result)
    SendNUIMessage({ action = 'result', data = {
        title = result.title, subject = result.subject, text = result.text, duration = Config.ResultDuration,
    } })
    local chat = GlobalState.rpChatResource or Config.ChatResource
    if Config.ResultsInChat and GetResourceState(chat) == 'started' then
        local ok = pcall(function()
            exports[chat]:addPrivate({ title = result.title, subject = result.subject, text = result.text })
        end)
        if not ok then -- ancien chat sans addPrivate
            pcall(function()
                exports[chat]:addMessage({ args = { ('[Privé] %s (%s)'):format(result.title, result.subject), result.text }, color = { 140, 200, 255 } })
            end)
        end
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
            civilMode = RPI.civilMode and RPI.civilMode() or false,
            tipsManual = RPI.tipsManual and RPI.tipsManual() or false,
        } })
    end)
end

local function closeMenu()
    if not ui.menu then return end
    RPI.setUi('menu', false)
    SendNUIMessage({ action = 'menu', data = { open = false } })
end

RPI.closeMenu = closeMenu

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
