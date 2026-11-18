--[[
    RP STAGES - client
    ------------------
    Conducteur d'un véhicule configuré (config.lua) : UNE touche pour les stages principaux (stage suivant à chaque appui)
    et une touche par stage secondaire (TA gauche, TA droite, Steady Burn). Aucun élément visuel.
    SIRÈNE : gérée par Bozlights (main). rp_stages ne l'allume, ne la coupe et ne la met jamais en sourdine, et ne touche
    pas aux gyrophares du jeu : il la SURVEILLE (SirenCheck, ou l'événement « rp_stages:siren ») pour passer au stage 3
    quand elle s'allume hors stage 3, puis revenir au stage d'avant quand elle se coupe.
    L'état est calculé ici (shared/logic.lua), appliqué tout de suite aux extras du véhicule, puis envoyé au serveur qui le
    vérifie et le partage (state bag « rpStages ») : chaque joueur proche voit les mêmes extras.
    Performance : hors véhicule configuré, une vérification toutes les CheckInterval ms (et une toutes les
    StreamInterval ms pour les véhicules réglés qui arrivent à portée) ; au volant d'un véhicule configuré, la sirène est
    regardée toutes les SirenInterval ms (et la roue radio bloquée à chaque image si DisableRadioWheel).
]]

local C = RPStagesConfig
local Logic = RPStagesLogic
local DATA = Logic.load(C)
local BAG = 'rpStages'

local current = { veh = 0, cfg = nil, state = nil } -- véhicule conduit (configuré) et son état
local applied = {}  -- [véhicule] = version appliquée (véhicules des autres joueurs)
local warned = {}   -- [modèle .. extra] = true (extra absent du modèle : averti une fois)
local sirenEvent = nil -- sirène annoncée par Bozlights (TriggerEvent('rp_stages:siren', bool)) ; nil = SirenCheck

for _, w in ipairs(DATA.warnings) do print(('^3[rp_stages]^0 config.lua : %s'):format(w)) end

local function cfgOf(veh)
    if veh == 0 or not DoesEntityExist(veh) then return nil end
    return DATA.byHash[Logic.unsigned(GetEntityModel(veh))]
end

local function bagState(veh)
    local ok, st = pcall(function() return Entity(veh).state[BAG] end)
    return ok and type(st) == 'table' and st or nil
end

--- Sirène du véhicule conduit allumée ? (Bozlights : événement, sinon SirenCheck de config.lua)
local function sirenOn(veh)
    if sirenEvent ~= nil then return sirenEvent end
    if type(C.SirenCheck) ~= 'function' then return false end
    local ok, on = pcall(C.SirenCheck, veh)
    return ok and on == true
end

-- =========================================================================
-- APPLICATION AU VÉHICULE : extras seulement (jamais la sirène ni les gyrophares)
-- =========================================================================
local function apply(veh, cfg, st)
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
end

-- =========================================================================
-- CHANGEMENTS (touches, sirène) : conducteur d'un véhicule configuré seulement
-- =========================================================================
local lastSend = 0
local function change(newState)
    local veh, cfg = current.veh, current.cfg
    newState.v = (current.state.v or 0) + 1
    current.state = newState
    applied[veh] = newState.v
    apply(veh, cfg, newState)
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
    { cmd = 'rps_stage', key = C.Keys.stages, label = 'Stages : stage suivant (1, 2, 3)', run = function() act(Logic.cycleStage, C.CycleOff ~= false) end },
    { cmd = 'rps_ta_left', key = C.Keys.taLeft, label = 'Stages : Traffic Advisor gauche', run = function() act(Logic.pressSecondary, 'taLeft') end },
    { cmd = 'rps_ta_right', key = C.Keys.taRight, label = 'Stages : Traffic Advisor droite', run = function() act(Logic.pressSecondary, 'taRight') end },
    { cmd = 'rps_steady', key = C.Keys.steadyBurn, label = 'Stages : Steady Burn', run = function() act(Logic.pressSecondary, 'steadyBurn') end },
}
for _, k in ipairs(KEYS) do
    RegisterCommand(k.cmd, k.run, false)
    RegisterKeyMapping(k.cmd, k.label, 'keyboard', k.key or '')
end

--- Bozlights (client) peut annoncer la sirène lui-même : TriggerEvent('rp_stages:siren', true / false)
AddEventHandler('rp_stages:siren', function(on)
    sirenEvent = on == true
    if current.cfg and sirenOn(current.veh) ~= (current.state.siren == true) then act(Logic.sirenChanged, sirenEvent) end
end)

-- =========================================================================
-- VÉHICULE DU JOUEUR
-- =========================================================================
local function enter(veh, cfg)
    local st = bagState(veh)
    current.veh, current.cfg = veh, cfg
    current.state = st and Logic.sanitize(cfg, st) or Logic.newState()
    current.state.v = st and st.v or 0
    apply(veh, cfg, current.state)
    -- Au volant : la sirène (Bozlights) est regardée ; allumée -> stage 3, coupée -> stage d'avant
    CreateThread(function()
        local nextCheck = 0
        while current.veh == veh do
            if GetGameTimer() >= nextCheck then
                nextCheck = GetGameTimer() + (C.SirenInterval or 150)
                local on = sirenOn(veh)
                if on ~= (current.state.siren == true) then act(Logic.sirenChanged, on) end
            end
            if C.DisableRadioWheel then
                DisableControlAction(0, 85, true) -- roue de la radio (Q, touche des stages par défaut)
                Wait(0)
            else
                Wait(C.SirenInterval or 150)
            end
        end
    end)
end

local function leave()
    current.veh, current.cfg, current.state = 0, nil, nil
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
        if veh == 0 then sirenEvent = nil end -- (à pied : l'annonce de Bozlights ne vaut plus)
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
            apply(veh, cfg, current.state)
        end
        return
    end
    applied[veh] = value.v
    apply(veh, cfg, Logic.sanitize(cfg, value))
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
                        apply(veh, cfg, Logic.sanitize(cfg, st))
                    end
                end
            end
        end
    end
end)

RPStagesClient = { current = current, apply = apply, data = DATA } -- (tests)
