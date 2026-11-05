--[[
    RP Police Cards - client
    ------------------------
    Cartes affichées SANS focus NUI : le joueur garde les commandes du jeu et peut ouvrir ses autres menus.
    /cartes : focus le temps d'ajuster (déplacer, taille) ; place et taille gardées (KVP du client).
    Boucle : seulement quand une carte est affichée (menu pause, 250 ms) ; 0.00 ms sinon.
    Exports : toggle(id), show(id), hide(id), isShown(id), cards().
]]

local C = CardsConfig or {}
local KVP = 'rp_policecards:layout:'
local CARDS, ORDER = {}, {}
for _, card in ipairs(C.Cards or {}) do
    if type(card.id) == 'string' and type(card.image) == 'string' then
        CARDS[card.id] = card
        ORDER[#ORDER + 1] = card.id
    end
end

local shown = {}       -- [id] = true
local adjusting = false
local watching = false -- boucle du menu pause en cours

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

--- Place et taille de la carte : enregistrées par le joueur, sinon celles de la configuration
local function layoutOf(card)
    local l = { x = card.x or 0.7, y = card.y or 0.1, width = card.width or 0.28 }
    local raw = GetResourceKvpString(KVP .. card.id)
    if raw then
        local ok, saved = pcall(json.decode, raw)
        if ok and type(saved) == 'table' and tonumber(saved.x) and tonumber(saved.y) and tonumber(saved.width) then
            l = { x = tonumber(saved.x), y = tonumber(saved.y), width = tonumber(saved.width) }
        end
    end
    l.width = clamp(l.width, C.MinWidth or 0.12, C.MaxWidth or 0.6)
    l.x, l.y = clamp(l.x, -0.5, 0.98), clamp(l.y, -0.5, 0.98)
    return l
end

local function anyShown() return next(shown) ~= nil end

local function stopAdjust()
    if not adjusting then return end
    adjusting = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'adjust', data = { on = false } })
end

-- Menu pause : cartes masquées (boucle seulement tant qu'une carte est affichée)
local function watchPause()
    if watching or C.HideInPauseMenu == false then return end
    watching = true
    CreateThread(function()
        local paused = false
        while anyShown() do
            local now = IsPauseMenuActive()
            if now ~= paused then
                paused = now
                SendNUIMessage({ action = 'paused', data = { paused = paused } })
            end
            Wait(250)
        end
        if paused then SendNUIMessage({ action = 'paused', data = { paused = false } }) end
        watching = false
    end)
end

local function show(id)
    local card = CARDS[id]
    if not card or shown[id] then return false end
    shown[id] = true
    local l = layoutOf(card)
    SendNUIMessage({ action = 'show', data = { id = id, image = card.image, label = card.label, x = l.x, y = l.y, width = l.width,
        minWidth = C.MinWidth or 0.12, maxWidth = C.MaxWidth or 0.6 } })
    watchPause()
    return true
end

local function hide(id)
    if not shown[id] then return false end
    shown[id] = nil
    SendNUIMessage({ action = 'hide', data = { id = id } })
    if not anyShown() then stopAdjust() end
    return true
end

local function toggle(id)
    if not CARDS[id] then return nil end
    if shown[id] then hide(id) else show(id) end
    return shown[id] == true
end

local function notify(text)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end

for _, id in ipairs(ORDER) do
    local card = CARDS[id]
    local command = card.command or id
    RegisterCommand(command, function() toggle(id) end, false)
    for _, alias in ipairs(card.aliases or {}) do RegisterCommand(alias, function() toggle(id) end, false) end
    RegisterKeyMapping(command, ('Carte : %s (afficher / masquer)'):format(card.label or id), 'keyboard', '')
end

-- /cartes : ajuster les cartes affichées (curseur) ; à nouveau ou Échap / Entrée : fini
RegisterCommand(C.AdjustCommand or 'cartes', function()
    if adjusting then return stopAdjust() end
    if not anyShown() then
        local names = {}
        for _, id in ipairs(ORDER) do names[#names + 1] = '/' .. (CARDS[id].command or id) end
        return notify(('Aucune carte affichée (%s).'):format(table.concat(names, ', ')))
    end
    adjusting = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'adjust', data = { on = true } })
end, false)

-- =========================================================================
-- NUI
-- =========================================================================
--- Fin de l'ajustement : place et taille de chaque carte affichée
RegisterNUICallback('done', function(d, cb)
    cb({ ok = true })
    if type(d) == 'table' and type(d.layouts) == 'table' then
        for id, l in pairs(d.layouts) do
            if CARDS[id] and type(l) == 'table' and tonumber(l.x) and tonumber(l.y) and tonumber(l.width) then
                SetResourceKvp(KVP .. id, json.encode({
                    x = clamp(tonumber(l.x), -0.5, 0.98), y = clamp(tonumber(l.y), -0.5, 0.98),
                    width = clamp(tonumber(l.width), C.MinWidth or 0.12, C.MaxWidth or 0.6) }))
            end
        end
    end
    stopAdjust()
end)

--- Clic droit sur une carte pendant l'ajustement : masquée
RegisterNUICallback('hide', function(d, cb)
    cb({ ok = true })
    if type(d) == 'table' and type(d.id) == 'string' then hide(d.id) end
end)

-- rp_freecam (mode photo) : cartes masquées tant que « Masquer les interfaces » est coché
AddEventHandler('rp_freecam:hideUi', function(hidden) SendNUIMessage({ action = 'rpHideUi', data = { hidden = hidden == true } }) end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and adjusting then SetNuiFocus(false, false) end
end)

-- =========================================================================
-- EXPORTS (Menu Interaction > Police)
-- =========================================================================
exports('toggle', toggle)
exports('show', show)
exports('hide', hide)
exports('isShown', function(id) return shown[id] == true end)
exports('cards', function()
    local list = {}
    for _, id in ipairs(ORDER) do
        local card = CARDS[id]
        list[#list + 1] = { id = id, label = card.label or id, command = card.command or id, shown = shown[id] == true }
    end
    return list
end)

RPPoliceCards = { toggle = toggle, show = show, hide = hide, shown = shown, layoutOf = layoutOf } -- tests
