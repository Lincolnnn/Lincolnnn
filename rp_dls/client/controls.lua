--[[
    RP DLS - commandes du conducteur (client)
    -----------------------------------------
    Mêmes commandes et même logique que DLS solo (touches : Échap > Paramètres > Raccourcis clavier > FiveM,
    « DLS : … ») : stages (cycle ou direct), Traffic Advisor (direction et motif), Steady Burn, plafonnier,
    blackout, sirène (marche / arrêt, tons 1 à 4, deuxième sirène, manuelle, air horn sur le klaxon, scan),
    verrouillage des touches. Modes spéciaux du XML : Wail Setup (stage imposé par un ton), stage gardé en
    descendant (PresetSirenOnLeaveVehicle), sirène coupée en descendant (SirenKill).
    Seul le conducteur d'un véhicule DLS (ou d'urgence) commande ; tout est envoyé au serveur (état "dls").
]]

local Config = DLSConfig
local Keys = Config.Keys

DLSC.locked = false
DLSC.scan = false

local vehicle, model = 0, nil   -- véhicule conduit (0 : aucun) et son modèle DLS
local manActive = false         -- sirène lancée par la touche manuelle / le klaxon (coupée au relâchement)
local beforeHorn = 0            -- ton à reprendre après l'air horn / la manuelle (AirHornInterruptsSiren)
local hornDown, manDown = false, false
local lastMan = false           -- dernier état de la touche manuelle pris en compte
local wailing, beforeWail = false, 0
local leftStages = {}           -- [netId] = stage d'avant le stage de descente (PresetSirenOnLeaveVehicle)
local lastStages = {}           -- [véhicule] = dernier stage allumé (rallumé par la touche du jeu)
local scanNext = 0

--- Nombre entier (touche, ou bouton du panneau : nombre venu du JSON), sinon nil
local function toint(v)
    v = tonumber(v)
    return v and math.tointeger(v)
end

--- Véhicule conduit et son modèle, si le joueur peut commander
local function context()
    if vehicle == 0 or not model or DLSC.bool(IsPauseMenuActive()) then return nil end
    return vehicle, model
end

-- =========================================================================
-- RÈGLES DE DLS
-- =========================================================================
local function indexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
    return nil
end

--- Ton suivant disponible après `tone` (boucle sur les tons 1 à 4 du modèle)
local function nextTone(m, tone)
    for step = 1, 4 do
        local t = (tone + step - 1) % 4 + 1
        if m.tones[t] then return t end
    end
    return 0
end

local function firstTone(m) return nextTone(m, 0) end

--- Nouveau stage de gyrophares : règles de Lights.Update de DLS
local function withStage(m, state, s)
    state.s = s
    if s == 0 then
        state.tone, state.ta, state.sb = 0, 0, false
        DLSC.scan = false
    elseif m.ta then
        -- Traffic Advisor allumé / éteint tout seul selon le stage (AutoEnableStages / AutoDisableStages)
        if state.ta == 0 and indexOf(m.ta.autoEnable, s) then
            state.ta = indexOf(DLS.TA_DIRECTIONS, m.ta.default) or 2
            if m.ta.divergeOnly then state.ta = 2 end
        end
        if indexOf(m.ta.autoDisable, s) then state.ta = 0 end
    end
    return state
end

local function setStage(s)
    local v, m = context()
    if not v then return end
    DLSC.beep()
    if s ~= 0 then lastStages[v] = s end
    DLSC.set(v, withStage(m, DLSC.copy(v), s))
    wailing = false
end

-- =========================================================================
-- ACTIONS (touches et boutons du panneau)
-- =========================================================================
local actions = {}

--- Gyrophares allumés / éteints : SEULEMENT par la touche du jeu de base (LightsControl), même touche pour
--- les deux. Allumage sur le dernier stage utilisé sur ce véhicule (ou LightsOnStage), sinon le premier.
function actions.lights()
    local v, m = context()
    if not v or #m.available == 0 then return end
    local s = DLSC.copy(v).s
    if s ~= 0 then
        lastStages[v] = s
        setStage(0)
        return
    end
    local wanted = Config.LightsOnStage
    if wanted == 'last' or wanted == nil then wanted = lastStages[v] end
    wanted = tonumber(wanted)
    setStage(wanted and DLS.hasStage(m, wanted) and wanted ~= 0 and wanted or m.available[1])
end

--- Stage suivant, gyrophares allumés seulement (sans passer par « éteint » : c'est la touche du jeu)
function actions.stageNext()
    local _, m = context()
    if not m then return end
    local s = DLSC.copy(vehicle).s
    if s == 0 then return end
    local i = indexOf(m.available, s)
    setStage((i and m.available[i + 1]) or m.available[1])
end

--- Stage précis, gyrophares allumés seulement
function actions.stage(n)
    n = toint(n)
    local _, m = context()
    if not m or not n or n == 0 or not DLS.hasStage(m, n) then return end
    local s = DLSC.copy(vehicle).s
    if s == 0 or s == n then return end
    setStage(n)
end

function actions.trafficAdvisor()
    local v, m = context()
    if not v or not m.ta then return end
    local state = DLSC.copy(v)
    if m.ta.divergeOnly then
        state.ta = state.ta == 0 and 2 or 0
    else
        -- éteint -> gauche -> diverge -> droite -> warn -> éteint (DLS v2 : directions présentes dans le fichier)
        repeat
            state.ta = (state.ta + 1) % 5
        until state.ta == 0 or not m.ta.v2 or m.ta.modes[state.ta]
    end
    DLSC.beep()
    DLSC.set(v, state)
end

--- Direction précise du Traffic Advisor (panneau) : 1 gauche, 2 diverge, 3 droite, 4 warn ; même bouton : éteint
function actions.taDirection(n)
    n = toint(n)
    local v, m = context()
    if not v or not m.ta or not n or n < 1 or n > 4 then return end
    if m.ta.divergeOnly then n = 2 end
    local state = DLSC.copy(v)
    state.ta = state.ta == n and 0 or n
    DLSC.beep()
    DLSC.set(v, state)
end

function actions.taPattern()
    local v, m = context()
    local count = DLS.taPatternCount(m)
    if not v or count < 2 then return end
    local state = DLSC.copy(v)
    local _, current = DLS.taPattern(m, state.tap ~= 0 and state.tap or nil)
    state.tap = current % count + 1
    DLSC.beep()
    DLSC.set(v, state)
end

--- Cruise : DLS v2 -> modes du groupe « Cruise » l'un après l'autre puis éteint ; DLS v1 -> Steady Burn
function actions.steadyBurn()
    local v, m = context()
    if not v then return end
    if m.v2 then
        if m.cruise == 0 then return end
        DLSC.beep()
        DLSC.update(v, { cr = (DLSC.copy(v).cr + 1) % (m.cruise + 1) })
        return
    end
    if not m.steady then return end
    DLSC.beep()
    DLSC.update(v, { sb = not DLSC.copy(v).sb })
end

--- Takedown (projecteurs vers l'avant) : DLS v2 -> modes du groupe « Takedown » puis éteint ; sinon allumé /
--- éteint (projecteurs dessinés par le script)
function actions.takedown()
    local v, m = context()
    if not v then return end
    local count = m.v2 and m.takedown or 1
    if count == 0 then return end
    DLSC.beep()
    DLSC.update(v, { td = (DLSC.copy(v).td + 1) % (count + 1) })
end

local function alleyAllowed(m, bit)
    if not m.v2 then return true end
    return (bit == 1 and m.alley.left) or (bit == 2 and m.alley.right)
end

--- Alley (projecteurs sur le côté) : gauche (1) ou droite (2), allumé / éteint
function actions.alleySide(bit)
    bit = toint(bit)
    local v, m = context()
    if not v or (bit ~= 1 and bit ~= 2) or not alleyAllowed(m, bit) then return end
    DLSC.beep()
    DLSC.update(v, { al = DLSC.copy(v).al ~ bit })
end

--- Alley au clavier : gauche -> droite -> les deux -> éteint (côtés présents seulement)
function actions.alley()
    local v, m = context()
    if not v then return end
    local al = DLSC.copy(v).al
    repeat
        al = (al + 1) % 4
    until al == 0 or ((al & 1 == 0 or alleyAllowed(m, 1)) and (al & 2 == 0 or alleyAllowed(m, 2)))
    DLSC.beep()
    DLSC.update(v, { al = al })
end

function actions.interiorLight()
    local v = context()
    if not v then return end
    DLSC.beep()
    DLSC.update(v, { int = not DLSC.copy(v).int })
end

function actions.blackout()
    local v = context()
    if not v then return end
    DLSC.beep()
    local state = DLSC.copy(v)
    if state.bo then
        state.bo = false
    else
        -- Comme DLS : gyrophares, sirène, TA, Steady Burn et plafonnier coupés
        state.bo, state.s, state.ta, state.sb, state.int, state.tone, state.aux, state.horn = true, 0, 0, false, false, 0, false, false
        state.cr, state.td, state.al = 0, 0, 0
        DLSC.scan = false
    end
    DLSC.set(v, state)
end

function actions.sirenToggle()
    local v, m = context()
    if not v then return end
    local state = DLSC.copy(v)
    if state.s == 0 then return end -- comme DLS : sirène seulement gyrophares allumés
    if state.tone == 0 then
        state.tone = firstTone(m)
    else
        state.tone = 0
        DLSC.scan = false
    end
    manActive = false
    DLSC.set(v, state)
end

function actions.tone(n)
    n = toint(n)
    local v, m = context()
    if not v or not n or not m.tones[n] then return end
    DLSC.scan = false
    manActive = false
    local state = DLSC.copy(v)
    state.tone = state.tone == n and 0 or n
    DLSC.set(v, state)
end

function actions.aux()
    local v, m = context()
    if not v or not m.tones[1] then return end
    DLSC.update(v, { aux = not DLSC.copy(v).aux })
end

function actions.scan()
    local v, m = context()
    if not v then return end
    DLSC.scan = not DLSC.scan
    if DLSC.scan then
        local tone = firstTone(m)
        if tone == 0 then DLSC.scan = false return end
        scanNext = GetGameTimer() + math.random(2, 7) * 1000
        DLSC.update(v, { tone = tone })
    else
        DLSC.update(v, { tone = 0 })
    end
end

function actions.lock()
    if vehicle == 0 then return end
    DLSC.locked = not DLSC.locked
    DLSC.beep(DLSC.locked and 'TOGGLE_ON' or 'NAV_UP_DOWN')
    DLSC.changed(vehicle, DLSC.get(vehicle))
end

DLSC.actions = actions

--- Action demandée (touche ou panneau). Touches verrouillées : seul le verrou répond ; blackout : seuls le
--- blackout et le verrou répondent (comme DLS)
function DLSC.action(name, arg)
    local fn = actions[name]
    if not fn or vehicle == 0 then return end
    if DLSC.locked and name ~= 'lock' then return end
    local state = DLSC.get(vehicle)
    if state and state.bo and name ~= 'blackout' and name ~= 'lock' then return end
    fn(arg)
end

-- =========================================================================
-- TOUCHES
-- =========================================================================
local function bind(command, label, key, action, arg)
    RegisterCommand(command, function() DLSC.action(action, arg) end, false)
    RegisterKeyMapping(command, 'DLS : ' .. label, 'keyboard', key)
end

bind('dls_stage_next', 'stage suivant', Keys.stageNext, 'stageNext')
bind('dls_stage1', 'stage 1', Keys.stage1, 'stage', 1)
bind('dls_stage2', 'stage 2', Keys.stage2, 'stage', 2)
bind('dls_stage3', 'stage 3', Keys.stage3, 'stage', 3)
bind('dls_ta', 'Traffic Advisor (direction suivante)', Keys.trafficAdvisor, 'trafficAdvisor')
bind('dls_ta_pattern', 'Traffic Advisor (motif suivant)', Keys.taPattern, 'taPattern')
bind('dls_steady', 'Steady Burn / Cruise', Keys.steadyBurn, 'steadyBurn')
bind('dls_interior', 'plafonnier', Keys.interiorLight, 'interiorLight')
bind('dls_blackout', 'blackout (tous feux éteints)', Keys.blackout, 'blackout')
bind('dls_siren', 'sirène marche / arrêt', Keys.sirenToggle, 'sirenToggle')
bind('dls_tone1', 'ton 1', Keys.tone1, 'tone', 1)
bind('dls_tone2', 'ton 2', Keys.tone2, 'tone', 2)
bind('dls_tone3', 'ton 3', Keys.tone3, 'tone', 3)
bind('dls_tone4', 'ton 4', Keys.tone4, 'tone', 4)
bind('dls_aux', 'deuxième sirène', Keys.aux, 'aux')
bind('dls_scan', 'scan des tons', Keys.scan, 'scan')
bind('dls_lock', 'verrouiller les touches', Keys.lock, 'lock')
bind('dls_takedown', 'takedown (projecteurs avant)', Keys.takedown, 'takedown')
bind('dls_alley', 'alley (projecteurs gauche / droite / les deux)', Keys.alley, 'alley')

-- Sirène manuelle : maintenue (+ appui, - relâchement)
RegisterCommand('+dls_manual', function() manDown = true end, false)
RegisterCommand('-dls_manual', function() manDown = false end, false)
RegisterKeyMapping('+dls_manual', 'DLS : sirène manuelle (maintenir)', 'keyboard', Keys.manual)

-- =========================================================================
-- SIRÈNE MANUELLE ET AIR HORN (klaxon du jeu) : logique du « Siren Manager » de DLS
-- =========================================================================
local function manualAndHorn(v, m)
    local state = DLSC.copy(v)
    local horn, man = hornDown, manDown
    if DLSC.locked or state.bo then horn, man = false, false end

    if state.tone == 0 and not manActive then
        if man and not horn then
            state.tone = firstTone(m)
            manActive = state.tone ~= 0
        elseif man and horn then
            state.tone = m.tones[2] and 2 or nextTone(m, 1)
            manActive = state.tone ~= 0
        elseif horn then
            state.tone = 5
            manActive = true
        end
    elseif manActive then
        if man and not horn then
            if state.tone ~= firstTone(m) then state.tone = firstTone(m) end
        elseif man and horn then
            if m.tones[2] then state.tone = 2 end
        elseif horn then
            state.tone = 5
        else
            state.tone = 0
            manActive = false
        end
    else
        -- Sirène déjà lancée
        if not m.hornInterrupts then
            state.horn = horn
        end
        if horn and m.hornInterrupts then
            if beforeHorn == 0 then beforeHorn = state.tone end
            state.tone = 5
        elseif man then
            if beforeHorn == 0 then beforeHorn = state.tone end
            state.tone = nextTone(m, beforeHorn)
        elseif beforeHorn ~= 0 then
            state.tone = beforeHorn
            beforeHorn = 0
        end
    end
    if not horn and state.horn and state.tone == 0 then state.horn = false end
    DLSC.set(v, state)
end

-- =========================================================================
-- BOUCLE DU CONDUCTEUR
-- =========================================================================
local function onEnter(v, m)
    vehicle, model = v, m
    manActive, beforeHorn, wailing = false, 0, false
    DLSC.scan = false
    if Config.DisableRadio then SetVehicleRadioEnabled(v, false) end
    -- Gyrophares d'origine déjà allumés (véhicule pris à un PNJ, sorti d'un garage…) : repris comme stage 3,
    -- sirène comprise si elle sonnait (comme DLS). Un peu après : le temps que le serveur voie le conducteur.
    if not DLSC.get(v) and DLSC.bool(IsVehicleSirenOn(v)) then
        local audio = DLSC.bool(IsVehicleSirenAudioOn(v))
        SetTimeout(500, function()
            if vehicle ~= v or DLSC.get(v) then return end
            local stage = DLS.hasStage(m, 3) and 3 or m.available[#m.available] or 0
            local state = withStage(m, DLSC.copy(v), stage)
            if audio then state.tone = firstTone(m) end
            DLSC.set(v, state)
        end)
    end
    if NetworkGetEntityIsNetworked(v) then
        local netId = VehToNet(v)
        TriggerServerEvent('rp_dls:driver', netId)
        -- Stage de descente encore en place : on reprend le stage d'avant (comme DLS)
        local previous = leftStages[netId]
        leftStages[netId] = nil
        local state = DLSC.get(v)
        local preset = indexOf(DLS.STAGE_NAMES, m.preset)
        if previous and state and preset and state.s == preset then
            SetTimeout(500, function()
                if vehicle == v then DLSC.set(v, withStage(m, DLSC.copy(v), previous)) end
            end)
        end
    end
    DLSC.changed(v, DLSC.get(v))
end

local function onLeave(v, m)
    vehicle, model = 0, nil
    hornDown, manDown, lastMan = false, false, false
    if not DoesEntityExist(v) then return end
    if Config.DisableRadio then SetVehicleRadioEnabled(v, true) end
    local state = DLSC.get(v)
    if state then
        local new = DLSC.copy(v)
        -- Air horn / manuelle relâchés
        if manActive then new.tone = 0 end
        if beforeHorn ~= 0 then new.tone = beforeHorn end
        new.horn = false
        -- Stage de descente (PresetSirenOnLeaveVehicle)
        local preset = indexOf(DLS.STAGE_NAMES, m.preset)
        if preset and DLS.hasStage(m, preset) and new.s ~= 0 and new.s ~= preset then
            if NetworkGetEntityIsNetworked(v) then leftStages[VehToNet(v)] = new.s end
            withStage(m, new, preset)
        end
        -- Sirène coupée en descendant
        if Config.SirenKill or m.sirenKill then new.tone, new.aux = 0, false end
        DLSC.set(v, new)
    end
    manActive, beforeHorn, wailing = false, 0, false
    DLSC.scan = false
    DLSC.changed(v, DLSC.get(v))
end

-- Contrôles du jeu bloqués tant qu'on conduit un véhicule DLS : klaxon (repris en air horn), sirène / caméra
-- cinéma (R), sélection d'arme sur 1 à 6, radio. La touche des gyrophares du jeu (LightsControl) est bloquée
-- aussi : c'est le script qui allume / éteint, le jeu ne doit pas basculer sa sirène de son côté.
local BLOCKED = { 86, 80, 157, 158, 160, 164, 165, 159 }
local RADIO = { 81, 82 }
local LIGHTS = Config.LightsControl or 85

CreateThread(function()
    local wasIn = 0
    while true do
        local ped = PlayerPedId()
        local v = GetVehiclePedIsIn(ped, false)
        local m = v ~= 0 and GetPedInVehicleSeat(v, -1) == ped and DLSC.modelOf(v) or nil
        if not m then v = 0 end
        if v ~= wasIn then
            if wasIn ~= 0 and model then onLeave(wasIn, model) end
            if v ~= 0 then onEnter(v, m) end
            wasIn = v
        end

        if vehicle == 0 then
            Wait(250)
        else
            for _, control in ipairs(BLOCKED) do DisableControlAction(0, control, true) end
            if Config.DisableRadio then
                for _, control in ipairs(RADIO) do DisableControlAction(0, control, true) end
            end
            DisableControlAction(0, LIGHTS, true)
            if IsDisabledControlJustPressed(0, LIGHTS) and not DLSC.bool(IsPauseMenuActive()) then
                DLSC.action('lights')
            end
            local horn = DLSC.bool(IsDisabledControlPressed(0, 86)) and not DLSC.bool(IsPauseMenuActive())
            if horn ~= hornDown or manDown ~= lastMan then
                hornDown, lastMan = horn, manDown
                manualAndHorn(vehicle, model)
            end

            local state = DLSC.get(vehicle)
            if state then
                -- Scan : ton changé au hasard toutes les 2 à 8 s (pas pendant la manuelle / l'air horn)
                if DLSC.scan and not manDown and not (model.hornInterrupts and hornDown) and GetGameTimer() >= scanNext then
                    scanNext = GetGameTimer() + math.random(2, 8) * 1000
                    local tones = {}
                    for t = 1, 4 do
                        if model.tones[t] and t ~= state.tone then tones[#tones + 1] = t end
                    end
                    if #tones > 0 then DLSC.update(vehicle, { tone = tones[math.random(#tones)] }) end
                end
                -- Wail Setup : un ton impose son stage de gyrophares, puis le stage d'avant revient
                local wail = model.wail
                if wail then
                    if not wailing and state.s ~= 0 and state.tone == wail.tone and state.s ~= wail.light and DLS.hasStage(model, wail.light) then
                        beforeWail, wailing = state.s, true
                        DLSC.set(vehicle, withStage(model, DLSC.copy(vehicle), wail.light))
                    elseif wailing and state.tone ~= wail.tone then
                        wailing = false
                        if state.s ~= 0 then DLSC.set(vehicle, withStage(model, DLSC.copy(vehicle), beforeWail)) end
                    end
                end
            end
            Wait(0)
        end
    end
end)

--- Véhicule conduit (0 : aucun) et son modèle
function DLSC.driving() return vehicle, model end

--- Klaxon et touche manuelle enfoncés
function DLSC.inputs() return hornDown, manDown end
