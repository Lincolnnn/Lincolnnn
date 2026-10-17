--[[
    RP RoleplayZone - client : mode sélection (création d'une scène par le civil)
    -----------------------------------------------------------------------------
    On vise avec la caméra :
      - ZONE DE RECHERCHE / PÉRIMÈTRE À FOUILLER : un CERCLE BLANC lumineux qui épouse le terrain (sols, trottoirs,
        murs, toits, objets), comme l'indicateur de lancer de grenade de PUBG, suit le point visé ; molette : rayon
        (zone 15 à 60 m, périmètre 0,5 à 5 m) ;
      - OBJET À FOUILLER : l'objet du décor visé ressort en CONTOUR BLANC, avec un cercle blanc à son pied.
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

local function objectAt(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 3 then return nil end
    if RZ.isDroppedWeapon(entity) then return nil end
    return entity
end

-- =========================================================================
-- SÉLECTION
-- =========================================================================
local function stop(message)
    setOutline(nil)
    selecting = nil
    others = {}
    if message then RZ.notify(message) end
end

local function helpLines()
    local k = selecting.kind
    local lines = { ('~INPUT_CONTEXT~ Choisir : %s'):format(KIND_LABEL[k]:lower()) }
    if k == 'object' then
        lines[1] = selecting.target and '~INPUT_CONTEXT~ Choisir cet objet' or 'Visez un objet du décor'
    else
        lines[#lines + 1] = ('~INPUT_WEAPON_WHEEL_NEXT~ Rayon : %s'):format(fmt(selecting.radius))
    end
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
    CreateThread(function()
        while selecting do
            for _, c in ipairs(DISABLED) do DisableControlAction(0, c, true) end
            local now = GetGameTimer()
            local pulse = 190 + math.floor(45 * math.sin(now / 180))
            local ped = PlayerPedId()
            local me = GetEntityCoords(ped)
            drawOthers(me)

            local point, center, entity
            if selecting.kind == 'object' then
                point, entity = RZ.aim(S.ObjectRange or 30.0, 1 + 16)
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
                point = RZ.aim(S.Range or 60.0, 1 + 16)
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
                    stop()
                    onDone(choice)
                elseif selecting.kind ~= 'object' and center then
                    local choice = { kind = selecting.kind, pos = RZ.vec(center), radius = selecting.radius,
                        label = RZ.locationText(center) }
                    stop()
                    onDone(choice)
                else
                    RZ.notify(selecting.kind == 'object' and 'Visez un objet du décor.' or 'Visez le sol.')
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
    if resource == GetCurrentResourceName() then setOutline(nil) end
end)
