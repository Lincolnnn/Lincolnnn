--[[
    RP Ganghunt - client : les vagues
    ---------------------------------
    Le joueur qui lance la chasse fait apparaître les ennemis lui-même (il en garde le contrôle réseau : ils ne
    passent pas à un autre joueur, leur ordre « traquer » n'est jamais perdu) :
      - une vague = WaveSize ennemis (10) : hélicoptère (pilote + 2 tireurs) s'il est choisi, le reste en véhicules
        de la faction (4 par véhicule au plus) s'ils sont choisis, sinon à pied ; hors de vue, à 90-150 m ;
      - chacun a une arme de poing : seulement elle si le joueur a choisi une arme de poing, sinon une arme longue
        (répartie selon les pourcentages choisis, ou au hasard dans les armes de la faction) + le pistolet de combat ;
      - même groupe pour tous : ils ne s'entretuent pas (ni tir ami) ; hostiles aux joueurs ;
      - AUCUN PÉRIMÈTRE : vue / ouïe très longues, jamais de fuite ; toutes les secondes, chacun est relancé sur le
        joueur s'il le perd. À pied et trop loin (ou le joueur part en véhicule), ils reçoivent un véhicule de leur
        faction et le poursuivent ; un véhicule poursuit à pleine vitesse (passagers : tirs) ; près du joueur à pied,
        ils descendent et combattent ; l'hélicoptère le suit et ses tireurs tirent ;
      - vague éliminée : la suivante quelques secondes plus tard ; dernière vague éliminée : chasse réussie ;
        joueur mort ou /ganghunt stop : chasse terminée, tous les ennemis et leurs véhicules retirés.
    Performance : aucune chasse -> aucune boucle. Pendant une chasse : une vérification par seconde.
]]

GH = GH or {}
local Config = GanghuntConfig

local session = nil
local GROUP_NAME = 'RP_GANGHUNT'
local PLAYER_GROUP = GetHashKey('PLAYER')
local group = nil

local TASK_COMBAT = GetHashKey('SCRIPT_TASK_COMBAT')
local TASK_CHASE = GetHashKey('SCRIPT_TASK_VEHICLE_CHASE')
local TASK_HELI = GetHashKey('SCRIPT_TASK_HELI_CHASE')

local WEAPON_INFO = {}
for _, w in ipairs(Config.Weapons) do WEAPON_INFO[w.name] = w end

function GH.active() return session ~= nil end
function GH.session() return session end

local function notify(text)
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started'
        and pcall(function() exports[chat]:addPrivate({ title = 'Ganghunt', text = text }) end) then
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end
GH.notify = notify

local function hud()
    if not session then return SendNUIMessage({ action = 'hud', data = { show = false } }) end
    local alive = 0
    for _, h in pairs(session.hunters) do if not h.dead then alive = alive + 1 end end
    SendNUIMessage({ action = 'hud', data = { show = true, faction = session.faction.label, wave = session.wave,
        waves = session.waves, alive = alive, waiting = session.waiting } })
end

--- Chargement d'un modèle ; faux aussi si la chasse a été arrêtée (ou relancée) pendant l'attente
local function loadModel(hash)
    if not IsModelInCdimage(hash) then return false end
    local s = session
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    if session ~= s or not s then SetModelAsNoLongerNeeded(hash) return false end
    return HasModelLoaded(hash)
end

-- =========================================================================
-- GROUPE : ils ne s'entretuent pas, hostiles aux joueurs
-- =========================================================================
local function ensureGroup()
    if group then return group end
    local _, hash = AddRelationshipGroup(GROUP_NAME)
    group = hash
    SetRelationshipBetweenGroups(0, group, group)          -- entre eux : compagnons
    SetRelationshipBetweenGroups(5, group, PLAYER_GROUP)   -- les joueurs : ennemis
    SetRelationshipBetweenGroups(5, PLAYER_GROUP, group)
    return group
end

-- =========================================================================
-- ARMES : répartition choisie (pourcentages) ou au hasard dans celles de la faction
-- =========================================================================
local function pickWeapon()
    local list = session.weapons
    if not list or #list == 0 then
        local pool = session.faction.random or { 'WEAPON_PISTOL' }
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

local function arm(ped)
    local weapon = pickWeapon()
    local info = WEAPON_INFO[weapon]
    if info and info.handgun then
        GiveWeaponToPed(ped, GetHashKey(weapon), 500, false, true)           -- arme de poing seule
    else
        GiveWeaponToPed(ped, GetHashKey(Config.DefaultSidearm or 'WEAPON_COMBATPISTOL'), 250, false, false)
        GiveWeaponToPed(ped, GetHashKey(weapon), 999, false, true)           -- arme longue en main
    end
    SetPedDropsWeaponsWhenDead(ped, false)
end

-- =========================================================================
-- ENNEMIS
-- =========================================================================
local function noMigrate(entity)
    if NetworkGetEntityIsNetworked(entity) then
        local net = NetworkGetNetworkIdFromEntity(entity)
        SetNetworkIdCanMigrate(net, false)
        SetNetworkIdExistsOnAllMachines(net, true)
        return net
    end
end

--- Réglages « traqueur » : jamais de fuite, perception très longue, combat offensif
local function setupHunter(ped)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedRelationshipGroupHash(ped, ensureGroup())
    SetCanAttackFriendly(ped, false, false)
    SetEntityMaxHealth(ped, Config.Health or 200)
    SetEntityHealth(ped, Config.Health or 200)
    SetPedArmour(ped, session.faction.armour or Config.Armour or 0)
    SetPedAccuracy(ped, Config.Accuracy or 35)
    SetPedCombatAbility(ped, 2)             -- professionnel
    SetPedCombatRange(ped, 2)               -- loin
    SetPedCombatMovement(ped, 2)            -- avance
    SetPedFleeAttributes(ped, 0, false)
    for _, attribute in ipairs({ 0, 1, 2, 3, 5, 21, 46, 52, 58 }) do SetPedCombatAttributes(ped, attribute, true) end
    SetPedCombatAttributes(ped, 17, false)  -- jamais « toujours fuir »
    SetPedSeeingRange(ped, 1500.0)
    SetPedHearingRange(ped, 1500.0)
    SetPedAlertness(ped, 3)
    SetPedConfigFlag(ped, 281, true)        -- pas de blessures qui le font fuir / se rendre
    SetPedKeepTask(ped, true)
    SetPedDiesWhenInjured(ped, false)
    arm(ped)
    if Config.Blips then
        local blip = AddBlipForEntity(ped)
        SetBlipSprite(blip, 1)
        SetBlipColour(blip, 1)
        SetBlipScale(blip, 0.6)
        SetBlipAsShortRange(blip, false)
    end
    noMigrate(ped)
end

local function track(entity)
    session.entities[#session.entities + 1] = entity
    local net = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or nil
    if net then TriggerServerEvent('rp_ganghunt:track', net) end
end

local function newHunter(model, x, y, z, heading)
    local hash = GetHashKey(model)
    if not loadModel(hash) then return nil end
    local ped = CreatePed(4, hash, x, y, z, heading or 0.0, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return nil end
    setupHunter(ped)
    track(ped)
    local h = { ped = ped, role = 'foot', wave = session.wave }
    session.hunters[ped] = h
    return h
end

local function randomModel()
    local models = session.faction.models
    return models[math.random(1, #models)]
end

local function target() return PlayerPedId() end

local function combat(h)
    ClearPedTasks(h.ped)
    TaskCombatPed(h.ped, target(), 0, 16)
    h.role, h.taskAt = h.veh and h.role or 'foot', GetGameTimer()
end

local function chase(h)
    local ped, veh = h.ped, h.veh
    SetDriverAbility(ped, 1.0)
    SetDriverAggressiveness(ped, 1.0)
    TaskVehicleChase(ped, target())
    SetTaskVehicleChaseIdealPursuitDistance(ped, 0.0)
    SetTaskVehicleChaseBehaviorFlag(ped, 1, true)
    h.role, h.taskAt = 'driver', GetGameTimer()
    if veh then SetVehicleEngineOn(veh, true, true, false) end
end

-- =========================================================================
-- POSITIONS D'APPARITION (hors de vue, autour du joueur)
-- =========================================================================
local function aroundPlayer(minD, maxD)
    local p = GetEntityCoords(target())
    local angle = math.random() * math.pi * 2
    local d = minD + math.random() * (maxD - minD)
    return vector3(p.x + math.cos(angle) * d, p.y + math.sin(angle) * d, p.z)
end

--- Point de route le plus proche (et son cap) d'un point autour du joueur
local function roadNear(point)
    local found, pos, heading = GetClosestVehicleNodeWithHeading(point.x, point.y, point.z, 1, 3.0, 0)
    if found then return pos, heading end
    return point, 0.0
end

local function footSpot()
    local SD = Config.SpawnDistance or { 90.0, 150.0 }
    for _ = 1, 6 do
        local point = aroundPlayer(SD[1], SD[2])
        local ok, safe = GetSafeCoordForPed(point.x, point.y, point.z + 2.0, false, 16)
        if ok then return safe end
        local road = roadNear(point)
        if road then return road end
    end
    return aroundPlayer(SD[1], SD[2])
end

-- =========================================================================
-- VÉHICULES ET HÉLICOPTÈRE
-- =========================================================================
local function newVehicle(model, pos, heading)
    local hash = GetHashKey(model)
    if not loadModel(hash) then return nil end
    local veh = CreateVehicle(hash, pos.x, pos.y, pos.z + 0.5, heading or 0.0, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not veh or veh == 0 then return nil end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleHasBeenOwnedByPlayer(veh, false)
    SetVehicleDoorsLocked(veh, 1)
    noMigrate(veh)
    track(veh)
    return veh
end

local function seatsOf(model)
    local seats = GetVehicleModelNumberOfSeats(GetHashKey(model))
    if not seats or seats < 1 then seats = 4 end
    return math.min(4, seats)
end

--- Un véhicule de la faction, `count` ennemis à bord (ou déjà là : `hunters`), qui poursuit le joueur
local function crewVehicle(pos, heading, hunters, count)
    if not session then return 0 end
    local models = session.faction.vehicles or {}
    local model = #models > 0 and models[math.random(1, #models)] or 'baller'
    local veh = newVehicle(model, pos, heading)
    if not veh then return 0 end
    local seats = seatsOf(model)
    local placed = 0
    for seat = -1, seats - 2 do
        if not session then break end
        local h = hunters and hunters[placed + 1] or nil
        if not h and not hunters and placed < count then h = newHunter(randomModel(), pos.x, pos.y, pos.z + 1.0, heading) end
        if not h then break end
        SetPedIntoVehicle(h.ped, veh, seat)
        h.veh = veh
        h.role = seat == -1 and 'driver' or 'passenger'
        h.remountAt = GetGameTimer()
        placed = placed + 1
        if seat == -1 then chase(h) else combat(h); h.role = 'passenger' end
        if hunters == nil and placed >= count then break end
    end
    return placed
end

local function crewHeli(count)
    local model = session.faction.heli or 'maverick'
    local p = GetEntityCoords(target())
    local angle = math.random() * math.pi * 2
    local d = Config.HeliDistance or 260.0
    local pos = vector3(p.x + math.cos(angle) * d, p.y + math.sin(angle) * d, p.z + (Config.HeliHeight or 70.0))
    local heli = newVehicle(model, pos, math.deg(angle) + 90.0)
    if not heli then return 0 end
    if session.faction.heliLivery then SetVehicleLivery(heli, session.faction.heliLivery) end
    SetHeliBladesFullSpeed(heli)
    SetEntityCoordsNoOffset(heli, pos.x, pos.y, pos.z, false, false, false)
    local seats = { -1, 1, 2, 0 }
    local placed = 0
    for _, seat in ipairs(seats) do
        if not session or placed >= count or not IsVehicleSeatFree(heli, seat) and seat ~= -1 then break end
        local h = newHunter(randomModel(), pos.x, pos.y, pos.z, 0.0)
        if not h then break end
        SetPedIntoVehicle(h.ped, heli, seat)
        h.veh = heli
        placed = placed + 1
        if seat == -1 then
            h.role = 'pilot'
            TaskHeliChase(h.ped, target(), 0.0, 0.0, 35.0)
            h.taskAt = GetGameTimer()
        else
            h.role = 'gunner'
            TaskCombatPed(h.ped, target(), 0, 16)
        end
    end
    return placed
end

-- =========================================================================
-- VAGUES
-- =========================================================================
local function spawnWave(s)
    if not s or session ~= s then return end
    s.wave = s.wave + 1
    s.waiting = false
    local remaining = Config.WaveSize or 10
    if s.heli then remaining = remaining - crewHeli(math.min(3, remaining)) end
    if session ~= s then return end -- arrêtée pendant l'apparition
    if s.vehicles then
        local guard = 0
        while remaining > 0 and guard < 10 and session == s do
            guard = guard + 1
            local pos, heading = roadNear(aroundPlayer((Config.SpawnDistance or { 90, 150 })[1], (Config.SpawnDistance or { 90, 150 })[2]))
            local placed = crewVehicle(pos, heading, nil, math.min(4, remaining))
            if placed == 0 then break end
            remaining = remaining - placed
        end
    end
    -- à pied : par petits groupes au même endroit
    while remaining > 0 and session == s do
        local spot = footSpot()
        for _ = 1, math.min(remaining, 3) do
            local h = newHunter(randomModel(), spot.x + math.random(-3, 3), spot.y + math.random(-3, 3), spot.z, 0.0)
            remaining = remaining - 1
            if h then combat(h) end
        end
    end
    if session ~= s then return end
    notify(('Vague %d / %d : %s arrivent.'):format(s.wave, s.waves, s.faction.label))
    hud()
end

--- Fin de la chasse : tout est retiré (ennemis vivants ou morts, véhicules)
function GH.stop(message)
    if not session then return end
    local s = session
    session = nil
    for _, entity in ipairs(s.entities) do
        if DoesEntityExist(entity) then
            local blip = GetBlipFromEntity(entity)
            if blip and blip ~= 0 then RemoveBlip(blip) end
            SetEntityAsMissionEntity(entity, true, true)
            DeleteEntity(entity)
        end
    end
    TriggerServerEvent('rp_ganghunt:clear')
    TriggerEvent('rp_npccontrol:ganghunt', false) -- rp_NPCcontrol : « ignore player » redonné
    hud()
    if message then notify(message) end
end

-- =========================================================================
-- TRAQUE : une vérification par seconde
-- =========================================================================
local function statusOf(ped, task) return GetScriptTaskStatus(ped, task) end

--- Descente du véhicule puis combat (une fois toutes les 5 s au plus : pas de tâche relancée à chaque passage)
local function dismount(h, veh, now)
    if h.dismountAt and now - h.dismountAt < 5000 then return end
    h.dismountAt = now
    ClearPedTasks(h.ped)
    local sequence = OpenSequenceTask()
    TaskLeaveVehicle(0, veh, 256)
    TaskCombatPed(0, target(), 0, 16)
    CloseSequenceTask(sequence)
    TaskPerformSequence(h.ped, sequence)
    ClearSequenceTask(sequence)
end

--- Ennemis à pied trop loin : par groupes de 4 (proches les uns des autres), un véhicule de la faction
local function remount(far)
    local used = {}
    for _, h in ipairs(far) do
        if not used[h] then
            local crew = { h }
            used[h] = true
            local hp = GetEntityCoords(h.ped)
            for _, o in ipairs(far) do
                if #crew >= 4 then break end
                if not used[o] and #(GetEntityCoords(o.ped) - hp) < 20.0 then crew[#crew + 1] = o; used[o] = true end
            end
            local pos, heading = roadNear(hp)
            crewVehicle(pos, heading, crew, #crew)
        end
    end
end

local function manage()
    local me = target()
    local myPos = GetEntityCoords(me)
    local meInVehicle = IsPedInAnyVehicle(me, false)
    local now = GetGameTimer()
    local alive, far = 0, {}
    for ped, h in pairs(session.hunters) do
        if not DoesEntityExist(ped) then
            session.hunters[ped] = nil
        elseif h.dead then
            if now - h.dead > (Config.BodyCleanup or 20000) then
                session.hunters[ped] = nil
                SetEntityAsNoLongerNeeded(ped)
            end
        elseif IsPedDeadOrDying(ped, true) then
            h.dead = now
            local blip = GetBlipFromEntity(ped)
            if blip and blip ~= 0 then RemoveBlip(blip) end
        else
            alive = alive + 1
            local d = #(GetEntityCoords(ped) - myPos)
            local veh = GetVehiclePedIsIn(ped, false)
            if veh == 0 then h.veh = nil end
            if h.role == 'pilot' and veh ~= 0 then
                if statusOf(ped, TASK_HELI) == 7 then TaskHeliChase(ped, me, 0.0, 0.0, 35.0) end
            elseif veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and h.role ~= 'gunner' then
                -- conducteur : poursuite ; tout près du joueur à pied, ou véhicule hors d'usage : descente, combat
                if not IsVehicleDriveable(veh, false) or (d < (Config.DismountDistance or 30.0) and not meInVehicle) then
                    dismount(h, veh, now)
                elseif statusOf(ped, TASK_CHASE) == 7 and not (h.dismountAt and now - h.dismountAt < 5000) then
                    chase(h)
                end
            elseif veh ~= 0 then
                -- passager (ou tireur d'hélicoptère) : tirs ; véhicule arrêté près du joueur à pied : descente
                local driver = GetPedInVehicleSeat(veh, -1)
                local noDriver = driver == 0 or IsPedDeadOrDying(driver, true)
                local stopped = GetEntitySpeed(veh) < 2.0
                if h.role ~= 'gunner' and (noDriver or stopped and (not IsVehicleDriveable(veh, false)
                    or (d < (Config.DismountDistance or 30.0) and not meInVehicle))) then
                    dismount(h, veh, now)
                elseif statusOf(ped, TASK_COMBAT) == 7 and not (h.dismountAt and now - h.dismountAt < 5000) then
                    TaskCombatPed(ped, me, 0, 16)
                end
            else
                -- à pied : trop loin (ou le joueur part en véhicule) -> un véhicule ; sinon combat relancé s'il le perd
                local tooFar = d > (Config.FarDistance or 160.0) or (meInVehicle and d > (Config.VehicleChaseDistance or 70.0))
                if tooFar and not (h.remountAt and now - h.remountAt < 15000) then
                    far[#far + 1] = h
                elseif not IsPedInCombat(ped, me) and statusOf(ped, TASK_COMBAT) == 7 then
                    TaskCombatPed(ped, me, 0, 16)
                    h.taskAt = now
                end
            end
        end
    end
    if #far > 0 then remount(far) end
    if session then session.alive = alive end
    return alive
end

local function loop()
    local s = session
    CreateThread(function()
        while session == s do -- (une chasse arrêtée puis relancée : l'ancienne boucle s'arrête)
            if IsEntityDead(PlayerPedId()) then
                GH.stop('Vous êtes mort : la chasse est terminée.')
                break
            end
            local alive = manage()
            if session ~= s then break end
            if alive == 0 and not session.waiting then
                if session.wave >= session.waves then
                    GH.stop(('Chasse réussie : %d vague%s éliminée%s !'):format(session.waves, session.waves > 1 and 's' or '', session.waves > 1 and 's' or ''))
                    break
                end
                session.waiting = true
                notify(('Vague %d éliminée. La suivante arrive…'):format(session.wave))
                SetTimeout(Config.NextWaveDelay or 7000, function()
                    if session == s then CreateThread(function() spawnWave(s) end) end
                end)
            end
            hud()
            Wait(Config.ManagerInterval or 1000)
        end
    end)
end

--- Lance une chasse : opts = { faction, waves, weapons = { { name, pct } } | nil (aléatoire), vehicles, heli }
function GH.start(opts)
    if session then return false, 'Une chasse est déjà en cours (/ganghunt stop pour l\'arrêter).' end
    local faction = Config.Factions[opts.faction]
    if not faction then return false, 'Faction inconnue.' end
    local waves = math.max(1, math.min(Config.MaxWaves or 10, math.floor(tonumber(opts.waves) or 1)))
    local weapons = {}
    for _, w in ipairs(type(opts.weapons) == 'table' and opts.weapons or {}) do
        if #weapons >= (Config.MaxWeapons or 10) then break end
        local pct = tonumber(w.pct) or 0
        if WEAPON_INFO[w.name] and pct > 0 then weapons[#weapons + 1] = { name = w.name, pct = pct } end
    end
    session = { faction = faction, key = opts.faction, waves = waves, wave = 0, weapons = weapons,
        vehicles = opts.vehicles == true, heli = opts.heli == true, hunters = {}, entities = {} }
    TriggerEvent('rp_npccontrol:ganghunt', true) -- rp_NPCcontrol : les PNJ n'ignorent plus ce joueur
    local s = session
    CreateThread(function()
        spawnWave(s)
        if session == s then loop() end
    end)
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and session then GH.stop() end
end)
