--[[
    RP Interact - Voiture (spawn, radio) et Équipements (serveur)
    -------------------------------------------------------------
    - Véhicules : lus dans data/vehicles.txt (spawn code ; service ; nom ; livery ; extras), relus avec
      la commande console "rpi_vehicles". Seuls les véhicules de cette liste peuvent être demandés ;
      véhicules de police réservés aux policiers en service si SpawnPoliceOnly.
    - Radio : état du véhicule "rpiRadio" = { url, start (heure UTC de lancement, s), volume (0-100) },
      lu par tous les clients (chacun joue le son, plus ou moins fort selon sa distance et les vitres /
      portières). Réglable par les places AVANT, ou par un joueur collé au véhicule (œil, portière
      avant ouverte).
    - Équipements : tenues et armes de data/equipment.lua (vérification de l'accès).
    Aucune boucle.
]]

local Config = InteractConfig
local S = RPIServer
local SERVICES = {
    ['atlanta police department'] = 'apd',
    ['georgia state patrol'] = 'gsp',
}

-- =========================================================================
-- VÉHICULES (data/vehicles.txt)
-- =========================================================================
local Vehicles, byCode = {}, {}

local function trim(text) return (text or ''):gsub('^%s+', ''):gsub('%s+$', '') end

local function loadVehicles()
    Vehicles, byCode = {}, {}
    local raw = LoadResourceFile(GetCurrentResourceName(), 'data/vehicles.txt')
    if not raw then
        print('^3[RP Interact] data/vehicles.txt introuvable : aucun véhicule dans le menu Voiture.^0')
        return
    end
    local line = 0
    for text in (raw .. '\n'):gmatch('([^\r\n]*)\r?\n') do
        line = line + 1
        text = trim(text)
        if text ~= '' and text:sub(1, 1) ~= '#' then
            local f = {}
            for field in (text .. ';'):gmatch('([^;]*);') do f[#f + 1] = trim(field) end
            local code, service, label = f[1], f[2] or '', f[3] or ''
            if code == '' or label == '' then
                print(('^3[RP Interact] vehicles.txt ligne %d ignorée (spawn code ou nom manquant).^0'):format(line))
            else
                local extras
                if f[5] and f[5] ~= '' then
                    extras = {}
                    for n in f[5]:gmatch('%d+') do extras[#extras + 1] = tonumber(n) end
                end
                local entry = {
                    code = code:lower(), label = label:sub(1, 80),
                    service = SERVICES[service:lower()] or 'other',
                    livery = tonumber(f[4] or ''), extras = extras,
                }
                local existing = byCode[entry.code]
                if existing then
                    -- Même spawn code deux fois : la dernière ligne l'emporte (à la même place dans la liste)
                    existing.label, existing.service = entry.label, entry.service
                    existing.livery, existing.extras = entry.livery, entry.extras
                else
                    Vehicles[#Vehicles + 1] = entry
                    byCode[entry.code] = entry
                end
            end
        end
    end
    print(('^5[RP Interact]^0 %d véhicule(s) lu(s) dans data/vehicles.txt'):format(#Vehicles))
end

loadVehicles()
RegisterCommand('rpi_vehicles', function(src)
    if src == 0 or IsPlayerAceAllowed(src, Config.PoliceVehiclesAce) then loadVehicles() end
end, false)

local function isPolice(src) return S.policeUnit(src) ~= nil end

S.on('vehicleList', function(src)
    return { ok = true, vehicles = Vehicles, police = isPolice(src), policeOnly = Config.SpawnPoliceOnly ~= false }
end)

S.on('spawnVehicle', function(src, p)
    local entry = byCode[type(p.code) == 'string' and p.code:lower() or '']
    if not entry then return { ok = false, error = 'Véhicule inconnu.' } end
    if entry.service ~= 'other' and Config.SpawnPoliceOnly ~= false and not isPolice(src) then
        return { ok = false, error = 'Véhicule de police : rejoignez une unité dans le MDC.' }
    end
    return { ok = true, vehicle = entry }
end)

-- =========================================================================
-- RADIO DU VÉHICULE
-- =========================================================================
local function vehicleFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
    return entity
end

--- Places avant (conducteur, passager avant) ou joueur collé au véhicule (œil, portière avant ouverte)
local function canUseRadio(src, vehicle)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    if GetPedInVehicleSeat(vehicle, -1) == ped or GetPedInVehicleSeat(vehicle, 0) == ped then return true end
    if GetVehiclePedIsIn(ped, false) == vehicle then return false end -- à l'arrière
    return #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= 4.0
end

local function validUrl(url)
    if type(url) ~= 'string' then return nil end
    url = trim(url)
    if #url > 400 or not url:match('^https?://[%w%-%.]+') or url:find('[%s<>"\']') then return nil end
    return url
end

S.on('radio', function(src, p)
    local vehicle = vehicleFromNet(p.netId)
    if not vehicle then return { ok = false, error = 'Véhicule introuvable.' } end
    if not canUseRadio(src, vehicle) then
        return { ok = false, error = 'Seules les places avant peuvent régler la radio.' }
    end
    local state = Entity(vehicle).state
    local current = type(state.rpiRadio) == 'table' and state.rpiRadio or nil
    if p.action == 'play' then
        local url = validUrl(p.url)
        if not url then return { ok = false, error = 'Lien invalide (adresse http:// ou https://).' } end
        local volume = math.floor(math.max(0, math.min(100, tonumber(p.volume) or (current and current.volume) or 60)))
        state:set('rpiRadio', { url = url, start = os.time(), volume = volume, by = src }, true)
    elseif p.action == 'stop' then
        state:set('rpiRadio', false, true)
    elseif p.action == 'volume' then
        if not current then return { ok = false, error = 'La radio est éteinte.' } end
        local volume = math.floor(math.max(0, math.min(100, tonumber(p.volume) or current.volume)))
        state:set('rpiRadio', { url = current.url, start = current.start, volume = volume, by = current.by }, true)
    else
        return { ok = false, error = 'Action inconnue.' }
    end
    return { ok = true, radio = state.rpiRadio or false }
end)

-- =========================================================================
-- ÉQUIPEMENTS (data/equipment.lua)
-- =========================================================================
S.on('equipment', function(src, p)
    if Config.EquipmentPoliceOnly ~= false and not isPolice(src) then
        return { ok = false, error = 'Réservé à la police : rejoignez une unité dans le MDC.' }
    end
    local list = p.kind == 'outfit' and InteractEquipment.Outfits or p.kind == 'loadout' and InteractEquipment.Loadouts or nil
    local index = tonumber(p.index)
    if not list or not index or not list[index] then return { ok = false, error = 'Équipement inconnu.' } end
    return { ok = true }
end)
