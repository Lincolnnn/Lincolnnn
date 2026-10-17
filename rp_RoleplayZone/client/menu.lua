--[[
    RP RoleplayZone - client : menu des créations (NUI, style du MDC / de rp_TrafficControl), commandes
    --------------------------------------------------------------------------------------------------
    /scene (civils) : 1. le TYPE (zone de recherche, périmètre à fouiller, objet à fouiller) ; 2. la SÉLECTION autour
    de soi (selector.lua) ; 3. la DESCRIPTION (message de la zone / ce que le policier trouvera), la durée -> Créer.
    Mes scènes : lieu, temps restant, fouilles ; Repérer (point GPS), Modifier, Supprimer. Bouton « Lâcher mon arme ».
    /lacherarme : lâcher l'arme qu'on a en main. Aucune boucle : le menu se met à jour quand les scènes changent.
]]

RZ = RZ or {}
local Config = SceneConfig

local open = false
local last = nil -- dernière réponse « list » (durées, limites)

local function closeMenu(keepFocusBlock)
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    if not keepFocusBlock then RZ.blockPause(function() return open end) end
end

local function sendList()
    RZ.request('list', { civil = RZ.civilMode() }, function(res)
        if open and res.ok then
            last = res
            SendNUIMessage({ action = 'list', data = { scenes = res.scenes or {}, admin = res.admin } })
        end
    end)
end

--- Ouvre le menu ; draft : une sélection à décrire (étape 3), sinon l'accueil
local function openMenu(draft)
    if open or RZ.selecting() then return end
    RZ.request('list', { civil = RZ.civilMode() }, function(res)
        if not res.ok then return RZ.notify(res.error or 'Menu indisponible.') end
        if not res.allowed then return RZ.notify(res.reason or 'Création de scènes réservée aux civils.') end
        last = res
        open = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'open', data = {
            scenes = res.scenes or {}, admin = res.admin, durations = res.durations or Config.Durations,
            defaultDuration = res.defaultDuration or Config.DefaultDuration,
            zone = res.zone or Config.Zone, perimeter = res.perimeter or Config.Perimeter,
            titleLength = res.titleLength or Config.TitleLength, textLength = res.textLength or Config.TextLength,
            weapons = res.weapons ~= false, draft = draft,
        } })
    end)
end

-- Scènes changées (par lui ou un autre) : liste du menu ouvert mise à jour
RZ.onScenesChanged = function() if open then sendList() end end

RegisterCommand(Config.Command or 'scene', function()
    if open then closeMenu() else openMenu() end
end, false)
if Config.Key and Config.Key ~= '' then
    RegisterKeyMapping(Config.Command or 'scene', 'Scènes de roleplay : zones et objets à fouiller', 'keyboard', Config.Key)
end
TriggerEvent('chat:addSuggestion', '/' .. (Config.Command or 'scene'), 'Civil : préparer une zone de recherche, un périmètre ou un objet à fouiller')

RegisterCommand(Config.DropCommand or 'lacherarme', function() RZ.dropWeapon() end, false)
TriggerEvent('chat:addSuggestion', '/' .. (Config.DropCommand or 'lacherarme'), 'Lâcher au sol l\'arme que vous avez en main')

-- =========================================================================
-- CALLBACKS NUI
-- =========================================================================
local function message(text, isError)
    SendNUIMessage({ action = 'message', data = { text = text, error = isError == true } })
end

RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    closeMenu()
end)

-- Étape 2 : sélection dans le monde { kind, radius }
RegisterNUICallback('pick', function(data, cb)
    cb({ ok = true })
    if type(data) ~= 'table' or (data.kind ~= 'zone' and data.kind ~= 'perimeter' and data.kind ~= 'object') then return end
    closeMenu(true)
    RZ.startSelector(data.kind, { radius = data.radius }, function(choice)
        openMenu(choice)
    end)
end)

-- Étape 3 validée : { draft, title, text, duration }
RegisterNUICallback('create', function(data, cb)
    cb({ ok = true })
    if type(data) ~= 'table' or type(data.draft) ~= 'table' then return end
    local d = data.draft
    RZ.request('create', { kind = d.kind, pos = d.pos, radius = d.radius, model = d.model, rot = d.rot, label = d.label,
        title = data.title, text = data.text, duration = data.duration, civil = RZ.civilMode() }, function(res)
        if not res.ok then return message(res.error or 'Création impossible.', true) end
        SendNUIMessage({ action = 'created', data = { scenes = res.scenes or {} } })
        message('Scène créée : elle attend les policiers.')
    end)
end)

RegisterNUICallback('update', function(data, cb)
    cb({ ok = true })
    if type(data) ~= 'table' then return end
    RZ.request('update', { id = data.id, title = data.title, text = data.text, duration = data.duration }, function(res)
        if not res.ok then return message(res.error or 'Modification impossible.', true) end
        SendNUIMessage({ action = 'created', data = { scenes = res.scenes or {} } })
        message('Scène modifiée.')
    end)
end)

RegisterNUICallback('remove', function(data, cb)
    cb({ ok = true })
    RZ.request('remove', { id = type(data) == 'table' and data.id }, function(res)
        if not res.ok then return message(res.error, true) end
        message('Scène supprimée.')
    end)
end)

RegisterNUICallback('clear', function(data, cb)
    cb({ ok = true })
    RZ.request('clear', { mine = not (type(data) == 'table' and data.mine == false) }, function(res)
        if not res.ok then return message(res.error, true) end
        local n = res.count or 0
        message(('%d scène%s supprimée%s.'):format(n, n > 1 and 's' or '', n > 1 and 's' or ''))
    end)
end)

-- « Repérer » : point GPS sur la scène
RegisterNUICallback('locate', function(data, cb)
    cb({ ok = true })
    local id = type(data) == 'table' and tonumber(data.id)
    for _, s in ipairs((last and last.scenes) or {}) do
        if s.id == id then
            SetNewWaypoint(s.pos.x + 0.0, s.pos.y + 0.0)
            return message('Point GPS placé sur la scène.')
        end
    end
    for _, s in ipairs(RZ.scenes()) do
        if s.id == id then
            SetNewWaypoint(s.pos.x + 0.0, s.pos.y + 0.0)
            return message('Point GPS placé sur la scène.')
        end
    end
end)

RegisterNUICallback('drop', function(_, cb)
    cb({ ok = true })
    closeMenu()
    RZ.dropWeapon()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and open then SetNuiFocus(false, false) end
end)
