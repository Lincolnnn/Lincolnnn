--[[
    RP TrafficControl - client : menu (NUI, style du MDC) et commande /trafic
    -------------------------------------------------------------------------
    Nouvelle mesure (fermeture / ralentissement / arrêt ; portée : voie, sens ou route entière ; durée, vitesse)
    -> l'outil de pose (editor.lua). Mesures actives : lieu, auteur, temps restant, « Repérer » (point GPS) et « Lever ».
    Aucune boucle : le menu se met à jour quand les mesures changent (GlobalState.rpTraffic).
]]

TC = TC or {}
local Config = TrafficConfig

local open = false
local pending, nextId = {}, 0

-- =========================================================================
-- DEMANDES AU SERVEUR
-- =========================================================================
function TC.request(action, data, cb)
    nextId = nextId + 1
    pending[nextId] = cb
    TriggerServerEvent('rp_traffic:request', nextId, action, data or {})
end

RegisterNetEvent('rp_traffic:response', function(id, result)
    local cb = pending[id]
    pending[id] = nil
    if cb then cb(result or {}) end
end)

-- =========================================================================
-- MENU
-- =========================================================================
local function blockPauseAfterClose()
    CreateThread(function()
        local untilTime, extra = GetGameTimer() + 3000, 10
        while extra > 0 and GetGameTimer() < untilTime and not open do
            for _, c in ipairs({ 199, 200, 322 }) do DisableControlAction(0, c, true) end
            if IsPauseMenuActive() then SetPauseMenuActive(false) end
            if not (IsDisabledControlPressed(0, 200) or IsDisabledControlPressed(0, 322)) then extra = extra - 1 end
            Wait(0)
        end
    end)
end

local function closeMenu()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    blockPauseAfterClose()
end

local function refresh()
    TC.request('list', {}, function(res)
        if open and res.ok then SendNUIMessage({ action = 'list', data = { measures = res.measures or {} } }) end
    end)
end

local function openMenu()
    if open or TC.editing() then return end
    TC.request('list', {}, function(res)
        if not res.ok or not res.allowed then
            return TC.notify(res.error or 'Gestion du trafic réservée aux policiers en service (unité du MDC).')
        end
        open = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'open', data = {
            measures = res.measures or {}, durations = res.durations or Config.Durations,
            defaultDuration = res.defaultDuration or Config.DefaultDuration, speed = res.speed or Config.Speed,
            unit = LocalPlayer.state.mdcUnit or '', max = res.max, maxMine = res.maxMine,
        } })
    end)
end

-- Mesures changées (par lui ou un collègue) : menu ouvert mis à jour
TC.onChange = function() if open then refresh() end end

RegisterCommand(Config.Command or 'trafic', function()
    if open then closeMenu() else openMenu() end
end, false)
if Config.Key and Config.Key ~= '' then
    RegisterKeyMapping(Config.Command or 'trafic', 'Gestion du trafic (fermetures, ralentissements)', 'keyboard', Config.Key)
end
TriggerEvent('chat:addSuggestion', '/' .. (Config.Command or 'trafic'), 'Gestion du trafic : fermer une voie / un sens / la route, ralentir, arrêter')

-- =========================================================================
-- CALLBACKS NUI
-- =========================================================================
RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    closeMenu()
end)

-- Nouvelle mesure : { kind, scope, duration, speed } -> outil de pose
RegisterNUICallback('pick', function(data, cb)
    cb({ ok = true })
    if type(data) ~= 'table' or (data.kind ~= 'close' and data.kind ~= 'slow' and data.kind ~= 'stop') then return end
    closeMenu()
    TC.startEditor(data.kind, { scope = data.scope, duration = data.duration, speed = data.speed })
end)

RegisterNUICallback('remove', function(data, cb)
    cb({ ok = true })
    TC.request('remove', { id = type(data) == 'table' and data.id }, function(res)
        if not res.ok then return SendNUIMessage({ action = 'message', data = { text = res.error, error = true } }) end
        SendNUIMessage({ action = 'message', data = { text = 'Mesure levée : le trafic reprend.' } })
    end)
end)

RegisterNUICallback('clear', function(data, cb)
    cb({ ok = true })
    TC.request('clear', { mine = type(data) == 'table' and data.mine == true }, function(res)
        if not res.ok then return SendNUIMessage({ action = 'message', data = { text = res.error, error = true } }) end
        SendNUIMessage({ action = 'message', data = { text = ('%d mesure%s levée%s.'):format(res.count or 0,
            (res.count or 0) > 1 and 's' or '', (res.count or 0) > 1 and 's' or '') } })
    end)
end)

-- « Repérer » : point GPS sur la mesure
RegisterNUICallback('locate', function(data, cb)
    cb({ ok = true })
    local id = type(data) == 'table' and tonumber(data.id)
    for _, m in ipairs(TC.measures or {}) do
        if m.id == id then
            local p = { x = (m.a.x + m.b.x) / 2, y = (m.a.y + m.b.y) / 2 }
            SetNewWaypoint(p.x + 0.0, p.y + 0.0)
            SendNUIMessage({ action = 'message', data = { text = 'Point GPS placé sur la mesure.' } })
            return
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and open then SetNuiFocus(false, false) end
end)
