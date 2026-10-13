--[[
    RP Interact - Options de l'œil (Eye Target)
    -------------------------------------------
    RPI.getOptions(ctx) retourne la liste des options pour ce que vise le joueur.
    ctx = {
        entity, type = 'ped' | 'vehicle' | 'object', model, hit (point visé),
        distance (joueur -> point visé), pedDistance (joueur -> personne visée),
        isPlayer, serverId (joueur), isSelf, netId (entité réseau), police (joueur dans une unité du MDC)
    }
    Chaque option : { id, label, icon, police (réservée à la police), disabled, run = function(ctx) }

    Personnes (joueurs, PNJ, soi-même en test) et véhicules (tous, enregistrés ou non) :
      - tout le monde : inspections visuelles et olfactives (jusqu'à 10 m) ;
      - policier (dans une unité du MDC) : détail notoire (10 m), fouilles (3 m, barre de chargement),
        menotter / prendre par le bras / faire s'asseoir (2 m), placer à l'arrière / faire sortir d'un véhicule.
      - joueurs autorisés : supprimer (PNJ, véhicules sans joueur, objets) jusqu'à 50 m (DeleteDistance),
        la seule option proposée de loin.
    Props posés avec le script de props du serveur : "Déplacer le props" / "Supprimer le props"
    (client/props.lua).
    Les options apparaissent quand on s'approche (jamais grisées pour une question de distance).
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

local playAnim = function(dict, clip, duration, flag) RPI.playAnim(dict, clip, duration, flag) end
local withControl = function(entity, fn) RPI.withControl(entity, fn) end

--- Distance utilisée pour une option : personne -> distance entre les deux personnages,
--- véhicule / objet -> distance jusqu'au point visé
local function within(ctx, range)
    return (ctx.pedDistance or ctx.distance or 0) <= range
end

local function faceEntity(entity)
    TaskTurnPedToFaceEntity(PlayerPedId(), entity, 800)
end

-- =========================================================================
-- INSPECTIONS ET FOUILLES (résultats donnés par le serveur : profil actif / profil du véhicule)
-- =========================================================================
local function inspectPayload(ctx, kind, field)
    local payload = { kind = kind, field = field }
    if kind == 'player' then
        payload.target = ctx.serverId
    else
        payload.target = ctx.netId
        -- Véhicule observé : le modèle seulement (pas la plaque d'immatriculation)
        payload.label = kind == 'vehicle' and RPI.vehicleLabel(ctx.entity) or tostring(ctx.model)
    end
    return payload
end

local function showResult(res)
    if res and res.ok then
        RPI.showResult(res)
    else
        RPI.notify(res and res.error or 'Action impossible.', 'error')
    end
end

-- Animations de fouille (en boucle pendant la barre de chargement)
local SEARCH_ANIMS = {
    person = { 'anim@gangops@facility@servers@bodysearch@', 'player_search', 49 },
    vehicle = { 'mini@repair', 'fixing_a_player', 49 },
}

--- Fouille : le serveur la démarre (annonce /me), barre de chargement (X pour annuler), puis résultat
local function search(ctx, kind, def)
    local payload = inspectPayload(ctx, kind, def.field)
    local category = kind == 'vehicle' and 'vehicle' or 'person'
    RPI.request('startSearch', payload, function(res)
        if not res or not res.ok then return showResult(res) end
        if not ctx.isSelf then faceEntity(ctx.entity) end
        RPI.progress({
            label = def.label,
            duration = res.duration,
            anim = SEARCH_ANIMS[category],
            keep = function()
                if ctx.isSelf then return true end
                if not DoesEntityExist(ctx.entity) then return false end
                local tolerance = category == 'vehicle' and 3.5 or 1.0 -- taille du véhicule
                return #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ctx.entity)) <= Config.SearchDistance + tolerance
            end,
        }, function()
            RPI.request('inspect', payload, showResult)
        end, function()
            RPI.notify('Fouille interrompue.', 'error')
        end)
    end)
end

-- range : distance max ; search : fouille avec barre de chargement ; police : réservé à la police
local PERSON_OPTIONS = {
    { field = 'visual', label = 'Inspection visuelle', icon = 'eye', range = Config.ObserveDistance },
    { field = 'olfactory', label = 'Inspection olfactive', icon = 'nose', range = Config.ObserveDistance },
    { field = 'upper', label = 'Fouiller la partie supérieure du corps', icon = 'search', police = true, search = true, range = Config.SearchDistance },
    { field = 'lower', label = 'Fouiller la partie inférieure du corps', icon = 'search', police = true, search = true, range = Config.SearchDistance },
    { field = 'notable', label = 'Détail notoire', icon = 'note', police = true, range = Config.ObserveDistance },
}

local VEHICLE_OPTIONS = {
    { field = 'visualInterior', label = 'Inspection visuelle intérieure', icon = 'eye', range = Config.ObserveDistance },
    { field = 'visualExterior', label = 'Inspection visuelle extérieure', icon = 'eye', range = Config.ObserveDistance },
    { field = 'olfactory', label = 'Inspection olfactive', icon = 'nose', range = Config.ObserveDistance },
    { field = 'notable', label = 'Détail notoire', icon = 'note', police = true, range = Config.ObserveDistance },
    { field = 'cabin', label = 'Fouille de l\'habitacle', icon = 'search', police = true, search = true, range = Config.SearchDistance },
    { field = 'rear', label = 'Fouille de la banquette arrière', icon = 'search', police = true, search = true, range = Config.SearchDistance },
    { field = 'trunk', label = 'Fouille du coffre', icon = 'search', police = true, search = true, range = Config.SearchDistance },
}

local function inspectionOptions(list, ctx, kind)
    local out = {}
    for _, def in ipairs(list) do
        if (not def.police or ctx.police) and within(ctx, def.range) then
            out[#out + 1] = {
                id = kind .. ':' .. def.field, label = def.label, icon = def.icon, police = def.police or nil,
                run = function(c)
                    if def.search then return search(c, kind, def) end
                    if not c.isSelf then faceEntity(c.entity) end
                    RPI.request('inspect', inspectPayload(c, kind, def.field), showResult)
                end,
            }
        end
    end
    return out
end

--- Supprimer un PNJ, un véhicule sans joueur ou un objet (même créé par un joueur), jusqu'à 50 m
local function deleteOption(ctx, out)
    if within(ctx, Config.DeleteDistance) and RPI.Police.canDelete() and RPI.Police.deletable(ctx) then
        out[#out + 1] = { id = 'env:delete', label = 'Supprimer', icon = 'trash',
            run = function(c) RPI.Police.delete(c) end }
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

-- Portières ouvertes avec l'œil : si le joueur monte dans le véhicule et qu'il se met à avancer,
-- il referme lui-même les portières restées ouvertes. Surveillance légère (toutes les 250 ms),
-- uniquement tant qu'une portière ouverte par le joueur reste ouverte et qu'il est près du véhicule.
local DOOR_CLOSE_SPEED = 1.0   -- m/s (~4 km/h) : le véhicule "commence à avancer"
local DOOR_WATCH_RANGE = 30.0  -- m : au-delà (joueur à pied), la surveillance s'arrête
local doorWatch = {}           -- [véhicule] = { [n° de portière] = true }

local function watchDoor(vehicle, index)
    if doorWatch[vehicle] then
        doorWatch[vehicle][index] = true
        return
    end
    doorWatch[vehicle] = { [index] = true }
    CreateThread(function()
        local deadline = GetGameTimer() + 300000 -- 5 min max
        while GetGameTimer() < deadline do
            Wait(250)
            local doors = doorWatch[vehicle]
            if not doors or not DoesEntityExist(vehicle) then break end
            local ped = PlayerPedId()
            local inside = GetVehiclePedIsIn(ped, false) == vehicle
            if not inside and #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > DOOR_WATCH_RANGE then break end

            -- Portières refermées entre-temps : plus à surveiller
            for i in pairs(doors) do
                if GetVehicleDoorAngleRatio(vehicle, i) <= 0.05 then doors[i] = nil end
            end
            if next(doors) == nil then break end

            if inside and GetEntitySpeed(vehicle) > DOOR_CLOSE_SPEED then
                withControl(vehicle, function()
                    for i in pairs(doors) do SetVehicleDoorShut(vehicle, i, false) end
                end)
                break
            end
        end
        doorWatch[vehicle] = nil
    end)
end

local function isLocked(vehicle)
    local status = GetVehicleDoorLockStatus(vehicle)
    return status ~= 0 and status ~= 1
end

local function vehicleOptions(ctx)
    local out = inspectionOptions(VEHICLE_OPTIONS, ctx, 'vehicle')
    local vehicle = ctx.entity
    local Police = RPI.Police

    -- Police : placer l'individu tenu par le bras à l'arrière / faire sortir les passagers arrière
    if ctx.police then
        if Police.dragging() and within(ctx, Config.PlaceVehicleDistance) and Police.rearSeat(vehicle) then
            out[#out + 1] = { id = 'police:place', label = 'Placer l\'individu à l\'arrière', icon = 'car', police = true,
                run = function(c) Police.placeInVehicle(c.entity) end }
        end
        if within(ctx, Config.DoorDistance) and #Police.rearOccupants(vehicle) > 0 then
            out[#out + 1] = { id = 'police:takeout', label = 'Faire sortir l\'individu (arrière)', icon = 'car', police = true,
                run = function(c) Police.takeOut(c.entity) end }
        end
    end

    -- Radio : intérieur avant visé, portière avant ouverte (menu ouvert sur la page Radio)
    if within(ctx, 3.0) and not IsPedInAnyVehicle(PlayerPedId(), false) then
        for _, front in ipairs({ { door = 0, bone = 'seat_dside_f' }, { door = 1, bone = 'seat_pside_f' } }) do
            local bone = GetEntityBoneIndexByName(vehicle, front.bone)
            if bone ~= -1 and GetVehicleDoorAngleRatio(vehicle, front.door) > 0.1
                and #(ctx.hit - GetWorldPositionOfEntityBone(vehicle, bone)) < 1.3 then
                out[#out + 1] = { id = 'radio', label = 'Radio du véhicule', icon = 'music',
                    run = function(c) RPI.openRadio(c.entity) end }
                break
            end
        end
    end

    -- /policeon : pas d'option de portière sur un véhicule d'urgence pour un non-policier
    local door = within(ctx, Config.DoorDistance) and nearestDoor(vehicle, ctx.hit) or nil
    -- /policeon : pas de portière pour un non-policier, sauf portière ouverte par un policier
    if door and Police.restricted(vehicle, door.index) then door = nil end
    if not door then return deleteOption(ctx, out) end

    local locked = isLocked(vehicle)
    local isOpen = GetVehicleDoorAngleRatio(vehicle, door.index) > 0.05
    out[#out + 1] = {
        id = 'door:toggle', icon = 'door', disabled = locked and not isOpen or nil,
        label = ('%s %s%s'):format(isOpen and 'Fermer' or 'Ouvrir', door.name, locked and not isOpen and ' (verrouillé)' or ''),
        run = function(c)
            withControl(c.entity, function()
                local opening = GetVehicleDoorAngleRatio(c.entity, door.index) <= 0.05
                if opening then
                    SetVehicleDoorOpen(c.entity, door.index, false, false)
                    watchDoor(c.entity, door.index)
                else
                    SetVehicleDoorShut(c.entity, door.index, false)
                end
                -- Policier : portière ouverte "par un policier" (/policeon : un civil peut monter par celle-là)
                if RPI.isPolice() then RPI.markPoliceDoor(c.entity, door.index, opening) end
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
    return deleteOption(ctx, out)
end

-- =========================================================================
-- PERSONNES (joueurs, PNJ, soi-même en test)
-- =========================================================================
local function personOptions(ctx)
    local out = inspectionOptions(PERSON_OPTIONS, ctx, ctx.isPlayer and 'player' or 'npc')
    local Police = RPI.Police
    local ped = ctx.entity

    -- Police, à 2 m : menotter / retirer les menottes, prendre / lâcher le bras (joueurs et PNJ)
    if ctx.police and not ctx.isSelf and within(ctx, Config.ActionDistance) and not IsPedInAnyVehicle(ped, false) then
        local cuffed = Police.isCuffed(ped)
        out[#out + 1] = { id = 'police:cuff', label = cuffed and 'Retirer les menottes' or 'Menotter', icon = 'cuffs', police = true,
            run = function(c) Police.cuff(c.entity, not cuffed) end }
        local dragging = Police.dragging()
        if dragging and dragging.ped == ped then
            out[#out + 1] = { id = 'police:release', label = 'Lâcher le bras', icon = 'hand', police = true,
                run = function() Police.release() end }
        elseif not dragging then
            out[#out + 1] = { id = 'police:drag', label = 'Prendre par le bras', icon = 'hand', police = true,
                run = function(c) Police.drag(c.entity) end }
        end
        -- Faire s'asseoir au sol ("/e menotté2") / se relever : individu menotté, pas tenu par le bras
        if cuffed and not Police.isDragged(ped) then
            local seated = Police.isSeated(ped)
            out[#out + 1] = { id = 'police:seat', icon = 'seat', police = true,
                label = seated and 'Faire se relever l\'individu' or 'Faire s\'asseoir l\'individu',
                run = function(c) Police.seat(c.entity, not seated) end }
        end
    end

    if not ctx.isSelf and not IsPedDeadOrDying(ped, true) and within(ctx, Config.ObserveDistance) then
        out[#out + 1] = {
            id = 'ped:wave', label = 'Saluer', icon = 'wave',
            run = function(c)
                faceEntity(c.entity)
                playAnim('gestures@m@standing@casual', 'gesture_hello', 2500, 48)
            end,
        }
    end
    return deleteOption(ctx, out)
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
    -- Props posé avec le script de props (client/props.lua) : déplacer / supprimer
    if RPI.propOptions and RPI.propOptions(ctx, out) then return out end
    local seat = SEATS[ctx.model]
    local near = within(ctx, Config.ObjectDistance)
    if near and seat and not seated and not IsPedInAnyVehicle(PlayerPedId(), false) then
        out[#out + 1] = { id = 'env:sit', label = 'S\'asseoir', icon = 'seat', run = function(c) sit(c, seat) end }
    end
    if near and TRASH[ctx.model] then
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
    return deleteOption(ctx, out)
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
    if ctx.type == 'ped' then return 'Individu' end -- jamais d'identité, de profil ni de mention PNJ
    if ctx.type == 'vehicle' then return RPI.vehicleLabel(ctx.entity) end -- modèle, sans la plaque
    if SEATS[ctx.model] then return 'Siège' end
    if TRASH[ctx.model] then return 'Poubelle' end
    if RPI.isPlacedProp and RPI.isPlacedProp(ctx.entity) then return 'Props' end
    return 'Objet'
end
