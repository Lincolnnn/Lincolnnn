--[[
    RP DLS - application de l'état aux véhicules proches : gyrophares d'origine, sons, plafonnier, blackout
    -------------------------------------------------------------------------------------------------------
    Chaque client, pour chaque véhicule DLS (ou d'urgence) à portée dont l'état "dls" existe :
      - sirène d'origine du jeu toujours muette (les sons sont joués par le script, depuis le véhicule) ;
      - gyrophares d'origine allumés seulement pour un stage d'origine (carcols), sinon dessinés (render.lua) ;
      - tons 1 à 4, air horn, deuxième sirène : sons du jeu (ou d'un pack de sons) joués depuis le véhicule,
        entendus par tous les joueurs proches ;
      - plafonnier et blackout (tous les feux éteints).
    Un véhicule qu'aucun joueur n'a touché (PNJ, véhicule de mission) est laissé tel quel au jeu.
    Performance : liste des véhicules refaite toutes les 300 ms ; un changement d'état est appliqué tout de suite.
]]

local Config = DLSConfig
local SCAN_MS = 300

local tracked = {} -- [véhicule] = { model, sounds = { tone, aux, horn } = { id, name }, blackout, interior }

-- =========================================================================
-- SONS : "NOM" (sons du jeu) ou "NOM@BANQUE" (pack de sons d'un autre script : nom du son et sa banque)
-- =========================================================================
local function stopSound(sound)
    if not sound then return end
    StopSound(sound.id)
    ReleaseSoundId(sound.id)
end

local banks = {} -- banques audio déjà chargées (sons DLS v2 avec soundbank)

--- Son `slot` du véhicule : joué s'il change, coupé si `name` est nil. `soundset` / `bank` : sons DLS v2
--- d'un pack (soundset="" soundbank="" de la balise <Sound>)
local function setSound(entry, vehicle, slot, name, soundset, bank)
    local current = entry.sounds[slot]
    if current and current.name == name and not DLSC.bool(HasSoundFinished(current.id)) then return end
    stopSound(current)
    entry.sounds[slot] = nil
    if not name then return end
    if bank and not banks[bank] then
        banks[bank] = DLSC.bool(RequestScriptAudioBank(bank, false))
    end
    local id = GetSoundId()
    local audio, ref = name:match('^(.-)@(.+)$')
    PlaySoundFromEntity(id, audio or name, vehicle, soundset or ref or 0, false, 0)
    entry.sounds[slot] = { id = id, name = name }
end

local function stopAll(entry)
    for slot, sound in pairs(entry.sounds) do
        stopSound(sound)
        entry.sounds[slot] = nil
    end
end

-- =========================================================================
-- APPLICATION
-- =========================================================================
--- Extras des stages par extras (ExtraStages) : posés par le client qui commande le véhicule (synchronisés par
--- le jeu) ; gyrophares éteints ou véhicule jamais touché : tous les extras allumés (rampe complète)
local function applyExtras(vehicle, model, state)
    local es = model.extraStages
    if not es or not DLSC.owns(vehicle) then return end
    local s = state and not state.bo and state.s or 0
    local off = {}
    for _, id in ipairs((es.off or {})[s] or {}) do off[id] = true end
    for id in pairs(es.extras or {}) do
        if DLSC.bool(DoesExtraExist(vehicle, id)) then
            local on = not off[id]
            if DLSC.bool(IsVehicleExtraTurnedOn(vehicle, id)) ~= on then
                -- (sans ça, changer un extra répare le véhicule)
                if SetVehicleAutoRepairDisabled then SetVehicleAutoRepairDisabled(vehicle, true) end
                SetVehicleExtra(vehicle, id, not on)
            end
        end
    end
end

local function apply(vehicle, entry, state)
    local model = entry.model
    applyExtras(vehicle, model, state)
    if not state then
        -- Jamais touché par un joueur : laissé au jeu
        stopAll(entry)
        DLSC.active[vehicle] = nil
        return
    end

    SetVehicleHasMutedSirens(vehicle, true)

    local plan, sounds
    if model.v2 then
        -- DLS v2 : modes choisis + modes déclenchés (vitesse, portières, clignotants…) et sons actifs
        local active, audio = DLSC.v2Active(vehicle, model, state)
        plan = DLSC.v2Plan(model, active, not state.bo and state.s or 0)
        sounds = audio
    else
        plan = DLSC.plan(model, state, vehicle, DLSC.parked(vehicle, model, state))
    end

    -- Gyrophares d'origine : changés seulement s'ils ne sont pas déjà comme il faut (les rallumer alors qu'ils
    -- tournent relance leur séquence au début : ils restent figés), et seulement par le client qui commande le
    -- véhicule ; les autres joueurs reçoivent l'état de la sirène du jeu lui-même
    if DLSC.owns(vehicle) and DLSC.bool(IsVehicleSirenOn(vehicle)) ~= plan.native then
        SetVehicleSiren(vehicle, plan.native)
    end
    -- Takedown / alley : modes du fichier en DLS v2, sinon projecteurs dessinés par le script
    local scene = not model.v2 and not state.bo and ((state.td or 0) > 0 or (state.al or 0) > 0)
    DLSC.active[vehicle] = { model = model, state = state, plan = plan, scene = scene }

    if model.v2 then
        -- Sons des AudioModes actifs (deux AudioModes du même son : joué une fois)
        local wanted = {}
        for name in pairs(sounds) do
            local mode = model.audio.modes[name]
            if mode and mode.sound then wanted['v2:' .. mode.sound .. '|' .. (mode.soundset or '')] = mode end
        end
        for slot in pairs(entry.sounds) do
            if slot:sub(1, 3) == 'v2:' and not wanted[slot] then setSound(entry, vehicle, slot, nil) end
        end
        for slot, mode in pairs(wanted) do setSound(entry, vehicle, slot, mode.sound, mode.soundset, mode.bank) end
        -- Deuxième sirène : son du premier AudioMode du ton 1
        local first = model.audio.tones[1] and model.audio.modes[model.audio.tones[1][1]]
        setSound(entry, vehicle, 'aux', state.aux and first and first.sound or nil, first and first.soundset, first and first.bank)
    else
        -- Sons : tons (5 = air horn à la place de la sirène), deuxième sirène, air horn par-dessus
        local tone = state.tone and state.tone > 0 and model.tones[state.tone] or nil
        setSound(entry, vehicle, 'tone', tone)
        setSound(entry, vehicle, 'aux', state.aux and model.tones[1] or nil)
        setSound(entry, vehicle, 'horn', state.horn and state.tone ~= 5 and model.tones[5] or nil)
    end

    -- Plafonnier
    if entry.interior ~= state.int then
        entry.interior = state.int
        SetVehicleInteriorlight(vehicle, state.int == true)
    end
    -- Blackout : phares et feux arrière éteints (1 : toujours éteints), rendus au jeu ensuite (0)
    if state.bo then
        SetVehicleLights(vehicle, 1)
        entry.blackout = true
    elseif entry.blackout then
        SetVehicleLights(vehicle, 0)
        entry.blackout = nil
    end
end

local function untrack(vehicle)
    local entry = tracked[vehicle]
    if entry then stopAll(entry) end
    tracked[vehicle] = nil
    DLSC.active[vehicle] = nil
    DLSC.forgetV2(vehicle)
    DLSC.forgetPark(vehicle)
    if not DoesEntityExist(vehicle) then
        DLSC.forget(vehicle)
        DLSC.forgetBones(vehicle)
        DLSC.forgetTop(vehicle)
    end
end

DLSC.onChange(function(vehicle, state)
    local entry = tracked[vehicle]
    if not entry then
        local model = DLSC.modelOf(vehicle)
        if not model then return end
        entry = { model = model, sounds = {} }
        tracked[vehicle] = entry
    end
    apply(vehicle, entry, state)
end)

CreateThread(function()
    while true do
        local me = GetEntityCoords(PlayerPedId())
        local range = Config.Render.Distance
        local seen = {}
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            -- (véhicule commandé par ce client : suivi même loin, ses gyrophares d'origine dépendent de lui)
            if #(GetEntityCoords(vehicle) - me) <= range or DLSC.owns(vehicle) then
                local model = DLSC.modelOf(vehicle)
                if model then
                    seen[vehicle] = true
                    local entry = tracked[vehicle]
                    if not entry or entry.model ~= model then
                        if entry then stopAll(entry) end
                        entry = { model = model, sounds = {} }
                        tracked[vehicle] = entry
                    end
                    apply(vehicle, entry, DLSC.get(vehicle))
                end
            end
        end
        for vehicle in pairs(tracked) do
            if not seen[vehicle] then untrack(vehicle) end
        end
        Wait(SCAN_MS)
    end
end)

-- =========================================================================
-- STATIONNEMENT (DLS v1) : véhicule arrêté depuis Park.Delay ms, gyrophares allumés, sans sirène
-- =========================================================================
local stopped = {} -- [véhicule] = arrêté depuis (ms)

function DLSC.parked(vehicle, model, state)
    local Park = Config.Park or {}
    if not Park.Enabled or state.s == 0 or state.tone ~= 0 or state.bo then
        stopped[vehicle] = nil
        return false
    end
    if GetEntitySpeed(vehicle) > (Park.Speed or 0.1) then
        stopped[vehicle] = nil
        return false
    end
    local now = GetGameTimer()
    stopped[vehicle] = stopped[vehicle] or now
    return now - stopped[vehicle] >= (Park.Delay or 2000)
end

function DLSC.forgetPark(vehicle) stopped[vehicle] = nil end

-- Mise à jour rapide (10 fois par seconde) des véhicules dont les gyrophares dépendent de ce qui se passe :
-- déclencheurs DLS v2 (vitesse, portières, clignotants…), stationnement DLS v1
CreateThread(function()
    while true do
        local any = false
        for vehicle, entry in pairs(tracked) do
            local state = DLSC.get(vehicle)
            if state and DoesEntityExist(vehicle) and (entry.model.v2 or (Config.Park and Config.Park.Enabled)) then
                any = true
                apply(vehicle, entry, state)
            end
        end
        Wait(any and 100 or 500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for vehicle, entry in pairs(tracked) do
        stopAll(entry)
        if DoesEntityExist(vehicle) then SetVehicleHasMutedSirens(vehicle, false) end
    end
end)
