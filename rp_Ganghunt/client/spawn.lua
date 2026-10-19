--[[
    RP Ganghunt - client : apparition des ennemis
    ---------------------------------------------
    - Positions : dans un rayon de SpawnDistance (40-70 m) autour du joueur, de préférence hors de sa vue ; toujours au
      niveau de la rue la plus proche (jamais sur un toit, un pont au-dessus de lui, dans l'eau ou dans un intérieur).
    - À pied : par petits groupes de 3. Véhicules : en CONVOI depuis un même point de route, à la file.
      Hélicoptère : au-dessus du point du convoi (ou seul, autour du joueur), un pilote et deux tireurs.
    - Chaque ennemi : arme de poing seule, ou arme longue / spéciale + pistolet de combat ; silencieux et grenades si
      les options sont cochées ; réglé pour l'animosité maximale (jamais de fuite, charge, corps à corps).
    Les ennemis et véhicules restent au joueur qui lance la chasse (pas de migration réseau).
]]

GH = GH or {}
local Config = GanghuntConfig

local GROUP_NAME = 'RP_GANGHUNT'
local PLAYER_GROUP = GetHashKey('PLAYER')
local group = nil

local WEAPON_INFO = {}
for _, w in ipairs(Config.Weapons) do WEAPON_INFO[w.name] = w end
GH.WEAPON_INFO = WEAPON_INFO

local function S() return GH.session() end

--- Chargement d'un modèle ; faux aussi si la chasse a été arrêtée (ou relancée) pendant l'attente
function GH.loadModel(hash)
    if not IsModelInCdimage(hash) then return false end
    local s = S()
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    if not s or S() ~= s then SetModelAsNoLongerNeeded(hash) return false end
    return HasModelLoaded(hash)
end

-- =========================================================================
-- GROUPE : ils ne s'entretuent pas, hostiles aux joueurs
-- =========================================================================
function GH.group()
    if group then return group end
    local _, hash = AddRelationshipGroup(GROUP_NAME)
    group = hash
    SetRelationshipBetweenGroups(0, group, group)          -- entre eux : compagnons
    GH.setHostile(true)
    return group
end

--- Hostiles aux joueurs (5 : haine) ou neutres (1 : respect, option « Neutres » tant qu'on ne les attaque pas)
function GH.setHostile(hostile)
    local g = GH.group()
    local relation = hostile and 5 or 1
    SetRelationshipBetweenGroups(relation, g, PLAYER_GROUP)
    SetRelationshipBetweenGroups(relation, PLAYER_GROUP, g)
end

-- =========================================================================
-- ARMES : répartition choisie (pourcentages) ou au hasard dans celles de la faction
-- =========================================================================
function GH.pickWeapon()
    local s = S()
    local list = s.weapons
    if not list or #list == 0 then
        local pool = s.faction.random or { 'WEAPON_PISTOL' }
        return pool[math.random(1, #pool)]
    end
    local total = 0
    for _, w in ipairs(list) do total = total + w.pct end
    local roll = math.random() * total
    for _, w in ipairs(list) do
        roll = roll - w.pct
        if roll <= 0 then return w.name end
    end
    return list[#list].name
end

--- Silencieux : le premier accessoire de la liste que l'arme accepte
local function suppress(ped, weaponHash)
    for _, component in ipairs(Config.Suppressors or {}) do
        local hash = GetHashKey(component)
        if DoesWeaponTakeWeaponComponent(weaponHash, hash) then
            GiveWeaponComponentToPed(ped, weaponHash, hash)
            return true
        end
    end
    return false
end

local function arm(ped, h)
    local s = S()
    local weapon = GH.pickWeapon()
    local info = WEAPON_INFO[weapon]
    local main = GetHashKey(weapon)
    -- munitions illimitées : ils ne s'arrêtent jamais de tirer
    if info and info.handgun then
        GiveWeaponToPed(ped, main, 9999, false, true)          -- arme de poing seule
    else
        local side = GetHashKey(Config.DefaultSidearm or 'WEAPON_COMBATPISTOL')
        GiveWeaponToPed(ped, side, 9999, false, false)
        SetPedInfiniteAmmo(ped, true, side)
        if s.silencer then suppress(ped, side) end
        GiveWeaponToPed(ped, main, 9999, false, true)          -- arme longue / spéciale en main
    end
    SetPedInfiniteAmmo(ped, true, main)
    if s.silencer then suppress(ped, main) end
    h.weapon = main
    -- Grenades : une partie des ennemis en a quelques-unes (lancées par ai.lua)
    local G = Config.Grenades or {}
    if s.grenades and math.random() < (G.Chance or 0.5) then
        local pool = s.faction.grenades or G[s.category] or G.Gang or { 'WEAPON_GRENADE' }
        local grenade = pool[math.random(1, #pool)]
        h.grenade = GetHashKey(grenade)
        GiveWeaponToPed(ped, h.grenade, 3, false, false)
        SetCurrentPedWeapon(ped, main, true)
    end
    SetPedDropsWeaponsWhenDead(ped, false)
end

-- =========================================================================
-- ENNEMIS
-- =========================================================================
function GH.noMigrate(entity)
    if NetworkGetEntityIsNetworked(entity) then
        local net = NetworkGetNetworkIdFromEntity(entity)
        SetNetworkIdCanMigrate(net, false)
        SetNetworkIdExistsOnAllMachines(net, true)
        return net
    end
end

--- Réglages « traqueur » : animosité maximale, jamais de fuite ; vue / ouïe réalistes (la recherche en dépend)
local AGGRESSIVE = {
    0,  -- se met à couvert (brièvement : il avance quand même)
    1, 2, 3, -- véhicules : s'en sert, tire depuis, en descend
    5,  -- se bat toujours
    13, -- agressif
    14, -- enquête (va voir les bruits)
    21, -- poursuit à pied
    28, -- avance quand il ne peut pas tirer (« frustré »)
    41, -- réquisitionne des véhicules
    42, -- contourne
    46, -- se bat même désarmé
    50, -- charge
    52, -- attaque avec son véhicule
    58, -- ne fuit jamais un combat
    71, -- charge même au-delà de sa zone
}
local function setupHunter(ped, h)
    local s = S()
    local Search = Config.Search or {}
    SetEntityAsMissionEntity(ped, true, true)
    SetPedRelationshipGroupHash(ped, GH.group())
    SetCanAttackFriendly(ped, false, false)
    SetEntityMaxHealth(ped, Config.Health or 200)
    SetEntityHealth(ped, Config.Health or 200)
    SetPedArmour(ped, s.faction.armour or Config.Armour or 0)
    SetPedAccuracy(ped, Config.Accuracy or 40)
    SetPedCombatAbility(ped, 2)             -- professionnel
    SetPedCombatRange(ped, 0)               -- au plus près
    SetPedCombatMovement(ped, 3)            -- « suicidaire » : fonce sur la cible
    SetPedFleeAttributes(ped, 0, false)
    for _, attribute in ipairs(AGGRESSIVE) do SetPedCombatAttributes(ped, attribute, true) end
    SetPedCombatAttributes(ped, 17, false)  -- jamais « toujours fuir »
    -- vue du jeu : longue quand ils combattent (sinon ils perdent leur cible et cessent de tirer), courte pendant
    -- la recherche (ai.lua) ; la détection « repéré / recherche » est faite par ai.lua
    local engaged = s.alert ~= 'search'
    SetPedSeeingRange(ped, engaged and (Search.EngagedSight or 150.0) or (Search.Sight or 75.0))
    SetPedHearingRange(ped, Search.Hearing or 120.0)
    SetPedAlertness(ped, 3)
    SetPedConfigFlag(ped, 281, true)        -- pas de blessures qui le font fuir / se rendre
    SetPedConfigFlag(ped, 42, true)         -- n'influence pas l'indice de recherche
    SetPedKeepTask(ped, true)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanSwitchWeapon(ped, true)
    arm(ped, h)
    if Config.Blips then
        local blip = AddBlipForEntity(ped)
        SetBlipSprite(blip, 1)
        SetBlipColour(blip, 1)
        SetBlipScale(blip, 0.6)
        SetBlipAsShortRange(blip, false)
    end
    GH.noMigrate(ped)
end

function GH.track(entity)
    local s = S()
    s.entities[#s.entities + 1] = entity
    local net = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or nil
    if net then TriggerServerEvent('rp_ganghunt:track', net) end
end

local function randomModel()
    local models = S().faction.models
    return models[math.random(1, #models)]
end

function GH.newHunter(x, y, z, heading)
    local hash = GetHashKey(randomModel())
    if not GH.loadModel(hash) then return nil end
    local s = S()
    local ped = CreatePed(4, hash, x, y, z, heading or 0.0, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return nil end
    local h = { ped = ped, role = 'foot', wave = s.wave, home = vector3(x, y, z) }
    setupHunter(ped, h)
    GH.track(ped)
    s.hunters[ped] = h
    s.waveSpawned = (s.waveSpawned or 0) + 1
    return h
end

-- =========================================================================
-- POSITIONS (rue la plus proche, ni eau, ni toit, ni intérieur ; hors de vue si possible)
-- =========================================================================
local function me() return PlayerPedId() end

local function around(center, minD, maxD)
    local angle = math.random() * math.pi * 2
    local d = minD + math.random() * (maxD - minD)
    return vector3(center.x + math.cos(angle) * d, center.y + math.sin(angle) * d, center.z)
end
GH.around = around

--- Point de route le plus proche (et son cap)
function GH.roadNear(point)
    local found, pos, heading = GetClosestVehicleNodeWithHeading(point.x, point.y, point.z, 1, 3.0, 0)
    if found and pos then return pos, heading or 0.0 end
    return nil, 0.0
end

local function inWater(p)
    local water, height = GetWaterHeight(p.x, p.y, p.z + 2.0)
    return water == true and height and height > p.z - 1.0
end

--- Position utilisable : pas dans l'eau, pas dans un intérieur, au niveau de la rue (pas sur un toit)
function GH.validSpot(p, street)
    if not p or inWater(p) then return false end
    if GetInteriorAtCoords(p.x, p.y, p.z) ~= 0 then return false end
    if street and math.abs(p.z - street.z) > (Config.StreetLevel or 4.0) then return false end
    return true
end

local function hidden(p) return not IsSphereVisible(p.x, p.y, p.z + 1.0, 2.5) end

--- Position à pied dans le rayon d'apparition (hors de vue si possible)
function GH.footSpot(center)
    local SD = Config.SpawnDistance or { 40.0, 70.0 }
    center = center or GetEntityCoords(me())
    local fallback = nil
    for _ = 1, 12 do
        local point = around(center, SD[1], SD[2])
        local street = GH.roadNear(point)
        if street and #(street - center) <= SD[2] + 15.0 then
            -- 8 : pas dans l'eau ; 4 : pas dans un intérieur
            local ok, safe = GetSafeCoordForPed(point.x, point.y, street.z + 1.0, true, 12)
            local spot = ok and safe or street
            if #(spot - center) > SD[2] + 15.0 then spot = street end
            if GH.validSpot(spot, street) then
                if hidden(spot) then return spot end
                fallback = fallback or spot
            end
        end
    end
    return fallback or GH.roadNear(around(center, SD[1], SD[2])) or around(center, SD[1], SD[2])
end

--- Point de départ du convoi : une route dans le rayon d'apparition, hors de vue si possible
function GH.convoySpot(center)
    local SD = Config.SpawnDistance or { 40.0, 70.0 }
    center = center or GetEntityCoords(me())
    local fallback, fallbackHeading = nil, 0.0
    for _ = 1, 12 do
        local node, heading = GH.roadNear(around(center, SD[1], SD[2]))
        if node and #(node - center) <= SD[2] + 15.0 and GH.validSpot(node) then
            if hidden(node) then return node, heading end
            fallback, fallbackHeading = fallback or node, fallback and fallbackHeading or heading
        end
    end
    if fallback then return fallback, fallbackHeading end
    local node, heading = GH.roadNear(around(center, SD[1], SD[2]))
    return node or around(center, SD[1], SD[2]), heading
end

-- =========================================================================
-- VÉHICULES ET HÉLICOPTÈRE
-- =========================================================================
function GH.newVehicle(model, pos, heading)
    local hash = GetHashKey(model)
    if not GH.loadModel(hash) then return nil end
    local veh = CreateVehicle(hash, pos.x, pos.y, pos.z + 0.5, heading or 0.0, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not veh or veh == 0 then return nil end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleHasBeenOwnedByPlayer(veh, false)
    SetVehicleDoorsLocked(veh, 1)
    if GetVehicleClass(veh) == 18 then SetVehicleSiren(veh, true) end -- urgences : gyrophares
    GH.noMigrate(veh)
    GH.track(veh)
    local s = S()
    s.vehicles[veh] = true
    return veh
end

local function seatsOf(model)
    local seats = GetVehicleModelNumberOfSeats(GetHashKey(model))
    if not seats or seats < 1 then seats = 4 end
    return math.min(4, seats)
end

local function factionVehicle()
    local models = S().faction.vehicles or {}
    return #models > 0 and models[math.random(1, #models)] or 'baller'
end

--- Un véhicule de la faction avec `count` nouveaux ennemis à bord ; renvoie le nombre placé
function GH.crewVehicle(pos, heading, count)
    if not S() then return 0 end
    local model = factionVehicle()
    local veh = GH.newVehicle(model, pos, heading)
    if not veh then return 0 end
    local placed = 0
    for seat = -1, seatsOf(model) - 2 do
        if not S() or placed >= count then break end
        local h = GH.newHunter(pos.x, pos.y, pos.z + 1.0, heading)
        if not h then break end
        SetPedIntoVehicle(h.ped, veh, seat)
        h.veh, h.seat = veh, seat
        h.role = seat == -1 and 'driver' or 'passenger'
        placed = placed + 1
    end
    return placed
end

--- Convoi : tous les véhicules depuis le même point de route, à la file (le premier devant)
function GH.convoy(count)
    local origin, heading = GH.convoySpot()
    local myPos = GetEntityCoords(me())
    -- direction de la file : du point vers le joueur ; les suivants derrière
    local dx, dy = myPos.x - origin.x, myPos.y - origin.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.1 then dx, dy, len = 0.0, 1.0, 1.0 end
    dx, dy = dx / len, dy / len
    local towards = GetHeadingFromVector_2d(dx, dy)
    local placedTotal, i = 0, 0
    while placedTotal < count and i < 10 and S() do
        local back = i * (Config.ConvoySpacing or 8.0)
        local pos = vector3(origin.x - dx * back, origin.y - dy * back, origin.z)
        local node = GH.roadNear(pos)
        if node and #(node - pos) < 6.0 and GH.validSpot(node) then pos = node end
        local placed = GH.crewVehicle(pos, i == 0 and heading or towards, math.min(4, count - placedTotal))
        if placed == 0 then break end
        placedTotal = placedTotal + placed
        i = i + 1
    end
    return placedTotal, origin
end

--- Hélicoptère : pilote (poursuit / cherche) et tireurs ; au-dessus du point du convoi s'il y en a un
function GH.crewHeli(count, origin)
    local s = S()
    local model = s.faction.heli or 'maverick'
    local base = origin or GH.convoySpot()
    local pos = vector3(base.x, base.y, base.z + (Config.HeliHeight or 45.0))
    local myPos = GetEntityCoords(me())
    local heli = GH.newVehicle(model, pos, GetHeadingFromVector_2d(myPos.x - pos.x, myPos.y - pos.y))
    if not heli then return 0 end
    if s.faction.heliLivery then SetVehicleLivery(heli, s.faction.heliLivery) end
    SetHeliBladesFullSpeed(heli)
    SetEntityCoordsNoOffset(heli, pos.x, pos.y, pos.z, false, false, false)
    s.heli = heli
    s.helis[heli] = true
    local placed = 0
    for _, seat in ipairs({ -1, 1, 2, 0 }) do
        if not S() or placed >= count or (seat ~= -1 and not IsVehicleSeatFree(heli, seat)) then break end
        local h = GH.newHunter(pos.x, pos.y, pos.z, 0.0)
        if not h then break end
        SetPedIntoVehicle(h.ped, heli, seat)
        h.veh, h.seat = heli, seat
        h.role = seat == -1 and 'pilot' or 'gunner'
        placed = placed + 1
    end
    return placed
end

--- Ennemis à pied : par groupes de 3, chaque groupe à un endroit différent du rayon d'apparition
function GH.footGroups(count)
    local placedTotal = 0
    while placedTotal < count and S() do
        local spot = GH.footSpot()
        local n = math.min(3, count - placedTotal)
        for _ = 1, n do
            GH.newHunter(spot.x + math.random(-2, 2), spot.y + math.random(-2, 2), spot.z, 0.0)
            placedTotal = placedTotal + 1
        end
    end
    return placedTotal
end

--- Véhicule pour des ennemis à pied loin de leur objectif : le leur (ou un autre de la faction) s'il est proche et
--- libre, sinon un nouveau sur la route la plus proche. Hors de la vue du joueur : ils y sont placés ; sinon ils
--- courent y monter (12 s au plus).
function GH.remount(crew)
    local s = S()
    local leader = crew[1]
    local lp = GetEntityCoords(leader.ped)
    local veh = nil
    for v in pairs(s.vehicles) do
        if DoesEntityExist(v) and not s.helis[v] and IsVehicleDriveable(v, false) and #(GetEntityCoords(v) - lp) < 40.0
            and GetVehicleNumberOfPassengers(v) == 0 and IsVehicleSeatFree(v, -1) then
            veh = v
            break
        end
    end
    if not veh then
        local node, heading = GH.roadNear(lp)
        if not node or not GH.validSpot(node) then return false end
        veh = GH.newVehicle(factionVehicle(), node, heading)
        if not veh then return false end
    end
    local maxSeat = math.min(2, GetVehicleMaxNumberOfPassengers(veh) - 1)
    local now = GetGameTimer()
    for i, h in ipairs(crew) do
        local seat = i - 2
        if seat > maxSeat then break end
        if DoesEntityExist(h.ped) then
            h.remountAt = now
            h.veh, h.seat = veh, seat
            h.role = seat == -1 and 'driver' or 'passenger'
            h.mode = nil
            if IsEntityOnScreen(h.ped) or IsEntityOnScreen(veh) then
                ClearPedTasks(h.ped)
                TaskEnterVehicle(h.ped, veh, 12000, seat, 2.0, 1, 0)
                h.boarding = now + 12000
            else
                SetPedIntoVehicle(h.ped, veh, seat)
                h.boarding = nil
            end
        end
    end
    return true
end
