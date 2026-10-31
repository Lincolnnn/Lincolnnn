--[[
    RP Interact - Menu "Voiture > Spawn" et "Équipements" (client)
    ---------------------------------------------------------------
    SPAWN : véhicules de data/vehicle.json uniquement (liste envoyée par le serveur), classés par catégorie
      principale ("Principale" : Police, Civil…) puis par sous-catégorie ("subCategory"). Deux options en haut, gardées chez
      le joueur : "Supprimer l'ancien véhicule" (le dernier qu'il a fait apparaître, s'il n'y a pas
      d'autre joueur dedans) et "Apparaître dans le véhicule". Livery, extras et teinte des vitres de la liste appliqués.
      Le véhicule est créé par ce script : Vehicle Control le considère comme neuf (plein, moteur coupé).
    ÉQUIPEMENTS : "Équipement WSP" / "Équipement KCSO" (equipment_services.json : tout l'équipement de départ
      de la police, toujours la version de base), "Équipements modifiés" (ceux que le joueur a nommés et enregistrés,
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

--- Livery (index de livery, ou mod de livery n° 48 pour les véhicules qui l'utilisent), extras et teinte des vitres
local function applyVehicleLook(vehicle, entry)
    if entry.windowTint then
        SetVehicleModKit(vehicle, 0)
        SetVehicleWindowTint(vehicle, entry.windowTint)
    end
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
-- ÉQUIPEMENTS : équipements de police (equipment_services.json : "Équipement WSP / KCSO", personnalisables
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

-- =========================================================================
-- CUSTOMISER ÉQUIPEMENT : aperçu en direct, zoom sur l'arme, souris dans l'onglet ouvert
-- =========================================================================
--- Aperçu : les armes du service prises / retirées, accessoires et teinte exactement comme choisis ; l'arme de
--- l'onglet ouvert (`focus`) en main. Les autres armes du joueur ne sont pas touchées.
local function applyPreview(ped, loadout, focus)
    for _, name in ipairs(loadout.off or {}) do
        local hash = GetHashKey(name)
        if HasPedGotWeapon(ped, hash, false) then RemoveWeaponFromPed(ped, hash) end
    end
    for _, w in ipairs(loadout.weapons or {}) do
        local hash = GetHashKey(w.weapon)
        if not HasPedGotWeapon(ped, hash, false) then GiveWeaponToPed(ped, hash, w.ammo or 0, false, false) end
        local want = {}
        for _, component in ipairs(w.components or {}) do want[GetHashKey(component)] = true end
        -- d'abord retirés (un seul chargeur, un seul viseur…), puis ajoutés
        for _, component in ipairs(w.all or {}) do
            local c = GetHashKey(component)
            if not want[c] and HasPedGotWeaponComponent(ped, hash, c) then RemoveWeaponComponentFromPed(ped, hash, c) end
        end
        for _, component in ipairs(w.components or {}) do
            local c = GetHashKey(component)
            if not HasPedGotWeaponComponent(ped, hash, c) then GiveWeaponComponentToPed(ped, hash, c) end
        end
        if GetPedWeaponTintIndex(ped, hash) ~= (w.tint or 0) then SetPedWeaponTintIndex(ped, hash, w.tint or 0) end
    end
    if focus then
        local hash = GetHashKey(focus)
        local want = HasPedGotWeapon(ped, hash, false) and hash or GetHashKey('WEAPON_UNARMED')
        -- déjà en main : pas ressortie (sinon l'arme était rangée / ressortie à chaque changement : à-coups à l'écran)
        if GetSelectedPedWeapon(ped) ~= want then SetCurrentPedWeapon(ped, want, true) end
    end
end

local Z = Config.EquipmentZoom or {}
local ZOOM_BLOCKED = { 1, 2, 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 44, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264 }
local focus = { weapon = nil, cam = nil, running = false }

local function stopCam()
    if not focus.cam then return end
    RenderScriptCams(false, true, 350, true, false)
    DestroyCam(focus.cam, false)
    focus.cam = nil
end

--- Caméra rapprochée sur l'arme en main (à pied) ; le joueur ne bouge pas tant qu'un onglet d'arme est ouvert.
--- La caméra est ACCROCHÉE au personnage et visée sur sa main droite par le jeu lui-même (une seule fois) : plus de
--- recalage à chaque image sur l'objet de l'arme, recréé à chaque accessoire changé (c'était les petites coupures).
-- Armes longues (groupes du jeu) : caméra plus loin (EquipmentZoom.Long), sinon réglage de base (armes de poing…)
local LONG_GROUPS = {}
for _, g in ipairs(Z.LongGroups or { 'GROUP_RIFLE', 'GROUP_SHOTGUN', 'GROUP_SNIPER', 'GROUP_MG' }) do LONG_GROUPS[GetHashKey(g)] = true end

local function zoomFor(weapon)
    local long = weapon and LONG_GROUPS[GetWeapontypeGroup(GetHashKey(weapon))]
    local L = long and (Z.Long or {}) or {}
    return L.Offset or Z.Offset or { x = 0.55, y = 0.95, z = 0.15 },
        L.Target or Z.Target or { x = 0.12, y = 0.0, z = 0.0 },
        L.Fov or Z.Fov or 34.0
end

--- Cadrage selon l'arme de l'onglet ouvert (changé sans recréer la caméra quand on passe d'une arme à l'autre)
local function frameCam(ped)
    local o, t, fov = zoomFor(focus.weapon)
    focus.camWeapon = focus.weapon
    SetCamFov(focus.cam, fov)
    AttachCamToEntity(focus.cam, ped, o.x, o.y, o.z, true)
    PointCamAtPedBone(focus.cam, ped, 57005, t.x, t.y, t.z, true) -- main droite (SKEL_R_Hand)
end

local function startCam(ped)
    focus.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    focus.ped = ped
    frameCam(ped)
    RenderScriptCams(true, true, 450, true, false)
end

local function focusLoop()
    if focus.running then return end
    focus.running = true
    CreateThread(function()
        while focus.weapon do
            for _, control in ipairs(ZOOM_BLOCKED) do DisableControlAction(0, control, true) end
            local ped = PlayerPedId()
            if Z.Enabled ~= false and not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
                if focus.cam and focus.ped ~= ped then stopCam() end -- personnage changé (tenue /eup…)
                if not focus.cam then startCam(ped)
                elseif focus.camWeapon ~= focus.weapon then frameCam(ped) end
            else
                stopCam()
            end
            Wait(0)
        end
        stopCam()
        focus.running = false
    end)
end

--- Onglet d'arme ouvert (`weapon`) ou fermé (nil) : zoom sur l'arme et souris dans le menu
function RPI.equipmentFocus(weapon)
    weapon = type(weapon) == 'string' and weapon ~= '' and weapon or nil
    focus.weapon = weapon
    RPI.setMenuCursor(weapon ~= nil)
    if weapon then
        local ped, hash = PlayerPedId(), GetHashKey(weapon)
        if HasPedGotWeapon(ped, hash, false) and GetSelectedPedWeapon(ped) ~= hash then SetCurrentPedWeapon(ped, hash, true) end
        focusLoop()
    end
end

RegisterNUICallback('equipmentFocus', function(data, cb)
    cb({ ok = true })
    RPI.equipmentFocus(type(data) == 'table' and data.weapon or nil)
end)

-- "preview" (aperçu en direct, à chaque changement), "Enregistrer" (équipement modifié nommé), "Supprimer"
RegisterNUICallback('equipmentCustomSave', function(data, cb)
    data = type(data) == 'table' and data or {}
    local action = (data.action == 'save' or data.action == 'delete' or data.action == 'preview') and data.action or 'apply'
    RPI.request('equipmentCustomSave', { key = data.key, id = data.id, action = action, name = data.name, choices = data.choices },
        function(res)
            if not res or not res.ok then
                cb(res or { ok = false })
                return RPI.notify(res and res.error or 'Action impossible.', 'error')
            end
            if action == 'preview' then
                if type(res.loadout) == 'table' then applyPreview(PlayerPedId(), res.loadout, data.focus) end
                return cb({ ok = true })
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
