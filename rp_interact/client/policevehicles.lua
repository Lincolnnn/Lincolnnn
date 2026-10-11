--[[
    RP Interact - Véhicules de police : /policeon et /policeoff
    ------------------------------------------------------------
    "Policier" = joueur dans une unité de police du MDC (état "mdcUnit", vérifié aussi par le serveur).

    /policeoff (par défaut, et à chaque redémarrage du serveur) : aucune règle, tout le monde monte
    dans tous les véhicules. Ce fichier ne fait alors STRICTEMENT RIEN (aucune boucle, aucun native
    sur les véhicules).

    /policeon : seuls les policiers montent dans un véhicule de police. Pour tous les autres joueurs
    (mode civil coché ou non) :
      - il essaie d'ouvrir la portière, elle reste verrouillée : il est arrêté AVANT que la portière
        bouge (rien n'est cassé, la vitre non plus, pas de vol du véhicule avec son conducteur), puis
        tire sur la poignée (LockedDoorAnim) ;
      - il fait apparaître un véhicule de police (menu de spawn) en étant placé dedans : le véhicule
        apparaît et RESTE, le joueur en descend aussitôt et ne peut plus y remonter ;
      - l'œil ne lui propose plus d'ouvrir les portières ni de monter.
    Exception : l'individu placé à l'arrière par un policier (il y monte et y reste).
    Tout le monde peut faire apparaître un véhicule ; ce fichier ne supprime jamais rien et ne change
    jamais l'état d'un véhicule (verrou, portières) : il agit uniquement sur le personnage du joueur.

    Véhicule de police : classe du jeu "véhicule d'urgence" (PoliceVehicleClasses) ou modèle listé dans
    PoliceVehicleModels (véhicules ajoutés d'une autre classe).

    Performance : /policeoff : 0 boucle. /policeon : une vérification toutes les 200 ms chez les
    non-policiers (à chaque image seulement pendant une tentative de montée), 1 s chez les policiers.
]]

local Config = InteractConfig

local DOORS = { -- siège -> portière (index), poignée et charnière (os du véhicule)
    [-1] = { index = 0, handle = 'handle_dside_f', door = 'door_dside_f' },
    [0]  = { index = 1, handle = 'handle_pside_f', door = 'door_pside_f' },
    [1]  = { index = 2, handle = 'handle_dside_r', door = 'door_dside_r' },
    [2]  = { index = 3, handle = 'handle_pside_r', door = 'door_pside_r' },
}
local HANDLE_RANGE = 1.15 -- m : le joueur est arrêté à la poignée (avant d'ouvrir)
local DOOR_RANGE = 1.6    -- m : idem, mesuré depuis la charnière (véhicule sans os de poignée)
local PLACED_WINDOW = 15000 -- ms : placé par un policier, il a ce temps pour monter

local classes, models = {}, {}
for _, class in ipairs(Config.PoliceVehicleClasses or { 18 }) do classes[class] = true end
for _, name in ipairs(Config.PoliceVehicleModels or {}) do models[GetHashKey(name)] = true end

local active = GlobalState.rpiPoliceVehicles == true
local running = false
local placed = { vehicle = nil, untilTime = 0 } -- véhicule où un policier vient de placer le joueur

local function isPoliceVehicle(vehicle)
    return vehicle ~= 0 and DoesEntityExist(vehicle)
        and (classes[GetVehicleClass(vehicle)] == true or models[GetEntityModel(vehicle)] == true)
end

--- Placé par un policier dans ce véhicule : autorisé à y monter (15 s) puis à y rester
local function placedIn(vehicle)
    return vehicle == placed.vehicle
        and (GetGameTimer() <= placed.untilTime or GetVehiclePedIsIn(PlayerPedId(), false) == vehicle)
end

function RPI.allowPoliceVehicle(vehicle)
    placed.vehicle, placed.untilTime = vehicle, GetGameTimer() + PLACED_WINDOW
end

--- Ce joueur est-il interdit de ce véhicule ? (utilisé par l'œil pour retirer les portières)
function RPI.Police.restricted(vehicle)
    return active and not RPI.isPolice() and isPoliceVehicle(vehicle) and not placedIn(vehicle)
end

--- Point où le joueur doit être arrêté pour la place visée : poignée, sinon charnière, sinon véhicule
local function stopPoint(vehicle, seat)
    local door = DOORS[seat] or DOORS[-1]
    local bone = GetEntityBoneIndexByName(vehicle, door.handle)
    if bone ~= -1 then return GetWorldPositionOfEntityBone(vehicle, bone), HANDLE_RANGE, door.index end
    bone = GetEntityBoneIndexByName(vehicle, door.door)
    if bone ~= -1 then return GetWorldPositionOfEntityBone(vehicle, bone), DOOR_RANGE, door.index end
    return GetEntityCoords(vehicle), 2.5, door.index
end

--- Le joueur tire sur la poignée d'une portière verrouillée : tentative arrêtée, rien ne bouge
local function lockedAttempt(ped)
    ClearPedTasks(ped)
    local anim = Config.LockedDoorAnim
    if anim then CreateThread(function() RPI.playAnimNow(ped, anim.dict, anim.clip, 1600, 0) end) end
end

--- Tentative de montée en cours : surveillée à chaque image jusqu'à la poignée
local function watchAttempt(ped, vehicle)
    local point, range, doorIndex = stopPoint(vehicle, GetSeatPedIsTryingToEnter(ped))
    local doorStart = GetVehicleDoorAngleRatio(vehicle, doorIndex)
    while active and GetVehiclePedIsTryingToEnter(ped) == vehicle and not RPI.isPolice() do
        -- À la poignée, ou la portière / vitre commence à bouger : arrêt immédiat
        if #(GetEntityCoords(ped) - point) <= range
            or GetVehicleDoorAngleRatio(vehicle, doorIndex) > doorStart + 0.01
            or IsPedJacking(ped) then
            lockedAttempt(ped)
            return
        end
        Wait(0)
        if GetVehiclePedIsIn(ped, false) == vehicle then return end -- placé directement (spawn) : géré ensuite
    end
end

local function start()
    if running then return end
    running = true
    CreateThread(function()
        local previous = GetVehiclePedIsIn(PlayerPedId(), false) -- déjà à bord au moment de /policeon : on n'y touche pas
        local ejected, lastEject = nil, 0
        while active do
            if RPI.isPolice() then
                previous, ejected = GetVehiclePedIsIn(PlayerPedId(), false), nil
                Wait(1000)
            else
                local ped = PlayerPedId()
                local current = GetVehiclePedIsIn(ped, false)
                -- Placé par un policier : l'autorisation s'arrête quand il est descendu (délai passé)
                if placed.vehicle and current ~= placed.vehicle and GetGameTimer() > placed.untilTime then
                    placed.vehicle = nil
                end

                -- Apparu / placé directement dans un véhicule de police (menu de spawn…) : il en descend
                -- aussitôt (le véhicule reste), et à nouveau s'il y est replacé
                if current ~= 0 and isPoliceVehicle(current) and not placedIn(current)
                    and (current ~= previous or ejected == current) then
                    if ejected ~= current or GetGameTimer() - lastEject > 2500 then
                        TaskLeaveVehicle(ped, current, 0)
                        ejected, lastEject = current, GetGameTimer()
                    end
                elseif current == 0 then
                    ejected = nil
                end
                previous = current

                -- Tentative de montée (touche F, œil…)
                local target = GetVehiclePedIsTryingToEnter(ped)
                if target ~= 0 and current == 0 and isPoliceVehicle(target) and not placedIn(target) then
                    watchAttempt(ped, target)
                end
                Wait(200)
            end
        end
        running = false
    end)
end

AddStateBagChangeHandler('rpiPoliceVehicles', 'global', function(_, _, value)
    active = value == true
    if active then start() end
end)
if active then start() end
