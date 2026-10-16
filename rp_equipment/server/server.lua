--[[
    RP Equipment - serveur
    ----------------------
    - Types de véhicules : modèles de config.lua + services de rp_interact/data/vehicles.json, publiés à tous
      les clients (GlobalState.rpEquipModels : [hash du modèle] = type).
    - Vérifie chaque demande : policier en service (unité du MDC), près du véhicule, pièce / emplacement permis
      pour ce type de véhicule.
    - Équipement EUP par catégorie de véhicule (equipment.json, même format que les tenues du /eup).
    - Râtelier d'armes longues par plaque (data/racks.json) : rangé / ressorti à l'identique (modèle,
      accessoires, teintes). Une seule arme par emplacement, même si deux policiers cliquent ensemble.
    - Coffre comme un inventaire, par plaque (data/stock.json) : plots de circulation (6 au départ, 10 au maximum ; un
      plot pris et pas remis n'y est plus) et fusées de détresse ; plots posés au sol et ramassés.
    Performance : aucune boucle.
]]

local Config = EquipConfig
local Racks = {}       -- [plaque] = { [emplacement] = arme }

local function trim(text) return (tostring(text or '')):gsub('^%s+', ''):gsub('%s+$', '') end

-- =========================================================================
-- TYPES DE VÉHICULES
-- =========================================================================
local function readInteractVehicles()
    local source = Config.InteractVehicles
    if not source or not source.Resource then return {} end
    local raw = LoadResourceFile(source.Resource, source.File or 'data/vehicles.json')
    if not raw or raw == '' then return {} end
    local ok, list = pcall(json.decode, raw)
    if not ok or type(list) ~= 'table' then
        print(('^3[rp_equipment] %s/%s illisible : services des véhicules ignorés^7'):format(source.Resource, source.File))
        return {}
    end
    return list
end

local function field(object, name)
    if type(object) ~= 'table' then return nil end
    if object[name] ~= nil then return object[name] end
    for key, value in pairs(object) do
        if type(key) == 'string' and key:lower() == name:lower() then return value end
    end
    return nil
end

local function buildModels()
    local models = {}
    -- 1. Services de rp_interact
    for _, v in ipairs(readInteractVehicles()) do
        local code = trim(field(v, 'Code'))
        local kind = (Config.ServiceTypes or {})[trim(field(v, 'Service')):lower()]
        if code ~= '' and kind and Config.Types[kind] then models[GetHashKey(code)] = kind end
    end
    -- 2. Modèles de config.lua (prioritaires)
    for kind, t in pairs(Config.Types) do
        for _, model in ipairs(t.Models or {}) do models[GetHashKey(model)] = kind end
    end
    GlobalState.rpEquipModels = models
    return models
end
local Models = buildModels()

-- =========================================================================
-- ÉQUIPEMENT EUP PAR CATÉGORIE (equipment.json)
-- =========================================================================
local OUTFIT_PARTS = {
    Hat = { prop = 0 }, Glasses = { prop = 1 }, Ear = { prop = 2 }, Watch = { prop = 6 }, Bracelet = { prop = 7 },
    Mask = { component = 1 }, UpperSkin = { component = 3 }, Pants = { component = 4 }, Parachute = { component = 5 },
    Shoes = { component = 6 }, Accessories = { component = 7 }, UnderCoat = { component = 8 }, Armor = { component = 9 },
    Decal = { component = 10 }, Top = { component = 11 },
}
local Assets = {}   -- [type] = { { id, name, gender, components = { {n°, modèle, texture} }, props = {...} } }

--- Type d'une catégorie du fichier : "Atlanta Police Department" (ServiceTypes) ou directement "apd"
local function typeOfCategory(name)
    local key = trim(name):lower()
    local kind = (Config.ServiceTypes or {})[key] or key
    return Config.Types[kind] and kind or nil
end

local function parseAsset(o, oneBased)
    local name = trim(field(o, 'Name'))
    if name == '' then return nil end
    -- Objet (arme du jeu), ex. jerrican : { "Name": "Jerrican d'essence", "Weapon": "WEAPON_PETROLCAN", "Ammo": 4500 }
    local weapon = trim(field(o, 'Weapon')):upper()
    if weapon ~= '' then
        return { name = name:sub(1, 60), item = true, weapon = weapon, ammo = math.max(0, math.floor(tonumber(field(o, 'Ammo')) or 0)) }
    end
    local gender = trim(field(o, 'Gender')):lower()
    gender = (gender == 'female' or gender == 'femme' or gender == 'f') and 'female'
        or ((gender == 'male' or gender == 'homme' or gender == 'm') and 'male' or nil)
    local components, props = {}, {}
    for part, target in pairs(OUTFIT_PARTS) do
        local d, t = tostring(field(o, part) or ''):match('^%s*(%-?%d+)%s*:%s*(%-?%d+)%s*$')
        d, t = tonumber(d), tonumber(t)
        if d then
            if oneBased then d, t = d - 1, math.max((t or 1) - 1, 0) end
            if target.prop then props[#props + 1] = { target.prop, d, t or 0 }
            else components[#components + 1] = { target.component, math.max(d, 0), t or 0 } end
        end
    end
    if #components == 0 and #props == 0 then return nil end
    return { name = name:sub(1, 60), gender = gender, components = components, props = props }
end

local function loadAssets()
    Assets = {}
    local file = Config.EquipmentFile or 'equipment.json'
    local raw = LoadResourceFile(GetCurrentResourceName(), file)
    if not raw or raw == '' then
        print(('^3[rp_equipment] %s introuvable : aucun équipement EUP^7'):format(file))
        return
    end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        print(('^1[rp_equipment] %s illisible (JSON invalide) : aucun équipement EUP^7'):format(file))
        return
    end
    local oneBased = not (Config.Eup and Config.Eup.OneBased == false)
    local count = 0
    for category, list in pairs(data) do
        local kind = typeOfCategory(category)
        if not kind then
            print(('^3[rp_equipment] %s : catégorie "%s" inconnue (ignorée)^7'):format(file, tostring(category)))
        elseif type(list) == 'table' then
            Assets[kind] = Assets[kind] or {}
            for i, o in ipairs(list) do
                local asset = parseAsset(o, oneBased)
                if asset then
                    asset.id = ('%s:%d'):format(kind, #Assets[kind] + 1)
                    Assets[kind][#Assets[kind] + 1] = asset
                    count = count + 1
                else
                    print(('^3[rp_equipment] %s : "%s" n°%d ignoré (Name ou pièce manquant)^7'):format(file, category, i))
                end
            end
        end
    end
    print(('^5[rp_equipment]^7 %d pièce(s) d\'équipement EUP (%s)'):format(count, file))
end
loadAssets()

RegisterCommand('rpequip_reload', function(src)
    if src ~= 0 then return end
    Models = buildModels()
    loadAssets()
    print('[rp_equipment] types de véhicules et équipement relus')
end, true)

--- Type d'un véhicule : modèle connu, sinon celui annoncé par le client si ce type se reconnaît à la classe
--- (la classe d'un véhicule n'est lisible que par le client)
local function vehicleType(vehicle, claimed)
    local known = Models[GetEntityModel(vehicle)]
    if known then return known end
    local t = Config.Types[claimed]
    if t and t.Classes and #t.Classes > 0 then return claimed end
    return nil
end

-- =========================================================================
-- RÂTELIERS (par plaque)
-- =========================================================================
local function loadRacks()
    local raw = LoadResourceFile(GetCurrentResourceName(), Config.LongGuns.SaveFile)
    if not raw or raw == '' then return end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == 'table' then Racks = data else
        print('^1[rp_equipment] ' .. Config.LongGuns.SaveFile .. ' illisible : râteliers vides (le fichier n\'est pas écrasé avant une modification)^7')
    end
end
loadRacks()

local function saveRacks()
    SaveResourceFile(GetCurrentResourceName(), Config.LongGuns.SaveFile, json.encode(Racks, { indent = true }), -1)
end

local function plateOf(vehicle)
    local plate = trim(GetVehicleNumberPlateText(vehicle))
    return plate ~= '' and plate:upper() or nil
end

--- Résumé d'un râtelier pour le menu : [emplacement] = { label, components } ou false
local function rackSummary(plate)
    local rack = Racks[plate] or {}
    local out = {}
    for _, slot in ipairs(Config.LongGuns.Slots) do
        local w = rack[slot.Id]
        out[slot.Id] = w and { label = w.label, components = #(w.components or {}) } or false
    end
    return out
end

-- =========================================================================
-- VÉRIFICATIONS
-- =========================================================================
--- Unité MDC du joueur (policier en service) ou nil. Le MDC publie son nom de ressource (GlobalState.mdcResource),
--- quel que soit le nom de son dossier ; en secours : l'état "mdcUnit" que le MDC donne au joueur.
local function policeUnit(src)
    if not Config.PoliceOnly then return { name = 'Tous' } end
    local resource = GlobalState.mdcResource or Config.MdcResource or 'mdc_standalone'
    if GetResourceState(resource) == 'started' then
        local ok, unit = pcall(function() return exports[resource]:getPlayerUnit(src) end)
        if ok and type(unit) == 'table' then return unit end
    end
    local name = Player(src).state.mdcUnit
    if type(name) == 'string' and name ~= '' then return { name = name } end
    return nil
end

local function nearVehicle(src, netId)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or -1)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    -- distance au centre du véhicule (la carrosserie côté client) : marge pour les grands véhicules
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > (Config.CloseDistance or 4.0) + 5.0 then return nil end
    return vehicle
end

local function allowedFor(entry, kind)
    if not entry.Vehicles then return true end
    for _, k in ipairs(entry.Vehicles) do if k == kind then return true end end
    return false
end

local function allowedWhere(entryWhere, where)
    return entryWhere == 'both' or entryWhere == nil or entryWhere == where
end

local SLOTS = {}
for _, slot in ipairs(Config.LongGuns.Slots) do SLOTS[slot.Id] = slot end

--- Contexte d'une demande : unité, véhicule, type, plaque ; nil + erreur
local function context(src, data)
    if type(data) ~= 'table' then return nil, 'Demande invalide.' end
    local unit = policeUnit(src)
    if not unit then return nil, 'Réservé aux policiers en service (unité du MDC).' end
    local vehicle = nearVehicle(src, data.net)
    if not vehicle then return nil, 'Vous êtes trop loin du véhicule.' end
    local kind = vehicleType(vehicle, data.type)
    if not kind then return nil, 'Ce véhicule n\'a pas d\'équipement.' end
    local where = data.where == 'trunk' and 'trunk' or 'front'
    return { unit = unit, vehicle = vehicle, kind = kind, where = where, plate = plateOf(vehicle) }
end

local function rackAllowed(ctx)
    local lg = Config.LongGuns
    return allowedWhere(lg.Where, ctx.where) and allowedFor(lg, ctx.kind)
end

-- =========================================================================
-- DEMANDES DU CLIENT (réponse : rp_equipment:response)
-- =========================================================================
local Handlers = {}

-- =========================================================================
-- COFFRE : INVENTAIRE (plots de circulation, fusées de détresse), par plaque (Stock.SaveFile)
--   Un plot pris et jamais remis n'y est plus ; un plot ramassé peut être rangé dans n'importe quel coffre (max).
--   Un policier porte plusieurs plots (Cones.MaxCarry) : il en prend le nombre voulu, en ramasse plusieurs, range tout.
-- =========================================================================
local S = Config.Stock or {}
local Stock = {}       -- [plaque] = { cones, flares }
local carrying = {}    -- [joueur] = nombre de plots portés (pris dans un coffre ou ramassés au sol)
local placedCones = {} -- [objet] = { x, y, z } : plots posés (publiés pour la déviation du trafic PNJ)
local MAX_CARRY = math.max(1, math.floor(tonumber(S.Cones and S.Cones.MaxCarry) or 10))

local function carried(src) return carrying[src] or 0 end
local function setCarried(src, n) carrying[src] = n > 0 and n or nil end

local function loadStock()
    local raw = S.SaveFile and LoadResourceFile(GetCurrentResourceName(), S.SaveFile)
    if not raw or raw == '' then return end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == 'table' then Stock = data else
        print('^1[rp_equipment] ' .. S.SaveFile .. ' illisible : coffres remis à leur contenu de départ^7')
    end
end
loadStock()

local function saveStock()
    if S.SaveFile then SaveResourceFile(GetCurrentResourceName(), S.SaveFile, json.encode(Stock, { indent = true }), -1) end
end

--- Contenu du coffre de cette plaque (contenu de départ si le coffre n'a jamais servi)
local function stockOf(plate)
    local st = Stock[plate]
    if not st then
        st = { cones = S.Cones and S.Cones.Default or 0, flares = S.Flares and S.Flares.Default or 0 }
        Stock[plate] = st
    end
    return st
end

local function stockView(plate)
    local st = stockOf(plate)
    return { cones = st.cones, flares = st.flares, maxCones = S.Cones and S.Cones.Max or 0, maxFlares = S.Flares and S.Flares.Max or 0 }
end

local function stockAllowed(ctx)
    return S.Enabled ~= false and ctx.plate ~= nil and allowedWhere(S.Where or 'trunk', ctx.where)
end

--- Coffre changé : tous les menus ouverts sur cette plaque mis à jour
local function stockChanged(plate)
    saveStock()
    TriggerClientEvent('rp_equipment:stock', -1, plate, stockView(plate))
end

function Handlers.open(src, data)
    local ctx, err = context(src, data)
    if not ctx then return { ok = false, error = err } end
    return {
        ok = true, type = ctx.kind, plate = ctx.plate, assets = Assets[ctx.kind] or {},
        rack = rackAllowed(ctx) and ctx.plate and rackSummary(ctx.plate) or false,
        stock = stockAllowed(ctx) and stockView(ctx.plate) or false, carrying = carried(src), maxCarry = MAX_CARRY,
    }
end

--- /restock : coffre du véhicule rempli à 100 % (plots et fusées au maximum) ; les armes longues ne sont pas touchées
function Handlers.restock(src, data)
    local ctx, err = context(src, data)
    if not ctx then return { ok = false, error = err } end
    if S.Enabled == false or not ctx.plate then return { ok = false, error = 'Ce véhicule n\'a pas de coffre.' } end
    local st = stockOf(ctx.plate)
    st.cones = S.Cones and S.Cones.Max or 10
    st.flares = S.Flares and S.Flares.Max or 20
    stockChanged(ctx.plate)
    return { ok = true, plate = ctx.plate, stock = stockView(ctx.plate) }
end

--- Prendre `count` plots dans le coffre (le joueur les porte, en plus de ceux qu'il a déjà, MaxCarry au plus)
function Handlers.coneTake(src, data)
    local ctx, err = context(src, data)
    if not ctx then return { ok = false, error = err } end
    if not stockAllowed(ctx) then return { ok = false, error = 'Pas de coffre ici.' } end
    local room = MAX_CARRY - carried(src)
    if room <= 0 then return { ok = false, error = ('Vous portez déjà %d plots (maximum).'):format(MAX_CARRY) } end
    local st = stockOf(ctx.plate)
    if st.cones <= 0 then return { ok = false, error = 'Plus de plot dans ce coffre.' } end
    local count = math.min(math.max(1, math.floor(tonumber(data.count) or 1)), room, st.cones)
    st.cones = st.cones - count
    setCarried(src, carried(src) + count)
    stockChanged(ctx.plate)
    return { ok = true, count = count, carrying = carried(src), stock = stockView(ctx.plate) }
end

--- Ranger d'un coup tous les plots portés dans le coffre (n'importe quel coffre, dans la limite : le reste reste porté)
function Handlers.coneStore(src, data)
    local ctx, err = context(src, data)
    if not ctx then return { ok = false, error = err } end
    if not stockAllowed(ctx) then return { ok = false, error = 'Pas de coffre ici.' } end
    if carried(src) <= 0 then return { ok = false, error = 'Vous ne portez pas de plot.' } end
    local st = stockOf(ctx.plate)
    local max = S.Cones.Max or 10
    local count = math.min(carried(src), max - st.cones)
    if count <= 0 then return { ok = false, error = ('Coffre plein : %d plots au maximum.'):format(max) } end
    st.cones = st.cones + count
    setCarried(src, carried(src) - count)
    stockChanged(ctx.plate)
    return { ok = true, count = count, carrying = carried(src), stock = stockView(ctx.plate) }
end

--- Fusées : prendre `count` du coffre / ranger `count` (celles que le joueur a sur lui)
function Handlers.flares(src, data)
    local ctx, err = context(src, data)
    if not ctx then return { ok = false, error = err } end
    if not stockAllowed(ctx) then return { ok = false, error = 'Pas de coffre ici.' } end
    local st = stockOf(ctx.plate)
    local count = math.floor(math.max(0, math.min(tonumber(data.count) or 0, 25)))
    if count <= 0 then return { ok = false, error = 'Rien à faire.' } end
    if data.mode == 'take' then
        count = math.min(count, st.flares)
        if count <= 0 then return { ok = false, error = 'Plus de fusée dans ce coffre.' } end
        st.flares = st.flares - count
    else
        count = math.min(count, (S.Flares.Max or 20) - st.flares)
        if count <= 0 then return { ok = false, error = ('Coffre plein : %d fusées au maximum.'):format(S.Flares.Max or 20) } end
        st.flares = st.flares + count
    end
    stockChanged(ctx.plate)
    return { ok = true, mode = data.mode == 'take' and 'take' or 'store', count = count, stock = stockView(ctx.plate) }
end

--- Plots posés publiés à tous les joueurs (GlobalState.rpCones = { { x, y, z }, ... }) : leurs clients font dévier
--- le trafic PNJ (client/traffic.lua). Regroupé : une seule publication par image serveur.
local publishPending = false
local function publishCones()
    if publishPending then return end
    publishPending = true
    SetTimeout(0, function()
        publishPending = false
        local list = {}
        for _, pos in pairs(placedCones) do list[#list + 1] = pos end
        GlobalState.rpCones = list
    end)
end

--- Plot posé au sol : créé ici (visible par tous, reste en place), marqué "rpCone" (repris avec l'œil)
local function createCone(src, x, y, z, heading)
    local object = CreateObjectNoOffset(GetHashKey(S.Cones.Model or 'prop_roadcone02a'), x, y, z, true, true, false)
    local timeout = GetGameTimer() + 2000
    while not DoesEntityExist(object) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(object) then return false end
    SetEntityHeading(object, heading)
    FreezeEntityPosition(object, true)
    Entity(object).state:set('rpCone', { by = src }, true)
    placedCones[object] = { x = x, y = y, z = z }
    publishCones()
    return true
end

-- Plots portés posés : { spots = { { x, y, z, heading }, ... } } (G : un plot ; mort : tous, à ses pieds)
RegisterNetEvent('rp_equipment:cone:place', function(data)
    local src = source
    if carried(src) <= 0 or type(data) ~= 'table' or type(data.spots) ~= 'table' then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local here = GetEntityCoords(ped)
    local placed = 0
    for i = 1, math.min(#data.spots, carried(src)) do
        local spot = data.spots[i]
        local x, y, z = tonumber(type(spot) == 'table' and spot.x), tonumber(type(spot) == 'table' and spot.y), tonumber(type(spot) == 'table' and spot.z)
        if x and y and z and #(here - vector3(x, y, z)) <= 3.0 and createCone(src, x, y, z, tonumber(spot.heading) or 0.0) then
            placed = placed + 1
        end
    end
    setCarried(src, carried(src) - placed)
    TriggerClientEvent('rp_equipment:cone:placed', src, carried(src), placed)
end)

--- Plot au sol retiré et porté par ce joueur
local function takeFromGround(src, object)
    placedCones[object] = nil
    publishCones()
    Entity(object).state:set('rpCone', nil, true)
    DeleteEntity(object)
    setCarried(src, carried(src) + 1)
end

--- Vérifications communes du ramassage avec l'œil : le plot visé, à côté d'un policier en service qui a de la place
local function pickupTarget(src, netId)
    local object = NetworkGetEntityFromNetworkId(tonumber(netId) or -1)
    if not object or object == 0 or not DoesEntityExist(object) or type(Entity(object).state.rpCone) ~= 'table' then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(object)) > 4.0 then return nil end
    if not policeUnit(src) then
        TriggerClientEvent('rp_equipment:notify', src, 'Réservé aux policiers en service (unité du MDC).')
        return nil
    end
    if carried(src) >= MAX_CARRY then
        TriggerClientEvent('rp_equipment:notify', src, ('Vous portez déjà %d plots (maximum).'):format(MAX_CARRY))
        return nil
    end
    return object
end

-- Plot au sol ramassé avec l'œil (rp_interact) : porté avec les autres
RegisterNetEvent('rp_equipment:cone:pickup', function(netId)
    local src = source
    local object = pickupTarget(src, netId)
    if not object then return end
    takeFromGround(src, object)
    TriggerClientEvent('rp_equipment:cone:carry', src, carried(src), 1)
end)

-- Œil : « Ramasser les plots autour » : le plot visé et ceux posés autour de lui (Cones.PickupRadius), d'un coup
RegisterNetEvent('rp_equipment:cone:pickupAll', function(netId)
    local src = source
    local object = pickupTarget(src, netId)
    if not object then return end
    local center = GetEntityCoords(object)
    local list = { { object = object, dist = 0.0 } }
    for other in pairs(placedCones) do
        if other ~= object and DoesEntityExist(other) and type(Entity(other).state.rpCone) == 'table' then
            local dist = #(GetEntityCoords(other) - center)
            if dist <= (S.Cones.PickupRadius or 8.0) then list[#list + 1] = { object = other, dist = dist } end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    local taken = 0
    for _, item in ipairs(list) do
        if carried(src) >= MAX_CARRY then break end
        takeFromGround(src, item.object)
        taken = taken + 1
    end
    TriggerClientEvent('rp_equipment:cone:carry', src, carried(src), taken)
end)

-- Plot porté perdu (mort : posé à ses pieds par le client ; déconnexion : perdu)
AddEventHandler('playerDropped', function() carrying[source] = nil end)
AddEventHandler('entityRemoved', function(entity)
    if placedCones[entity] then placedCones[entity] = nil; publishCones() end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for object in pairs(placedCones) do
        if DoesEntityExist(object) then DeleteEntity(object) end
    end
    GlobalState.rpCones = {}
end)
GlobalState.rpCones = {} -- démarrage : aucun plot posé

--- Pièce d'équipement EUP de ce véhicule (le client la met ou la retire de la tenue du joueur)
function Handlers.wear(src, data)
    local ctx, err = context(src, data)
    if not ctx then return { ok = false, error = err } end
    for _, asset in ipairs(Assets[ctx.kind] or {}) do
        if asset.id == data.asset then return { ok = true, asset = asset } end
    end
    return { ok = false, error = 'Cet équipement n\'est pas dans ce véhicule.' }
end

--- Rangement : le joueur tient l'arme (vérifié ici), l'emplacement est libre ; l'arme lui est retirée
function Handlers.store(src, data)
    local ctx, err = context(src, data)
    if not ctx then return { ok = false, error = err } end
    if not rackAllowed(ctx) or not ctx.plate then return { ok = false, error = 'Pas de râtelier ici.' } end
    local slot = SLOTS[tostring(data.slot)]
    local w = type(data.weapon) == 'table' and data.weapon or nil
    if not slot or not w or type(w.hash) ~= 'number' then return { ok = false, error = 'Arme invalide.' } end
    local ped = GetPlayerPed(src)
    local current = GetSelectedPedWeapon(ped) -- arme en main (synchronisée) ; 0 / nil : non disponible
    if current and current ~= 0 and (current & 0xFFFFFFFF) ~= (w.hash & 0xFFFFFFFF) then
        return { ok = false, error = 'Tenez l\'arme dans les mains.' }
    end
    Racks[ctx.plate] = Racks[ctx.plate] or {}
    if Racks[ctx.plate][slot.Id] then return { ok = false, error = ('Emplacement "%s" déjà occupé.'):format(slot.Label) } end
    local components, tints = {}, {}
    for _, name in ipairs(type(w.components) == 'table' and w.components or {}) do
        if type(name) == 'string' and #components < 20 then components[#components + 1] = name:sub(1, 64) end
    end
    for name, tint in pairs(type(w.componentTints) == 'table' and w.componentTints or {}) do
        if type(name) == 'string' and tonumber(tint) then tints[name:sub(1, 64)] = math.floor(tonumber(tint)) end
    end
    Racks[ctx.plate][slot.Id] = {
        hash = w.hash,
        name = type(w.name) == 'string' and w.name:sub(1, 64) or nil,
        label = type(w.label) == 'string' and w.label:sub(1, 60) or slot.Label,
        tint = math.floor(tonumber(w.tint) or 0),
        components = components,
        componentTints = tints,
        by = ctx.unit.name,
        at = os.time(),
    }
    saveRacks()
    RemoveWeaponFromPed(ped, w.hash)
    TriggerClientEvent('rp_equipment:rack', -1, ctx.plate, rackSummary(ctx.plate))
    return { ok = true, rack = rackSummary(ctx.plate) }
end

--- Sortie : l'emplacement est vidé, l'arme est rendue à l'identique au client
function Handlers.retrieve(src, data)
    local ctx, err = context(src, data)
    if not ctx then return { ok = false, error = err } end
    if not rackAllowed(ctx) or not ctx.plate then return { ok = false, error = 'Pas de râtelier ici.' } end
    local slot = SLOTS[tostring(data.slot)]
    local rack = Racks[ctx.plate]
    local weapon = slot and rack and rack[slot.Id]
    if not weapon then return { ok = false, error = 'Cet emplacement est vide.' } end
    rack[slot.Id] = nil
    if next(rack) == nil then Racks[ctx.plate] = nil end
    saveRacks()
    TriggerClientEvent('rp_equipment:rack', -1, ctx.plate, rackSummary(ctx.plate))
    return { ok = true, weapon = weapon, rack = rackSummary(ctx.plate) }
end

RegisterNetEvent('rp_equipment:request', function(id, action, data)
    local src = source
    local handler = Handlers[action]
    local ok, result = pcall(function() return handler and handler(src, data) or { ok = false, error = 'Action inconnue.' } end)
    if not ok then
        print(('^1[rp_equipment] erreur (%s) : %s^7'):format(tostring(action), tostring(result)))
        result = { ok = false, error = 'Erreur du serveur.' }
    end
    TriggerClientEvent('rp_equipment:response', src, id, result)
end)
