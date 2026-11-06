--[[
    RP TrafficControl - client : menu (NUI, style du MDC) et commande /trafic
    -------------------------------------------------------------------------
    Nouvelle mesure, dans cet ordre :
      1. « Choisir la zone du trafic » (portée : voie, sens ou route entière) -> on vise la route (editor.lua) : les
         nœuds du trafic concernés s'affichent ;
      2. zone choisie : le panneau propose l'ACTION sur ce trafic : fermeture de voie (le trafic se réoriente vers une
         autre voie), ralentissement (vitesse), arrêt du trafic ; puis la durée -> « Appliquer ».
    Mesures actives : lieu, auteur, temps restant, « Repérer » (point GPS) et « Lever ».
    Aucune boucle : le menu se met à jour quand les mesures changent (GlobalState.rpTraffic).
]]

TC = TC or {}
local Config = TrafficConfig

local open = false
local mode = nil -- 'home' (menu) | 'zone' (zone choisie : action à choisir)
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

--- keepZone : la zone choisie reste (action appliquée / zone rechoisie) ; sinon fermer le panneau l'abandonne
local function closeMenu(keepZone)
    if not open then return end
    local wasZone = mode == 'zone'
    open, mode = false, nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    blockPauseAfterClose()
    if wasZone and not keepZone then TC.cancelZone() end
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
        open, mode = true, 'home'
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'open', data = {
            measures = res.measures or {}, durations = res.durations or Config.Durations,
            defaultDuration = res.defaultDuration or Config.DefaultDuration, speed = res.speed or Config.Speed,
            unit = LocalPlayer.state.mdcUnit or '', max = res.max, maxMine = res.maxMine,
        } })
    end)
end

-- Mesures changées (par lui ou un collègue) : menu ouvert mis à jour
TC.onChange = function() if open and mode == 'home' then refresh() end end

--- Zone du trafic choisie (editor.lua) : panneau des actions (fermeture de voie, ralentissement, arrêt), la zone
--- restant affichée dans le monde
TC.onZoneChosen = function(zone)
    open, mode = true, 'zone'
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'zone', data = {
        zone = zone, durations = Config.Durations, defaultDuration = Config.DefaultDuration, speed = Config.Speed,
        unit = LocalPlayer.state.mdcUnit or '',
    } })
end

RegisterCommand(Config.Command or 'trafic', function()
    if open then return closeMenu() end
    if TC.spikesBusy() then return TC.notify('Herse en main : posez-la, lancez-la ou rangez-la d\'abord.') end
    openMenu()
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

-- 1. « Choisir la zone du trafic » : { scope } -> on vise la route (editor.lua)
RegisterNUICallback('pickZone', function(data, cb)
    cb({ ok = true })
    if mode ~= 'home' then return end
    closeMenu()
    TC.startEditor({ scope = type(data) == 'table' and data.scope or 'lane' })
end)

-- 2. Action surlignée dans le panneau : couleur de la zone dans le monde
RegisterNUICallback('zoneKind', function(data, cb)
    cb({ ok = true })
    if mode == 'zone' then TC.zonePreview(type(data) == 'table' and data.kind or nil) end
end)

-- « Appliquer » : { kind = 'close' | 'slow' | 'stop', speed, duration }
RegisterNUICallback('apply', function(data, cb)
    cb({ ok = true })
    if mode ~= 'zone' or type(data) ~= 'table' then return end
    if data.kind ~= 'close' and data.kind ~= 'slow' and data.kind ~= 'stop' then
        return SendNUIMessage({ action = 'message', data = { text = 'Choisissez une action.', error = true } })
    end
    closeMenu(true)
    TC.applyZone(data.kind, data.speed, data.duration)
end)

-- « Rechoisir la zone » : retour à la visée de la route
RegisterNUICallback('reselect', function(_, cb)
    cb({ ok = true })
    if mode ~= 'zone' then return end
    closeMenu(true)
    TC.reselectZone()
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
