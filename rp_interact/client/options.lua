--[[
    RP Interact - Options de l'œil (Eye Target)
    -------------------------------------------
    RPI.getOptions(ctx) retourne la liste des options pour ce que vise le joueur.
    ctx = {
        entity, type = 'ped' | 'vehicle' | 'object', model, hit (point visé), distance,
        isPlayer, serverId (joueur), isSelf, netId (entité réseau), police (joueur dans une unité du MDC)
    }
    Chaque option : { id, label, icon, police (réservée à la police), disabled, run = function(ctx) }

    Personnes (joueurs, PNJ, soi-même en test) et véhicules (tous, enregistrés ou non) :
      - tout le monde : inspections visuelles et olfactives ;
      - policier (dans une unité du MDC) : en plus, fouilles et détail notoire.
    Les inspections sont affichées en premier, puis les actions sur l'environnement.
]]

local Config = InteractConfig

-- =========================================================================
-- OUTILS
-- =========================================================================
local function hashes(list)
    local set = {}
    for _, name in ipairs(list or {}) do set[GetHashKey(name)] = true end
    return set
end

-- Sièges et poubelles (modèles de config.lua)
local SEATS = {}
for _, def in pairs(Config.Seats) do
    for hash in pairs(hashes(def.models)) do SEATS[hash] = def end
end
local TRASH = hashes(Config.TrashBins)

local function loadAnim(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 1500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function playAnim(dict, clip, duration, flag)
    CreateThread(function()
        if loadAnim(dict) then
            TaskPlayAnim(PlayerPedId(), dict, clip, 8.0, -8.0, duration or -1, flag or 49, 0.0, false, false, false)
            RemoveAnimDict(dict)
        end
    end)
end

--- Contrôle réseau d'une entité (portières d'un véhicule d'un autre joueur), puis action
local function withControl(entity, fn)
    CreateThread(function()
        local timeout = GetGameTimer() + 1000
        NetworkRequestControlOfEntity(entity)
        while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
            Wait(0)
            NetworkRequestControlOfEntity(entity)
        end
        fn()
    end)
end

local function faceEntity(entity)
    TaskTurnPedToFaceEntity(PlayerPedId(), entity, 800)
end

-- =========================================================================
-- INSPECTIONS (résultats donnés par le serveur : profil actif / profil du véhicule)
-- =========================================================================
local function inspect(ctx, kind, field)
    local payload = { kind = kind, field = field }
    if kind == 'player' then
        payload.target = ctx.serverId
    else
        payload.target = ctx.netId
        payload.label = kind == 'vehicle'
            and ('%s%s'):format(RPI.vehicleLabel(ctx.entity), RPI.vehiclePlate(ctx.entity) ~= '' and (' — ' .. RPI.vehiclePlate(ctx.entity)) or '')
            or tostring(ctx.model)
    end
    RPI.request('inspect', payload, function(res)
        if res and res.ok then
            RPI.showResult(res)
        else
            RPI.notify(res and res.error or 'Action impossible.', 'error')
        end
    end)
end

-- Fouille : petite animation pour le joueur qui fouille
local SEARCH_ANIM = { 'anim@gangops@facility@servers@bodysearch@', 'player_search', 3000 }

local PERSON_OPTIONS = {
    { field = 'visual', label = 'Inspection visuelle', icon = 'eye' },
    { field = 'olfactory', label = 'Inspection olfactive', icon = 'nose' },
    { field = 'upper', label = 'Fouiller la partie supérieure du corps', icon = 'search', police = true, anim = true },
    { field = 'lower', label = 'Fouiller la partie inférieure du corps', icon = 'search', police = true, anim = true },
    { field = 'notable', label = 'Détail notoire', icon = 'note', police = true },
}

local VEHICLE_OPTIONS = {
    { field = 'visualInterior', label = 'Inspection visuelle intérieure', icon = 'eye' },
    { field = 'visualExterior', label = 'Inspection visuelle extérieure', icon = 'eye' },
    { field = 'olfactory', label = 'Inspection olfactive', icon = 'nose' },
    { field = 'notable', label = 'Détail notoire', icon = 'note', police = true },
    { field = 'cabin', label = 'Fouille de l\'habitacle', icon = 'search', police = true, anim = true },
    { field = 'rear', label = 'Fouille de la banquette arrière', icon = 'search', police = true, anim = true },
    { field = 'trunk', label = 'Fouille du coffre', icon = 'search', police = true, anim = true },
}

local function inspectionOptions(list, ctx, kind)
    local out = {}
    for _, def in ipairs(list) do
        if not def.police or ctx.police then
            out[#out + 1] = {
                id = kind .. ':' .. def.field, label = def.label, icon = def.icon, police = def.police or nil,
                run = function(c)
                    if not c.isSelf then faceEntity(c.entity) end
                    if def.anim then playAnim(SEARCH_ANIM[1], SEARCH_ANIM[2], SEARCH_ANIM[3]) end
                    inspect(c, kind, def.field)
                end,
            }
        end
    end
    return out
end

-- =========================================================================
-- VÉHICULES : portières, capot, coffre, monter
-- =========================================================================
local DOORS = {
    { bone = 'door_dside_f', index = 0, seat = -1, name = 'la portière avant gauche', seatName = 'Monter (conducteur)' },
    { bone = 'door_pside_f', index = 1, seat = 0, name = 'la portière avant droite', seatName = 'Monter (passager avant)' },
    { bone = 'door_dside_r', index = 2, seat = 1, name = 'la portière arrière gauche', seatName = 'Monter (arrière gauche)' },
    { bone = 'door_pside_r', index = 3, seat = 2, name = 'la portière arrière droite', seatName = 'Monter (arrière droite)' },
    { bone = 'bonnet', index = 4, name = 'le capot' },
    { bone = 'boot', index = 5, name = 'le coffre' },
}
local DOOR_RANGE = 1.8 -- m entre le point visé et la portière

--- Portière (ou capot / coffre) la plus proche du point visé
local function nearestDoor(vehicle, hit)
    local best, bestDistance = nil, DOOR_RANGE
    for _, door in ipairs(DOORS) do
        local bone = GetEntityBoneIndexByName(vehicle, door.bone)
        if bone ~= -1 and GetIsDoorValid(vehicle, door.index) then
            local d = #(GetWorldPositionOfEntityBone(vehicle, bone) - hit)
            if d < bestDistance then best, bestDistance = door, d end
        end
    end
    return best
end

local function isLocked(vehicle)
    local status = GetVehicleDoorLockStatus(vehicle)
    return status ~= 0 and status ~= 1
end

local function vehicleOptions(ctx)
    local out = inspectionOptions(VEHICLE_OPTIONS, ctx, 'vehicle')
    local vehicle = ctx.entity
    local door = nearestDoor(vehicle, ctx.hit)
    if not door then return out end

    local locked = isLocked(vehicle)
    local isOpen = GetVehicleDoorAngleRatio(vehicle, door.index) > 0.05
    out[#out + 1] = {
        id = 'door:toggle', icon = 'door', disabled = locked and not isOpen or nil,
        label = ('%s %s%s'):format(isOpen and 'Fermer' or 'Ouvrir', door.name, locked and not isOpen and ' (verrouillé)' or ''),
        run = function(c)
            withControl(c.entity, function()
                if GetVehicleDoorAngleRatio(c.entity, door.index) > 0.05 then
                    SetVehicleDoorShut(c.entity, door.index, false)
                else
                    SetVehicleDoorOpen(c.entity, door.index, false, false)
                end
            end)
        end,
    }
    if door.seat and not IsPedInAnyVehicle(PlayerPedId(), false) and IsVehicleSeatFree(vehicle, door.seat) then
        out[#out + 1] = {
            id = 'door:enter', icon = 'seat', label = door.seatName .. (locked and ' (verrouillé)' or ''),
            disabled = locked or nil,
            run = function(c) TaskEnterVehicle(PlayerPedId(), c.entity, 10000, door.seat, 1.0, 1, 0) end,
        }
    end
    return out
end

-- =========================================================================
-- PERSONNES (joueurs, PNJ, soi-même en test)
-- =========================================================================
local function personOptions(ctx)
    local out = inspectionOptions(PERSON_OPTIONS, ctx, ctx.isPlayer and 'player' or 'npc')
    if not ctx.isSelf and not IsPedDeadOrDying(ctx.entity, true) then
        out[#out + 1] = {
            id = 'ped:wave', label = 'Saluer', icon = 'hand',
            run = function(c)
                faceEntity(c.entity)
                playAnim('gestures@m@standing@casual', 'gesture_hello', 2500, 48)
            end,
        }
    end
    return out
end

-- =========================================================================
-- ENVIRONNEMENT : bancs, chaises, poubelles
-- =========================================================================
local seated = false

local function standUpLoop()
    -- Boucle active UNIQUEMENT pendant que le joueur est assis
    CreateThread(function()
        local ped = PlayerPedId()
        local started = GetGameTimer()
        while seated do
            Wait(0)
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('~INPUT_VEH_DUCK~ Se lever')
            EndTextCommandDisplayHelp(0, false, false, -1)
            local moving = IsControlJustPressed(0, 32) or IsControlJustPressed(0, 33)
                or IsControlJustPressed(0, 34) or IsControlJustPressed(0, 35)
            if IsControlJustPressed(0, 73) or moving
                or (GetGameTimer() - started > 2000 and not IsPedUsingAnyScenario(ped)) then
                seated = false
                ClearPedTasks(ped)
            end
        end
    end)
end

local function sit(ctx, def)
    local object = ctx.entity
    local offset = GetOffsetFromEntityGivenWorldCoords(object, ctx.hit.x, ctx.hit.y, ctx.hit.z)
    local x = math.max(-def.width, math.min(def.width, offset.x)) -- place la plus proche sur un banc
    local seat = GetOffsetFromEntityInWorldCoords(object, x, 0.0, def.z)
    TaskStartScenarioAtPosition(PlayerPedId(), def.scenario, seat.x, seat.y, seat.z,
        (GetEntityHeading(object) + def.heading) % 360.0, 0, true, true)
    seated = true
    standUpLoop()
end

local function objectOptions(ctx)
    local out = {}
    local seat = SEATS[ctx.model]
    if seat and not seated and not IsPedInAnyVehicle(PlayerPedId(), false) then
        out[#out + 1] = { id = 'env:sit', label = 'S\'asseoir', icon = 'seat', run = function(c) sit(c, seat) end }
    end
    if TRASH[ctx.model] then
        out[#out + 1] = {
            id = 'env:bin', label = 'Fouiller la poubelle', icon = 'search',
            run = function(c)
                faceEntity(c.entity)
                TaskStartScenarioInPlace(PlayerPedId(), 'PROP_HUMAN_BUM_BIN', 0, true)
                SetTimeout(5000, function()
                    ClearPedTasks(PlayerPedId())
                    RPI.notify('Vous ne trouvez rien d\'intéressant.', 'info')
                end)
            end,
        }
    end
    return out
end

-- =========================================================================
-- POINT D'ENTRÉE
-- =========================================================================
function RPI.getOptions(ctx)
    if ctx.type == 'ped' then return personOptions(ctx) end
    if ctx.type == 'vehicle' then return vehicleOptions(ctx) end
    if ctx.type == 'object' then return objectOptions(ctx) end
    return {}
end

--- Nom affiché sous l'œil
function RPI.targetLabel(ctx)
    if ctx.type == 'ped' then
        if ctx.isSelf then return 'Vous-même (test)' end
        return ctx.isPlayer and 'Individu' or 'Individu (PNJ)'
    end
    if ctx.type == 'vehicle' then
        local plate = RPI.vehiclePlate(ctx.entity)
        return RPI.vehicleLabel(ctx.entity) .. (plate ~= '' and (' — ' .. plate) or '')
    end
    if SEATS[ctx.model] then return 'Siège' end
    if TRASH[ctx.model] then return 'Poubelle' end
    return nil
end
