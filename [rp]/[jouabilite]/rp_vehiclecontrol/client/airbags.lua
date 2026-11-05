--[[
    Vehicle Control - airbags de Riven Impact Dynamics : vérification et secours (client)
    -------------------------------------------------------------------------------------
    Riven déclenche les airbags (état « rcpBags » du véhicule : f = conducteur + passager, L / R = rideaux) et les
    accroche lui-même. Ce script ne les bloque pas ; il aide quand rien n'apparaît :
      - /airbagtest (à bord) : modèles riven_crash_airbag_* bien chargés par le jeu ? points d'attache du véhicule
        présents (volant, siège passager, portières avant) ? état de Riven ? -> compte rendu dans le chat ;
      - SECOURS (Airbags.Fallback) : airbags déclenchés par Riven mais rien d'accroché au bout de Airbags.Delay ms
        (véhicule ajouté sans os « steeringwheel »…) : ce script accroche les mêmes modèles, à un point d'attache de
        remplacement (siège) ; retirés quand Riven les retire (véhicule réparé). Chez chaque joueur proche.
    Performance : aucune boucle (événement de l'état du véhicule) ; tant que des airbags de secours existent, une
    vérification toutes les 2 s.
]]

if not VC.riven then return end
local C = VCConfig.Airbags or {}
if C.Enabled == false then return end

local SPECS = C.Specs or {}
local ORDER = { { key = 'f', specs = { 'driver', 'passenger' } }, { key = 'L', specs = { 'curtainL' } }, { key = 'R', specs = { 'curtainR' } } }

local hashes = {}
for _, s in pairs(SPECS) do if s.model then hashes[GetHashKey(s.model)] = s.model end end

--- Modèle connu du jeu (stream/*.ydr + archétype dans un .ytyp déclaré par data_file)
local function streamed(model)
    local h = GetHashKey(model)
    return IsModelInCdimage(h) and IsModelValid(h)
end

local function loadModel(model)
    if not streamed(model) then return nil end
    local h = GetHashKey(model)
    RequestModel(h)
    local stopAt = GetGameTimer() + 3000
    while not HasModelLoaded(h) do
        if GetGameTimer() > stopAt then return nil end
        Wait(0)
    end
    return h
end

--- Airbags (de Riven ou les nôtres) accrochés à ce véhicule : [nom du modèle] = nombre
local function attachedBags(vehicle)
    local found = {}
    for _, obj in ipairs(GetGamePool('CObject')) do
        local name = hashes[GetEntityModel(obj)]
        if name and IsEntityAttachedToEntity(obj, vehicle) then found[name] = (found[name] or 0) + 1 end
    end
    return found
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
-- SECOURS
-- =========================================================================
local ours = {} -- [véhicule] = { objets }

local function attach(vehicle, spec)
    local index, b = boneOf(vehicle, spec)
    if not index then return nil end
    local h = loadModel(spec.model)
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

local function clearOurs(vehicle)
    for _, obj in ipairs(ours[vehicle] or {}) do
        if DoesEntityExist(obj) then DeleteObject(obj) end
    end
    ours[vehicle] = nil
end

local watching = false
local function watch()
    if watching then return end
    watching = true
    CreateThread(function()
        while next(ours) do
            Wait(2000)
            for vehicle in pairs(ours) do
                local st = DoesEntityExist(vehicle) and Entity(vehicle).state.rcpBags or nil
                if type(st) ~= 'table' then clearOurs(vehicle) end
            end
        end
        watching = false
    end)
end

--- Airbags déclenchés par Riven : ceux qui manquent au bout de Delay ms sont accrochés ici
local function fallback(vehicle, want)
    if C.Fallback == false or ours[vehicle] then return end
    SetTimeout(C.Delay or 2500, function()
        if not DoesEntityExist(vehicle) or ours[vehicle] then return end
        if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle)) > (C.Range or 100.0) then return end
        local st = Entity(vehicle).state.rcpBags
        if type(st) ~= 'table' then return end
        local present = attachedBags(vehicle)
        local list = {}
        for _, group in ipairs(ORDER) do
            if want[group.key] or st[group.key] then
                for _, name in ipairs(group.specs) do
                    local spec = SPECS[name]
                    if spec and not present[spec.model] and not (name == 'passenger' and C.Passenger == false) then
                        list[#list + 1] = attach(vehicle, spec)
                    end
                end
            end
        end
        if #list > 0 then
            ours[vehicle] = list
            watch()
        end
    end)
end

AddStateBagChangeHandler('rcpBags', nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if not vehicle or vehicle == 0 then return end
    if type(value) ~= 'table' then return clearOurs(vehicle) end
    fallback(vehicle, value)
end)

-- =========================================================================
-- /airbagtest : compte rendu (modèles, points d'attache, état de Riven)
-- =========================================================================
if C.Command then
    RegisterCommand(C.Command, function()
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local lines = {}
        local missing = {}
        for _, name in ipairs({ 'driver', 'passenger', 'curtainL' }) do
            local spec = SPECS[name]
            if spec and not streamed(spec.model) then missing[#missing + 1] = spec.model end
        end
        if #missing > 0 then
            lines[#lines + 1] = ('Modèles NON chargés par le jeu : %s. Il manque l\'archétype : stream/riven_crash_props.ytyp dans le dossier de Riven et la ligne data_file \'DLC_ITYP_REQUEST\' \'stream/riven_crash_props.ytyp\' dans son fxmanifest (ou ce .ytyp ne contient pas ces modèles).')
                :format(table.concat(missing, ', '))
        else
            lines[#lines + 1] = 'Modèles des airbags : chargés par le jeu (OK).'
        end
        if vehicle == 0 then
            lines[#lines + 1] = 'Montez dans un véhicule pour vérifier ses points d\'attache.'
        else
            local bones = {}
            for _, name in ipairs({ 'steeringwheel', 'seat_pside_f', 'door_dside_f', 'door_pside_f' }) do
                bones[#bones + 1] = ('%s %s'):format(name, GetEntityBoneIndexByName(vehicle, name) ~= -1 and 'oui' or 'NON')
            end
            lines[#lines + 1] = 'Points d\'attache du véhicule : ' .. table.concat(bones, ', ') .. '.'
            local st = Entity(vehicle).state.rcpBags
            local present = attachedBags(vehicle)
            local n = 0
            for _, c in pairs(present) do n = n + c end
            lines[#lines + 1] = ('Riven : airbags %s ; %d airbag(s) accroché(s) au véhicule ; classe %d.')
                :format(type(st) == 'table' and 'déclenchés' or 'non déclenchés', n, GetVehicleClass(vehicle))
            lines[#lines + 1] = 'Test : /crashpropstest airbags (place conducteur), puis /airbagtest.'
        end
        for _, line in ipairs(lines) do VC.chat(line) end
    end, false)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for vehicle in pairs(ours) do clearOurs(vehicle) end
end)

VCAirbags = { fallback = fallback, ours = ours, streamed = streamed } -- pour les tests
