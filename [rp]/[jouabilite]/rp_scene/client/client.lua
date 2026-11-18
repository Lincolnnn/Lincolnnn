--[[
    RP SCENE - client
    -----------------
    Ajoute dans l'œil (Alt) des options qui lancent les commandes de Riven Scene Dynamics, par notre pont ox_target
    (exports addGlobalVehicle, addModel). Ne contient aucun code de Riven et ne le modifie pas : Riven reste tel
    quel, avec sa licence (refusée ou Riven arrêté : aucune option).
    Réservé aux policiers en service : ox_target/config.lua, PoliceOnly.
    Performance : rien ne tourne ; les conditions sont lues seulement pendant que l'œil vise.
]]

local C = RPSceneConfig
local CMD = C.Commands
local trunkModels = {}
for _, name in ipairs(C.TrunkModels or {}) do trunkModels[GetHashKey(name)] = true end

local function rivenUp() return GetResourceState(C.Resource) == 'started' end

local function isEmergency(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    return (C.TrunkClasses or {})[GetVehicleClass(veh)] == true or trunkModels[GetEntityModel(veh)] == true
end

local function run(command) ExecuteCommand(command) end

local function entityOf(data)
    if type(data) == 'table' then return data.entity or 0 end
    return tonumber(data) or 0
end

--- Point derrière le pare-chocs arrière du véhicule (là où Riven ouvre son coffre)
local function trunkPoint(veh)
    local min = GetModelDimensions(GetEntityModel(veh))
    return GetOffsetFromEntityInWorldCoords(veh, 0.0, min.y - (C.TrunkStand or 0.6), 0.0)
end

--- Le joueur marche jusqu'au coffre (si besoin), se tourne vers le véhicule, puis ouvre le kit de Riven
local busy = false
local function openTrunk(data)
    local veh = entityOf(data)
    if busy or not DoesEntityExist(veh) then return end
    busy = true
    CreateThread(function()
        local ped = PlayerPedId()
        local target = trunkPoint(veh)
        if #(GetEntityCoords(ped) - target) > 0.9 then
            TaskGoStraightToCoord(ped, target.x, target.y, target.z, 1.0, C.WalkTimeout or 4000, GetEntityHeading(veh), 0.3)
            local limit = GetGameTimer() + (C.WalkTimeout or 4000)
            while GetGameTimer() < limit and DoesEntityExist(veh) and #(GetEntityCoords(ped) - trunkPoint(veh)) > 0.6 do
                Wait(100)
            end
            ClearPedTasks(ped)
        end
        if DoesEntityExist(veh) then
            TaskTurnPedToFaceEntity(ped, veh, 600)
            Wait(600)
            run(CMD.trunk)
        end
        busy = false
    end)
end

local O = C.Options or {}
local D = C.Distance or {}

-- Véhicules : coffre (kit), périmètre, gestion de scène, enregistrement
local vehicleOptions = {}
if O.trunk then
    vehicleOptions[#vehicleOptions + 1] = {
        name = 'rp_scene:trunk', label = 'Kit de scène (banderoles, poteaux, cônes, preuves)', icon = 'fa-solid fa-box-open',
        bones = { 'boot' }, distance = D.trunk or 3.0,
        canInteract = function(entity) return rivenUp() and isEmergency(entity) end,
        onSelect = openTrunk,
    }
end
if O.perimeter then
    for _, size in ipairs({ { 'small', 'petit' }, { 'medium', 'moyen' }, { 'large', 'grand' } }) do
        vehicleOptions[#vehicleOptions + 1] = {
            name = 'rp_scene:auto_' .. size[1], label = ('Périmètre automatique : %s'):format(size[2]), icon = 'fa-solid fa-road-barrier',
            distance = D.vehicle or 4.0,
            canInteract = function(entity) return rivenUp() and isEmergency(entity) end,
            onSelect = function() run(('%s auto %s'):format(CMD.scene, size[1])) end,
        }
    end
end
if O.ui then
    vehicleOptions[#vehicleOptions + 1] = {
        name = 'rp_scene:ui', label = 'Gestion de la scène', icon = 'fa-solid fa-note-sticky',
        distance = D.vehicle or 4.0,
        canInteract = function(entity) return rivenUp() and isEmergency(entity) end,
        onSelect = function() run(CMD.ui) end,
    }
end
if O.register then
    vehicleOptions[#vehicleOptions + 1] = {
        name = 'rp_scene:register', label = 'Enregistrer le véhicule à la scène', icon = 'fa-solid fa-car',
        distance = D.vehicle or 4.0,
        canInteract = function(entity) return rivenUp() and not isEmergency(entity) end,
        onSelect = function() run(('%s register'):format(CMD.vehicle)) end,
    }
end
if #vehicleOptions > 0 then exports.ox_target:addGlobalVehicle(vehicleOptions) end

-- Plots de preuve
if O.evidence and #(C.EvidenceModels or {}) > 0 then
    exports.ox_target:addModel(C.EvidenceModels, {
        {
            name = 'rp_scene:evidence_collect', label = 'Collecter la preuve', icon = 'fa-solid fa-magnifying-glass',
            distance = D.object or 2.5,
            canInteract = function() return rivenUp() end,
            onSelect = function() run(('%s collect'):format(CMD.evidence)) end,
        },
    })
end

-- Poteaux de banderole
if O.post and #(C.PostModels or {}) > 0 then
    exports.ox_target:addModel(C.PostModels, {
        {
            name = 'rp_scene:post_remove', label = 'Retirer le poteau', icon = 'fa-solid fa-trash',
            distance = D.object or 2.5,
            canInteract = function() return rivenUp() end,
            onSelect = function() run(('%s post remove'):format(CMD.scene)) end,
        },
    })
end
