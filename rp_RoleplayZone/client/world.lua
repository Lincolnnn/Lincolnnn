--[[
    RP RoleplayZone - client : scènes appliquées dans le monde
    ----------------------------------------------------------
    - ZONE DE RECHERCHE (policiers) : en entrant, la description du civil s'affiche en haut au milieu de l'écran et y
      reste jusqu'à la sortie (ou la suppression de la zone) ; un court son d'intrigue à l'entrée, un son proche qui
      « lève » l'intrigue à la sortie ; le cercle de la zone apparaît sur la carte seulement pendant qu'on est dedans.
    - PÉRIMÈTRE / OBJET À FOUILLER (policiers) : sur place, « E Fouiller… » -> barre de chargement (X annule) -> le
      contenu écrit par le civil (fiche à l'écran + copie privée dans le chat). Non signalés avant d'y être :
      l'œil d'aigle aide à les trouver.
    - RIEN NE DISPARAÎT (Config.Protect) : autour de chaque scène, objets du décor, PNJ et véhicules stationnés
      marqués comme entités de mission (un « ClearArea » d'un autre script ne les retire plus) ; l'objet à fouiller
      est remis à sa place (copie fixe) s'il disparaît quand même.

    Performance : aucune scène -> aucune boucle. Sinon une vérification toutes les 500 ms (distances) ; boucle à chaque
    image seulement à côté d'une fouille (aide « E »), ou pendant une fouille. Protection : toutes les 2 s, seulement
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

--- Objet d'une scène « objet » : l'objet du décor à sa place, ou sa copie remise ; nil s'il n'est pas chargé
function RZ.sceneEntity(s)
    if s.kind ~= 'object' or not s.model then return nil end
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
-- FOUILLES
-- =========================================================================
--- Distance à laquelle on peut fouiller une scène
local function reachOf(s)
    if s.kind == 'perimeter' then return s.radius + (SR.Distance or 1.2) end
    return (Config.Object and Config.Object.Distance or 1.8) + (s.radius or 1.0) * 0.5
end

local function showResult(res)
    SendNUIMessage({ action = 'result', data = {
        kind = res.kind, title = res.title or '', text = res.text or '', label = res.label or '',
        duration = SR.ResultDuration or 25000,
    } })
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started' then
        pcall(function()
            exports[chat]:addPrivate({ title = res.kind == 'object' and 'Fouille de l\'objet' or 'Fouille des lieux',
                subject = (res.title ~= '' and res.title) or res.label or '', text = res.text })
        end)
    end
end

local PROGRESS_BLOCKED = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 44, 140, 141, 142, 143, 257, 263, 264 }

local function search(s)
    if searching then return end
    searching = true
    local ped = PlayerPedId()
    local label = s.kind == 'object' and 'Fouille de l\'objet' or 'Fouille des lieux'
    local time = SR.Time or 6000
    SendNUIMessage({ action = 'progress', data = { show = true, label = label, duration = time } })
    if s.kind == 'object' then
        local e = RZ.sceneEntity(s)
        local target = e and GetEntityCoords(e) or vector3(s.pos.x, s.pos.y, s.pos.z)
        TaskTurnPedToFaceCoord(ped, target.x, target.y, target.z, 600)
        Wait(600)
    end
    local scenario = s.kind == 'object' and SR.ObjectScenario or SR.PerimeterScenario
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
        ClearPedTasks(ped)
        searching = false
        if reason == 'cancel' then return RZ.notify('Fouille annulée.') end
        if reason then return end
        RZ.request('search', { id = s.id }, function(res)
            if not res.ok then return RZ.notify(res.error or 'Fouille impossible.') end
            showResult(res)
        end)
    end)
end

--- Aide « E Fouiller… » à chaque image tant qu'une fouille est à portée
local promptRunning = false
local function promptLoop()
    if promptRunning then return end
    promptRunning = true
    CreateThread(function()
        while nearSearch do
            local s = nearSearch.scene
            if not searching and not IsPauseMenuActive() and not RZ.selecting() then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName(s.kind == 'object' and '~INPUT_CONTEXT~ Fouiller l\'objet'
                    or '~INPUT_CONTEXT~ Fouiller les lieux')
                EndTextCommandDisplayHelp(0, false, false, -1)
                if IsControlJustPressed(0, SR.Key or 38) then search(s) end
            end
            Wait(0)
        end
        promptRunning = false
    end)
end

local function updateNearSearch(p, ped)
    nearSearch = nil
    if not RZ.isSearcher() or IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end
    local best, bestD
    for _, s in pairs(byId) do
        if s.kind ~= 'zone' then
            local d = #(vector3(p.x, p.y, p.z) - vector3(s.pos.x, s.pos.y, s.pos.z))
            if d <= reachOf(s) and (not bestD or d < bestD) then best, bestD = s, d end
        end
    end
    if best then
        nearSearch = { scene = best }
        promptLoop()
    end
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
        if RZ.dist2D(s.pos, c) <= protectRadius(s) then return true end
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
    local budget = PR.MaxPerScene or 250
    local function within(e)
        local c = GetEntityCoords(e)
        local dx, dy = c.x - s.pos.x, c.y - s.pos.y
        return dx * dx + dy * dy <= r * r and math.abs(c.z - s.pos.z) <= r + 15.0
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
    if not PR.RestoreObject or s.kind ~= 'object' or not s.model then return end
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
        if RZ.dist2D(s.pos, p) <= (PR.Range or 150.0) + protectRadius(s) then near[#near + 1] = s end
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
