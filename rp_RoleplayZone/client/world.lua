--[[
    RP RoleplayZone - client : scènes appliquées dans le monde
    ----------------------------------------------------------
    - ZONE DE RECHERCHE (policiers) : en entrant, la description du civil s'affiche en haut au milieu de l'écran et y
      reste jusqu'à la sortie (ou la suppression de la zone) ; un court son d'intrigue à l'entrée, un son proche qui
      « lève » l'intrigue à la sortie ; le cercle de la zone apparaît sur la carte seulement pendant qu'on est dedans.
    - PÉRIMÈTRE / OBJET / VÉHICULE À FOUILLER (policiers) : avec l'œil de rp_interact (Alt), « Fouiller… » -> barre
      de chargement (objet / véhicule 8 s ; périmètre 6 à 30 s selon sa taille ; X annule) -> le contenu écrit par le
      civil (fiche à l'écran + copie privée dans le chat) ; l'animation continue jusqu'à X. Au civil qui l'a créée :
      « Modifier la description ». Sans rp_interact : « E Fouiller » sur place.
    - DESCRIPTION VISUELLE : affichée au-dessus du lieu / de l'objet aux policiers à moins de 10 m qui le voient
      (rien entre leur caméra et lui : derrière un mur, elle n'apparaît pas).
    - RIEN NE DISPARAÎT (Config.Protect) : autour de chaque scène, objets du décor, PNJ et véhicules stationnés
      marqués comme entités de mission (un « ClearArea » d'un autre script ne les retire plus) ; l'objet à fouiller
      est remis à sa place (copie fixe) s'il disparaît quand même.

    Performance : aucune scène -> aucune boucle. Sinon une vérification toutes les 500 ms (distances) ; boucle à chaque
    image seulement pendant une fouille, ou à moins de 10 m d'une description visuelle (vue vérifiée toutes les 250 ms). Protection : toutes les 2 s, seulement
    à moins de Protect.Range m d'une scène.
]]

RZ = RZ or {}
local Config = SceneConfig
local SR = Config.Search or {}
local PR = Config.Protect or {}

local running = false
local insideZone = nil       -- id de la zone affichée
local zoneBlip = nil
local nearSearch = nil       -- { scene, reach } : fouille à portée
local searching = false
local restored = {}          -- [id de scène] = objet remis (copie locale)
local missing = {}           -- [id de scène] = nombre de vérifications sans l'objet
local protected = {}         -- [entité] = true : marquée comme entité de mission par ce script
local lastProtect = 0

-- =========================================================================
-- SCÈNES CONNUES
-- =========================================================================
local byId = {}

local function rebuild()
    byId = {}
    for _, s in ipairs(RZ.scenes()) do byId[s.id] = s end
end

function RZ.sceneById(id) return byId[id] end

--- Position actuelle d'une scène (un véhicule à fouiller a pu bouger)
function RZ.scenePos(s)
    if s.vehicle then
        local e = RZ.sceneEntity(s)
        if e then
            local c = GetEntityCoords(e)
            return { x = c.x, y = c.y, z = c.z }
        end
    end
    return s.pos
end

--- Objet d'une scène « objet » : le véhicule à fouiller, l'objet du décor à sa place, ou sa copie remise ; nil s'il
--- n'est pas chargé
function RZ.sceneEntity(s)
    if s.kind ~= 'object' or not s.model then return nil end
    if s.vehicle then
        if s.netId and NetworkDoesNetworkIdExist(s.netId) then
            local v = NetToVeh(s.netId)
            if v and v ~= 0 and DoesEntityExist(v) then return v end
        end
        return nil
    end
    local copy = restored[s.id]
    if copy and DoesEntityExist(copy) then return copy end
    local found = GetClosestObjectOfType(s.pos.x, s.pos.y, s.pos.z, 0.8, s.model, false, false, false)
    if found and found ~= 0 then return found end
    return nil
end

-- =========================================================================
-- ZONE : MESSAGE, SONS, CERCLE SUR LA CARTE
-- =========================================================================
function RZ.sound(name)
    SendNUIMessage({ action = 'sound', data = { name = name, volume = (Config.Sounds and Config.Sounds.Volume) or 0.45 } })
end

local function removeBlip()
    if zoneBlip and DoesBlipExist(zoneBlip) then RemoveBlip(zoneBlip) end
    zoneBlip = nil
end

local function enterZone(s)
    insideZone = s.id
    SendNUIMessage({ action = 'zone', data = { show = true, title = s.title or '', text = s.text or '', label = s.label or '' } })
    RZ.sound('enter')
    removeBlip()
    zoneBlip = AddBlipForRadius(s.pos.x + 0.0, s.pos.y + 0.0, s.pos.z + 0.0, s.radius + 0.0)
    SetBlipColour(zoneBlip, (Config.ZoneBlip and Config.ZoneBlip.Color) or 0)
    SetBlipAlpha(zoneBlip, (Config.ZoneBlip and Config.ZoneBlip.Alpha) or 90)
    SetBlipHighDetail(zoneBlip, true)
end

local function leaveZone(sound)
    if not insideZone then return end
    insideZone = nil
    SendNUIMessage({ action = 'zone', data = { show = false } })
    if sound then RZ.sound('exit') end
    removeBlip()
end

function RZ.insideZone() return insideZone and byId[insideZone] or nil end

local function inZone(s, p)
    return RZ.dist2D(s.pos, p) <= s.radius and math.abs(p.z - s.pos.z) <= s.radius + 30.0
end

local function updateZone(p)
    if not RZ.isSearcher() then return leaveZone(false) end
    -- la plus petite zone qui contient le joueur
    local best
    for _, s in pairs(byId) do
        if s.kind == 'zone' and inZone(s, p) and (not best or s.radius < best.radius) then best = s end
    end
    if best and insideZone == best.id then
        return
    end
    if best then
        if insideZone then leaveZone(false) end
        enterZone(best)
    elseif insideZone then
        leaveZone(true)
    end
end

-- =========================================================================
-- FOUILLES (avec l'œil de rp_interact : exports targetOptions / targetSelect plus bas)
-- =========================================================================
--- Distance à laquelle on peut fouiller une scène
local function reachOf(s)
    if s.kind == 'perimeter' then return s.radius + (SR.Distance or 1.2) end
    return (Config.Object and Config.Object.Distance or 1.8) + (s.radius or 1.0) * 0.5
end

--- Durée de la fouille : objet / véhicule 8 s ; périmètre de 6 s (le plus petit) à 30 s (le plus grand)
function RZ.searchTime(s)
    if s.kind ~= 'perimeter' then return SR.ObjectTime or 8000 end
    local P = Config.Perimeter
    local t = (s.radius - P.MinRadius) / math.max(0.01, P.MaxRadius - P.MinRadius)
    t = math.max(0.0, math.min(1.0, t))
    local min, max = SR.PerimeterMinTime or 6000, SR.PerimeterMaxTime or 30000
    return math.floor(min + (max - min) * t + 0.5)
end

local function kindLabel(s)
    if s.vehicle then return 'Fouille du véhicule' end
    return s.kind == 'object' and 'Fouille de l\'objet' or 'Fouille des lieux'
end

local function showResult(res)
    SendNUIMessage({ action = 'result', data = {
        kind = res.kind, vehicle = res.vehicle, title = res.title or '', text = res.text or '', label = res.label or '',
        duration = SR.ResultDuration or 25000,
    } })
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started' then
        pcall(function()
            exports[chat]:addPrivate({ title = kindLabel(res), subject = (res.title ~= '' and res.title) or res.label or '',
                text = res.text })
        end)
    end
end

local PROGRESS_BLOCKED = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 44, 140, 141, 142, 143, 257, 263, 264 }

--- Fouille terminée : l'animation continue jusqu'à X (ou jusqu'à ce que le personnage la quitte)
local function holdUntilStop(ped)
    CreateThread(function()
        local stopKey = SR.StopKey or 73
        local started = GetGameTimer()
        while true do
            if not IsPauseMenuActive() then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~INPUT_VEH_DUCK~ Arrêter l\'animation')
                EndTextCommandDisplayHelp(0, false, false, -1)
            end
            if IsControlJustPressed(0, stopKey) or IsDisabledControlJustPressed(0, stopKey) then break end
            if IsEntityDead(ped) or (GetGameTimer() - started > 1500 and not IsPedUsingAnyScenario(ped)) then return end
            Wait(0)
        end
        ClearPedTasks(ped)
    end)
end

function RZ.search(s)
    if searching or not RZ.isSearcher() then return end
    searching = true
    local ped = PlayerPedId()
    local time = RZ.searchTime(s)
    SendNUIMessage({ action = 'progress', data = { show = true, label = kindLabel(s), duration = time } })
    if s.kind == 'object' then
        local e = RZ.sceneEntity(s)
        local target = e and GetEntityCoords(e) or vector3(s.pos.x, s.pos.y, s.pos.z)
        TaskTurnPedToFaceCoord(ped, target.x, target.y, target.z, 600)
        Wait(600)
    end
    local scenario = s.vehicle and SR.VehicleScenario or (s.kind == 'object' and SR.ObjectScenario or SR.PerimeterScenario)
    if scenario and scenario ~= '' then TaskStartScenarioInPlace(ped, scenario, 0, true) end
    CreateThread(function()
        local endsAt = GetGameTimer() + time
        local reason
        while true do
            Wait(0)
            for _, c in ipairs(PROGRESS_BLOCKED) do DisableControlAction(0, c, true) end
            if IsControlJustPressed(0, 73) then reason = 'cancel' break end -- X
            if IsEntityDead(ped) or not byId[s.id] then reason = 'lost' break end
            if GetGameTimer() >= endsAt then break end
        end
        SendNUIMessage({ action = 'progress', data = { show = false } })
        searching = false
        if reason then
            ClearPedTasks(ped)
            if reason == 'cancel' then RZ.notify('Fouille annulée.') end
            return
        end
        holdUntilStop(ped) -- l'animation continue : X pour l'arrêter
        RZ.request('search', { id = s.id }, function(res)
            if not res.ok then return RZ.notify(res.error or 'Fouille impossible.') end
            showResult(res)
        end)
    end)
end

-- Sans rp_interact (pas d'œil) : « E Fouiller » sur place (Search.PromptWithoutTarget)
local promptRunning = false
local function promptLoop()
    if promptRunning then return end
    promptRunning = true
    CreateThread(function()
        while nearSearch do
            local s = nearSearch.scene
            if not searching and not IsPauseMenuActive() and not RZ.selecting() then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. (s.vehicle and 'Fouiller le véhicule'
                    or (s.kind == 'object' and 'Fouiller l\'objet' or 'Fouiller les lieux')))
                EndTextCommandDisplayHelp(0, false, false, -1)
                if IsControlJustPressed(0, SR.Key or 38) then RZ.search(s) end
            end
            Wait(0)
        end
        promptRunning = false
    end)
end

local function updateNearSearch(p, ped)
    nearSearch = nil
    if SR.PromptWithoutTarget == false or GetResourceState('rp_interact') == 'started' then return end
    if not RZ.isSearcher() or IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end
    local best, bestD
    for _, s in pairs(byId) do
        if s.kind ~= 'zone' then
            local c = RZ.scenePos(s)
            local d = #(vector3(p.x, p.y, p.z) - vector3(c.x, c.y, c.z))
            if d <= reachOf(s) and (not bestD or d < bestD) then best, bestD = s, d end
        end
    end
    if best then
        nearSearch = { scene = best }
        promptLoop()
    end
end

-- =========================================================================
-- ŒIL DE rp_interact (TargetProviders) : « Fouiller les lieux / l'objet / le véhicule » ; au civil qui a créé la
-- scène : « Modifier la description »
-- =========================================================================
local function myServerId() return GetPlayerServerId(PlayerId()) end

--- Scène visée : l'objet / le véhicule visé, ou le point du sol / du mur dans un périmètre
local function aimedScene(info)
    local hit = info.hit
    for _, s in pairs(byId) do
        if s.kind == 'object' then
            local e = info.entity ~= 0 and RZ.sceneEntity(s) or nil
            if e and e == info.entity then return s end
        elseif s.kind == 'perimeter' then
            if RZ.dist2D(s.pos, hit) <= s.radius and math.abs(hit.z - s.pos.z) <= 2.5 then return s end
        end
    end
    return nil
end

local AREA = (Config.Protect and Config.Protect.AreaMargin) or 70.0

--- Secteur d'une scène : la zone (ou le lieu / l'objet) et ses alentours (AreaMargin m, 70 par défaut)
local function inArea(s, p)
    local c = RZ.scenePos(s)
    return RZ.dist2D(c, p) <= (s.radius or 0) + AREA
end

--- Un point dans le secteur d'une scène (rp_interact : pas de « Supprimer » à l'œil dans ces secteurs)
function RZ.isProtectedArea(p)
    if type(p) ~= 'table' and type(p) ~= 'vector3' then return false end
    for _, s in pairs(byId) do
        if inArea(s, p) then return true end
    end
    return false
end
exports('isProtectedArea', function(p) return RZ.isProtectedArea(p) end)

--- « Modifier la description » : le civil (mode civil, hors unité du MDC) qui a créé la scène, dans son secteur
local function canEdit(s, me)
    return s.src ~= nil and s.src == myServerId() and RZ.civilMode() and not RZ.isPolice() and inArea(s, me)
end

local function labelOf(s)
    if s.kind == 'zone' then return 'Zone de recherche' end
    return s.vehicle and 'Véhicule à fouiller' or (s.kind == 'object' and 'Objet à fouiller' or 'Lieu à fouiller')
end

exports('targetOptions', function(info)
    if type(info) ~= 'table' or type(info.hit) ~= 'table' then return nil end
    local meV = GetEntityCoords(PlayerPedId())
    local me = { x = meV.x, y = meV.y, z = meV.z }
    local s = aimedScene(info)
    if not s then
        -- sa propre zone de recherche (on vise le sol dans la zone ou à ses alentours) : la modifier
        for _, z in pairs(byId) do
            if z.kind == 'zone' and canEdit(z, me) and inArea(z, info.hit) then
                return { label = labelOf(z), options = { { id = 'edit:' .. z.id, icon = 'note', label = 'Modifier la zone de recherche' } } }
            end
        end
        return nil
    end
    local options = {}
    local c = RZ.scenePos(s)
    local d = #(meV - vector3(c.x, c.y, c.z))
    if RZ.isSearcher() and not searching and d <= reachOf(s) + 0.5 then
        options[#options + 1] = { id = 'search:' .. s.id, icon = 'search', police = true,
            label = s.vehicle and 'Fouiller le véhicule' or (s.kind == 'object' and 'Fouiller l\'objet' or 'Fouiller les lieux') }
    end
    if canEdit(s, me) then
        options[#options + 1] = { id = 'edit:' .. s.id, icon = 'note', label = 'Modifier la description' }
    end
    if #options == 0 then return nil end
    return { label = labelOf(s), options = options }
end)

exports('targetSelect', function(id, info)
    local action, sid = tostring(id):match('^(%a+):(%d+)$')
    local s = byId[tonumber(sid)]
    if not s then return RZ.notify('Il n\'y a plus rien ici.') end
    if action == 'search' then
        local c = RZ.scenePos(s)
        if #(GetEntityCoords(PlayerPedId()) - vector3(c.x, c.y, c.z)) > reachOf(s) + 1.0 then
            return RZ.notify('Rapprochez-vous pour fouiller.')
        end
        CreateThread(function() RZ.search(s) end)
    elseif action == 'edit' and RZ.openEdit then
        RZ.openEdit(s.id)
    end
end)

-- =========================================================================
-- DESCRIPTION VISUELLE : au-dessus du lieu / de l'objet, pour les policiers à moins de 10 m qui le voient
-- =========================================================================
local LK = Config.Look or {}
local looks = {}          -- [id] = { s, visible, anchor } : descriptions proches
local lookRunning = false

--- Point au-dessus duquel la description s'affiche
local function lookAnchor(s)
    if s.kind == 'object' then
        local e = RZ.sceneEntity(s)
        if e then
            local _, max = GetModelDimensions(GetEntityModel(e))
            local c = GetEntityCoords(e)
            return vector3(c.x, c.y, c.z + math.max(0.3, max.z) + 0.35), e
        end
    end
    local c = RZ.scenePos(s)
    return vector3(c.x, c.y, c.z + 0.9), nil
end

--- Visible : rien entre la caméra et le point (un mur, un véhicule…), l'objet lui-même mis à part
local function inSight(anchor, entity)
    local cam = GetFinalRenderedCamCoord()
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, anchor.x, anchor.y, anchor.z,
        1 + 2 + 16, PlayerPedId(), 7)
    local _, hit, coords, _, hitEntity = GetShapeTestResult(ray)
    if hit ~= 1 and hit ~= true then return true end
    if entity and hitEntity == entity then return true end
    return #(coords - anchor) <= 0.6
end

--- Texte coupé en lignes de ~38 caractères
local function wrap(text, width)
    local lines = {}
    for paragraph in (text .. '\n'):gmatch('(.-)\n') do
        local line = ''
        for word in paragraph:gmatch('%S+') do
            if #line + #word + 1 > width and line ~= '' then lines[#lines + 1] = line; line = word
            else line = line == '' and word or (line .. ' ' .. word) end
        end
        if line ~= '' then lines[#lines + 1] = line end
    end
    return lines
end

local function drawLook(anchor, lines, distance)
    local scale = (LK.Scale or 0.34) * math.max(0.75, math.min(1.15, 6.0 / math.max(distance, 1.0)))
    local color = LK.Color or { 245, 238, 215 }
    local lineH = 0.028 * scale / 0.34
    local longest = 0
    for _, l in ipairs(lines) do if #l > longest then longest = #l end end
    SetDrawOrigin(anchor.x, anchor.y, anchor.z, 0)
    local height = #lines * lineH + 0.012
    DrawRect(0.0, (#lines - 1) * lineH / 2 + lineH * 0.45, longest * 0.0052 * scale / 0.34 + 0.016, height, 0, 0, 0, 140)
    for i, l in ipairs(lines) do
        SetTextFont(4)
        SetTextScale(0.0, scale)
        SetTextColour(color[1], color[2], color[3], 235)
        SetTextCentre(true)
        SetTextOutline()
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(l)
        EndTextCommandDisplayText(0.0, (i - 1) * lineH)
    end
    ClearDrawOrigin()
end

local function lookLoop()
    if lookRunning then return end
    lookRunning = true
    CreateThread(function()
        local nextCheck = 0
        while next(looks) do
            local now = GetGameTimer()
            local me = GetEntityCoords(PlayerPedId())
            if now >= nextCheck then
                nextCheck = now + (LK.CheckInterval or 250)
                for _, l in pairs(looks) do
                    l.anchor, l.entity = lookAnchor(l.s)
                    l.visible = #(me - l.anchor) <= (LK.Distance or 10.0) + 0.5 and inSight(l.anchor, l.entity)
                end
            end
            if not IsPauseMenuActive() then
                for _, l in pairs(looks) do
                    if l.visible then drawLook(l.anchor, l.lines, #(me - l.anchor)) end
                end
            end
            Wait(0)
        end
        lookRunning = false
    end)
end

--- Descriptions visuelles proches (toutes les 500 ms, depuis la boucle principale)
local function updateLooks(p)
    local wanted = {}
    if RZ.isSearcher() then
        for _, s in pairs(byId) do
            if s.look and s.look ~= '' and s.kind ~= 'zone' then
                local c = RZ.scenePos(s)
                if RZ.dist2D(c, p) <= (LK.Distance or 10.0) + 2.0 and math.abs(c.z - p.z) <= 8.0 then wanted[s.id] = s end
            end
        end
    end
    for id in pairs(looks) do if not wanted[id] then looks[id] = nil end end
    for id, s in pairs(wanted) do
        if not looks[id] or looks[id].s ~= s then looks[id] = { s = s, lines = wrap(s.look, 38), visible = false } end
    end
    if next(looks) then lookLoop() end
end

-- =========================================================================
-- RIEN NE DISPARAÎT : PROTECTION ET OBJET REMIS
-- =========================================================================
local function protectRadius(s)
    if s.kind == 'zone' then return s.radius end
    return math.max(PR.Radius or 10.0, s.radius or 0)
end

local function covered(e)
    if not DoesEntityExist(e) then return false end
    local c = GetEntityCoords(e)
    for _, s in pairs(byId) do
        if RZ.dist2D(RZ.scenePos(s), c) <= protectRadius(s) then return true end
    end
    return false
end

local function canTouch(e)
    return not NetworkGetEntityIsNetworked(e) or NetworkHasControlOfEntity(e)
end

local function mark(e)
    if protected[e] or IsEntityAMissionEntity(e) or not canTouch(e) then return false end
    SetEntityAsMissionEntity(e, true, true)
    protected[e] = true
    return true
end

local function protectScene(s, pools)
    local r = protectRadius(s)
    local center = RZ.scenePos(s)
    local budget = PR.MaxPerScene or 250
    local function within(e)
        local c = GetEntityCoords(e)
        local dx, dy = c.x - center.x, c.y - center.y
        return dx * dx + dy * dy <= r * r and math.abs(c.z - center.z) <= r + 15.0
    end
    if PR.Objects ~= false then
        for _, e in ipairs(pools.objects) do
            if budget <= 0 then break end
            if within(e) and mark(e) then budget = budget - 1 end
        end
    end
    if PR.Peds ~= false then
        for _, e in ipairs(pools.peds) do
            if budget <= 0 then break end
            if not IsPedAPlayer(e) and within(e) and mark(e) then budget = budget - 1 end
        end
    end
    if PR.ParkedVehicles ~= false then
        for _, e in ipairs(pools.vehicles) do
            if budget <= 0 then break end
            if IsVehicleSeatFree(e, -1) and within(e) and mark(e) then budget = budget - 1 end
        end
    end
end

--- Objet à fouiller : toujours là (sinon une copie fixe à sa place, propre à ce joueur)
local function checkObject(s, p)
    if not PR.RestoreObject or s.kind ~= 'object' or not s.model or s.vehicle then return end
    if RZ.dist2D(s.pos, p) > 70.0 then return end
    local copy = restored[s.id]
    local found = GetClosestObjectOfType(s.pos.x, s.pos.y, s.pos.z, 0.8, s.model, false, false, false)
    if found ~= 0 and found ~= copy then
        -- l'objet d'origine est là : la copie ne sert plus
        if copy and DoesEntityExist(copy) then DeleteEntity(copy) end
        restored[s.id], missing[s.id] = nil, 0
        mark(found)
        return
    end
    if copy and DoesEntityExist(copy) then return end
    if not HasCollisionLoadedAroundEntity(PlayerPedId()) then return end
    missing[s.id] = (missing[s.id] or 0) + 1
    if missing[s.id] < 2 then return end -- absent deux fois de suite (4 s) : remis
    if not IsModelInCdimage(s.model) then return end
    RequestModel(s.model)
    local timeout = GetGameTimer() + 2000
    while not HasModelLoaded(s.model) and GetGameTimer() < timeout do Wait(10) end
    if not HasModelLoaded(s.model) or not byId[s.id] then return end
    local obj = CreateObjectNoOffset(s.model, s.pos.x, s.pos.y, s.pos.z, false, false, false)
    SetEntityRotation(obj, s.rot and s.rot.x or 0.0, s.rot and s.rot.y or 0.0, s.rot and s.rot.z or 0.0, 2, true)
    FreezeEntityPosition(obj, true)
    SetEntityAsMissionEntity(obj, true, true)
    SetModelAsNoLongerNeeded(s.model)
    restored[s.id] = obj
end

local function protectAll(p)
    if PR.Enabled == false then return end
    local near = {}
    for _, s in pairs(byId) do
        if RZ.dist2D(RZ.scenePos(s), p) <= (PR.Range or 150.0) + protectRadius(s) then near[#near + 1] = s end
    end
    if #near == 0 then return end
    local pools = { objects = GetGamePool('CObject'), peds = GetGamePool('CPed'), vehicles = GetGamePool('CVehicle') }
    for _, s in ipairs(near) do
        protectScene(s, pools)
        checkObject(s, p)
    end
end

--- Entités qui ne sont plus dans aucune scène : rendues au jeu ; copies d'objets de scènes supprimées : retirées
local function release()
    for e in pairs(protected) do
        if not DoesEntityExist(e) then
            protected[e] = nil
        elseif not covered(e) and canTouch(e) then
            SetEntityAsNoLongerNeeded(e)
            protected[e] = nil
        end
    end
    for id, obj in pairs(restored) do
        if not byId[id] then
            if DoesEntityExist(obj) then DeleteEntity(obj) end
            restored[id], missing[id] = nil, nil
        end
    end
end

-- =========================================================================
-- BOUCLE (seulement s'il y a des scènes)
-- =========================================================================
local function loop()
    if running then return end
    running = true
    CreateThread(function()
        while running do
            local ped = PlayerPedId()
            local c = GetEntityCoords(ped)
            local p = { x = c.x, y = c.y, z = c.z }
            updateZone(p)
            updateNearSearch(p, ped)
            updateLooks(p)
            local now = GetGameTimer()
            if now - lastProtect >= 2000 then
                lastProtect = now
                release() -- PNJ / véhicules sortis des scènes : rendus au jeu
                protectAll(p)
            end
            Wait(500)
        end
    end)
end

local function onScenes()
    rebuild()
    if insideZone and not byId[insideZone] then leaveZone(true) end -- zone supprimée : message retiré
    if insideZone and byId[insideZone] then -- description modifiée par le civil
        local s = byId[insideZone]
        SendNUIMessage({ action = 'zone', data = { show = true, title = s.title or '', text = s.text or '', label = s.label or '' } })
    end
    release()
    if next(byId) then
        loop()
    else
        running = false
        nearSearch = nil
    end
    if RZ.onScenesChanged then RZ.onScenesChanged() end
end

AddStateBagChangeHandler('rpScenes', 'global', function()
    SetTimeout(0, onScenes) -- GlobalState mis à jour après l'appel
end)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('rp_scene:hello')
    onScenes()
end)

-- =========================================================================
-- ARRÊT DE LA RESSOURCE : tout est rendu au jeu
-- =========================================================================
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    removeBlip()
    for e in pairs(protected) do
        if DoesEntityExist(e) and canTouch(e) then SetEntityAsNoLongerNeeded(e) end
    end
    for _, obj in pairs(restored) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
end)
