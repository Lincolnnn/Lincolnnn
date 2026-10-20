--[[
    RP DLS - serveur
    ----------------
    Seul à écrire l'état "dls" des véhicules (state bag répliqué à tous les clients), après vérification :
      - l'auteur conduit le véhicule, ou vient d'en descendre (stage de descente, sirène coupée : 15 s, 20 m) ;
      - chaque valeur est possible pour ce modèle (stages présents dans son XML, Traffic Advisor et Steady Burn
        seulement s'il en a, tons 0 à 5…). Véhicule sans fichier DLS : gyrophares d'origine (stage 3) seulement.
    Un changement refusé est signalé au client (son état revient à celui du serveur). Aucune boucle.
]]

local MAX_PER_SECOND = 25
local LEFT_MS = 15000
local LEFT_RANGE = 20.0

local lastDriver = {} -- [véhicule] = { src, time } : dernier conducteur (descente du véhicule)
local rate = {}       -- [src] = { second, count }

-- =========================================================================
-- FICHIERS : ceux de la configuration + tous les .xml de dls/ et tous les packs de dls/packs/ (trouvés seuls :
-- copier un fichier suffit). La liste est envoyée aux clients (GlobalState.rpDlsFiles), qui lisent les mêmes.
-- =========================================================================
local function listDir(path, wantDirs)
    local windows = package.config:sub(1, 1) == '\\'
    local cmd
    if windows then
        cmd = ('dir /b %s "%s" 2>nul'):format(wantDirs and '/ad' or '/a-d', (path:gsub('/', '\\')))
    else
        cmd = ('ls -1p "%s" 2>/dev/null'):format(path)
    end
    local ok, pipe = pcall(io.popen, cmd)
    if not ok or not pipe then return nil end
    local list = {}
    for line in pipe:lines() do
        line = line:gsub('[\r\n]', '')
        if windows then
            if line ~= '' then list[#list + 1] = line end
        else
            local dir = line:sub(-1) == '/'
            if dir == (wantDirs == true) and line ~= '' then list[#list + 1] = dir and line:sub(1, -2) or line end
        end
    end
    pipe:close()
    return list
end

--- Fichier data_file d'une ressource (manifest : data_file 'TYPE' 'chemin') : son chemin
local function dataFilePath(extra)
    if not extra then return nil end
    local ok, decoded = pcall(json.decode, extra)
    local path = ok and type(decoded) == 'table' and decoded[1] or tostring(extra):match('"([^"]+)"') or extra
    if type(path) ~= 'string' or path:find('%*') then return nil end -- (chemin avec * : pas lisible directement)
    return path
end

--- Gyrophares des ressources de véhicules démarrées : leurs CARCOLS_FILE et VEHICLE_VARIATION_FILE
--- (aucune copie nécessaire : lus directement dans la ressource du pack)
local function resourcePacks()
    local packs = {}
    local self = GetCurrentResourceName()
    for i = 0, GetNumResources() - 1 do
        local res = GetResourceByFindIndex(i)
        local state = res and GetResourceState(res)
        if res and res ~= self and (state == 'started' or state == 'starting') then
            local metas = {}
            for n = 0, GetNumResourceMetadata(res, 'data_file') - 1 do
                local kind = GetResourceMetadata(res, 'data_file', n)
                if kind == 'CARCOLS_FILE' or kind == 'VEHICLE_VARIATION_FILE' then
                    local path = dataFilePath(GetResourceMetadata(res, 'data_file_extra', n))
                    if path and path:lower():match('%.meta$') then metas[#metas + 1] = { resource = res, path = path } end
                end
            end
            if #metas > 0 then packs[#packs + 1] = { name = res, files = metas } end
        end
    end
    return packs
end

local function discover()
    local files = DLS.configFiles()
    for _, pack in ipairs(resourcePacks()) do files.packs[#files.packs + 1] = pack end
    local root = GetResourcePath(GetCurrentResourceName()) .. '/dls'
    local known, knownPacks = {}, {}
    for _, entry in ipairs(files.vehicles) do
        known[(type(entry) == 'table' and (entry.file or entry.model) or entry):lower()] = true
    end
    for _, pack in ipairs(files.packs) do knownPacks[pack.name:lower()] = true end

    local xml = listDir(root, false)
    if not xml then
        print('^3[rp_dls] Ce serveur ne permet pas de lister le dossier dls/ : les fichiers .xml doivent être '
            .. 'ajoutés à Vehicles dans config.lua (nom du fichier, sans .xml).^0')
        return files
    end
    table.sort(xml)
    for _, name in ipairs(xml) do
        local file = name:match('^(.+)%.[xX][mM][lL]$')
        if file and not known[file:lower()] then
            files.vehicles[#files.vehicles + 1] = file
            known[file:lower()] = true
        end
    end
    -- Packs : un dossier par pack dans dls/packs/ (ses .meta), ou des .meta posés directement dans dls/packs/
    local packsRoot = root .. '/packs'
    local loose = {}
    for _, name in ipairs(listDir(packsRoot, false) or {}) do
        if name:lower():match('%.meta$') then loose[#loose + 1] = 'dls/packs/' .. name end
    end
    if #loose > 0 then files.packs[#files.packs + 1] = { name = 'packs', files = loose } end
    for _, dir in ipairs(listDir(packsRoot, true) or {}) do
        if not knownPacks[dir:lower()] then
            local metas = {}
            for _, name in ipairs(listDir(packsRoot .. '/' .. dir, false) or {}) do
                if name:lower():match('%.meta$') then metas[#metas + 1] = ('dls/packs/%s/%s'):format(dir, name) end
            end
            if #metas > 0 then
                files.packs[#files.packs + 1] = { name = dir, files = metas }
            else
                print(('^3[rp_dls] dls/packs/%s/ : aucun fichier .meta (carcols.meta, carvariations.meta).^0'):format(dir))
            end
        end
    end
    return files
end

--- Ce que lit ce serveur : dossier de la ressource et config.lua (une autre copie de rp_dls dans resources/, ou
--- une ressource pas redémarrée après avoir modifié config.lua, se voit tout de suite ici)
local function describe(list)
    local out = {}
    for _, entry in ipairs(list or {}) do
        out[#out + 1] = type(entry) == 'table' and (tostring(entry.model or '?') .. '>' .. tostring(entry.file or '')) or tostring(entry)
    end
    return #out > 0 and table.concat(out, ', ') or '(vide)'
end

local function load()
    print(('[rp_dls] Ressource lue dans : %s'):format(GetResourcePath(GetCurrentResourceName())))
    print(('[rp_dls] config.lua : Vehicles = %s ; Packs = %s'):format(describe(DLSConfig.Vehicles), describe(DLSConfig.Packs)))
    local files = discover()
    GlobalState.rpDlsFiles = files
    DLS.load(files)
end

CreateThread(load)

-- Ressource de véhicules démarrée après rp_dls (ou redémarrée) : ses gyrophares sont relus
local reloadAt = nil
AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() or GetNumResourceMetadata(res, 'data_file') == 0 then return end
    local due = reloadAt == nil
    reloadAt = GetGameTimer() + 1000
    if not due then return end
    CreateThread(function()
        while GetGameTimer() < reloadAt do Wait(200) end
        reloadAt = nil
        load()
    end)
end)

local function vehicleFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
    return entity
end

local function isDriver(src, vehicle)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
end

local function justLeft(src, vehicle)
    local last = lastDriver[vehicle]
    if not last or last.src ~= src or GetGameTimer() - last.time > LEFT_MS then return false end
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= LEFT_RANGE
end

local function limited(src)
    local now = os.time()
    local r = rate[src]
    if not r or r.second ~= now then r = { second = now, count = 0 }; rate[src] = r end
    r.count = r.count + 1
    return r.count > MAX_PER_SECOND
end

local function int(v, min, max)
    v = type(v) == 'number' and math.tointeger(v)
    return v and v >= min and v <= max and v or nil
end

--- État reçu -> état propre pour ce modèle, ou nil s'il est impossible
local function clean(model, st)
    if type(st) ~= 'table' then return nil end
    local s, ta, tap, tone = int(st.s, 0, 5), int(st.ta or 0, 0, 4), int(st.tap or 0, 0, 64), int(st.tone or 0, 0, 5)
    if not s or not DLS.hasStage(model, s) then return nil end
    if not ta or (ta ~= 0 and not model.ta) then return nil end
    if not tap or tap > DLS.taPatternCount(model) then return nil end
    if not tone or (tone ~= 0 and not model.tones[tone]) then return nil end
    for _, key in ipairs({ 'sb', 'int', 'bo', 'aux', 'horn' }) do
        if st[key] ~= nil and type(st[key]) ~= 'boolean' then return nil end
    end
    if st.sb and not model.steady then return nil end
    if ta ~= 0 and model.v2 and not model.ta.modes[ta] then return nil end
    -- Cruise, takedown, alley : modes du fichier en DLS v2 ; sinon takedown / alley dessinés par le script
    local cr, td, al = int(st.cr or 0, 0, 9), int(st.td or 0, 0, 9), int(st.al or 0, 0, 3)
    if not cr or not td or not al then return nil end
    if model.v2 then
        if cr > model.cruise or td > model.takedown then return nil end
        if (al & 1 ~= 0 and not model.alley.left) or (al & 2 ~= 0 and not model.alley.right) then return nil end
    elseif cr ~= 0 or td > 1 then
        return nil
    end
    return {
        s = s, ta = ta, tap = tap, sb = st.sb == true, int = st.int == true, bo = st.bo == true,
        tone = tone, aux = st.aux == true, horn = st.horn == true, cr = cr, td = td, al = al,
    }
end

RegisterNetEvent('rp_dls:driver', function(netId)
    local src = source
    local vehicle = vehicleFromNet(netId)
    if vehicle and isDriver(src, vehicle) then lastDriver[vehicle] = { src = src, time = GetGameTimer() } end
end)

RegisterNetEvent('rp_dls:set', function(netId, st)
    local src = source
    if limited(src) then return end
    local vehicle = vehicleFromNet(netId)
    if not vehicle then return end
    local driver = isDriver(src, vehicle)
    if driver then
        lastDriver[vehicle] = { src = src, time = GetGameTimer() }
    elseif not justLeft(src, vehicle) then
        TriggerClientEvent('rp_dls:refused', src, netId)
        return
    end
    local model = DLS.models[GetEntityModel(vehicle)] or DLS.generic
    local value = clean(model, st)
    if not value then
        TriggerClientEvent('rp_dls:refused', src, netId)
        return
    end
    Entity(vehicle).state:set('dls', value, true)
end)

AddEventHandler('entityRemoved', function(entity) lastDriver[entity] = nil end)
AddEventHandler('playerDropped', function() rate[source] = nil end)
