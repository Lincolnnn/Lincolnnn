--[[
    RP Interact - Menu "Voiture > Spawn" et "Équipements" (client)
    ---------------------------------------------------------------
    SPAWN : véhicules de data/vehicle.json uniquement (liste envoyée par le serveur), classés par catégorie
      principale ("Principale" : Police, Civil…) puis par sous-catégorie ("subCategory"). Deux options en haut, gardées chez
      le joueur : "Supprimer l'ancien véhicule" (le dernier qu'il a fait apparaître, s'il n'y a pas
      d'autre joueur dedans) et "Apparaître dans le véhicule". Livery et extras de la liste appliqués.
      Le véhicule est créé par ce script : Vehicle Control le considère comme neuf (plein, moteur coupé).
    ÉQUIPEMENTS : boutons "Équipement GSP / APD / FCSO" (equipment_services.json : tout l'équipement de départ
      du service, toujours la version de base), "Équipements modifiés" (ceux que le joueur a nommés et enregistrés,
      gardés par le serveur, propres à lui), "Customiser équipement" (accessoires, teintes, armes en plus, selon le
      service choisi), autres lots (data/loadouts.json) ; bouton
      "Accéder aux tenues" (menu /eup, client/eup.lua, tenues de data/outfits.json).
    Aucune boucle.
]]

local Config = InteractConfig
local KVP_OPTIONS = 'rpi_spawn_options'

local function loadOptions()
    local options = { deleteOld = true, warpInto = true }
    local raw = GetResourceKvpString(KVP_OPTIONS)
    local ok, saved = pcall(json.decode, raw or '')
    if ok and type(saved) == 'table' then
        options.deleteOld = saved.deleteOld ~= false
        options.warpInto = saved.warpInto ~= false
    end
    return options
end

local options = loadOptions()
local lastVehicle = nil -- dernier véhicule apparu par ce joueur

-- =========================================================================
-- SPAWN
-- =========================================================================
RegisterNUICallback('vehicleList', function(_, cb)
    RPI.request('vehicleList', {}, function(res)
        res = res or { ok = false }
        res.options = options
        cb(res)
    end)
end)

RegisterNUICallback('spawnOptions', function(data, cb)
    data = type(data) == 'table' and data or {}
    options.deleteOld = data.deleteOld == true
    options.warpInto = data.warpInto == true
    SetResourceKvp(KVP_OPTIONS, json.encode(options))
    cb({ ok = true, options = options })
end)

--- Un autre joueur est-il dans ce véhicule ?
local function otherPlayerInside(vehicle)
    local me = PlayerPedId()
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and ped ~= me and IsPedAPlayer(ped) then return true end
    end
    return false
end

local function deleteOld()
    local vehicle = lastVehicle
    lastVehicle = nil
    if not vehicle or not DoesEntityExist(vehicle) or otherPlayerInside(vehicle) then return end
    NetworkRequestControlOfEntity(vehicle)
    local timeout = GetGameTimer() + 1000
    while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < timeout do Wait(0) end
    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)
    if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
end

local function loadVehicleModel(model)
    RequestModel(model)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(10) end
    return HasModelLoaded(model)
end

--- Livery (index de livery, ou mod de livery n° 48 pour les véhicules qui l'utilisent) et extras
local function applyVehicleLook(vehicle, entry)
    if entry.livery then
        if GetVehicleLiveryCount(vehicle) > 0 then
            SetVehicleLivery(vehicle, entry.livery)
        else
            SetVehicleModKit(vehicle, 0)
            if GetNumVehicleMods(vehicle, 48) > 0 then SetVehicleMod(vehicle, 48, entry.livery, false) end
        end
    end
    if type(entry.extras) == 'table' then
        -- extras listés : true activé, false désactivé ; non listés : désactivés
        for id = 0, 20 do
            if DoesExtraExist(vehicle, id) then SetVehicleExtra(vehicle, id, entry.extras[id] ~= true) end -- true = désactivé
        end
    end
end

local function spawn(entry)
    local model = GetHashKey(entry.code)
    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then
        return RPI.notify(('Modèle "%s" introuvable (spawn code / dossier stream).'):format(entry.code), 'error')
    end
    if not loadVehicleModel(model) then return RPI.notify('Le modèle du véhicule n\'a pas pu être chargé.', 'error') end

    local ped = PlayerPedId()
    local current = GetVehiclePedIsIn(ped, false)
    local currentIsOld = current ~= 0 and current == lastVehicle
    if options.deleteOld then deleteOld() end

    -- Dans le véhicule : à la place du joueur (ou de son ancien véhicule) ; sinon devant lui
    local x, y, z, heading
    if options.warpInto and (current == 0 or (currentIsOld and options.deleteOld)) then
        local c = current ~= 0 and DoesEntityExist(current) and GetEntityCoords(current) or GetEntityCoords(ped)
        x, y, z, heading = c.x, c.y, c.z, GetEntityHeading(ped)
    else
        local c = GetOffsetFromEntityInWorldCoords(current ~= 0 and current or ped, 0.0, current ~= 0 and 7.0 or 4.5, 0.0)
        x, y, z, heading = c.x, c.y, c.z, GetEntityHeading(ped) + (options.warpInto and 0.0 or 90.0)
    end

    local vehicle = CreateVehicle(model, x, y, z + 0.3, heading, true, false)
    SetModelAsNoLongerNeeded(model)
    if not vehicle or vehicle == 0 then return RPI.notify('Le véhicule n\'a pas pu apparaître.', 'error') end
    SetVehicleOnGroundProperly(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetVehicleNeedsToBeHotwired(vehicle, false)
    SetVehRadioStation(vehicle, 'OFF')
    applyVehicleLook(vehicle, entry)
    lastVehicle = vehicle
    if options.warpInto then TaskWarpPedIntoVehicle(ped, vehicle, -1) end
    RPI.notify(('Véhicule : %s'):format(entry.label), 'success')
end

RegisterNUICallback('spawnVehicle', function(data, cb)
    cb({ ok = true })
    local id = type(data) == 'table' and tonumber(data.id) or nil
    RPI.request('spawnVehicle', { id = id }, function(res)
        if not res or not res.ok then return RPI.notify(res and res.error or 'Action impossible.', 'error') end
        CreateThread(function() spawn(res.vehicle) end)
    end)
end)

-- =========================================================================
-- ÉQUIPEMENTS : équipements de service (equipment_services.json : "Équipement GSP / APD / FCSO", personnalisables
-- par chaque joueur), autres lots d'armes (data/loadouts.json) ; les tenues sont dans le menu /eup (client/eup.lua)
-- =========================================================================
RegisterNUICallback('equipmentList', function(_, cb)
    RPI.request('loadoutList', {}, function(res)
        res = res or {}
        cb({ ok = res.ok == true, loadouts = res.loadouts or {}, services = res.services or {}, police = res.police == true,
            policeOnly = res.policeOnly ~= false, customs = res.customs or {}, maxCustom = res.maxCustom })
    end)
end)

local function giveLoadout(ped, loadout)
    if loadout.replace then RemoveAllPedWeapons(ped, true) end
    for _, w in ipairs(loadout.weapons or {}) do
        local hash = GetHashKey(w.weapon)
        GiveWeaponToPed(ped, hash, w.ammo or 0, false, false)
        for _, component in ipairs(w.components or {}) do GiveWeaponComponentToPed(ped, hash, GetHashKey(component)) end
        if w.tint then SetPedWeaponTintIndex(ped, hash, w.tint) end -- teinte choisie (Customiser équipement)
    end
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
end

-- Customiser équipement : armes, accessoires et teintes du service choisi (équipement de base ou équipement modifié)
RegisterNUICallback('equipmentCustom', function(data, cb)
    data = type(data) == 'table' and data or {}
    RPI.request('equipmentCustom', { key = data.key, id = data.id }, function(res)
        cb(res or { ok = false })
    end)
end)

-- "Équiper" (sans enregistrer), "Enregistrer" (équipement modifié nommé), "Supprimer"
RegisterNUICallback('equipmentCustomSave', function(data, cb)
    data = type(data) == 'table' and data or {}
    local action = (data.action == 'save' or data.action == 'delete') and data.action or 'apply'
    RPI.request('equipmentCustomSave', { key = data.key, id = data.id, action = action, name = data.name, choices = data.choices },
        function(res)
            if not res or not res.ok then
                cb(res or { ok = false })
                return RPI.notify(res and res.error or 'Action impossible.', 'error')
            end
            if action == 'delete' then
                RPI.notify('Équipement modifié supprimé.', 'success')
                return cb({ ok = true, deleted = true, customs = res.customs or {} })
            end
            if type(res.loadout) == 'table' then giveLoadout(PlayerPedId(), res.loadout) end
            RPI.notify(action == 'save' and ('« %s » enregistré dans Équipements modifiés.'):format(res.name or '')
                or ('Armes : %s (non enregistré)'):format(res.loadout and res.loadout.name or ''), 'success')
            cb({ ok = true, saved = res.saved == true, id = res.id, name = res.name, customs = res.customs })
        end)
end)

RegisterNUICallback('useEquipment', function(data, cb)
    data = type(data) == 'table' and data or {}
    local ped = PlayerPedId()
    if data.kind == 'removeWeapons' then
        RemoveAllPedWeapons(ped, true)
        cb({ ok = true })
        return RPI.notify('Armes retirées.', 'success')
    end
    if data.kind ~= 'loadout' and data.kind ~= 'service' and data.kind ~= 'custom' then return cb({ ok = false }) end
    RPI.request('equipment', { kind = data.kind, index = data.index, key = data.key, id = data.id }, function(res)
        if not res or not res.ok or type(res.loadout) ~= 'table' then
            cb({ ok = false, error = res and res.error })
            return RPI.notify(res and res.error or 'Action impossible.', 'error')
        end
        giveLoadout(PlayerPedId(), res.loadout)
        RPI.notify(('Armes : %s%s'):format(res.loadout.name, res.custom and ' (équipement modifié)' or ''), 'success')
        cb({ ok = true })
    end)
end)

-- Équipements > "Accéder aux tenues" : menu /eup
RegisterNUICallback('openEup', function(_, cb)
    cb({ ok = true })
    if RPI.closeMenu then RPI.closeMenu() end
    if RPI.openEup then RPI.openEup() end
end)
