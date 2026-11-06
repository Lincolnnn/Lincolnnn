--[[
    Vehicle Control - airbags (client)
    ----------------------------------
    Riven Impact Dynamics n'a plus d'airbags (9.9.4) : ce script s'en charge, avec ou sans Riven.
      - DÉCLENCHEMENT : un occupant (joueur) du véhicule ressent un gros choc (événement 'impact' du noyau) :
          * AVANT : perte de vitesse vers l'avant d'au moins Front MPH -> volant (conducteur) + tableau de bord
            (passager, selon Passenger) ;
          * CÔTÉ : poussée de côté d'au moins Side MPH -> rideau du côté touché ;
          * TONNEAU (Rollover) : les deux rideaux ;
        piéton percuté : jamais ; objet / véhicule léger (cône, moto…) : seuils x Light. Le serveur vérifie et
        publie la liste des véhicules aux airbags sortis (GlobalState.vcAirbags).
      - AFFICHAGE : chaque joueur proche (Range m) accroche les airbags au véhicule (objets locaux, modèles de
        Specs ; modèle absent du jeu -> modèle de secours `fallback`, sinon rien) ; poussière + secousse au
        déclenchement.
      - RETRAIT : véhicule réparé (moteur ET carrosserie remis à neuf après avoir été abîmés : vMenu, mécanicien,
        SetVehicleFixed, Riven ; /repair et /fieldrepair selon ClearOnRepair / ClearOnFieldRepair, côté serveur) ;
        véhicule supprimé.
    /airbagtest : compte rendu (modèles, points d'attache, état) ; /airbagtest on : déclenche ceux de son véhicule.
    Performance : aucune boucle tant qu'aucun véhicule n'a d'airbags sortis ; sinon une vérification toutes les
    Interval ms (2 s).
]]

local C = VCConfig.Airbags or {}
if C.Enabled == false then return end

local SPECS = C.Specs or {}
local FLAGS = { f = { 'driver' }, p = { 'passenger' }, L = { 'curtainL' }, R = { 'curtainR' } }
local MPH = VC.MPH or 2.236936
local SKIP = C.SkipClasses or {}

-- =========================================================================
-- MODÈLES
-- =========================================================================
--- Modèle connu du jeu (stream/*.ydr + archétype dans un .ytyp déclaré par data_file)
local function streamed(model)
    if type(model) ~= 'string' or model == '' then return false end
    local h = GetHashKey(model)
    return IsModelInCdimage(h) and IsModelValid(h)
end

--- Modèle utilisé pour cette pièce : celui de Specs, sinon celui de secours ; nil si aucun n'existe
local function modelOf(spec)
    if streamed(spec.model) then return spec.model end
    if streamed(spec.fallback) then return spec.fallback end
    return nil
end

local function loadModel(model)
    local h = GetHashKey(model)
    RequestModel(h)
    local stopAt = GetGameTimer() + 3000
    while not HasModelLoaded(h) do
        if GetGameTimer() > stopAt then return nil end
        Wait(0)
    end
    return h
end

--- Premier os présent parmi la liste (avec son décalage) ; nil si aucun
local function boneOf(vehicle, spec)
    for _, b in ipairs(spec.bones or {}) do
        local index = GetEntityBoneIndexByName(vehicle, b.name)
        if index ~= -1 then return index, b end
    end
    return nil
end

-- =========================================================================
-- AFFICHAGE (chez chaque joueur proche)
-- =========================================================================
local ours = {}  -- [netId] = { vehicle, parts = { [nom de la pièce] = objet }, low = santé la plus basse vue }
local busy = {}  -- [netId .. pièce] = création en cours (chargement du modèle)
local burstAt = {} -- [netId] = déclenchement déjà montré (poussière une seule fois)

local function attach(vehicle, spec)
    local index, b = boneOf(vehicle, spec)
    local model = modelOf(spec)
    if not index or not model then return nil end
    local h = loadModel(model)
    if not h or not DoesEntityExist(vehicle) then return nil end
    local p = GetEntityCoords(vehicle)
    local obj = CreateObject(h, p.x, p.y, p.z - 6.0, false, false, false)
    SetModelAsNoLongerNeeded(h)
    if not obj or obj == 0 then return nil end
    SetEntityCollision(obj, false, false)
    local o, r = b.offset or { 0.0, 0.0, 0.0 }, b.rot or { 0.0, 0.0, 0.0 }
    if b.follow then
        AttachEntityToEntity(obj, vehicle, index, o[1], o[2], o[3], r[1], r[2], r[3], false, false, false, false, 2, true)
    else
        -- tenu par la caisse à l'endroit de l'os (une portière qui s'ouvre ne l'emporte pas)
        local wp = GetWorldPositionOfEntityBone(vehicle, index)
        local l = GetOffsetFromEntityGivenWorldCoords(vehicle, wp.x, wp.y, wp.z)
        AttachEntityToEntity(obj, vehicle, 0, l.x + o[1], l.y + o[2], l.z + o[3], r[1], r[2], r[3], false, false, false, false, 2, true)
    end
    return obj
end

local function clear(netId)
    local entry = ours[netId]
    if not entry then return end
    for _, obj in pairs(entry.parts) do
        if DoesEntityExist(obj) then DeleteObject(obj) end
    end
    ours[netId] = nil
end

--- Poussière (gaz de l'airbag) et secousse des occupants : seulement au déclenchement, pas en arrivant plus tard
local function burst(vehicle, names)
    local fx = C.Effect
    if type(fx) == 'table' and fx.name then
        local asset = fx.asset or 'core'
        RequestNamedPtfxAsset(asset)
        local stopAt = GetGameTimer() + 1000
        while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < stopAt do Wait(0) end
        if HasNamedPtfxAssetLoaded(asset) then
            for _, name in ipairs(names) do
                local index = boneOf(vehicle, SPECS[name] or {})
                local pos = index and GetWorldPositionOfEntityBone(vehicle, index) or GetEntityCoords(vehicle)
                UseParticleFxAssetNextCall(asset)
                StartParticleFxNonLoopedAtCoord(fx.name, pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, fx.scale or 0.6, false, false, false)
            end
        end
    end
    if (C.Shake or 0) > 0 and GetVehiclePedIsIn(PlayerPedId(), false) == vehicle then
        ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', C.Shake)
    end
end

local function list()
    local l = GlobalState.vcAirbags
    return type(l) == 'table' and l or {}
end

local repairAsked = {} -- [netId] = ms : demande de retrait déjà envoyée

--- Moteur ET carrosserie remis à neuf alors qu'ils avaient été vus abîmés PAR CE JOUEUR (jamais d'après une valeur
--- reçue : la santé d'un véhicule distant peut arriver en retard juste après le choc) : véhicule réparé
local function checkRepaired(netId, entry)
    local vehicle = entry.vehicle
    local health = math.min(GetVehicleEngineHealth(vehicle), GetVehicleBodyHealth(vehicle))
    entry.low = math.min(entry.low or 1000.0, health)
    if health >= 999.0 and entry.low < 990.0 then
        local now = GetGameTimer()
        if (repairAsked[netId] or 0) > now then return end
        repairAsked[netId] = now + 5000
        clear(netId)
        TriggerServerEvent('rp_vehiclecontrol:airbagsRepaired', tonumber(netId))
    end
end

local function sync()
    local l = list()
    local pos = GetEntityCoords(PlayerPedId())
    local cloud = GetCloudTimeAsInt()
    for key, info in pairs(l) do
        local netId = tonumber(key)
        local vehicle = netId and NetworkDoesEntityExistWithNetworkId(netId) and NetToVeh(netId) or 0
        if vehicle ~= 0 and DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - pos) <= (C.Range or 100.0) then
            local entry = ours[key]
            if entry and entry.vehicle ~= vehicle then clear(key); entry = nil end -- numéro réutilisé
            if not entry then
                entry = { vehicle = vehicle, parts = {} }
                ours[key] = entry
            end
            local fresh = math.abs(cloud - (tonumber(info.at) or 0)) <= 4
            local added = {}
            for flag, names in pairs(FLAGS) do
                if info[flag] then
                    for _, name in ipairs(names) do
                        local spec = SPECS[name]
                        local id = key .. name
                        if spec and not entry.parts[name] and not busy[id] then
                            busy[id] = true
                            local obj = attach(vehicle, spec)
                            busy[id] = nil
                            if obj and ours[key] == entry then entry.parts[name] = obj; added[#added + 1] = name
                            elseif obj then DeleteObject(obj) end
                        end
                    end
                end
            end
            if fresh and #added > 0 and burstAt[key] ~= info.at then burstAt[key] = info.at; burst(vehicle, added) end
            if ours[key] then checkRepaired(key, entry) end
        else
            clear(key) -- trop loin ou plus là : recréés en revenant
        end
    end
    for key in pairs(ours) do
        if not l[key] then clear(key) end -- retirés (réparé, supprimé)
    end
    for key in pairs(burstAt) do
        if not l[key] then burstAt[key] = nil end
    end
end

local watching = false
local function watch()
    if watching then return end
    watching = true
    CreateThread(function()
        while next(list()) or next(ours) do
            sync()
            Wait(C.Interval or 2000)
        end
        watching = false
    end)
end

AddStateBagChangeHandler('vcAirbags', 'global', function(_, _, value)
    SetTimeout(0, function() -- après la mise à jour de GlobalState
        if type(value) == 'table' and next(value) then watch() end
        if watching then sync() end
    end)
end)
if next(list()) then watch() end -- connecté alors que des airbags sont déjà sortis

-- =========================================================================
-- DÉCLENCHEMENT (occupant du véhicule accidenté)
-- =========================================================================
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

--- Pièces à sortir pour ce choc : { f, p, L, R } ou nil
function VC.airbagsFor(vehicle, velocity, after, hit)
    if SKIP[GetVehicleClass(vehicle)] then return nil end
    if hit and hit.kind == 'ped' then return nil end
    local factor = (hit and hit.severity == 'light') and (C.Light or 1.6) or 1.0
    local dv = (after or GetEntityVelocity(vehicle)) - velocity
    local origin = GetEntityCoords(vehicle)
    local right = GetOffsetFromEntityInWorldCoords(vehicle, 1.0, 0.0, 0.0) - origin   -- axe droit du véhicule
    local forward = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 1.0, 0.0) - origin -- axe avant
    local along, side = dot(dv, forward) * MPH, dot(dv, right) * MPH
    local out = {}
    if -along >= (C.Front or 25.0) * factor then
        out.f = true
        local passenger = C.Passenger
        if passenger == true or (passenger == 'occupied' and not IsVehicleSeatFree(vehicle, 0)) then out.p = true end
    end
    if math.abs(side) >= (C.Side or 18.0) * factor then
        if side > 0 then out.L = true else out.R = true end -- poussé vers la droite : touché à gauche
    end
    if C.Rollover ~= false and (IsEntityUpsidedown(vehicle) or math.abs(GetEntityRoll(vehicle)) > 75.0) then
        out.L, out.R = true, true
    end
    return next(out) and out or nil
end

local function already(vehicle, flags)
    local info = NetworkGetEntityIsNetworked(vehicle) and list()[tostring(VehToNet(vehicle))] or nil
    if type(info) ~= 'table' then return false end
    for flag in pairs(flags) do if not info[flag] then return false end end
    return true
end

local function deploy(vehicle, flags)
    if not NetworkGetEntityIsNetworked(vehicle) or already(vehicle, flags) then return end
    local health = math.min(GetVehicleEngineHealth(vehicle), GetVehicleBodyHealth(vehicle))
    TriggerServerEvent('rp_vehiclecontrol:airbags', VehToNet(vehicle), flags, health)
end

VC.on('impact', function(vehicle, before, loss, velocity, hit, jolt, after)
    local flags = VC.airbagsFor(vehicle, velocity, after, hit)
    if flags then deploy(vehicle, flags) end
end)

-- =========================================================================
-- /airbagtest : compte rendu (modèles, points d'attache, état) ; /airbagtest on : déclenchement
-- =========================================================================
if C.Command then
    RegisterCommand(C.Command, function(_, args)
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if args[1] == 'on' then
            if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return VC.chat('À la place du conducteur seulement.') end
            local flags = { f = true, L = true, R = true }
            if C.Passenger ~= false then flags.p = true end
            deploy(vehicle, flags)
            return VC.chat('Airbags déclenchés (retirés quand le véhicule est réparé).')
        end
        local lines = {}
        local parts = {}
        for _, name in ipairs({ 'driver', 'passenger', 'curtainL' }) do
            local spec = SPECS[name]
            if spec then
                local used = modelOf(spec)
                parts[#parts + 1] = ('%s : %s'):format(name, used == spec.model and 'OK' or used and ('secours ' .. used) or 'AUCUN modèle')
            end
        end
        lines[#lines + 1] = 'Modèles : ' .. table.concat(parts, ', ') .. '.'
        if not streamed((SPECS.driver or {}).model) then
            lines[#lines + 1] = ('« %s » absent du jeu : son .ydr, sa texture (.ytd) et un .ytyp qui le déclare (data_file \'DLC_ITYP_REQUEST\') doivent être streamés (voir README).')
                :format(tostring((SPECS.driver or {}).model))
        end
        if vehicle == 0 then
            lines[#lines + 1] = 'Montez dans un véhicule pour vérifier ses points d\'attache.'
        else
            local bones = {}
            for _, name in ipairs({ 'steeringwheel', 'seat_pside_f', 'door_dside_f', 'door_pside_f' }) do
                bones[#bones + 1] = ('%s %s'):format(name, GetEntityBoneIndexByName(vehicle, name) ~= -1 and 'oui' or 'NON')
            end
            lines[#lines + 1] = 'Points d\'attache du véhicule : ' .. table.concat(bones, ', ') .. '.'
            local info = NetworkGetEntityIsNetworked(vehicle) and list()[tostring(VehToNet(vehicle))] or nil
            local entry = NetworkGetEntityIsNetworked(vehicle) and ours[tostring(VehToNet(vehicle))] or nil
            local n = 0
            for _ in pairs(entry and entry.parts or {}) do n = n + 1 end
            lines[#lines + 1] = ('Airbags %s ; %d accroché(s) ; classe %d%s.'):format(type(info) == 'table' and 'sortis' or 'non sortis', n,
                GetVehicleClass(vehicle), SKIP[GetVehicleClass(vehicle)] and ' (sans airbags)' or '')
            lines[#lines + 1] = ('Test : /%s on (conducteur), puis réparer le véhicule pour les retirer.'):format(C.Command)
        end
        for _, line in ipairs(lines) do VC.chat(line) end
    end, false)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for key in pairs(ours) do clear(key) end
end)

VCAirbags = { sync = sync, ours = ours, streamed = streamed, modelOf = modelOf } -- pour les tests
