--[[
    RP Interact - Placement d'un objet (client)
    -------------------------------------------
    RPI.placeObject(model, opts, cb) : un objet FANTÔME (transparent, sans collision, visible seulement par ce joueur)
    suit le regard (la souris / la caméra) jusqu'à Range m du joueur ; on le tourne, le lève, le baisse, puis on le
    pose. cb({ x, y, z, heading }) à la pose, cb(nil) si annulé. Utilisé par /musique (« Faire apparaître l'objet »,
    et « Déplacer l'objet » avec l'œil).
    Touches (Music.PlaceKeys) : molette ou ← / → : tourner ; ↑ / ↓ : lever / baisser ; Maj : plus fin ;
    clic gauche ou E : poser ; clic droit ou Retour arrière : annuler.
    Performance : boucle à chaque image seulement pendant le placement.
]]

local Config = InteractConfig
local M = Config.Music or {}
local placing = false

local function help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

--- Point visé par la caméra (décor, objets), ramené à Range m du joueur ; nil si on vise le ciel
local function aimedPoint(ghost, range)
    local cam, rot = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2)
    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local to = cam + dir * (range + 12.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1 + 16, ghost, 7)
    local _, hit, coords = GetShapeTestResult(ray)
    if hit ~= 1 and hit ~= true then return nil end
    local ped = GetEntityCoords(PlayerPedId())
    local offset = coords - ped
    local flat = math.sqrt(offset.x * offset.x + offset.y * offset.y)
    if flat > range then coords = vector3(ped.x + offset.x / flat * range, ped.y + offset.y / flat * range, coords.z) end
    return coords
end

function RPI.isPlacing() return placing end

--- Place un objet du modèle `model` ; opts = { range, heading, label } ; cb(position) ou cb(nil)
function RPI.placeObject(model, opts, cb)
    opts = opts or {}
    if placing then return cb(nil) end
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) then return cb(nil, 'Cet objet n\'existe pas dans le jeu.') end
    RequestModel(hash)
    local stopAt = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < stopAt do Wait(0) end
    if not HasModelLoaded(hash) then return cb(nil, 'Objet pas chargé, réessayez.') end
    placing = true
    local ped = PlayerPedId()
    local start = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.0)
    -- fantôme : local (pas réseau), transparent, sans collision
    local ghost = CreateObjectNoOffset(hash, start.x, start.y, start.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAlpha(ghost, 160, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityInvincible(ghost, true)
    local min = GetModelDimensions(hash)
    local base = -(min and min.z or 0.0) -- posé sur sa base
    local range = opts.range or M.PlaceRange or 6.0
    local heading = opts.heading or (GetEntityHeading(ped) + 180.0)
    local lift = 0.0
    local maxLift = M.MaxLift or 2.5
    local last = start
    local result = nil
    CreateThread(function()
        while placing do
            for _, c in ipairs({ 24, 25, 14, 15, 16, 17, 37, 44, 140, 141, 142, 257, 263, 172, 173, 174, 175, 199, 200, 322 }) do
                DisableControlAction(0, c, true)
            end
            local fine = IsControlPressed(0, 21) -- Maj : réglage fin
            local step = fine and 0.5 or 2.0
            if IsDisabledControlPressed(0, 174) then heading = heading + step end           -- ←
            if IsDisabledControlPressed(0, 175) then heading = heading - step end           -- →
            if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then heading = heading - (fine and 3.0 or 15.0) end
            if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then heading = heading + (fine and 3.0 or 15.0) end
            if IsDisabledControlPressed(0, 172) then lift = math.min(maxLift, lift + (fine and 0.002 or 0.01)) end -- ↑
            if IsDisabledControlPressed(0, 173) then lift = math.max(-0.5, lift - (fine and 0.002 or 0.01)) end    -- ↓
            local point = aimedPoint(ghost, range)
            if point then last = point end
            SetEntityCoordsNoOffset(ghost, last.x, last.y, last.z + base + lift, false, false, false)
            SetEntityHeading(ghost, heading % 360.0)
            help(('%s~n~~INPUT_ATTACK~ / ~INPUT_CONTEXT~ Poser~n~Molette, ~INPUT_CELLPHONE_LEFT~ ~INPUT_CELLPHONE_RIGHT~ : tourner~n~~INPUT_CELLPHONE_UP~ ~INPUT_CELLPHONE_DOWN~ : lever / baisser (Maj : fin)~n~~INPUT_AIM~ / ~INPUT_FRONTEND_RRIGHT~ Annuler')
                :format(opts.label or 'Placer l\'objet'))
            if IsDisabledControlJustPressed(0, 24) or IsControlJustPressed(0, 38) then
                local p = GetEntityCoords(ghost)
                result = { x = p.x, y = p.y, z = p.z, heading = heading % 360.0 }
                placing = false
            elseif IsDisabledControlJustPressed(0, 25) or IsControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200)
                or IsEntityDead(PlayerPedId()) or IsPedInAnyVehicle(PlayerPedId(), false) then
                placing = false
            end
            Wait(0)
        end
        if DoesEntityExist(ghost) then DeleteObject(ghost) end
        cb(result)
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then placing = false end
end)
