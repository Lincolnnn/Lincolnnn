--[[
    RP STAGES - client
    ------------------
    Conducteur d'un véhicule configuré (config.lua) : touches des stages 1 / 2 / 3, des stages secondaires (TA gauche,
    TA droite, Steady Burn) et de la sirène. L'état est calculé ici (shared/logic.lua), appliqué tout de suite au
    véhicule, puis envoyé au serveur qui le vérifie et le partage (state bag « rpStages » du véhicule) : chaque joueur
    proche applique les mêmes extras et entend (ou non) la même sirène.
    Performance : hors véhicule configuré, une vérification toutes les CheckInterval ms (et une toutes les
    StreamInterval ms pour les véhicules réglés qui arrivent à portée) ; au volant d'un véhicule configuré, une boucle
    légère qui garde les gyrophares du jeu dans l'état du stage (la touche du jeu ne les change plus).
]]

local C = RPStagesConfig
local Logic = RPStagesLogic
local DATA = Logic.load(C)
local BAG = 'rpStages'

local current = { veh = 0, cfg = nil, state = nil } -- véhicule conduit (configuré) et son état
local applied = {}  -- [véhicule] = version appliquée (véhicules des autres joueurs)
local warned = {}   -- [modèle .. extra] = true (extra absent du modèle : averti une fois)

for _, w in ipairs(DATA.warnings) do print(('^3[rp_stages]^0 config.lua : %s'):format(w)) end

local function cfgOf(veh)
    if veh == 0 or not DoesEntityExist(veh) then return nil end
    return DATA.byHash[Logic.unsigned(GetEntityModel(veh))]
end

local function bagState(veh)
    local ok, st = pcall(function() return Entity(veh).state[BAG] end)
    return ok and type(st) == 'table' and st or nil
end

-- =========================================================================
-- APPLICATION AU VÉHICULE : extras, gyrophares, sirène
-- =========================================================================
--- Extras + son de la sirène (tous les joueurs) ; gyrophares du jeu (conducteur seulement : état réseau du véhicule)
local function apply(veh, cfg, st, driver)
    if veh == 0 or not DoesEntityExist(veh) then return end
    SetVehicleAutoRepairDisabled(veh, true) -- changer un extra ne répare plus le véhicule (dégâts de rp_vehiclecontrol)
    for id, on in pairs(Logic.extras(cfg, st)) do
        if DoesExtraExist(veh, id) then
            if IsVehicleExtraTurnedOn(veh, id) ~= on then SetVehicleExtra(veh, id, not on) end -- (3e paramètre : désactiver)
        elseif not warned[cfg.spawn .. id] then
            warned[cfg.spawn .. id] = true
            print(('^3[rp_stages]^0 %s : l\'extra %d n\'existe pas sur ce modèle (ignoré).'):format(cfg.spawn, id))
        end
    end
    SetVehicleHasMutedSirens(veh, not st.siren) -- sirène audible seulement quand elle est activée (stage 3)
    if driver then
        local lights = Logic.lights(cfg, st)
        if IsVehicleSirenOn(veh) ~= lights then SetVehicleSiren(veh, lights) end
    end
end

-- =========================================================================
-- INDICATEUR À L'ÉCRAN
-- =========================================================================
local hudShown = false
local function hud()
    if not C.Hud.enabled then return end
    local cfg, st = current.cfg, current.state
    if not cfg then
        if hudShown then hudShown = false SendNUIMessage({ action = 'hide' }) end
        return
    end
    hudShown = true
    local stages = {}
    for n = 1, 3 do if cfg.stages[n] then stages[#stages + 1] = n end end
    local secondary = {}
    for _, k in ipairs(Logic.SECONDARY) do
        if cfg.secondary[k] then secondary[#secondary + 1] = { key = k, label = cfg.secondary[k].label, on = st[k] == true } end
    end
    SendNUIMessage({ action = 'state', data = { label = cfg.label, stages = stages, stage = st.stage, auto = st.prev ~= nil,
        secondary = secondary, siren = st.siren, sirenNeeds3 = Logic.sirenNeedsStage3(cfg) } })
end

-- =========================================================================
-- TOUCHES (conducteur d'un véhicule configuré seulement)
-- =========================================================================
local lastSend = 0
local function change(newState)
    local veh, cfg = current.veh, current.cfg
    newState.v = (current.state.v or 0) + 1
    current.state = newState
    applied[veh] = newState.v
    apply(veh, cfg, newState, true)
    hud()
    lastSend = GetGameTimer()
    TriggerServerEvent('rp_stages:set', NetworkGetNetworkIdFromEntity(veh), newState)
end

local function act(fn, ...)
    if not current.cfg then return end
    if GetPedInVehicleSeat(current.veh, -1) ~= PlayerPedId() then return end
    local st, changed = fn(current.cfg, current.state, ...)
    if changed then change(st) end
end

local KEYS = {
    { cmd = 'rps_stage1', key = C.Keys.stage1, label = 'Stages : stage 1', run = function() act(Logic.pressStage, 1) end },
    { cmd = 'rps_stage2', key = C.Keys.stage2, label = 'Stages : stage 2', run = function() act(Logic.pressStage, 2) end },
    { cmd = 'rps_stage3', key = C.Keys.stage3, label = 'Stages : stage 3 (réponse)', run = function() act(Logic.pressStage, 3) end },
    { cmd = 'rps_ta_left', key = C.Keys.taLeft, label = 'Stages : Traffic Advisor gauche', run = function() act(Logic.pressSecondary, 'taLeft') end },
    { cmd = 'rps_ta_right', key = C.Keys.taRight, label = 'Stages : Traffic Advisor droite', run = function() act(Logic.pressSecondary, 'taRight') end },
    { cmd = 'rps_steady', key = C.Keys.steadyBurn, label = 'Stages : Steady Burn', run = function() act(Logic.pressSecondary, 'steadyBurn') end },
    { cmd = 'rps_siren', key = C.Keys.siren, label = 'Stages : sirène (stage 3)', run = function() act(Logic.pressSiren) end },
}
for _, k in ipairs(KEYS) do
    RegisterCommand(k.cmd, k.run, false)
    RegisterKeyMapping(k.cmd, k.label, 'keyboard', k.key or '')
end

-- =========================================================================
-- VÉHICULE DU JOUEUR
-- =========================================================================
local function enter(veh, cfg)
    local st = bagState(veh)
    current.veh, current.cfg = veh, cfg
    current.state = st and Logic.sanitize(cfg, st) or Logic.newState()
    current.state.v = st and st.v or 0
    apply(veh, cfg, current.state, true)
    hud()
    -- Au volant : les gyrophares du jeu restent ceux du stage (la touche du jeu ne les allume / coupe plus),
    -- la sirène reste muette hors stage 3
    CreateThread(function()
        while current.veh == veh do
            local cs = current.state
            local lights = Logic.lights(cfg, cs)
            if IsVehicleSirenOn(veh) ~= lights then SetVehicleSiren(veh, lights) end
            if not cs.siren and IsVehicleSirenAudioOn(veh) then SetVehicleHasMutedSirens(veh, true) end
            Wait(0)
        end
    end)
end

local function leave()
    current.veh, current.cfg, current.state = 0, nil, nil
    hud()
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local driver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
        if driver and veh ~= current.veh then
            local cfg = cfgOf(veh)
            if cfg and (not C.Ace or IsAceAllowed(C.Ace)) then enter(veh, cfg) elseif current.cfg then leave() end
        elseif not driver and current.cfg then
            leave()
        end
        Wait(C.CheckInterval)
    end
end)

-- =========================================================================
-- VÉHICULES DES AUTRES JOUEURS : état partagé (state bag) appliqué ici aussi
-- =========================================================================
AddStateBagChangeHandler(BAG, nil, function(bagName, _, value)
    if type(value) ~= 'table' then return end
    local veh = GetEntityFromStateBagName(bagName)
    if veh == 0 then return end -- pas encore à portée : appliqué à son arrivée (boucle ci-dessous)
    local cfg = cfgOf(veh)
    if not cfg then return end
    if veh == current.veh then
        -- (conducteur : sa propre modification revient du serveur ; une version plus récente vient d'ailleurs)
        if (value.v or 0) > (current.state.v or 0) and GetGameTimer() - lastSend > 1000 then
            current.state = Logic.sanitize(cfg, value)
            current.state.v = value.v
            apply(veh, cfg, current.state, true)
            hud()
        end
        return
    end
    applied[veh] = value.v
    apply(veh, cfg, Logic.sanitize(cfg, value), false)
end)

CreateThread(function()
    while true do
        Wait(C.StreamInterval)
        local me = GetEntityCoords(PlayerPedId())
        for veh, _ in pairs(applied) do if not DoesEntityExist(veh) then applied[veh] = nil end end
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if veh ~= current.veh and #(GetEntityCoords(veh) - me) < C.StreamDistance then
                local st = bagState(veh)
                if st and applied[veh] ~= st.v then
                    local cfg = cfgOf(veh)
                    if cfg then
                        applied[veh] = st.v
                        apply(veh, cfg, Logic.sanitize(cfg, st), false)
                    end
                end
            end
        end
    end
end)

-- rp_freecam (mode photo) : indicateur masqué tant que « Masquer les interfaces » est coché
AddEventHandler('rp_freecam:hideUi', function(hidden) SendNUIMessage({ action = 'rpHideUi', data = { hidden = hidden == true } }) end)

CreateThread(function()
    Wait(500)
    SendNUIMessage({ action = 'config', data = { right = C.Hud.right, bottom = C.Hud.bottom } })
end)

RPStagesClient = { current = current, apply = apply, data = DATA } -- (tests)
