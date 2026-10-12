--[[
    RP Interact - Véhicules de police : /policeon et /policeoff
    ------------------------------------------------------------
    "Policier" = joueur dans une unité de police du MDC (état "mdcUnit", vérifié aussi par le serveur).

    /policeoff (par défaut, et à chaque redémarrage du serveur) : aucune règle, tout le monde monte
    dans tous les véhicules. Ce fichier ne fait alors STRICTEMENT RIEN (aucune boucle, aucun native
    sur les véhicules).

    /policeon : seuls les policiers montent dans un véhicule de police. Pour tous les autres joueurs
    (mode civil coché ou non) :
      - il essaie d'ouvrir la portière, elle reste verrouillée : sa tentative est arrêtée AVANT que la
        portière bouge (rien n'est cassé, la vitre non plus, pas de vol du véhicule avec son conducteur),
        il marche jusqu'à la portière visée (à quelques centimètres, bien en face) et tire sur la poignée
        (LockedDoorAnim) ;
      - il fait apparaître un véhicule de police (menu de spawn) en étant placé dedans : le véhicule
        apparaît et RESTE, le joueur en descend aussitôt et ne peut plus y remonter ;
      - l'œil ne lui propose plus d'ouvrir les portières ni de monter.
    Exceptions : l'individu placé à l'arrière par un policier (il y monte et y reste), et une portière
    OUVERTE PAR UN POLICIER (œil, placer / faire sortir un individu) : il peut monter par celle-là.
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
local PLACED_WINDOW = 15000 -- ms : placé par un policier, il a ce temps pour monter
local STAND = Config.LockedDoorStand or { distance = 0.38, along = 0.0 } -- position devant la poignée

local classes, models = {}, {}
for _, class in ipairs(Config.PoliceVehicleClasses or { 18 }) do classes[class] = true end
for _, name in ipairs(Config.PoliceVehicleModels or {}) do models[GetHashKey(name)] = true end

local active = GlobalState.rpiPoliceVehicles == true
local running = false
local placed = { vehicle = nil, untilTime = 0 } -- véhicule où un policier vient de placer le joueur
local enteredByOpenDoor = nil -- véhicule où il est monté par une portière ouverte par un policier

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

--- Portière ouverte PAR UN POLICIER (état du véhicule "rpiPoliceDoors", écrit par le serveur) et
--- toujours ouverte : un civil peut monter par celle-là
local function policeOpenedDoor(vehicle, doorIndex)
    if not doorIndex or not NetworkGetEntityIsNetworked(vehicle) then return false end
    local doors = Entity(vehicle).state.rpiPoliceDoors
    return type(doors) == 'table' and doors[tostring(doorIndex)] == true
        and GetVehicleDoorAngleRatio(vehicle, doorIndex) > 0.1
end
RPI.policeOpenedDoor = policeOpenedDoor

--- Policier : signale au serveur qu'il a ouvert / fermé cette portière (véhicule en réseau)
function RPI.markPoliceDoor(vehicle, doorIndex, open)
    if not RPI.isPolice() or not NetworkGetEntityIsNetworked(vehicle) then return end
    RPI.request('policeDoor', { netId = VehToNet(vehicle), door = doorIndex, open = open == true }, function() end)
end

--- Ce joueur est-il interdit de ce véhicule (ou de cette portière) ? (l'œil retire alors les portières)
function RPI.Police.restricted(vehicle, doorIndex)
    return active and not RPI.isPolice() and isPoliceVehicle(vehicle) and not placedIn(vehicle)
        and not policeOpenedDoor(vehicle, doorIndex)
end

--- Où se tenir pour tirer sur la poignée : face à la portière, à quelques centimètres (STAND.distance
--- entre le centre du personnage et la poignée), décalé de STAND.along le long du véhicule
local function standPoint(vehicle, door)
    local bone = GetEntityBoneIndexByName(vehicle, door.handle)
    if bone == -1 then bone = GetEntityBoneIndexByName(vehicle, door.door) end
    local point = bone ~= -1 and GetWorldPositionOfEntityBone(vehicle, bone) or GetEntityCoords(vehicle)
    local forward, right = GetEntityMatrix(vehicle)
    local side = (door.index % 2 == 0) and -1.0 or 1.0 -- portières 0 / 2 : côté conducteur (gauche)
    local ox, oy = right.x * side, right.y * side
    local len = math.sqrt(ox * ox + oy * oy)
    if len < 0.001 then ox, oy, len = 1.0, 0.0, 1.0 end
    ox, oy = ox / len, oy / len
    local x = point.x + ox * STAND.distance + forward.x * (STAND.along or 0.0)
    local y = point.y + oy * STAND.distance + forward.y * (STAND.along or 0.0)
    return x, y, GetHeadingFromVector_2d(-ox, -oy)
end

--- Le joueur va jusqu'à la portière et tire sur la poignée d'une portière verrouillée : rien ne bouge
local function lockedAttempt(ped, vehicle, door)
    ClearPedTasks(ped) -- la tentative du jeu est arrêtée tout de suite : la portière ne bougera pas
    local x, y, heading = standPoint(vehicle, door)
    local z = GetEntityCoords(ped).z
    local distance = #(vector3(x, y, z) - GetEntityCoords(ped))
    if distance > 0.08 then
        TaskGoStraightToCoord(ped, x, y, z, distance > 4.0 and 2.0 or 1.0, 8000, heading, 0.05)
        local timeout = GetGameTimer() + math.floor(distance / 1.0 * 1000) + 1500
        while GetGameTimer() < timeout and active do
            Wait(0)
            local pos = GetEntityCoords(ped)
            if (pos.x - x) ^ 2 + (pos.y - y) ^ 2 <= 0.12 * 0.12 then break end
            if IsPedRagdoll(ped) or IsEntityDead(ped) or GetVehiclePedIsIn(ped, false) ~= 0 then return end
        end
        -- Petit ajustement final (quelques centimètres) : bien en face de la poignée
        local pos = GetEntityCoords(ped)
        if (pos.x - x) ^ 2 + (pos.y - y) ^ 2 <= 0.6 * 0.6 then SetEntityCoordsNoOffset(ped, x, y, pos.z, false, false, false) end
    end
    SetEntityHeading(ped, heading)
    local anim = Config.LockedDoorAnim
    if anim then RPI.playAnimNow(ped, anim.dict, anim.clip, 1600, 0) end
end

--- Tentative de montée détectée : portière ouverte par un policier -> autorisé ; sinon arrêtée aussitôt
local function watchAttempt(ped, vehicle)
    local door = DOORS[GetSeatPedIsTryingToEnter(ped)] or DOORS[-1]
    if policeOpenedDoor(vehicle, door.index) then
        enteredByOpenDoor = vehicle
        return
    end
    lockedAttempt(ped, vehicle, door)
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
                if current ~= 0 and isPoliceVehicle(current) and not placedIn(current) and current ~= enteredByOpenDoor
                    and (current ~= previous or ejected == current) then
                    if ejected ~= current or GetGameTimer() - lastEject > 2500 then
                        TaskLeaveVehicle(ped, current, 0)
                        ejected, lastEject = current, GetGameTimer()
                    end
                elseif current == 0 then
                    ejected = nil
                    if GetVehiclePedIsTryingToEnter(ped) ~= enteredByOpenDoor then enteredByOpenDoor = nil end
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
