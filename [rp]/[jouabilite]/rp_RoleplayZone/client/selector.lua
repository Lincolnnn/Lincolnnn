--[[
    RP RoleplayZone - client : mode sélection (création d'une scène par le civil)
    -----------------------------------------------------------------------------
    On vise avec la caméra :
      - ZONE DE RECHERCHE / PÉRIMÈTRE À FOUILLER : un CERCLE BLANC lumineux qui épouse le terrain (sols, trottoirs,
        murs, toits, objets), comme l'indicateur de lancer de grenade de PUBG, suit le point visé ; molette : rayon
        (zone 15 à 60 m, périmètre 0,5 à 5 m) ;
      - OBJET À FOUILLER : l'objet du décor ou le VÉHICULE visé ressort en CONTOUR BLANC, avec un cercle blanc à son pied.
    Vue du jeu (autour du personnage) ou CAMÉRA LIBRE (choisie dans le menu ; V change de vue pendant la sélection) :
    on se balade dans les environs sans déplacer le personnage.
    E valide (puis la description, dans le menu) ; Retour arrière, clic droit ou Échap annulent (Échap n'ouvre pas le
    menu pause). Les scènes déjà posées autour sont dessinées en plus pâle pour se repérer.
    Boucle à chaque image SEULEMENT pendant la sélection ; le cercle n'est recalculé que si le point visé bouge.
]]

RZ = RZ or {}
local Config = SceneConfig
local S = Config.Selector or {}

local selecting = nil

local DISABLED = { 14, 15, 16, 17, 24, 25, 37, 44, 45, 140, 141, 142, 199, 200, 257, 263, 264, 322, 99, 100, 115, 116, 38 }
local CONFIRM = 38           -- E
local WHEEL_UP, WHEEL_DOWN = 15, 14
local CANCEL = { 177, 194, 202, 25 } -- Retour arrière, clic droit
local PAUSE = { 200, 322 }           -- Échap
local WHITE = { 255, 255, 255 }
local KIND_LABEL = { zone = 'Zone de recherche', perimeter = 'Périmètre à fouiller', object = 'Objet à fouiller' }

function RZ.selecting() return selecting ~= nil end

local function fmt(m)
    if m >= 10 then return ('%d m'):format(math.floor(m + 0.5)) end
    return (('%.2f'):format(m):gsub('0+$', ''):gsub('%.$', '')):gsub('%.', ',') .. ' m'
end

-- =========================================================================
-- CERCLES (cache : recalculés seulement quand le centre ou le rayon change)
-- =========================================================================
local function cachedRing(cache, c, r, now)
    local moved = not cache.c or RZ.dist2D(cache.c, c) > 0.12 or math.abs(cache.c.z - c.z) > 0.3 or cache.r ~= r
    if moved and (now - (cache.at or 0) > 60 or not cache.pts) then
        cache.c, cache.r, cache.at = c, r, now
        cache.pts = RZ.ringPoints(c, r, RZ.ringCount(r))
    end
    return cache.pts
end

local others = {} -- [id] = { pts } : scènes posées autour
local function drawOthers(p)
    for _, s in ipairs(RZ.scenes()) do
        if RZ.dist2D(s.pos, p) < 90.0 + (s.radius or 0) then
            local cache = others[s.id]
            if not cache or cache.r ~= s.radius then
                cache = { r = s.radius, pts = RZ.ringPoints(s.pos, s.radius, RZ.ringCount(s.radius, 72)) }
                others[s.id] = cache
            end
            local tint = s.kind == 'zone' and { 170, 200, 255 } or { 255, 225, 150 }
            RZ.drawRing(cache.pts, s.kind == 'zone' and 0.12 or 0.08, tint, 70, false)
        end
    end
end

-- =========================================================================
-- OBJET VISÉ : contour blanc
-- =========================================================================
local outlined = nil
local function setOutline(e)
    if outlined == e then return end
    if outlined and DoesEntityExist(outlined) then SetEntityDrawOutline(outlined, false) end
    outlined = e
    if e then
        SetEntityDrawOutlineColor(255, 255, 255, 255)
        SetEntityDrawOutlineShader((Config.Eagle and Config.Eagle.OutlineShader) or 0)
        SetEntityDrawOutline(e, true)
    end
end

--- Objet du décor ou véhicule visé
local function objectAt(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local t = GetEntityType(entity)
    if t ~= 3 and t ~= 2 then return nil end
    if t == 3 and RZ.isDroppedWeapon(entity) then return nil end
    return entity
end

-- =========================================================================
-- CAMÉRA LIBRE : on se balade dans les environs sans déplacer le personnage (V : vue du jeu <-> caméra libre)
-- Souris : regarder ; Z/Q/S/D (W/A/S/D) : avancer / côtés ; Espace / Ctrl : monter / descendre ; Maj : plus vite.
-- Elle reste à moins de FreecamRange m du personnage.
-- =========================================================================
local FREE_BLOCKED = { 1, 2, 21, 22, 30, 31, 32, 33, 34, 35, 36, 44, 0, 26, 79 }
local free = nil -- { cam, pos, rot }

local function startFreecam()
    if free then return end
    local pos, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, pos.x, pos.y, pos.z)
    SetCamRot(cam, rot.x, rot.y, rot.z, 2)
    SetCamFov(cam, GetGameplayCamFov())
    RenderScriptCams(true, true, 350, true, true)
    free = { cam = cam, pos = pos, rot = vector3(rot.x, 0.0, rot.z) }
end

local function stopFreecam()
    if not free then return end
    RenderScriptCams(false, true, 350, true, true)
    DestroyCam(free.cam, false)
    ClearFocus()
    free = nil
end

local function updateFreecam(dt)
    for _, c in ipairs(FREE_BLOCKED) do DisableControlAction(0, c, true) end
    local lookX, lookY = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
    local rx = math.max(-85.0, math.min(85.0, free.rot.x - lookY * 8.0))
    local rz = (free.rot.z - lookX * 8.0) % 360.0
    free.rot = vector3(rx, 0.0, rz)
    local forward = RZ.rotDirection(free.rot)
    local right = vector3(math.cos(math.rad(rz)), math.sin(math.rad(rz)), 0.0)
    local move = vector3(0.0, 0.0, 0.0)
    if IsDisabledControlPressed(0, 32) then move = move + forward end
    if IsDisabledControlPressed(0, 33) then move = move - forward end
    if IsDisabledControlPressed(0, 35) then move = move + right end
    if IsDisabledControlPressed(0, 34) then move = move - right end
    if IsDisabledControlPressed(0, 22) then move = move + vector3(0.0, 0.0, 1.0) end
    if IsDisabledControlPressed(0, 36) then move = move - vector3(0.0, 0.0, 1.0) end
    local speed = (S.FreecamSpeed or 6.0) * (IsDisabledControlPressed(0, 21) and 3.0 or 1.0)
    local pos = free.pos + move * (speed * dt)
    -- reste à moins de FreecamRange m du personnage
    local me = GetEntityCoords(PlayerPedId())
    local offset = pos - me
    local maxRange = S.FreecamRange or 60.0
    if #offset > maxRange then pos = me + offset * (maxRange / #offset) end
    free.pos = pos
    SetCamCoord(free.cam, pos.x, pos.y, pos.z)
    SetCamRot(free.cam, rx, 0.0, rz, 2)
    SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)
end

--- Ce que vise la caméra active (caméra libre ou vue du jeu)
local function aimNow(range, flags)
    if free then return RZ.aim(range, flags, free.pos, RZ.rotDirection(free.rot)) end
    return RZ.aim(range, flags)
end

-- =========================================================================
-- SÉLECTION
-- =========================================================================
local function stop(message)
    stopFreecam()
    setOutline(nil)
    selecting = nil
    others = {}
    if message then RZ.notify(message) end
end

local function helpLines()
    local k = selecting.kind
    local lines = { ('~INPUT_CONTEXT~ Choisir : %s'):format(KIND_LABEL[k]:lower()) }
    if k == 'object' then
        local isVehicle = selecting.target and GetEntityType(selecting.target) == 2
        lines[1] = selecting.target and (isVehicle and '~INPUT_CONTEXT~ Choisir ce véhicule' or '~INPUT_CONTEXT~ Choisir cet objet')
            or 'Visez un objet du décor ou un véhicule'
    else
        lines[#lines + 1] = ('~INPUT_WEAPON_WHEEL_NEXT~ Rayon : %s'):format(fmt(selecting.radius))
    end
    lines[#lines + 1] = free and '~INPUT_NEXT_CAMERA~ Vue du personnage (caméra libre : ZQSD, Espace / Ctrl, Maj)'
        or '~INPUT_NEXT_CAMERA~ Caméra libre'
    lines[#lines + 1] = '~INPUT_FRONTEND_CANCEL~ Annuler'
    return lines
end

--- Démarre la sélection : kind = 'zone' | 'perimeter' | 'object' ; opts = { radius } ; onDone(choix)
function RZ.startSelector(kind, opts, onDone)
    if selecting then return end
    opts = type(opts) == 'table' and opts or {}
    local limits = kind == 'zone' and Config.Zone or Config.Perimeter
    selecting = {
        kind = kind,
        radius = math.max(limits.MinRadius, math.min(limits.MaxRadius, tonumber(opts.radius) or limits.DefaultRadius)),
        ring = {}, objectRing = {},
    }
    if opts.camera == 'free' then startFreecam() end
    CreateThread(function()
        local lastFrame = GetGameTimer()
        while selecting do
            for _, c in ipairs(DISABLED) do DisableControlAction(0, c, true) end
            DisableControlAction(0, S.ToggleKey or 0, true)
            local now = GetGameTimer()
            local dt = math.min(0.1, (now - lastFrame) / 1000.0)
            lastFrame = now
            if IsDisabledControlJustPressed(0, S.ToggleKey or 0) then
                if free then stopFreecam() else startFreecam() end
            end
            if free then updateFreecam(dt) end
            local pulse = 190 + math.floor(45 * math.sin(now / 180))
            local ped = PlayerPedId()
            local me = GetEntityCoords(ped)
            drawOthers(me)

            local point, center, entity
            if selecting.kind == 'object' then
                point, entity = aimNow(S.ObjectRange or 30.0, 1 + 2 + 16)
                entity = objectAt(entity)
                selecting.target = entity
                setOutline(entity)
                if entity then
                    SetEntityDrawOutline(entity, true) -- redemandé à chaque image
                    local c = GetEntityCoords(entity)
                    local r = RZ.modelRadius(GetEntityModel(entity))
                    local z = RZ.surfaceZ(c.x, c.y, c.z, 0.5, 6.0, entity) or c.z
                    center = { x = c.x, y = c.y, z = z }
                    RZ.drawRing(cachedRing(selecting.objectRing, center, r, now), 0.08, WHITE, pulse)
                elseif point then
                    RZ.drawCenter(point, { 200, 200, 200 }, 120, 0.25)
                end
            else
                point = aimNow(S.Range or 60.0, 1 + 16)
                if point then
                    center = { x = point.x, y = point.y, z = point.z }
                    local band = selecting.kind == 'zone' and (S.Band or 0.18) * 1.6 or (S.Band or 0.18) * 0.7
                    RZ.drawRing(cachedRing(selecting.ring, center, selecting.radius, now), band, WHITE, pulse)
                    RZ.drawCenter(center, WHITE, pulse, selecting.kind == 'zone' and 0.5 or 0.2)
                end
                local wheel = (IsDisabledControlJustPressed(0, WHEEL_UP) and 1) or (IsDisabledControlJustPressed(0, WHEEL_DOWN) and -1) or 0
                if wheel ~= 0 then
                    selecting.radius = math.max(limits.MinRadius, math.min(limits.MaxRadius, selecting.radius + wheel * limits.Step))
                end
            end
            if not IsPauseMenuActive() then RZ.help(helpLines()) end

            if IsDisabledControlJustPressed(0, CONFIRM) then
                if selecting.kind == 'object' and entity then
                    local c, rot = GetEntityCoords(entity), GetEntityRotation(entity, 2)
                    local choice = { kind = 'object', pos = RZ.vec(c), model = GetEntityModel(entity),
                        rot = RZ.vec(rot), radius = RZ.modelRadius(GetEntityModel(entity)), label = RZ.locationText(c) }
                    if GetEntityType(entity) == 2 then
                        -- véhicule : suivi par son n° réseau (il peut bouger)
                        if not NetworkGetEntityIsNetworked(entity) then
                            RZ.notify('Ce véhicule n\'est pas synchronisé : choisissez-en un autre.')
                            choice = nil
                        else
                            choice.vehicle, choice.netId = true, VehToNet(entity)
                        end
                    end
                    if choice then
                        stop()
                        onDone(choice)
                    end
                elseif selecting.kind ~= 'object' and center then
                    local choice = { kind = selecting.kind, pos = RZ.vec(center), radius = selecting.radius,
                        label = RZ.locationText(center) }
                    stop()
                    onDone(choice)
                else
                    RZ.notify(selecting.kind == 'object' and 'Visez un objet du décor ou un véhicule.' or 'Visez le sol.')
                end
            else
                for _, c in ipairs(PAUSE) do
                    if IsDisabledControlJustPressed(0, c) then stop('Sélection annulée.'); RZ.blockPause() break end
                end
                if selecting then
                    for _, c in ipairs(CANCEL) do
                        if IsDisabledControlJustPressed(0, c) then stop('Sélection annulée.') break end
                    end
                end
            end
            Wait(0)
        end
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        setOutline(nil)
        stopFreecam()
    end
end)
