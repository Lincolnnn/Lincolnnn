--[[
    Vehicle Control - plein d'essence (client) : pompe avec un vrai pistolet, jerrican
    ---------------------------------------------------------------------------------
    POMPE :
      1. à pied, près d'une pompe : E "Prendre le pistolet" (vrai pistolet en main, relié à la pompe par un tuyau
         vu par tous les joueurs proches) ;
      2. aller à la TRAPPE À ESSENCE du véhicule, toujours côté ARRIÈRE GAUCHE (repère vert au sol de la trappe) ;
         moteur COUPÉ obligatoire (le joueur est forcément descendu : on ne prend pas le pistolet à bord) ;
         E "Mettre le pistolet dans la trappe" : il reste dans la trappe (sur la carrosserie, bec vers l'intérieur) et le
         plein se fait tout seul ;
      3. plein : de vide à plein en Fuel.RefuelPerSecond (1 minute au maximum) ; s'arrête tout seul réservoir plein,
         ou moteur allumé ; plein fini : un seul message, "E pour ranger le pistolet" (il retourne à la pompe). Pistolet
         en main, loin d'une trappe : E le range aussi (vc_nozzle : réglage en jeu de sa position dans la trappe).
      - Tuyau trop court (HoseLength m) ou véhicule qui part avec le pistolet : le pistolet retourne à la pompe.
      - Pistolet en main : impossible de monter dans un véhicule, de frapper ou de viser.
    JERRICAN (WEAPON_PETROLCAN) : rempli à la pompe (G) ou pris dans l'équipement d'un véhicule de police
      (rp_equipment). Plein, il remplit JerrycanFuel % d'un réservoir (2/5) ; en main près de la trappe : E "Verser".
    Performance : à pied, recherche d'une pompe toutes les 500 ms (boucle de main.lua) ; boucle à chaque image
    uniquement près d'une pompe, pistolet sorti ou jerrican en main. Tuyaux des autres joueurs : aucun boucle
    (état du joueur "vcHose").
]]

local Config = VCConfig.Fuel
local Nozzle = Config.Nozzle or {}
local PETROLCAN = GetHashKey('WEAPON_PETROLCAN')
local UNARMED = GetHashKey('WEAPON_UNARMED')
local FLARE = GetHashKey('WEAPON_FLARE')
local CAN_AMMO = 4500 -- jerrican plein
local NOZZLE_MODEL = GetHashKey(Nozzle.Model or 'prop_cs_fuel_nozle')
local HOSE = Nozzle.HoseLength or 7.0
local FLAP_DISTANCE = Config.FlapDistance or 1.3
local POUR_ANIM = { 'weapon@w_sp_jerrycan', 'fire' }
local FILL_CAN_ANIM = { 'timetable@gardener@filling_can', 'gar_ig_5_filling_can' }
local HAND_ANIM = { 'anim@am_hold_up@male', 'shoplift_high' }

local nozzle = nil   -- pistolet sorti : { prop, pump, pumpPos, rope, vehicle (dans la trappe), at, fuel, lastSend, stopped }
local pouring = nil  -- jerrican versé : { vehicle, fuel, lastSend, debt }
local fillingCan = nil -- jerrican rempli à la pompe : heure de fin
local active = false

-- =========================================================================
-- OUTILS
-- =========================================================================
local pumpHashes = {}
for _, model in ipairs(Config.PumpModels) do pumpHashes[#pumpHashes + 1] = GetHashKey(model) end

local function nearestPump(pos, range)
    for _, hash in ipairs(pumpHashes) do
        local pump = GetClosestObjectOfType(pos.x, pos.y, pos.z, range or Config.PumpDistance, hash, false, false, false)
        if pump ~= 0 then return pump end
    end
    return nil
end

local function help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function playAnim(ped, anim, flag, duration)
    if loadDict(anim[1]) then TaskPlayAnim(ped, anim[1], anim[2], 4.0, 4.0, duration or -1, flag or 48, 0, false, false, false) end
end

-- Carrosserie à la trappe (côté gauche), par modèle : le cadre du modèle déborde (rétroviseurs, roues) ; un rayon
-- tiré depuis l'extérieur vers le véhicule trouve la vraie tôle. [modèle] = x local de la carrosserie
local bodyX = {}

local function bodySurfaceX(vehicle, minX, y, z)
    local model = GetEntityModel(vehicle)
    if bodyX[model] then return bodyX[model] end
    local from = GetOffsetFromEntityInWorldCoords(vehicle, minX - 0.6, y, z)
    local to = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, y, z)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, -1, PlayerPedId(), 4)
    local _, hit, coords, _, entity = GetShapeTestResult(ray)
    if (hit == true or hit == 1) and entity == vehicle then
        local x = GetOffsetFromEntityGivenWorldCoords(vehicle, coords.x, coords.y, coords.z).x
        bodyX[model] = math.max(minX, math.min(x, -0.2))
        return bodyX[model]
    end
    return minX + 0.12 -- rayon gêné (autre véhicule…) : estimation, réessayé la prochaine fois
end

--- Trappe à essence : toujours à l'ARRIÈRE GAUCHE du véhicule, sur la carrosserie (position dans le monde, et par
--- rapport au véhicule)
function VC.flapPosition(vehicle)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local flap = Config.Flap or {}
    local y = min.y + (max.y - min.y) * (flap.Y or 0.22)
    local z = min.z + (max.z - min.z) * (flap.Z or 0.5)
    local x = bodySurfaceX(vehicle, min.x, y, z)
    return GetOffsetFromEntityInWorldCoords(vehicle, x, y, z), vector3(x, y, z)
end

--- Véhicule (avec réservoir) dont la trappe est la plus proche, à moins de `range` m
local function vehicleAtFlap(pos, range)
    local best, bestDistance = nil, range
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(vehicle) - pos) < 8.0 and VC.hasTank(vehicle) then
            local d = #(VC.flapPosition(vehicle) - pos)
            if d <= bestDistance then best, bestDistance = vehicle, d end
        end
    end
    return best
end

local function fuelOf(vehicle)
    local fuel = VC.fuel(vehicle)
    if fuel == nil then fuel = VC.initialFuel(vehicle) end
    return fuel
end

local function canPercent(ped)
    return math.floor(GetAmmoInPedWeapon(ped, PETROLCAN) / CAN_AMMO * 100 + 0.5)
end

--- Repère de la trappe (petit cône vert), quand le joueur tient le pistolet ou le jerrican
local function markFlap(vehicle)
    local p = VC.flapPosition(vehicle)
    DrawMarker(0, p.x, p.y, p.z + 0.35, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.18, 0.18, 0.18, 80, 200, 120, 160, false, true, 2, false, nil, nil, false)
end

-- =========================================================================
-- TUYAU (corde entre la pompe et le pistolet), créé par chaque client
-- =========================================================================
local function pumpAt(pos)
    return nearestPump(pos, 2.5)
end

local function makeRope(pump, pumpPos, prop)
    if Nozzle.Rope == false or not pump or not DoesEntityExist(prop) then return nil end
    RopeLoadTextures()
    local timeout = GetGameTimer() + 1000
    while not RopeAreTexturesLoaded() and GetGameTimer() < timeout do Wait(0) end
    local rope = AddRope(pumpPos.x, pumpPos.y, pumpPos.z, 0.0, 0.0, 0.0, 3.0, 1, HOSE, 0.0, 1.0, false, false, false, 1.0, true)
    if not rope then return nil end
    ActivatePhysics(rope)
    local tip = GetOffsetFromEntityInWorldCoords(prop, 0.0, -0.033, -0.195)
    AttachEntitiesToRope(rope, pump, prop, pumpPos.x, pumpPos.y, pumpPos.z, tip.x, tip.y, tip.z, HOSE, false, false, nil, nil)
    return rope
end

local function attachToHand(ped, prop)
    local h = Nozzle.Hand or { 0.13, 0.04, 0.01, -42.0, -115.0, -63.42 }
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 18905), h[1], h[2], h[3], h[4], h[5], h[6], false, true, false, true, 0, true)
end

local function publishHose()
    if nozzle and NetworkGetEntityIsNetworked(nozzle.prop) then
        local p = nozzle.pumpPos
        LocalPlayer.state:set('vcHose', { x = p.x, y = p.y, z = p.z, net = ObjToNet(nozzle.prop) }, true)
    else
        LocalPlayer.state:set('vcHose', false, true)
    end
end

-- =========================================================================
-- PISTOLET
-- =========================================================================
local function sendNow(vehicle, fuel, reason)
    if not DoesEntityExist(vehicle) then return end
    VC.sendFuel(vehicle, fuel, reason)
    VC.refueled(vehicle, fuel)
end

local function takeNozzle(pump)
    local ped = PlayerPedId()
    RequestModel(NOZZLE_MODEL)
    local timeout = GetGameTimer() + 2000
    while not HasModelLoaded(NOZZLE_MODEL) and GetGameTimer() < timeout do Wait(10) end
    if not HasModelLoaded(NOZZLE_MODEL) then return VC.chat('Pistolet de la pompe introuvable (modèle).') end
    SetCurrentPedWeapon(ped, UNARMED, true)
    TaskTurnPedToFaceEntity(ped, pump, 500)
    playAnim(ped, HAND_ANIM, 48, 700)
    local pos = GetEntityCoords(ped)
    local prop = CreateObject(NOZZLE_MODEL, pos.x, pos.y, pos.z + 0.2, true, true, false)
    SetModelAsNoLongerNeeded(NOZZLE_MODEL)
    attachToHand(ped, prop)
    local pumpPos = GetOffsetFromEntityInWorldCoords(pump, 0.0, 0.0, Nozzle.PumpHeight or 1.2)
    nozzle = { prop = prop, pump = pump, pumpPos = pumpPos }
    nozzle.rope = makeRope(pump, pumpPos, prop)
    publishHose()
end

--- Plein en cours : dernière valeur envoyée
local function stopFilling()
    if not nozzle or not nozzle.vehicle then return end
    sendNow(nozzle.vehicle, nozzle.fuel, 'pump')
    nozzle.vehicle = nil
end

--- Pistolet raccroché (ou retourné tout seul à la pompe)
local function hangUp(text)
    if not nozzle then return end
    stopFilling()
    if nozzle.rope then DeleteRope(nozzle.rope) end
    if DoesEntityExist(nozzle.prop) then
        DetachEntity(nozzle.prop, true, true)
        DeleteEntity(nozzle.prop)
    end
    nozzle = nil
    publishHose()
    if text then VC.chat(text) end
end

--- Pistolet dans la trappe : sur la carrosserie, bec vers l'intérieur (Nozzle.InFlap : décalage x y z, rotation)
local function attachInFlap(vehicle)
    local _, offset = VC.flapPosition(vehicle)
    local o = Nozzle.InFlap or { -0.10, 0.0, 0.05, -125.0, -90.0, -90.0 }
    DetachEntity(nozzle.prop, true, true)
    AttachEntityToEntity(nozzle.prop, vehicle, 0, offset.x + o[1], offset.y + o[2], offset.z + o[3], o[4], o[5], o[6],
        false, false, false, false, Nozzle.RotationOrder or 1, true)
end

local function insertNozzle(vehicle)
    local ped = PlayerPedId()
    if GetIsVehicleEngineRunning(vehicle) then return VC.chat('Coupez le moteur avant de faire le plein.') end
    local fuel = fuelOf(vehicle)
    if fuel >= 99.5 then return VC.chat('Le réservoir est déjà plein.') end
    local flap = VC.flapPosition(vehicle)
    TaskTurnPedToFaceCoord(ped, flap.x, flap.y, flap.z, 500)
    playAnim(ped, HAND_ANIM, 48, 700)
    attachInFlap(vehicle)
    nozzle.vehicle, nozzle.fuel, nozzle.at = vehicle, fuel, GetEntityCoords(vehicle)
    nozzle.lastSend, nozzle.stopped = GetGameTimer(), false
end

-- Réglage en jeu de la position du pistolet dans la trappe (essais) : vc_nozzle x y z rx ry rz [ordre]
-- Les valeurs à recopier dans config.lua (Fuel.Nozzle.InFlap / RotationOrder) sont affichées dans la console F8.
RegisterCommand('vc_nozzle', function(_, args)
    local v = {}
    for i = 1, 6 do v[i] = tonumber(args[i]) end
    if not v[6] then
        local o = Nozzle.InFlap or {}
        return print(('[rp_vehiclecontrol] InFlap = { %s }, RotationOrder = %s (usage : vc_nozzle x y z rx ry rz [ordre])')
            :format(table.concat(o, ', '), tostring(Nozzle.RotationOrder or 1)))
    end
    Nozzle.InFlap = v
    if tonumber(args[7]) then Nozzle.RotationOrder = math.floor(tonumber(args[7])) end
    if nozzle and nozzle.vehicle and DoesEntityExist(nozzle.vehicle) then attachInFlap(nozzle.vehicle) end
    print(('[rp_vehiclecontrol] InFlap = { %s }, RotationOrder = %d'):format(table.concat(v, ', '), Nozzle.RotationOrder or 1))
end, false)

--- Plein en cours (pistolet dans la trappe), à chaque image
local function fillTick(dt)
    local vehicle = nozzle.vehicle
    if not DoesEntityExist(vehicle) then
        nozzle.vehicle = nil
        return hangUp('Véhicule disparu : pistolet raccroché.')
    end
    if #(GetEntityCoords(vehicle) - nozzle.at) > 1.5 or #(VC.flapPosition(vehicle) - nozzle.pumpPos) > HOSE + 1.0 then
        return hangUp('Le véhicule est parti avec le pistolet : il est retourné à la pompe.')
    end
    if nozzle.stopped then return end
    if GetIsVehicleEngineRunning(vehicle) then
        nozzle.stopped = true
        sendNow(vehicle, nozzle.fuel, 'pump')
        return VC.chat(('Moteur allumé : plein interrompu (%d %%).'):format(math.floor(nozzle.fuel)))
    end
    nozzle.fuel = math.min(100.0, nozzle.fuel + Config.RefuelPerSecond * dt)
    local now = GetGameTimer()
    if nozzle.fuel >= 100.0 then
        nozzle.stopped = true
        sendNow(vehicle, 100.0, 'pump') -- seule l'aide reste : "E pour ranger le pistolet"
    elseif now - nozzle.lastSend >= 1000 then
        nozzle.lastSend = now
        sendNow(vehicle, nozzle.fuel, 'pump')
    end
end

-- =========================================================================
-- JERRICAN
-- =========================================================================
local function stopPouring(text)
    if not pouring then return end
    local ped = PlayerPedId()
    StopAnimTask(ped, POUR_ANIM[1], POUR_ANIM[2], 1.0)
    sendNow(pouring.vehicle, pouring.fuel, 'jerrycan')
    if text then VC.chat(text) end
    pouring = nil
end

local function startPouring(vehicle)
    local ped = PlayerPedId()
    if GetIsVehicleEngineRunning(vehicle) then return VC.chat('Coupez le moteur avant de faire le plein.') end
    if GetAmmoInPedWeapon(ped, PETROLCAN) <= 0 then return VC.chat('Le jerrican est vide.') end
    local fuel = fuelOf(vehicle)
    if fuel >= 99.5 then return VC.chat('Le réservoir est déjà plein.') end
    local flap = VC.flapPosition(vehicle)
    TaskTurnPedToFaceCoord(ped, flap.x, flap.y, flap.z, 500)
    playAnim(ped, POUR_ANIM, 49)
    pouring = { vehicle = vehicle, fuel = fuel, lastSend = GetGameTimer(), debt = 0.0 }
end

local function pourTick(ped, pos, dt)
    local vehicle = pouring.vehicle
    if not DoesEntityExist(vehicle) or #(VC.flapPosition(vehicle) - pos) > FLAP_DISTANCE + 1.0 then return stopPouring() end
    if GetSelectedPedWeapon(ped) ~= PETROLCAN then return stopPouring() end
    if GetIsVehicleEngineRunning(vehicle) then return stopPouring('Moteur allumé : arrêté.') end
    local ammo = GetAmmoInPedWeapon(ped, PETROLCAN)
    if ammo <= 0 then return stopPouring(('Jerrican vide : réservoir à %d %%.'):format(math.floor(pouring.fuel))) end
    local add = (Config.JerrycanPerSecond or 4.0) * dt
    pouring.debt = pouring.debt + add * CAN_AMMO / Config.JerrycanFuel
    if pouring.debt >= 1.0 then
        local used = math.floor(pouring.debt)
        pouring.debt = pouring.debt - used
        SetPedAmmo(ped, PETROLCAN, math.max(0, ammo - used))
    end
    pouring.fuel = math.min(100.0, pouring.fuel + add)
    if pouring.fuel >= 100.0 then return stopPouring('Réservoir plein.') end
    local now = GetGameTimer()
    if now - pouring.lastSend >= 1000 then
        pouring.lastSend = now
        sendNow(vehicle, pouring.fuel, 'jerrycan')
    end
end

-- =========================================================================
-- BOUCLE : près d'une pompe, pistolet sorti ou jerrican en main (à chaque image, seulement ici)
-- =========================================================================
local function stationLoop()
    active = true
    CreateThread(function()
        local nextScan, flapVehicle, nearVehicle, pump = 0, nil, nil, nil
        while true do
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local dt = GetFrameTime()
            local now = GetGameTimer()
            local onFoot = not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped)

            if now >= nextScan then
                nextScan = now + 250
                pump = nearestPump(pos, Config.PumpDistance + 0.5)
                flapVehicle = vehicleAtFlap(pos, FLAP_DISTANCE)
                nearVehicle = (nozzle or Config.Jerrycan) and vehicleAtFlap(pos, 5.0) or nil -- repère de la trappe
            end
            local holdingCan = Config.Jerrycan and GetSelectedPedWeapon(ped) == PETROLCAN

            -- Pistolet dans une trappe : le plein avance, même si le joueur s'éloigne (longueur du tuyau)
            if nozzle and nozzle.vehicle then fillTick(dt) end
            -- Pistolet en main : tuyau trop court, ou joueur monté dans un véhicule / mort
            if nozzle and not nozzle.vehicle then
                if not onFoot then
                    hangUp('Pistolet raccroché.')
                elseif #(pos - nozzle.pumpPos) > HOSE + 0.5 then
                    hangUp('Tuyau trop court : le pistolet est retourné à la pompe.')
                end
            end
            if pouring then
                if not onFoot then stopPouring() else pourTick(ped, pos, dt) end
            end

            local pressed = onFoot and IsControlJustPressed(0, 38) -- E
            local lines = {}
            if onFoot and fillingCan then
                lines[#lines + 1] = 'Remplissage du jerrican…'
                if now >= fillingCan then
                    fillingCan = nil
                    StopAnimTask(ped, FILL_CAN_ANIM[1], FILL_CAN_ANIM[2], 1.0)
                    if HasPedGotWeapon(ped, PETROLCAN, false) then SetPedAmmo(ped, PETROLCAN, CAN_AMMO)
                    else GiveWeaponToPed(ped, PETROLCAN, CAN_AMMO, false, true) end
                    VC.chat(('Jerrican rempli (de quoi remplir %d %% d\'un réservoir).'):format(math.floor(Config.JerrycanFuel)))
                end
            elseif onFoot and nozzle and not nozzle.vehicle then
                -- Pistolet en main : ni monter dans un véhicule, ni frapper, ni viser
                DisableControlAction(0, 23, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                if nearVehicle then markFlap(nearVehicle) end
                if flapVehicle then
                    local fuel = fuelOf(flapVehicle)
                    if GetIsVehicleEngineRunning(flapVehicle) then
                        lines[#lines + 1] = 'Coupez le moteur du véhicule pour faire le plein.'
                    elseif fuel >= 99.5 then
                        lines[#lines + 1] = 'Réservoir plein.'
                    else
                        lines[#lines + 1] = ('~INPUT_CONTEXT~ Mettre le pistolet dans la trappe (%d %%)'):format(math.floor(fuel))
                        if pressed then insertNozzle(flapVehicle) end
                    end
                else
                    -- Ailleurs : E le range (il retourne à la pompe)
                    lines[#lines + 1] = '~INPUT_CONTEXT~ pour ranger le pistolet'
                    if pressed then
                        playAnim(ped, HAND_ANIM, 48, 700)
                        hangUp()
                    end
                end
            elseif onFoot and nozzle and nozzle.vehicle then
                -- Pistolet dans la trappe : E le range (plein arrêté s'il n'est pas fini) ; plein fini : seul ce message
                if #(GetEntityCoords(nozzle.vehicle) - pos) < 8.0 then
                    if not (nozzle.stopped and nozzle.fuel >= 100.0) then
                        lines[#lines + 1] = ('%s : %d %%'):format(nozzle.stopped and 'Plein interrompu' or 'Plein en cours', math.floor(nozzle.fuel))
                    end
                    lines[#lines + 1] = '~INPUT_CONTEXT~ pour ranger le pistolet'
                    if pressed then
                        playAnim(ped, HAND_ANIM, 48, 700)
                        hangUp()
                    end
                end
            elseif onFoot and pouring then
                lines[#lines + 1] = ('Jerrican : réservoir %d %% · jerrican %d %%~n~~INPUT_CONTEXT~ Arrêter'):format(math.floor(pouring.fuel), canPercent(ped))
                if pressed then stopPouring() end
            elseif onFoot then
                if holdingCan and flapVehicle then
                    markFlap(flapVehicle)
                    lines[#lines + 1] = ('~INPUT_CONTEXT~ Verser le jerrican (réservoir %d %% · jerrican %d %%)'):format(math.floor(fuelOf(flapVehicle)), canPercent(ped))
                    if pressed then startPouring(flapVehicle) end
                elseif holdingCan and nearVehicle then
                    markFlap(nearVehicle)
                end
                if pump then
                    if not holdingCan then
                        lines[#lines + 1] = '~INPUT_CONTEXT~ Prendre le pistolet'
                        if pressed then takeNozzle(pump) end
                    end
                    if Config.Jerrycan then
                        local full = holdingCan and GetAmmoInPedWeapon(ped, PETROLCAN) >= CAN_AMMO
                        if not full then
                            lines[#lines + 1] = holdingCan and '~INPUT_DETONATE~ Remplir le jerrican' or '~INPUT_DETONATE~ Prendre un jerrican'
                            -- G (sauf fusée de détresse en main : G la pose, rp_flares)
                            if IsControlJustPressed(0, 47) and GetSelectedPedWeapon(ped) ~= FLARE
                                and not LocalPlayer.state.rpCarryingCone then -- (G pose aussi un plot porté : rp_equipment)
                                playAnim(ped, FILL_CAN_ANIM, 49, Config.JerrycanFillTime or 3000)
                                fillingCan = now + (Config.JerrycanFillTime or 3000)
                            end
                        end
                    end
                end
            end
            if #lines > 0 then help(table.concat(lines, '~n~')) end
            -- Action d'essence proposée sur E (état LOCAL du joueur, non envoyé) : rp_equipment ne réagit pas à E
            local prompting = false
            for _, line in ipairs(lines) do
                if line:find('~INPUT_CONTEXT~', 1, true) then prompting = true break end
            end
            if prompting ~= (LocalPlayer.state.vcFuelPrompt == true) then LocalPlayer.state:set('vcFuelPrompt', prompting, false) end

            if not nozzle and not pouring and not fillingCan and not pump and not holdingCan then break end
            Wait(0)
        end
        if LocalPlayer.state.vcFuelPrompt then LocalPlayer.state:set('vcFuelPrompt', false, false) end
        active = false
    end)
end

VC.on('idle', function(ped)
    if active or IsEntityDead(ped) then return end
    if nozzle or nearestPump(GetEntityCoords(ped), Config.PumpDistance + 0.5)
        or (Config.Jerrycan and GetSelectedPedWeapon(ped) == PETROLCAN) then
        stationLoop()
    end
end)

-- =========================================================================
-- TUYAUX DES AUTRES JOUEURS (état du joueur "vcHose" : pompe + pistolet)
-- =========================================================================
local ropes = {} -- [nom du state bag] = corde

AddStateBagChangeHandler('vcHose', nil, function(bagName, _, value)
    local serverId = tonumber(bagName:match('^player:(%d+)$'))
    if not serverId or serverId == GetPlayerServerId(PlayerId()) then return end
    if ropes[bagName] then
        DeleteRope(ropes[bagName])
        ropes[bagName] = nil
    end
    if type(value) ~= 'table' or not value.net then return end
    CreateThread(function()
        local pumpPos = vector3(value.x + 0.0, value.y + 0.0, value.z + 0.0)
        if #(GetEntityCoords(PlayerPedId()) - pumpPos) > 120.0 then return end
        local timeout, prop = GetGameTimer() + 3000, 0
        while GetGameTimer() < timeout do
            prop = NetworkDoesNetworkIdExist(value.net) and NetToObj(value.net) or 0
            if prop ~= 0 then break end
            Wait(100)
        end
        if prop == 0 then return end
        ropes[bagName] = makeRope(pumpAt(pumpPos), pumpPos, prop)
    end)
end)

-- Ressource arrêtée : pistolet et tuyaux retirés
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if nozzle then
        if nozzle.rope then DeleteRope(nozzle.rope) end
        if DoesEntityExist(nozzle.prop) then DeleteEntity(nozzle.prop) end
        LocalPlayer.state:set('vcHose', false, true)
    end
    for _, rope in pairs(ropes) do DeleteRope(rope) end
end)
