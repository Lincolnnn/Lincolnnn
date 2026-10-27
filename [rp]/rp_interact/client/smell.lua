--[[
    RP Interact - odeurs détectées automatiquement (côté policier)
    --------------------------------------------------------------
    Dans la fiche civile (/fichecivil), le joueur civil choisit jusqu'à Smell.Max odeurs (drogues, alcool, autres :
    config.lua, Smells) pour son profil et / ou son véhicule. Le serveur envoie aux SEULS policiers en service (unité
    du MDC) les joueurs (profil actif) et les véhicules (profil) qui en ont. Un policier qui passe à moins de
    Smell.Distance m (6 m) de l'un d'eux reçoit une notification en haut de l'écran, comme l'entrée dans une zone de
    recherche de /scene (bandeau + court son) : « ODEUR DÉTECTÉE · Individu à proximité / Véhicule à proximité ».
    Une fois par source tant qu'il reste à côté ; de nouveau après s'être éloigné et Smell.Cooldown ms.
    Performance : aucune boucle hors service ou sans odeur autour ; sinon une distance par source toutes les 500 ms.
]]

local Config = InteractConfig
local S = Config.Smell or {}
local DISTANCE = S.Distance or 6.0
local LEAVE = DISTANCE + 1.5 -- s'éloigner un peu plus pour être prévenu de nouveau

local sources = { players = {}, vehicles = {} }
local state = {}   -- [clé] = { near, at }
local running = false

RPISmell = {} -- pour les tests

local function hasSources() return #sources.players > 0 or #sources.vehicles > 0 end

--- Le joueur est-il (encore) civil ? Un joueur entré dans une unité du MDC n'a plus d'odeur de profil
local function isPoliceTarget(serverId)
    local ok, unit = pcall(function() return Player(serverId).state.mdcUnit end)
    return ok and type(unit) == 'string' and unit ~= ''
end

--- Entité d'une source (nil si absente / pas chargée près du joueur)
local function playerPed(serverId)
    if serverId == GetPlayerServerId(PlayerId()) or isPoliceTarget(serverId) then return nil end
    local player = GetPlayerFromServerId(serverId)
    if not player or player == -1 then return nil end
    local ped = GetPlayerPed(player)
    return ped ~= 0 and DoesEntityExist(ped) and ped or nil
end

local function vehicleOf(netId)
    if not NetworkDoesNetworkIdExist(netId) then return nil end
    local vehicle = NetToVeh(netId)
    return vehicle ~= 0 and DoesEntityExist(vehicle) and vehicle or nil
end

local function show(found)
    local lines, labels = {}, {}
    for _, f in ipairs(found) do
        lines[#lines + 1] = RPISmells.sentence(f.text) .. '.'
        labels[#labels + 1] = f.label
    end
    SendNUIMessage({ action = 'smell', data = {
        show = true, label = table.concat(labels, ' · '), lines = lines,
        duration = S.Duration or 9000, volume = S.Volume or 0.4,
    } })
end

--- Une vérification : nouvelles odeurs à moins de DISTANCE m -> notification (regroupées)
local function check()
    local me = GetEntityCoords(PlayerPedId())
    local now = GetGameTimer()
    local found, alive = {}, {}
    local function test(key, entity, text, label)
        alive[key] = true
        local s = state[key] or {}
        state[key] = s
        local d = entity and #(me - GetEntityCoords(entity)) or math.huge
        if d <= DISTANCE then
            if not s.near and (not s.at or now - s.at >= (S.Cooldown or 60000)) then
                s.at = now
                found[#found + 1] = { text = text, label = label }
            end
            s.near = true
        elseif d > LEAVE then
            s.near = false
        end
    end
    for _, p in ipairs(sources.players) do test('p' .. p.id, playerPed(p.id), p.text, 'Individu à proximité') end
    for _, v in ipairs(sources.vehicles) do test('v' .. v.netId, vehicleOf(v.netId), v.text, 'Véhicule à proximité') end
    for key in pairs(state) do if not alive[key] then state[key] = nil end end
    if #found > 0 then show(found) end
end
RPISmell.check = check

local function start()
    if running or S.Enabled == false or not RPI.isPolice() or not hasSources() then return end
    running = true
    CreateThread(function()
        while RPI.isPolice() and hasSources() do
            if not IsEntityDead(PlayerPedId()) then check() end
            Wait(500)
        end
        running = false
    end)
end

local function setSources(list)
    list = type(list) == 'table' and list or {}
    sources = { players = {}, vehicles = {} }
    for _, p in ipairs(type(list.players) == 'table' and list.players or {}) do
        if tonumber(p.id) and type(p.text) == 'string' then sources.players[#sources.players + 1] = { id = tonumber(p.id), text = p.text } end
    end
    for _, v in ipairs(type(list.vehicles) == 'table' and list.vehicles or {}) do
        if tonumber(v.netId) and type(v.text) == 'string' then sources.vehicles[#sources.vehicles + 1] = { netId = tonumber(v.netId), text = v.text } end
    end
    start()
end
RPISmell.set = setSources

RegisterNetEvent('rp_interact:client:smells', setSources)

-- Entrée / sortie de service : le serveur renvoie la liste à jour à tous les policiers (moi compris)
RPI.onDuty(function()
    if not RPI.isPolice() then
        sources, state = { players = {}, vehicles = {} }, {}
        SendNUIMessage({ action = 'smell', data = { show = false } })
    end
    RPI.request('dutyChanged', {}, function() end)
end)

-- Déjà en service au démarrage du script
CreateThread(function()
    Wait(2000)
    if S.Enabled ~= false and RPI.isPolice() then
        RPI.request('getSmells', {}, function(res) if res and res.ok then setSources(res.smells) end end)
    end
end)
