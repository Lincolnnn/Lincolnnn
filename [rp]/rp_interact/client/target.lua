--[[
    RP Interact - Eye Target ("œil")
    --------------------------------
    Maintenir Alt (par défaut) : un œil apparaît au centre de l'écran. Il s'allume quand ce qui
    est visé propose des options (personnes, véhicules, bancs…). Clic gauche : liste des options,
    clic sur une option pour l'exécuter. Échap / clic droit : fermer.

    Fonctionne partout : tous les joueurs, les PNJ, soi-même (test, vue à la 3e personne,
    voir AllowSelfTarget), tous les véhicules (enregistrés ou non) et les objets configurés.
    Objets d'autres scripts (ExternalObjects : arme au sol, fusée…) : trouvés aussi quand le rayon touche le sol
    juste à côté (ExternalSnap), les petits objets couchés étant difficiles à viser.
    Autres scripts (TargetProviders, ex. rp_RoleplayZone) : leurs options s'ajoutent, y compris sur un point du
    sol ou d'un mur (aucune entité) : exports[script]:targetOptions(info) -> { label, options = { { id, label,
    icon } } } ; option choisie : exports[script]:targetSelect(id, info).

    Performance : la boucle (Wait(0), nécessaire pour bloquer le tir pendant la visée) ne tourne
    que pendant que la touche est maintenue / la liste d'options ouverte, puis s'arrête.
]]

local Config = InteractConfig

local active = false     -- œil affiché
local menuOpen = false   -- liste d'options ouverte (focus NUI)
local current = nil      -- { ctx, options, key } : cible actuelle
local DISABLED_CONTROLS = { 24, 25, 47, 58, 140, 141, 142, 143, 257, 263, 264 } -- tir, visée, corps à corps
local CAST_INTERVAL = 50 -- ms entre deux visées
local RAY_LENGTH = 25.0                              -- portée de la visée (caméra 3e personne comprise)
local DELETE_RAY_LENGTH = Config.DeleteDistance + 10.0 -- joueurs autorisés à supprimer : visée jusqu'à 50 m

function RPI.targetActive() return active end

-- =========================================================================
-- VISÉE (rayon depuis la caméra)
-- =========================================================================
local function cast(from, to, ignore)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, -1, ignore, 7)
    local _, hit, coords, _, entity = GetShapeTestResult(handle)
    return hit == 1 or hit == true, coords, entity
end

--- Ce que vise la caméra : (point, entité) ou nil
local function aim(length)
    local cam = GetFinalRenderedCamCoord()
    local to = cam + RPI.camDirection(GetFinalRenderedCamRot(2)) * length
    local ped = PlayerPedId()
    if Config.AllowSelfTarget then
        local hit, coords, entity = cast(cam, to, 0)
        -- Caméra à la 1re personne (dans la tête) : le rayon touche son propre corps -> on l'ignore
        if hit and not (entity == ped and #(coords - cam) < 0.9) then return coords, entity end
    end
    local hit, coords, entity = cast(cam, to, ped)
    if hit then return coords, entity end
    return nil
end

local TYPES = { [1] = 'ped', [2] = 'vehicle', [3] = 'object' }

--- Objet d'un autre script (ExternalObjects) à moins de ExternalSnap m du point visé (arme couchée au sol…)
local function nearbyExternal(coords)
    local snap = Config.ExternalSnap or 0.7
    local best, bestD
    for _, obj in ipairs(GetGamePool('CObject')) do
        local d = #(GetEntityCoords(obj) - coords)
        if d <= snap and (not bestD or d < bestD) and RPI.externalObject(obj) then best, bestD = obj, d end
    end
    return best
end

local function buildContext(coords, entity, canDelete)
    if not entity or entity == 0 or not DoesEntityExist(entity) or not TYPES[GetEntityType(entity)] then
        -- sol, mur… : un « lieu » (options des autres scripts seulement)
        local distance = #(GetEntityCoords(PlayerPedId()) - coords)
        if distance > Config.ObserveDistance then return nil end
        return { entity = 0, type = 'world', hit = coords, distance = distance, police = RPI.isPolice() }
    end
    local kind = TYPES[GetEntityType(entity)]

    local ped = PlayerPedId()
    local isSelf = entity == ped
    local origin = GetEntityCoords(ped)
    local distance = isSelf and 0.0 or #(origin - coords)
    -- Portée max de l'œil : 10 m (observations), 50 m pour les joueurs autorisés à supprimer
    -- (seule l'option "Supprimer" est alors proposée de loin) ; chaque option a sa propre distance
    if distance > (canDelete and math.max(Config.DeleteDistance, Config.ObserveDistance) or Config.ObserveDistance) then
        return nil
    end

    local ctx = {
        entity = entity, type = kind, model = GetEntityModel(entity), hit = coords, distance = distance,
        isSelf = isSelf, police = RPI.isPolice(),
    }
    if kind == 'ped' then
        ctx.pedDistance = isSelf and 0.0 or #(origin - GetEntityCoords(entity))
        ctx.isPlayer = IsPedAPlayer(entity)
        if ctx.isPlayer then ctx.serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)) end
    end
    if NetworkGetEntityIsNetworked(entity) then ctx.netId = NetworkGetNetworkIdFromEntity(entity) end
    return ctx
end

-- =========================================================================
-- AFFICHAGE
-- =========================================================================
local function sendEye(data)
    SendNUIMessage({ action = 'eye', data = data })
end

--- Options des autres scripts (Config.TargetProviders) pour ce qui est visé
local function providerOptions(ctx, options, onlyBridge)
    local info = { entity = ctx.entity, netId = ctx.netId, type = ctx.type, model = ctx.model,
        hit = { x = ctx.hit.x, y = ctx.hit.y, z = ctx.hit.z }, distance = ctx.distance, police = ctx.police }
    local base = #options
    for _, resource in ipairs(Config.TargetProviders or {}) do
        if GetResourceState(resource) == 'started' and (not onlyBridge or resource == 'ox_target') then
            local ok, res = pcall(function() return exports[resource]:targetOptions(info) end)
            if ok and type(res) == 'table' and type(res.options) == 'table' then
                for _, o in ipairs(res.options) do
                    local id = o.id
                    options[#options + 1] = { id = ('%s:%s'):format(resource, tostring(id)), label = o.label or '?',
                        icon = o.icon or 'search', police = o.police, primary = o.primary,
                        run = function() exports[resource]:targetSelect(id, info) end }
                end
                if #res.options > 0 and res.label then ctx.providerLabel = res.label end
            end
        end
    end
    ctx.providerOnly = base == 0 and #options > 0
    return options
end

--- Options PRINCIPALES (mises en avant dans la liste, en tête) : celles qui n'existent que pour ce qui est visé
--- précisément (portière visée, herse, porte, banc…) et les options de police (sauf faire s'asseoir au sol)
local NOT_PRIMARY = { ['police:seat'] = true }
local function markPrimary(options)
    for _, option in ipairs(options) do
        option.primary = option.primary == true or (option.police == true and not NOT_PRIMARY[option.id]) or nil
    end
    return options
end
RPI.markPrimary = markPrimary -- pour les tests

local function update()
    local canDelete = RPI.Police.canDelete()
    local coords, entity = aim(canDelete and math.max(RAY_LENGTH, DELETE_RAY_LENGTH) or RAY_LENGTH)
    -- petit objet d'un autre script couché à côté du point visé (arme au sol…) : c'est lui qui est visé
    if coords and (not entity or entity == 0 or GetEntityType(entity) == 3 or GetEntityType(entity) == 0)
        and not (entity and entity ~= 0 and RPI.externalObject(entity)) then
        local near = nearbyExternal(coords)
        if near then entity, coords = near, GetEntityCoords(near) end
    end
    local ctx = coords and buildContext(coords, entity, canDelete) or nil
    -- Herse de Riven en main : seulement les options des scripts passés par ox_target (ranger la herse au coffre…)
    local spikes = ctx and RPI.spikesBusy()
    local options = ctx and not spikes and RPI.getOptions(ctx) or {}
    if ctx then options = markPrimary(providerOptions(ctx, options, spikes)) end
    if #options == 0 then ctx = nil end

    -- Envoi au NUI seulement quand la cible ou ses options changent
    local key = ctx and table.concat({ ctx.entity, #options, options[1] and options[1].id or '', options[#options].id, options[#options].label }, '|') or ''
    if current and current.key == key then
        current.ctx = ctx -- point visé à jour (portière la plus proche…)
        current.options = options
        return
    end
    current = { ctx = ctx, options = options, key = key }
    sendEye({ active = true, hasOptions = ctx ~= nil, label = ctx and RPI.targetLabel(ctx) or nil })
end

local function stop()
    if not active then return end
    active, menuOpen, current = false, false, nil
    RPI.setUi('options', false)
    sendEye({ active = false })
end

local function openOptions()
    if not current or not current.ctx or #current.options == 0 then return end
    menuOpen = true
    RPI.setUi('options', true)
    SetCursorLocation(0.5, 0.5)
    local list = {}
    for i, option in ipairs(current.options) do
        list[i] = { index = i, label = option.label, icon = option.icon, police = option.police, primary = option.primary,
            disabled = option.disabled }
    end
    SendNUIMessage({ action = 'eyeOptions', data = { label = RPI.targetLabel(current.ctx), options = list } })
end

local function start()
    if active or IsPauseMenuActive() or RPI.uiOpen() or IsEntityDead(PlayerPedId()) then return end
    active = true
    current = nil
    sendEye({ active = true, hasOptions = false })

    CreateThread(function()
        local nextCast = 0
        while active do
            DisablePlayerFiring(PlayerId(), true)
            for _, control in ipairs(DISABLED_CONTROLS) do DisableControlAction(0, control, true) end
            if not menuOpen then
                local now = GetGameTimer()
                if now >= nextCast then
                    nextCast = now + CAST_INTERVAL
                    update()
                end
                if current and current.ctx and IsDisabledControlJustPressed(0, 24) then openOptions() end
            end
            Wait(0)
        end
    end)
end

-- Entrée / sortie d'une unité du MDC : options recalculées tout de suite
-- (liste ouverte refermée : elle pouvait contenir des fouilles qui ne sont plus permises)
function RPI.onDutyChanged()
    if not active then return end
    if menuOpen then stop() else current = nil end
end

-- Touche maintenue : l'œil reste affiché ; relâchée : il disparaît (sauf liste d'options ouverte)
RegisterCommand('+rpi_target', start, false)
RegisterCommand('-rpi_target', function()
    if not menuOpen then stop() end
end, false)
RegisterKeyMapping('+rpi_target', 'Œil : interagir (maintenir)', 'keyboard', Config.TargetKey)

-- =========================================================================
-- CHOIX D'UNE OPTION (NUI)
-- =========================================================================
RegisterNUICallback('eyeSelect', function(data, cb)
    cb({ ok = true })
    local option = current and current.options[tonumber(data and data.index)]
    local ctx = current and current.ctx
    stop()
    if not option or option.disabled or not ctx then return end
    if not ctx.isSelf and ctx.type ~= 'world' and not DoesEntityExist(ctx.entity) then
        RPI.notify('La cible n\'est plus là.', 'error')
        return
    end
    option.run(ctx)
end)

RegisterNUICallback('eyeCancel', function(_, cb)
    cb({ ok = true })
    stop()
end)
