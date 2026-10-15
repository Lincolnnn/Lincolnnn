--[[
    Vehicle Control - motos : projections et chutes (client)
    --------------------------------------------------------
    Motos (config.lua, Bike) très sensibles, pilote comme passager (chaque joueur pour lui-même) :
      - PROJECTION : accident à partir de MinSpeed MPH (35) -> ThrowChance (85 %). Même système que
        l'éjection des voitures (VC.launch : ragdoll, impulsion de départ calculée pour une distance idéale,
        plus grande avec la vitesse, jamais plus rapide que la moto ; la physique du jeu fait le reste).
        Sens : dans la course, sauf OffAxisChance (25 %) : sur le côté (gauche / droite), ou vers l'arrière
        quand c'est probable (choc contre une voiture / un camion).
        Si le jeu désarçonne lui-même le motard dans un tel choc, la même règle s'applique (même tirage).
      - CHUTE (ragdoll de la moto, sans projection) : petit incident (piéton renversé, poteau, objet,
        véhicule touché, trottoir, mur) -> FallChance (80 %). Un accident sans projection peut aussi
        finir en chute (FallIfNotThrown). Le motard TOMBE AVEC LA MOTO : ragdoll depuis la selle, avec
        l'élan de la moto (il glisse et roule dans la même course), jamais arrêté net ni posé à côté.
        Désarçonné par le jeu lui-même : il garde aussi cet élan.
      - Une seule décision par choc (le même accident n'est jamais tiré deux fois).
    Performance : aucune boucle à part, branché sur la boucle du véhicule (main.lua) ; à bord d'une moto,
    une lecture de vitesse verticale par image (trottoirs) ; rien à pied ni dans les autres véhicules.
]]

local Config = VCConfig.Bike or {}
local MPS = 1 / VC.MPH -- 1 MPH en m/s

local handledUntil = 0          -- choc déjà traité jusqu'à ce moment (une seule décision par accident)
local lastVz, wasOnWheels = nil, false

local function isBike(vehicle)
    return Config.Enabled ~= false and vehicle ~= 0 and (Config.Classes or {})[GetVehicleClass(vehicle)] == true
end
VC.isBike = isBike

--- Nature d'un choc à moto : 'accident' (projection possible), 'small' (chute possible) ou nil (rien)
--- before : vitesse avant le choc (MPH), drop : vitesse perdue (MPH), hit : { severity, kind } (main.lua)
function VC.bikeIncident(before, drop, hit)
    local kind = hit and hit.kind
    if before >= Config.MinSpeed
        and (drop >= Config.AccidentDrop or (kind == 'vehicle' and drop >= Config.SmallDrop)) then
        return 'accident'
    end
    if before < Config.FallMinSpeed then return nil end
    if kind == 'ped' or kind == 'curb' then return 'small' end
    if (kind == 'object' or kind == 'vehicle') and drop >= Config.SmallDrop then return 'small' end
    if drop >= Config.SmallWorldDrop then return 'small' end
    return nil
end

--- Issue d'un incident : 'throw', 'fall' ou nil ; rThrow, rFall : tirages (0..1)
function VC.bikeOutcome(incident, rThrow, rFall)
    if incident == 'accident' then
        if rThrow < Config.ThrowChance then return 'throw' end
        if not Config.FallIfNotThrown then return nil end
    elseif incident ~= 'small' then
        return nil
    end
    if rFall < Config.FallChance then return 'fall' end
    return nil
end

--- Sens de la projection : côté ('forward' | 'left' | 'right' | 'rear'), angle par rapport à la course
--- (degrés, positif = à gauche) et part de la distance idéale. rand : tirage (0..1), math.random par défaut
function VC.bikeDirection(hit, rand)
    rand = rand or math.random
    local function between(a, b) return a + (b - a) * rand() end
    if rand() >= Config.OffAxisChance then
        return 'forward', between(-Config.ForwardSpread, Config.ForwardSpread), 1.0
    end
    -- Vers l'arrière : seulement contre un véhicule lourd (voiture, camion) qui renvoie le motard
    local rearLikely = hit ~= nil and hit.kind == 'vehicle' and hit.severity == 'heavy'
    if rearLikely and rand() < Config.RearShare then
        return 'rear', 180.0 + between(-Config.RearSpread, Config.RearSpread), Config.RearDistance
    end
    local angle = between(Config.SideAngle[1], Config.SideAngle[2])
    if rand() < 0.5 then return 'left', angle, Config.SideDistance end
    return 'right', -angle, Config.SideDistance
end

local function rotate(dir, degrees)
    local a = math.rad(degrees)
    local c, s = math.cos(a), math.sin(a)
    return vector3(dir.x * c - dir.y * s, dir.x * s + dir.y * c, 0.0)
end

--- Projection ; fromGame : déjà désarçonné par le jeu (lancé de là où il est, sans le déplacer)
local function throw(ped, vehicle, before, velocity, hit, fromGame)
    local dir = vector3(velocity.x, velocity.y, 0.0)
    if #dir < 1.0 then
        local f = GetEntityForwardVector(vehicle)
        dir = vector3(f.x, f.y, 0.0)
    end
    local _, angle, share = VC.bikeDirection(hit)
    dir = rotate(dir / #dir, angle)
    local start, height = nil, 1.2
    if not fromGame then
        -- Départ : au-dessus de la selle, un peu décalé du côté où il part (dégagé de la moto)
        local min, max = GetModelDimensions(GetEntityModel(vehicle))
        local seat = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, max.z + 0.4)
        start = vector3(seat.x + dir.x * 0.6, seat.y + dir.y * 0.6, seat.z)
        height = (max.z + 0.4) - min.z
    end
    VC.launch(ped, {
        dir = dir, distance = VC.throwDistance(before, Config) * share, cap = before * MPS,
        start = start, height = height, damage = Config.ThrowDamage,
    })
end

--- Chute : le motard tombe AVEC la moto. Il part en ragdoll de là où il est assis, avec la vitesse de la moto
--- (FallCarry) et un peu vers un côté (FallSide) : il bascule, glisse et roule au sol dans la même course.
--- Jamais arrêté net, jamais déposé debout à côté. `velocity` : élan de la moto (juste avant le choc).
local function fall(ped, vehicle, velocity, fromGame)
    local carry = Config.FallCarry or 1.0
    local v = velocity or GetEntityVelocity(vehicle)
    local dir = vector3(v.x, v.y, 0.0)
    local side = vector3(0.0, 0.0, 0.0)
    if #dir > 0.5 then
        dir = dir / #dir
        local s = (math.random() < 0.5 and -1.0 or 1.0) * (Config.FallSide or 0.0)
        side = vector3(-dir.y * s, dir.x * s, 0.0) -- perpendiculaire à la course
    end
    local start = nil
    if not fromGame then
        -- Retiré de la selle sur place (un peu au-dessus, dégagé de la moto) : pas déplacé à côté
        local seat = GetEntityCoords(ped)
        start = vector3(seat.x + side.x * 0.15, seat.y + side.y * 0.15, seat.z + 0.3)
    end
    VC.launch(ped, {
        velocity = vector3(v.x * carry + side.x, v.y * carry + side.y, math.max(v.z, 0.0) + 0.5),
        start = start, damage = Config.FallDamage, pushTime = Config.FallPushTime or 200,
    })
end

local function decide(ped, vehicle, before, drop, velocity, hit, fromGame)
    local now = GetGameTimer()
    if now < handledUntil then return end -- même accident : déjà tiré
    local incident = VC.bikeIncident(before, drop, hit)
    if not incident then return end
    handledUntil = now + 2000
    local outcome = VC.bikeOutcome(incident, math.random(), math.random())
    if outcome == 'throw' then
        throw(ped, vehicle, before, velocity, hit, fromGame)
    elseif outcome == 'fall' or fromGame then
        -- Chute (ou déjà désarçonné par le jeu) : il garde l'élan de la moto, jamais arrêté net
        fall(ped, vehicle, velocity, fromGame)
    end
end

-- Choc détecté par main.lua (perte de vitesse pendant un contact), encore en selle
VC.on('impact', function(vehicle, before, drop, velocity, hit)
    if not isBike(vehicle) then return end
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= vehicle or IsEntityDead(ped) then return end
    decide(ped, vehicle, before, drop, velocity, hit, false)
end)

-- Trottoir : secousse verticale brusque, roues au sol juste avant (pas un atterrissage de saut)
VC.on('frame', function(ped, vehicle)
    if not isBike(vehicle) or (Config.CurbJolt or 0) <= 0 then return end
    local velocity = GetEntityVelocity(vehicle)
    local onWheels = IsVehicleOnAllWheels(vehicle)
    if lastVz and wasOnWheels and velocity.z - lastVz >= Config.CurbJolt then
        decide(ped, vehicle, GetEntitySpeed(vehicle) * VC.MPH, 0.0, velocity, { severity = 'light', kind = 'curb' }, false)
    end
    lastVz, wasOnWheels = velocity.z, onWheels
end)

VC.on('enter', function() lastVz, wasOnWheels = nil, false end)

-- Désarçonné par le jeu lui-même pendant un choc : même règle de projection (vitesse juste avant)
VC.on('leave', function(vehicle, _, info)
    lastVz, wasOnWheels = nil, false
    if not info or not isBike(vehicle) or not DoesEntityExist(vehicle) then return end
    local ped = PlayerPedId()
    if IsEntityDead(ped) or GetIsTaskActive(ped, 2) then return end -- descendu normalement
    local crash = info.crash
    if not crash and not HasEntityCollidedWithAnything(vehicle) then return end -- pas de choc
    if not IsPedRagdoll(ped) and not IsPedFalling(ped) then return end          -- pas désarçonné
    local before = math.max(info.peak or 0.0, crash and crash.before or 0.0)
    local after = crash and crash.min or GetEntitySpeed(vehicle) * VC.MPH
    local hit = crash and crash.hit or VC.classifyHit(vehicle)
    -- Le jeu l'a fait tomber : c'est un accident (au moins AccidentDrop perdus, côté motard)
    decide(ped, vehicle, before, math.max(before - after, Config.AccidentDrop), info.velocity or GetEntityVelocity(vehicle), hit, true)
end)
