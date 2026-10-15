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

function Handlers.open(src, data)
    local ctx, err = context(src, data)
    if not ctx then return { ok = false, error = err } end
    return {
        ok = true, type = ctx.kind, plate = ctx.plate, assets = Assets[ctx.kind] or {},
        rack = rackAllowed(ctx) and ctx.plate and rackSummary(ctx.plate) or false,
    }
end

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
