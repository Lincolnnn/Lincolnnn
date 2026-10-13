--[[
    RP Interact - Props posés avec le script de props du serveur (dossier "props")
    -------------------------------------------------------------------------------
    Avec l'œil, sur un objet posé par ce script : "Déplacer le props" et "Supprimer le props"
    (Config.Props : distance, accès).
      - Reconnaissance (voir config.lua) : état de l'objet ("rpiProp", ou les clés StateKeys du script
        de props), export du script de props, ou objet créé par ce script chez ce joueur (il est alors
        marqué pour tout le monde). Le serveur demande aussi automatiquement au créateur de chaque
        objet quel script l'a fait apparaître (événement "rp_interact:client:propCheck").
      - Déplacer : le props suit la visée (au sol, jusqu'à MoveRange m du joueur) ; ← / → ou la molette
        pour le tourner, E pour le poser, Retour arrière pour annuler.
      - Supprimer : par le serveur (objet réseau), ou localement pour un objet propre à ce joueur.
    Performance : aucune boucle, sauf pendant un déplacement (chaque image).
]]

local Config = InteractConfig
local P = Config.Props or {}

-- =========================================================================
-- RECONNAISSANCE
-- =========================================================================
local function createdByPropsScript(entity)
    local ok, script = pcall(GetEntityScript, entity)
    return ok and type(script) == 'string' and script == P.Resource
end

local function fromExport(entity)
    if not P.Export or P.Export == '' or GetResourceState(P.Resource) ~= 'started' then return false end
    local ok, result = pcall(function() return exports[P.Resource][P.Export](exports[P.Resource], entity) end)
    return ok and result == true
end

--- Marque l'objet comme props pour tous les joueurs (état "rpiProp", posé par le serveur)
local function mark(entity)
    if NetworkGetEntityIsNetworked(entity) and not Entity(entity).state.rpiProp then
        TriggerServerEvent('rp_interact:server:registerProp', ObjToNet(entity))
    end
end

--- L'objet a-t-il été posé avec le script de props ?
function RPI.isPlacedProp(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 3 then return false end
    if NetworkGetEntityIsNetworked(entity) then
        local state = Entity(entity).state
        for _, key in ipairs(P.StateKeys or {}) do
            if state[key] then return true end
        end
    end
    if fromExport(entity) or createdByPropsScript(entity) then
        mark(entity)
        return true
    end
    return false
end

-- Le script de props (ou un autre) peut marquer ses objets lui-même
exports('registerProp', function(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        if NetworkGetEntityIsNetworked(entity) then
            TriggerServerEvent('rp_interact:server:registerProp', ObjToNet(entity))
        else
            Entity(entity).state:set('rpiProp', true, false) -- objet local : marqué chez ce joueur
        end
        return true
    end
    return false
end)

-- Le serveur demande au créateur d'un objet quel script l'a fait apparaître
RegisterNetEvent('rp_interact:client:propCheck', function(netId)
    CreateThread(function()
        local timeout = GetGameTimer() + 2000
        local entity = NetworkDoesNetworkIdExist(netId) and NetToObj(netId) or 0
        while entity == 0 and GetGameTimer() < timeout do
            Wait(100)
            entity = NetworkDoesNetworkIdExist(netId) and NetToObj(netId) or 0
        end
        if entity ~= 0 and createdByPropsScript(entity) then
            TriggerServerEvent('rp_interact:server:registerProp', netId)
        end
    end)
end)

--- Qui peut déplacer / supprimer ce props ?
local function canUse(entity)
    if P.Access == 'police' then return RPI.isPolice() end
    if P.Access == 'owner' then
        local state = NetworkGetEntityIsNetworked(entity) and Entity(entity).state or {}
        local info = state.rpiProp
        local mine = GetPlayerServerId(PlayerId())
        return createdByPropsScript(entity) or (type(info) == 'table' and info.by == mine) or RPI.isPolice()
    end
    return true
end

-- =========================================================================
-- SUPPRIMER
-- =========================================================================
local function deleteProp(entity)
    if not DoesEntityExist(entity) then return end
    if not NetworkGetEntityIsNetworked(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
        return RPI.notify('Props supprimé.', 'success')
    end
    RPI.request('propAction', { action = 'delete', netId = ObjToNet(entity) }, function(res)
        if res and res.ok then return RPI.notify('Props supprimé.', 'success') end
        if res and res.fallback then -- sans OneSync : suppression par ce client
            RPI.withControl(entity, function()
                SetEntityAsMissionEntity(entity, true, true)
                DeleteEntity(entity)
            end)
            return RPI.notify('Props supprimé.', 'success')
        end
        RPI.notify(res and res.error or 'Suppression impossible.', 'error')
    end)
end

-- =========================================================================
-- DÉPLACER (boucle à chaque image pendant le déplacement uniquement)
-- =========================================================================
local moving = false

local function help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

--- Point visé au sol (décor), à MoveRange m du joueur au plus ; nil si rien
local function aimedGround()
    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local to = cam + dir * 15.0
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1, PlayerPedId(), 7)
    local _, hit, coords = GetShapeTestResult(ray)
    if hit ~= 1 then return nil end
    local ped = GetEntityCoords(PlayerPedId())
    local offset = coords - ped
    local flat = math.sqrt(offset.x * offset.x + offset.y * offset.y)
    local range = P.MoveRange or 6.0
    if flat > range then coords = vector3(ped.x + offset.x / flat * range, ped.y + offset.y / flat * range, coords.z) end
    return coords
end

local function moveProp(entity)
    if moving or not DoesEntityExist(entity) then return end
    moving = true
    RPI.withControl(entity, function()
        if NetworkGetEntityIsNetworked(entity) and not NetworkHasControlOfEntity(entity) then
            moving = false
            return RPI.notify('Ce props est utilisé par un autre joueur, réessayez.', 'error')
        end
        local origin, originHeading = GetEntityCoords(entity), GetEntityHeading(entity)
        local frozen = IsEntityPositionFrozen(entity)
        local heading = originHeading
        FreezeEntityPosition(entity, true)
        SetEntityCollision(entity, false, false)
        SetEntityAlpha(entity, 170, false)
        local done = nil
        while DoesEntityExist(entity) and not done do
            for _, control in ipairs({ 24, 25, 37, 44, 140, 141, 142, 257, 263, 14, 15, 16, 17 }) do
                DisableControlAction(0, control, true)
            end
            local ground = aimedGround()
            if ground then
                SetEntityCoordsNoOffset(entity, ground.x, ground.y, ground.z, false, false, false)
                PlaceObjectOnGroundProperly(entity)
            end
            if IsControlPressed(0, 174) then heading = heading + 2.0 end -- flèche gauche
            if IsControlPressed(0, 175) then heading = heading - 2.0 end -- flèche droite
            if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then heading = heading - 10.0 end -- molette
            if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then heading = heading + 10.0 end
            SetEntityHeading(entity, heading % 360.0)
            help('~INPUT_CONTEXT~ Poser le props~n~~INPUT_CELLPHONE_LEFT~ ~INPUT_CELLPHONE_RIGHT~ / molette : tourner~n~~INPUT_FRONTEND_RRIGHT~ Annuler')
            if IsControlJustPressed(0, 38) then done = 'place' end   -- E
            if IsControlJustPressed(0, 177) then done = 'cancel' end -- Retour arrière
            if IsEntityDead(PlayerPedId()) then done = 'cancel' end
            Wait(0)
        end
        if DoesEntityExist(entity) then
            if done ~= 'place' then
                SetEntityCoordsNoOffset(entity, origin.x, origin.y, origin.z, false, false, false)
                SetEntityHeading(entity, originHeading)
            end
            SetEntityCollision(entity, true, true)
            ResetEntityAlpha(entity)
            FreezeEntityPosition(entity, frozen)
            if done == 'place' then
                local c = GetEntityCoords(entity)
                if NetworkGetEntityIsNetworked(entity) then
                    RPI.request('propAction', { action = 'moved', netId = ObjToNet(entity),
                        coords = { x = c.x, y = c.y, z = c.z, heading = GetEntityHeading(entity) } }, function() end)
                end
                RPI.notify('Props déplacé.', 'success')
            end
        end
        moving = false
    end)
end

-- =========================================================================
-- OPTIONS DE L'ŒIL (appelées par client/options.lua pour les objets)
-- =========================================================================
--- Ajoute "Déplacer le props" / "Supprimer le props" ; true si l'objet est un props posé
function RPI.propOptions(ctx, out)
    if not RPI.isPlacedProp(ctx.entity) then return false end
    if (ctx.distance or 0) <= (P.Distance or 3.0) and canUse(ctx.entity) and not moving then
        out[#out + 1] = { id = 'prop:move', label = 'Déplacer le props', icon = 'move', run = function(c) moveProp(c.entity) end }
        out[#out + 1] = { id = 'prop:delete', label = 'Supprimer le props', icon = 'trash', run = function(c) deleteProp(c.entity) end }
    end
    return true
end
