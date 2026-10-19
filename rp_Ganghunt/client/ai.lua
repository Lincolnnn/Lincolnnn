--[[
    RP Ganghunt - client : comportement des ennemis (comme la police du jeu)
    ------------------------------------------------------------------------
    PERCEPTION (une fois par seconde ; 10 lignes de vue au plus, tous les ennemis testés en quelques secondes) :
      - pendant le combat, un ennemi qui a le joueur en ligne de vue jusqu'à EngagedSight m (150) le garde ;
      - pour le RETROUVER, il faut l'avoir devant soi, à portée de vue (75 m ; moins la nuit ou si le joueur est
        furtif, plus s'il est en véhicule, 150 m depuis l'hélicoptère) et sans obstacle ; tout près, il est trouvé ;
      - ils l'ENTENDENT tirer (moins avec un silencieux) et savent d'où vient une balle qui en touche un.
    NEUTRES (option) : ils restent autour du joueur sans l'attaquer, jusqu'à ce qu'il les attaque (balle, coup, tir
    près d'eux, véhicule touché) : alors tous sont hostiles (« REPÉRÉ »), jusqu'à ce que tous soient éliminés.
    RADIO : un seul ennemi qui le voit suffit (ou qui le combat / lui tire dessus de lui-même), toute la faction sait
    où il est (« REPÉRÉ ») :
      - à pied : TOUS convergent vers sa position : ceux qui sont loin (ConvergeDistance) foncent en courant, les
        autres combattent en avançant (zone de combat centrée sur lui, déplacée quand il bouge, sans s'arrêter à
        couvert), chargent et finissent au corps à corps ;
      - véhicules : foncent vers lui, s'arrêtent à DismountDistance m et tout le monde descend ; s'il est en véhicule,
        poursuite (les passagers tirent) ; à pied trop loin, ils reprennent un véhicule ;
      - hélicoptère : le suit, ses tireurs tirent ; grenades de temps en temps (option).
    RECHERCHE : personne ne le voit depuis LoseTime ms -> zone de recherche autour de sa dernière position connue,
    qui s'agrandit ; à pied ils la fouillent, les véhicules la sillonnent, l'hélicoptère la survole (projecteur).
    Sans le retrouver, la zone se rapproche de lui de temps en temps (renseignements). Revu -> tous sur lui.
]]

GH = GH or {}
local Config = GanghuntConfig
local Search = Config.Search or {}

local TASK = {
    combat = GetHashKey('SCRIPT_TASK_COMBAT'),
    chase = GetHashKey('SCRIPT_TASK_VEHICLE_CHASE'),
    heli = GetHashKey('SCRIPT_TASK_HELI_CHASE'),
    heliMission = GetHashKey('SCRIPT_TASK_HELI_MISSION'),
    drive = GetHashKey('SCRIPT_TASK_VEHICLE_DRIVE_TO_COORD_LONGRANGE'),
    nav = GetHashKey('SCRIPT_TASK_FOLLOW_NAV_MESH_TO_COORD'),
    goTo = GetHashKey('SCRIPT_TASK_GO_TO_ENTITY'),
}
local Passive = Config.Passive or {}
local function running(ped, task) return GetScriptTaskStatus(ped, TASK[task]) ~= 7 end

local function S() return GH.session() end

-- =========================================================================
-- ÉTAT DE LA FACTION : repéré / recherche
-- =========================================================================
local function sound(which)
    local snd = Config.Sounds and Config.Sounds[which]
    if snd then PlaySoundFrontend(-1, snd[1], snd[2], true) end
end

local function searchBlip(s)
    if not Search.Blip then return end
    if s.searchBlip then RemoveBlip(s.searchBlip) end
    local c = s.searchCenter
    s.searchBlip = AddBlipForRadius(c.x, c.y, c.z, s.searchRadius)
    SetBlipColour(s.searchBlip, 1)
    SetBlipAlpha(s.searchBlip, 90)
    s.searchBlipRadius = s.searchRadius
end

function GH.clearSearchBlip(s)
    if s and s.searchBlip then RemoveBlip(s.searchBlip) s.searchBlip = nil end
end

local function resetTasks(s)
    for _, h in pairs(s.hunters) do h.mode = nil end
end

--- Vue du jeu : longue pendant le combat (ils gardent leur cible et tirent), courte pendant la recherche
local function setPerception(s, engaged)
    local range = engaged and (Search.EngagedSight or 150.0) or (Search.Sight or 75.0)
    for ped, h in pairs(s.hunters) do
        if not h.dead and DoesEntityExist(ped) then SetPedSeeingRange(ped, range) end
    end
end

local function engage(s, now, silent)
    s.alert = 'engaged'
    GH.clearSearchBlip(s)
    resetTasks(s)
    setPerception(s, true)
    if not silent then sound('Spotted') end
    if GH.onAlert then GH.onAlert('engaged') end
end

--- Neutres (option) : ils ne l'attaquent pas
function GH.calm(s)
    s.alert = 'calm'
    GH.setHostile(false)
    GH.clearSearchBlip(s)
    resetTasks(s)
    if GH.onAlert then GH.onAlert('calm') end
end

--- Le joueur les attaque : tous hostiles, ils savent où il est
local function provoke(s, now, myPos)
    s.provoked = true
    GH.setHostile(true)
    s.lkp, s.lastSeen = myPos, now
    engage(s, now)
end

local function startSearch(s, now)
    s.alert = 'search'
    s.searchCenter = s.lkp
    s.searchRadius = Search.StartRadius or 35.0
    s.searchSince = now
    s.nextTip = now + (Search.TipInterval or 20000)
    searchBlip(s)
    resetTasks(s)
    setPerception(s, false)
    sound('Lost')
    if GH.onAlert then GH.onAlert('search') end
end

local function updateSearch(s, now, myPos, dt)
    s.searchRadius = math.min(Search.MaxRadius or 140.0, s.searchRadius + (Search.Growth or 2.0) * dt)
    if now >= s.nextTip then
        -- renseignements : la zone se rapproche du joueur
        local c, k = s.searchCenter, Search.TipShift or 0.3
        s.searchCenter = vector3(c.x + (myPos.x - c.x) * k, c.y + (myPos.y - c.y) * k, c.z + (myPos.z - c.z) * k)
        s.nextTip = now + (Search.TipInterval or 20000)
        searchBlip(s)
    elseif s.searchRadius - (s.searchBlipRadius or 0) >= 10.0 then
        searchBlip(s)
    end
end

--- Point à fouiller dans la zone (à pied : position sûre ; véhicule : route)
local function searchPoint(s, road)
    local p = GH.around(s.searchCenter, 0.0, s.searchRadius)
    if road then return GH.roadNear(p) or p end
    local ok, safe = GetSafeCoordForPed(p.x, p.y, p.z + 1.0, true, 12)
    return ok and safe or p
end

-- =========================================================================
-- PERCEPTION
-- =========================================================================
local function isNight()
    local hour = GetClockHours()
    return hour >= 21 or hour < 6
end

--- Le joueur a tiré depuis la dernière vérification (munitions de son arme en baisse, ou tir en cours)
local function playerFired(s, me)
    local _, weapon = GetCurrentPedWeapon(me, true)
    local ammo = GetAmmoInPedWeapon(me, weapon)
    local fired = IsPedShooting(me) or (s.lastWeapon == weapon and s.lastAmmo ~= nil and ammo < s.lastAmmo)
    s.lastWeapon, s.lastAmmo = weapon, ammo
    return fired
end

--- engaged : ils le combattent (ils le suivent des yeux loin, dans toutes les directions) ; sinon : ils le cherchent
local function sees(h, me, d, ctx, engaged)
    local inAir = h.role == 'pilot' or h.role == 'gunner'
    local range
    if inAir then
        range = Search.HeliSight or 150.0
    elseif engaged then
        range = Search.EngagedSight or 150.0
    else
        range = Search.Sight or 75.0
        if ctx.stealth then range = range * (Search.StealthFactor or 0.6) end
        if ctx.night then range = range * (Search.NightFactor or 0.7) end
        if ctx.inVehicle then range = range * (Search.VehicleFactor or 1.5) end
    end
    if d > range then return false end
    if d <= (Search.Bump or 5.0) then return true end
    if engaged or inAir or d <= (Search.CloseRange or 12.0) then return HasEntityClearLosToEntity(h.ped, me, 17) end
    return HasEntityClearLosToEntityInFront(h.ped, me) -- il doit l'avoir devant lui
end

-- =========================================================================
-- ACTIONS
-- =========================================================================
local function combat(h, me)
    TaskCombatPed(h.ped, me, 0, 16)
    h.mode = 'combat'
end

--- Descente du véhicule (puis combat si le joueur est repéré) ; une fois par 5 s au plus
local function dismount(h, veh, now, fight)
    if h.dismountAt and now - h.dismountAt < 5000 then return end
    h.dismountAt = now
    h.mode = 'dismount'
    ClearPedTasks(h.ped)
    local sequence = OpenSequenceTask()
    TaskLeaveVehicle(0, veh, 256)
    if fight then TaskCombatPed(0, PlayerPedId(), 0, 16) end
    CloseSequenceTask(sequence)
    TaskPerformSequence(h.ped, sequence)
    ClearSequenceTask(sequence)
end

local function dismountCrew(s, veh, now, fight)
    for _, o in pairs(s.hunters) do
        if not o.dead and DoesEntityExist(o.ped) and GetVehiclePedIsIn(o.ped, false) == veh then dismount(o, veh, now, fight) end
    end
end

local function driveTo(h, veh, pos, speed, stopRange, mode)
    TaskVehicleDriveToCoordLongrange(h.ped, veh, pos.x, pos.y, pos.z, speed, Config.DrivingStyle or 1074528293, stopRange)
    SetDriverAbility(h.ped, 1.0)
    SetDriverAggressiveness(h.ped, 1.0)
    h.mode, h.target, h.taskAt = mode, pos, GetGameTimer()
end

local function chase(h, veh, me)
    SetDriverAbility(h.ped, 1.0)
    SetDriverAggressiveness(h.ped, 1.0)
    TaskVehicleChase(h.ped, me)
    SetTaskVehicleChaseIdealPursuitDistance(h.ped, 0.0)
    SetTaskVehicleChaseBehaviorFlag(h.ped, 1, true)
    SetVehicleEngineOn(veh, true, true, false)
    h.mode = 'chase'
end

--- Grenade : arme changée, lancer vers le joueur (imprécis), l'arme revient 2,5 s plus tard
local function throwGrenade(s, h, myPos, now)
    local spread = (Config.Grenades or {}).Spread or 3.0
    SetCurrentPedWeapon(h.ped, h.grenade, true)
    TaskThrowProjectile(h.ped, myPos.x + (math.random() * 2 - 1) * spread, myPos.y + (math.random() * 2 - 1) * spread,
        myPos.z, 0, 0)
    h.throwUntil = now + 2500
    h.mode = 'throw'
end

local function nextGrenade(now)
    local I = (Config.Grenades or {}).Interval or { 7000, 15000 }
    return now + math.random(I[1], I[2])
end

-- =========================================================================
-- UNE VÉRIFICATION (par seconde)
-- =========================================================================
--- Renvoie le nombre d'ennemis vivants
function GH.think(now)
    local s = S()
    local me = PlayerPedId()
    local myPos = GetEntityCoords(me)
    local meInVehicle = IsPedInAnyVehicle(me, false)
    local dt = s.lastThink and (now - s.lastThink) / 1000 or 0
    s.lastThink = now

    -- 1. morts, rôles, distances ; touché par le joueur = il sait d'où ça vient
    local alive, list = 0, {}
    local hit = false
    for ped, h in pairs(s.hunters) do
        if not DoesEntityExist(ped) then
            s.hunters[ped] = nil
            if not h.dead then GH.countKill(s, h) end
        elseif h.dead then
            if now - h.dead > (Config.BodyCleanup or 20000) then
                s.hunters[ped] = nil
                SetEntityAsNoLongerNeeded(ped)
            end
        elseif IsPedDeadOrDying(ped, true) then
            h.dead = now
            GH.countKill(s, h)
            if GetPedSourceOfDeath(ped) == me then hit = true end
            local blip = GetBlipFromEntity(ped)
            if blip and blip ~= 0 then RemoveBlip(blip) end
        else
            alive = alive + 1
            local veh = GetVehiclePedIsIn(ped, false)
            if veh == 0 then
                h.role = 'foot'
            elseif s.helis[veh] then
                h.role = GetPedInVehicleSeat(veh, -1) == ped and 'pilot' or 'gunner'
            else
                h.role = GetPedInVehicleSeat(veh, -1) == ped and 'driver' or 'passenger'
            end
            h.inVeh = veh
            h.dist = #(GetEntityCoords(ped) - myPos)
            if HasEntityBeenDamagedByEntity(ped, me, true) then
                hit = true
                ClearEntityLastDamageEntity(ped)
            end
            list[#list + 1] = h
        end
    end
    if s.alert == 'calm' then
        -- neutres : leurs véhicules touchés par le joueur comptent comme une attaque
        for v in pairs(s.vehicles) do
            if DoesEntityExist(v) and HasEntityBeenDamagedByEntity(v, me, true) then
                hit = true
                ClearEntityLastDamageEntity(v)
            end
        end
    end
    if alive == 0 then
        if hit and s.alert == 'calm' then provoke(s, now, myPos) end
        return 0
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    local fired = playerFired(s, me)

    if s.alert == 'calm' then
        -- 2a. neutres : seulement s'il les attaque (touché, tué, ou tir tout près de l'un d'eux)
        if hit or (fired and list[1].dist <= (Passive.ProvokeRange or 25.0)) then provoke(s, now, myPos) end
    else
        -- 2b. perception : touché, entendu, vu
        local engagedNow = s.alert == 'engaged'
        local seen = hit
        if fired then
            local range = IsPedCurrentWeaponSilenced(me) and (Search.SilencedHearing or 20.0) or (Search.Hearing or 120.0)
            if list[1].dist <= range then seen = true end
        end
        if not seen and not engagedNow then
            -- pendant la recherche, un ennemi qui le repère de lui-même (le jeu le fait entrer en combat, ou il tire
            -- sur lui) prévient tous les autres
            for _, h in ipairs(list) do
                if IsPedShooting(h.ped) or IsPedInCombat(h.ped, me) then
                    if h.dist <= (Search.EngagedSight or 150.0) and HasEntityClearLosToEntity(h.ped, me, 17) then
                        seen = true
                        break
                    end
                end
            end
        end
        if not seen then
            -- lignes de vue : les 4 plus proches à chaque fois, puis 6 autres à tour de rôle
            local ctx = { stealth = GetPedStealthMovement(me), night = isNight(), inVehicle = meInVehicle }
            local cands = {}
            for _, h in ipairs(list) do
                if h.dist <= math.max(Search.HeliSight or 150.0, Search.EngagedSight or 150.0) then cands[#cands + 1] = h end
            end
            for i = 1, math.min(4, #cands) do
                if sees(cands[i], me, cands[i].dist, ctx, engagedNow) then seen = true break end
            end
            local rest = #cands - 4
            if not seen and rest > 0 then
                local cursor = s.losCursor or 0
                for k = 1, math.min(6, rest) do
                    local h = cands[4 + ((cursor + k - 1) % rest) + 1]
                    if sees(h, me, h.dist, ctx, engagedNow) then seen = true break end
                end
                s.losCursor = cursor + 6
            end
        end
        if seen then
            s.lkp, s.lastSeen = myPos, now
            if not engagedNow then engage(s, now) end
        elseif engagedNow and now - (s.lastSeen or now) > (Search.LoseTime or 8000) then
            startSearch(s, now)
        end
        if s.alert == 'search' then updateSearch(s, now, myPos, dt) end
    end
    local engaged = s.alert == 'engaged'
    local calm = s.alert == 'calm'

    -- 3. chacun selon son rôle
    local far = {}
    local meleeDistance = (Config.Melee or {}).Distance or 2.6
    local meleeCooldown = (Config.Melee or {}).Cooldown or 4000
    for _, h in ipairs(list) do
        local ped, veh, d = h.ped, h.inVeh, h.dist
        if h.boarding then
            -- il court monter dans un véhicule (12 s au plus)
            if veh ~= 0 and veh == h.veh then
                h.boarding, h.mode = nil, nil
            elseif now > h.boarding then
                h.boarding = nil
                if h.veh and DoesEntityExist(h.veh) and not IsEntityOnScreen(ped) then SetPedIntoVehicle(ped, h.veh, h.seat or -1) end
                h.mode = nil
            end
        elseif h.throwUntil then
            if now >= h.throwUntil then
                SetCurrentPedWeapon(ped, h.weapon, true)
                if h.grenade and GetAmmoInPedWeapon(ped, h.grenade) <= 0 then h.grenade = nil end
                h.throwUntil, h.mode = nil, nil
            end
        elseif h.mode == 'dismount' and now - (h.dismountAt or 0) < 5000 then
            -- il descend du véhicule
        elseif h.role == 'pilot' then
            if engaged then
                if h.mode ~= 'heli' or not running(ped, 'heli') then
                    TaskHeliChase(ped, me, 0.0, 0.0, 35.0)
                    h.mode = 'heli'
                end
            elseif calm then
                -- neutres : il tourne au-dessus du secteur
                if h.mode ~= 'heliCalm' or not running(ped, 'heliMission') or now - (h.taskAt or 0) > 15000 then
                    local p = GH.around(myPos, 40.0, 70.0)
                    TaskHeliMission(ped, veh, 0, 0, p.x, p.y, p.z + 50.0, 4, 15.0, 20.0, -1.0, 70, 40, -1.0, 0)
                    h.mode, h.taskAt = 'heliCalm', now
                end
            elseif h.mode ~= 'heliSearch' or not running(ped, 'heliMission') or now - (h.taskAt or 0) > 12000 then
                local p = searchPoint(s, false)
                TaskHeliMission(ped, veh, 0, 0, p.x, p.y, p.z + 40.0, 4, 20.0, 15.0, -1.0, 60, 30, -1.0, 0)
                h.mode, h.taskAt = 'heliSearch', now
            end
            SetVehicleSearchlight(veh, s.alert == 'search' or isNight(), true)
        elseif h.role == 'gunner' then
            if engaged then
                if h.mode ~= 'combat' or not running(ped, 'combat') then combat(h, me) end
            elseif h.mode ~= 'ride' then
                ClearPedTasks(ped)
                h.mode = 'ride'
            end
        elseif h.role == 'driver' then
            if not IsVehicleDriveable(veh, false) then
                dismountCrew(s, veh, now, engaged)
            elseif calm then
                -- neutres : ils viennent près de lui, se garent et descendent (sans l'attaquer)
                if d <= (Passive.ApproachDistance or 40.0) then
                    dismountCrew(s, veh, now, false)
                elseif h.mode ~= 'approach' or not running(ped, 'drive') or #(h.target - myPos) > 25.0 then
                    driveTo(h, veh, myPos, Config.SearchDriveSpeed or 14.0, 20.0, 'approach')
                end
            elseif engaged and meInVehicle then
                if h.mode ~= 'chase' or not running(ped, 'chase') then chase(h, veh, me) end
            elseif engaged then
                -- le joueur est à pied : on fonce vers lui, arrivés sur zone tout le monde descend
                if d <= (Config.DismountDistance or 35.0) then
                    dismountCrew(s, veh, now, true)
                elseif h.mode ~= 'drive' or not running(ped, 'drive') or #(h.target - myPos) > 15.0 then
                    driveTo(h, veh, myPos, Config.DriveSpeed or 35.0, 10.0, 'drive')
                end
            elseif h.mode ~= 'searchDrive' or not running(ped, 'drive') or #(GetEntityCoords(ped) - h.target) < 15.0 then
                driveTo(h, veh, searchPoint(s, true), Config.SearchDriveSpeed or 14.0, 8.0, 'searchDrive')
            end
        elseif h.role == 'passenger' then
            local driver = GetPedInVehicleSeat(veh, -1)
            if driver == 0 or IsPedDeadOrDying(driver, true) or not IsVehicleDriveable(veh, false) then
                dismount(h, veh, now, engaged)
            elseif engaged then
                if h.mode ~= 'combat' or not running(ped, 'combat') then combat(h, me) end -- tirs depuis le véhicule
            elseif h.mode ~= 'ride' then
                ClearPedTasks(ped)
                h.mode = 'ride'
            end
        else -- à pied
            -- pas de nouveau véhicule juste après en être descendu (5 s) ou en avoir repris un (15 s)
            local recent = (h.remountAt and now - h.remountAt < 15000) or (h.dismountAt and now - h.dismountAt < 5000)
            if calm then
                -- neutres : ils restent autour de lui (s'approchent s'il s'éloigne, flânent sinon)
                if d > (Config.FarDistance or 160.0) and not recent then
                    far[#far + 1] = h
                elseif d > (Passive.FollowDistance or 90.0) then
                    if h.mode ~= 'approach' or not running(ped, 'nav') or #(h.target - myPos) > 15.0 then
                        local p = GH.around(myPos, 15.0, 25.0)
                        ClearPedTasks(ped)
                        TaskFollowNavMeshToCoord(ped, p.x, p.y, p.z, 1.0, -1, 3.0, false, 0)
                        h.mode, h.target = 'approach', myPos
                    end
                elseif h.mode ~= 'calm' then
                    local p = GetEntityCoords(ped)
                    if h.area then RemovePedDefensiveArea(ped, false) h.area = nil end
                    ClearPedTasks(ped)
                    TaskWanderInArea(ped, p.x, p.y, p.z, Passive.WanderRadius or 15.0, 2.0, 4.0)
                    h.mode = 'calm'
                end
            elseif engaged then
                local tooFar = d > (Config.FarDistance or 160.0) or (meInVehicle and d > (Config.VehicleChaseDistance or 70.0))
                if tooFar and not recent then
                    far[#far + 1] = h
                elseif not meInVehicle and d <= meleeDistance and now - (h.meleeAt or 0) > meleeCooldown
                    and not IsPedInMeleeCombat(ped) then
                    -- tout près : corps à corps
                    TaskPutPedDirectlyIntoMelee(ped, me, 0.0, -1.0, 0.0, 0)
                    h.meleeAt, h.mode = now, 'combat'
                elseif d > (Config.ConvergeDistance or 60.0) then
                    -- radio : ils savent où il est, ceux qui sont loin foncent vers lui en courant
                    if h.mode ~= 'converge' or not running(ped, 'goTo') then
                        TaskGoToEntity(ped, me, -1, (Config.ConvergeDistance or 60.0) * 0.5, 3.0, 1073741824, 0)
                        h.mode = 'converge'
                    end
                else
                    -- combat en avançant sur lui : zone de combat centrée sur SA position (comme la police du jeu),
                    -- déplacée dès qu'il bouge : ils convergent au lieu d'attendre qu'il vienne
                    if not h.area or #(h.area - myPos) > 4.0 then
                        SetPedSphereDefensiveArea(ped, myPos.x, myPos.y, myPos.z, Config.ConvergeRadius or 12.0, false, false)
                        h.area = myPos
                    end
                    if h.mode ~= 'combat' or (not IsPedInCombat(ped, me) and not running(ped, 'combat')) then
                        combat(h, me)
                    end
                end
            else
                local fromZone = #(GetEntityCoords(ped) - s.searchCenter)
                if fromZone > (Config.FarDistance or 160.0) and not recent then
                    far[#far + 1] = h
                elseif h.mode ~= 'search' or not running(ped, 'nav') or #(GetEntityCoords(ped) - h.target) < 4.0 then
                    local p = searchPoint(s, false)
                    if h.area then RemovePedDefensiveArea(ped, false) h.area = nil end
                    ClearPedTasks(ped)
                    TaskFollowNavMeshToCoord(ped, p.x, p.y, p.z, 2.0, -1, 1.0, false, 0)
                    h.mode, h.target = 'search', p
                end
            end
        end
    end

    -- 4. grenades (repéré, à pied, à portée et en vue)
    if engaged and s.grenades and now >= (s.nextGrenade or 0) then
        local R = (Config.Grenades or {}).Range or { 8.0, 40.0 }
        local candidates = {}
        for _, h in ipairs(list) do
            if h.grenade and h.role == 'foot' and not h.throwUntil and h.dist >= R[1] and h.dist <= R[2] then
                candidates[#candidates + 1] = h
            end
        end
        if #candidates > 0 then
            local h = candidates[math.random(1, #candidates)]
            if HasEntityClearLosToEntity(h.ped, me, 17) then throwGrenade(s, h, myPos, now) end
        end
        s.nextGrenade = nextGrenade(now)
    end

    -- 5. à pied et loin de leur objectif : un véhicule, par équipes de 3 au plus (proches les unes des autres)
    if #far > 0 then
        local used = {}
        for _, h in ipairs(far) do
            if not used[h] and S() == s then
                local crew = { h }
                used[h] = true
                local hp = GetEntityCoords(h.ped)
                for _, o in ipairs(far) do
                    if #crew >= 3 then break end
                    if not used[o] and #(GetEntityCoords(o.ped) - hp) < 20.0 then crew[#crew + 1] = o; used[o] = true end
                end
                GH.remount(crew)
            end
        end
    end
    return alive
end

--- Nouvelle vague : neutre (option « Neutres », tant qu'il ne les attaque pas) ; sinon la faction sait où il est
function GH.alertNewWave(s, now)
    s.nextGrenade = nextGrenade(now)
    if s.passive and not s.provoked then
        if s.alert ~= 'calm' then GH.calm(s) end
        return
    end
    s.lkp, s.lastSeen = GetEntityCoords(PlayerPedId()), now
    if s.alert ~= 'engaged' then engage(s, now, true) end
end

--- Tous les ennemis présents éliminés (option « Neutres ») : la vague suivante arrivera neutre
function GH.allDown(s)
    if s.passive and s.provoked then
        s.provoked = false
        GH.calm(s)
    end
end
