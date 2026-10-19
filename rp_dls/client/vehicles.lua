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

--- Son `slot` du véhicule : joué s'il change, coupé si `name` est nil
local function setSound(entry, vehicle, slot, name)
    local current = entry.sounds[slot]
    if current and current.name == name and not HasSoundFinished(current.id) then return end
    stopSound(current)
    entry.sounds[slot] = nil
    if not name then return end
    local id = GetSoundId()
    local audio, bank = name:match('^(.-)@(.+)$')
    PlaySoundFromEntity(id, audio or name, vehicle, bank or 0, false, 0)
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
local function apply(vehicle, entry, state)
    local model = entry.model
    if not state then
        -- Jamais touché par un joueur : laissé au jeu
        stopAll(entry)
        DLSC.active[vehicle] = nil
        return
    end

    SetVehicleHasMutedSirens(vehicle, true)

    local plan = DLSC.plan(model, state)
    if IsVehicleSirenOn(vehicle) ~= plan.native then SetVehicleSiren(vehicle, plan.native) end
    DLSC.active[vehicle] = { model = model, state = state, plan = plan }

    -- Sons : tons (5 = air horn à la place de la sirène), deuxième sirène, air horn par-dessus
    local tone = state.tone and state.tone > 0 and model.tones[state.tone] or nil
    setSound(entry, vehicle, 'tone', tone)
    setSound(entry, vehicle, 'aux', state.aux and model.tones[1] or nil)
    setSound(entry, vehicle, 'horn', state.horn and state.tone ~= 5 and model.tones[5] or nil)

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
    if not DoesEntityExist(vehicle) then
        DLSC.forget(vehicle)
        DLSC.forgetBones(vehicle)
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
            if #(GetEntityCoords(vehicle) - me) <= range then
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

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for vehicle, entry in pairs(tracked) do
        stopAll(entry)
        if DoesEntityExist(vehicle) then SetVehicleHasMutedSirens(vehicle, false) end
    end
end)
