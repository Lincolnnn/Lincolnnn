--[[
    Vehicle Control - /inspectvehicle (état du véhicule) et /fieldrepair (réparation de fortune) (client)
    ----------------------------------------------------------------------------------------------------
    /inspectvehicle : fiche de l'état du véhicule où l'on est (ou du plus proche) : moteur, carrosserie, réservoir,
      essence, pneus, roues perdues, capot / coffre / portières, pare-chocs, vitres, phares, réparations de fortune.
      Affichée Inspect.Duration ms ; la commande refaite la fait disparaître.
    /fieldrepair : à pied, devant le capot : capot ouvert, animation de FieldRepair.Duration ms (annulée en s'éloignant,
      en montant dans un véhicule, à terre) ; le serveur vérifie le nombre de réparations de fortune (Max par véhicule)
      puis le moteur remonte à FieldRepair.Engine : le véhicule roule de nouveau, puissance réduite. La carrosserie,
      les pneus et les roues ne sont pas réparés.
    Performance : rien en dehors des commandes ; une boucle à chaque image pendant la réparation seulement.
]]

local Inspect = VCConfig.Inspect or {}
local Field = VCConfig.FieldRepair or {}
local Damage = VCConfig.Damage or {}

local TYRES = { { tyre = 0, wheel = 0, label = 'Avant gauche' }, { tyre = 1, wheel = 1, label = 'Avant droit' },
    { tyre = 4, wheel = 2, label = 'Arrière gauche' }, { tyre = 5, wheel = 3, label = 'Arrière droit' } }
local DOORS = { [0] = 'Portière avant gauche', [1] = 'Portière avant droite', [2] = 'Portière arrière gauche',
    [3] = 'Portière arrière droite', [4] = 'Capot', [5] = 'Coffre' }

local function pct(value) return math.max(0, math.min(100, math.floor((value or 0.0) / 10.0 + 0.5))) end

--- État du moteur en mots
local function engineLabel(engine)
    if engine <= (Damage.Broken or 100.0) then return 'Détruit', 'bad' end
    if engine < (Damage.Critical or 300.0) then return 'Très abîmé', 'bad' end
    if engine < (Damage.Damaged or 500.0) then return 'Abîmé', 'warn' end
    if engine < 900.0 then return 'Bon', 'ok' end
    return 'Neuf', 'ok'
end

--- Toutes les informations de la fiche
function VC.inspectData(vehicle)
    local engine, body, tank = GetVehicleEngineHealth(vehicle), GetVehicleBodyHealth(vehicle), GetVehiclePetrolTankHealth(vehicle)
    local label, level = engineLabel(engine)
    local lost = {}
    for _, w in ipairs(VC.state(vehicle, 'vcWheels') or {}) do lost[w] = true end
    for w in pairs((VC.lostWheels or {})[vehicle] or {}) do lost[w] = true end
    local tyres = {}
    for _, t in ipairs(TYRES) do
        local state, lvl = 'Bon état', 'ok'
        if lost[t.wheel] then state, lvl = 'Roue arrachée', 'bad'
        elseif IsVehicleTyreBurst(vehicle, t.tyre, true) then state, lvl = 'Sur la jante', 'bad'
        elseif IsVehicleTyreBurst(vehicle, t.tyre, false) then state, lvl = 'Crevé', 'warn' end
        tyres[#tyres + 1] = { label = t.label, state = state, level = lvl }
    end
    local parts = {}
    for door = 0, 5 do
        if GetIsDoorValid(vehicle, door) then
            if IsVehicleDoorDamaged(vehicle, door) then
                parts[#parts + 1] = { label = DOORS[door], state = 'Arraché' .. ((door == 4 or door == 5) and '' or 'e'), level = 'bad' }
            elseif GetVehicleDoorAngleRatio(vehicle, door) > 0.05 then
                parts[#parts + 1] = { label = DOORS[door], state = 'Ouvert' .. ((door == 4 or door == 5) and '' or 'e'), level = 'warn' }
            end
        end
    end
    if IsVehicleBumperBrokenOff(vehicle, true) then parts[#parts + 1] = { label = 'Pare-choc avant', state = 'Arraché', level = 'bad' } end
    if IsVehicleBumperBrokenOff(vehicle, false) then parts[#parts + 1] = { label = 'Pare-choc arrière', state = 'Arraché', level = 'bad' } end
    local broken = 0
    for index = 0, 3 do if not IsVehicleWindowIntact(vehicle, index) then broken = broken + 1 end end
    if broken > 0 then parts[#parts + 1] = { label = 'Vitres', state = ('%d cassée%s'):format(broken, broken > 1 and 's' or ''), level = 'warn' } end
    if not IsVehicleWindowIntact(vehicle, 6) then parts[#parts + 1] = { label = 'Pare-brise', state = 'Cassé', level = 'bad' } end
    local left, right = GetIsLeftVehicleHeadlightDamaged(vehicle), GetIsRightVehicleHeadlightDamaged(vehicle)
    if left or right then
        parts[#parts + 1] = { label = 'Phares', state = (left and right) and 'Les deux cassés' or (left and 'Gauche cassé' or 'Droit cassé'), level = 'warn' }
    end
    local fuel = VC.fuel and VC.fuel(vehicle) or nil
    return {
        name = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))),
        plate = (GetVehicleNumberPlateText(vehicle) or ''):gsub('^%s+', ''):gsub('%s+$', ''),
        engine = pct(engine), engineState = label, engineLevel = level,
        body = pct(body), tank = pct(tank), leaking = tank < 650.0,
        fuel = fuel and math.floor(fuel + 0.5) or nil,
        tyres = tyres, parts = parts,
        field = tonumber(VC.state(vehicle, 'vcFieldRepairs')) or 0, fieldMax = Field.Max or 2,
    }
end

-- =========================================================================
-- /inspectvehicle
-- =========================================================================
local shownUntil = 0

local function hideCard()
    shownUntil = 0
    SendNUIMessage({ action = 'inspect', data = false })
end

if Inspect.Command then
    RegisterCommand(Inspect.Command, function()
        if GetGameTimer() < shownUntil then return hideCard() end
        local vehicle = VC.nearestVehicle(Inspect.Distance or 5.0)
        if not vehicle then
            return VC.chat(('Aucun véhicule dans un rayon de %d m.'):format(math.floor(Inspect.Distance or 5.0)))
        end
        local duration = Inspect.Duration or 15000
        shownUntil = GetGameTimer() + duration
        local until_ = shownUntil
        SendNUIMessage({ action = 'inspect', data = VC.inspectData(vehicle) })
        SetTimeout(duration, function() if shownUntil == until_ then hideCard() end end)
    end, false)
end

-- =========================================================================
-- /fieldrepair
-- =========================================================================
local repairing = false

local function progress(value, text)
    SendNUIMessage({ action = 'progress', data = value and { value = value, text = text } or false })
end

--- Devant le capot ?
local function atHood(ped, vehicle)
    local _, max = GetModelDimensions(GetEntityModel(vehicle))
    local front = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, max.y + 0.3, 0.0)
    return #(GetEntityCoords(ped) - front) <= (Field.FrontDistance or 2.2)
end

local pendingRepair = nil -- { netId, vehicle } : réponse du serveur attendue

RegisterNetEvent('rp_vehiclecontrol:fieldRepair', function(netId, ok, count)
    if not pendingRepair or pendingRepair.netId ~= netId then return end
    local vehicle = pendingRepair.vehicle
    pendingRepair = nil
    if not ok then
        return VC.chat(('Plus de réparation de fortune possible sur ce véhicule (%d/%d) : il faut un garagiste.'):format(count or 0, Field.Max or 2))
    end
    VC.repairEngine(vehicle, Field.Engine or 450.0, false, function(done)
        if done then
            VC.chat(('Réparation de fortune faite (%d/%d) : le véhicule roule, puissance réduite. Carrosserie, pneus et roues non réparés.'):format(count or 1, Field.Max or 2))
        end
    end)
end)

local function fieldRepair()
    if repairing then return end
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= 0 then return VC.chat('Descendez du véhicule pour le réparer.') end
    local vehicle = VC.nearestVehicle(Field.Distance or 4.0)
    if not vehicle then return VC.chat('Aucun véhicule à côté de vous.') end
    local near = atHood(ped, vehicle)
    if not near then return VC.chat('Placez-vous devant le capot.') end
    local engine = GetVehicleEngineHealth(vehicle)
    if engine >= (Field.Engine or 450.0) then return VC.chat('Le moteur n\'a pas besoin d\'une réparation de fortune.') end
    if engine <= (Damage.Broken or 100.0) and not Field.AllowDestroyed then
        return VC.chat('Moteur détruit : une réparation de fortune ne suffit pas, il faut un garagiste.')
    end
    if (tonumber(VC.state(vehicle, 'vcFieldRepairs')) or 0) >= (Field.Max or 2) then
        return VC.chat(('Plus de réparation de fortune possible sur ce véhicule (%d/%d) : il faut un garagiste.'):format(Field.Max or 2, Field.Max or 2))
    end
    repairing = true
    CreateThread(function()
        local hoodWasOpen = GetVehicleDoorAngleRatio(vehicle, 4) > 0.1
        NetworkRequestControlOfEntity(vehicle)
        if not hoodWasOpen then SetVehicleDoorOpen(vehicle, 4, false, false) end
        local center = GetEntityCoords(vehicle)
        TaskTurnPedToFaceCoord(ped, center.x, center.y, center.z, 800) -- face au moteur
        Wait(800)
        local anim = Field.Anim or { 'mini@repair', 'fixing_a_ped' }
        RequestAnimDict(anim[1])
        local t = GetGameTimer() + 2000
        while not HasAnimDictLoaded(anim[1]) and GetGameTimer() < t do Wait(0) end
        TaskPlayAnim(ped, anim[1], anim[2], 3.0, 3.0, -1, 1, 0.0, false, false, false)
        local duration = Field.Duration or 15000
        local start = GetGameTimer()
        local cancelled, shown = false, 0
        while GetGameTimer() - start < duration do
            Wait(0)
            DisableControlAction(0, 23, true) -- monter dans un véhicule
            local now = GetGameTimer()
            if now - shown >= 100 then shown = now; progress((now - start) / duration, 'Réparation de fortune… (X : annuler)') end
            if not DoesEntityExist(vehicle) or IsPedRagdoll(ped) or IsEntityDead(ped) or GetVehiclePedIsIn(ped, false) ~= 0
                or not atHood(ped, vehicle) or IsControlJustPressed(0, 73) then -- X : annuler
                cancelled = true
                break
            end
        end
        StopAnimTask(ped, anim[1], anim[2], 1.0)
        RemoveAnimDict(anim[1])
        progress(false)
        if DoesEntityExist(vehicle) and not hoodWasOpen then SetVehicleDoorShut(vehicle, 4, false) end
        repairing = false
        if cancelled then return VC.chat('Réparation annulée.') end
        if not NetworkGetEntityIsNetworked(vehicle) then
            return VC.repairEngine(vehicle, Field.Engine or 450.0, false)
        end
        pendingRepair = { netId = VehToNet(vehicle), vehicle = vehicle }
        TriggerServerEvent('rp_vehiclecontrol:fieldRepair', pendingRepair.netId)
    end)
end
VC.fieldRepair = fieldRepair -- pour les tests

if Field.Command then
    RegisterCommand(Field.Command, fieldRepair, Field.Restricted == true)
end
