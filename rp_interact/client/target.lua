--[[
    RP Interact - Eye Target ("œil")
    --------------------------------
    Maintenir Alt (par défaut) : un œil apparaît au centre de l'écran. Il s'allume quand ce qui
    est visé propose des options (personnes, véhicules, bancs…). Clic gauche : liste des options,
    clic sur une option pour l'exécuter. Échap / clic droit : fermer.

    Fonctionne partout : tous les joueurs, les PNJ, soi-même (test, vue à la 3e personne,
    voir AllowSelfTarget), tous les véhicules (enregistrés ou non) et les objets configurés.

    Performance : la boucle (Wait(0), nécessaire pour bloquer le tir pendant la visée) ne tourne
    que pendant que la touche est maintenue / la liste d'options ouverte, puis s'arrête.
]]

local Config = InteractConfig

local active = false     -- œil affiché
local menuOpen = false   -- liste d'options ouverte (focus NUI)
local current = nil      -- { ctx, options, key } : cible actuelle
local DISABLED_CONTROLS = { 24, 25, 47, 58, 140, 141, 142, 143, 257, 263, 264 } -- tir, visée, corps à corps
local CAST_INTERVAL = 50 -- ms entre deux visées
local RAY_LENGTH = 25.0

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
local function aim()
    local cam = GetFinalRenderedCamCoord()
    local to = cam + RPI.camDirection(GetFinalRenderedCamRot(2)) * RAY_LENGTH
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

local function buildContext(coords, entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local kind = TYPES[GetEntityType(entity)]
    if not kind then return nil end

    local ped = PlayerPedId()
    local isSelf = entity == ped
    local distance = isSelf and 0.0 or #(GetEntityCoords(ped) - coords)
    local maxDistance = kind == 'object' and Config.ObjectDistance or Config.EntityDistance
    if distance > maxDistance then return nil end

    local ctx = {
        entity = entity, type = kind, model = GetEntityModel(entity), hit = coords, distance = distance,
        isSelf = isSelf, police = RPI.isPolice(),
    }
    if kind == 'ped' then
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

local function update()
    local coords, entity = aim()
    local ctx = coords and buildContext(coords, entity) or nil
    local options = ctx and RPI.getOptions(ctx) or {}
    if #options == 0 then ctx = nil end

    -- Envoi au NUI seulement quand la cible ou ses options changent
    local key = ctx and table.concat({ ctx.entity, #options, options[1] and options[1].id or '', options[#options].label }, '|') or ''
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
        list[i] = { index = i, label = option.label, icon = option.icon, police = option.police, disabled = option.disabled }
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
    if not ctx.isSelf and not DoesEntityExist(ctx.entity) then
        RPI.notify('La cible n\'est plus là.', 'error')
        return
    end
    option.run(ctx)
end)

RegisterNUICallback('eyeCancel', function(_, cb)
    cb({ ok = true })
    stop()
end)
