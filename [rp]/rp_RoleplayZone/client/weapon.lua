--[[
    RP RoleplayZone - client : lâcher son arme (MODE CIVIL uniquement)
    -------------------------------------------------------------------
    - Le joueur SORT une arme : pendant 10 s, un rappel en haut à gauche propose « [touche] Lâcher son arme ». La
      touche (G par défaut, modifiable dans les raccourcis FiveM) reste utilisable tout le temps : le rappel n'apparaît
      qu'au début.
    - Touche appuyée : le texte change et propose la MÊME touche pour « Jeter son arme » ; la MOLETTE (haut ou bas)
      bascule sur « Poser son arme au sol » (et inversement). Pendant ce choix, les actions du jeu de base liées à la
      molette (changer d'arme, roue des armes, zoom de la lunette) sont bloquées : aucune double action.
      Touche appuyée à nouveau : l'action choisie. Retour arrière : annuler. Arme rangée / changée : annulé.
    - JETER : geste de lancer, l'arme part vers l'avant (là où regarde la caméra) et retombe au sol (physique du jeu).
      POSER : l'arme est posée couchée au sol, devant le joueur.
    - L'arme au sol se récupère UNIQUEMENT avec l'œil de rp_interact (Alt : « Arme au sol » -> « Ramasser l'arme »).
    Performance : arme en main vérifiée toutes les 250 ms (civils seulement ; sinon toutes les 2 s) ; boucle à chaque
    image seulement pendant le rappel (10 s) ou le choix.
]]

RZ = RZ or {}
local Config = SceneConfig
local W = Config.Weapons or {}
local COMMAND = W.Command or 'lacherarme'
local UNARMED = GetHashKey('WEAPON_UNARMED')

local BLACKLIST = {}
for _, name in ipairs(W.Blacklist or {}) do BLACKLIST[GetHashKey(name)] = true end

-- Molette et actions du jeu qui s'en servent : bloquées pendant le choix
local WHEEL_UP = { 15, 241, 261 }   -- roue des armes / défilement / arme précédente
local WHEEL_DOWN = { 14, 242, 262 }
local WHEEL_BLOCKED = { 14, 15, 16, 17, 37, 39, 40, 99, 100, 115, 116, 241, 242, 261, 262, 334, 335 }
local CANCEL = { 177, 194 }         -- Retour arrière

local reminderUntil = 0             -- fin du rappel « Lâcher son arme »
local choice = nil                  -- { option = 'throw' | 'place', weapon, at }
local busy = false
local lastWeapon = UNARMED
local displayRunning = false

--- Touche choisie par le joueur pour la commande (raccourcis FiveM), ex. "G" ; à défaut, celle de la config
local function keyName()
    local ok, button = pcall(GetControlInstructionalButton, 0, (GetHashKey(COMMAND) & 0xFFFFFFFF) | 0x80000000, true)
    if ok and type(button) == 'string' and button:sub(1, 2) == 't_' and #button > 2 then return button:sub(3) end
    return W.Key or 'G'
end

local function droppable(weapon)
    return weapon and weapon ~= 0 and weapon ~= UNARMED and not BLACKLIST[weapon]
end

--- Lâcher son arme : mode civil seulement (W.CivilOnly), à pied, arme lâchable en main
local function canUse(ped)
    if W.Enabled == false then return false end
    if W.CivilOnly ~= false and not RZ.civilMode() then return false end
    if IsPedInAnyVehicle(ped, true) or IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedSwimming(ped) then return false end
    return droppable(GetSelectedPedWeapon(ped))
end

local function loadAnim(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 1000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function loadModel(model)
    RequestModel(model)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(10) end
    return HasModelLoaded(model)
end

--- Position et rotation pour que l'arme soit couchée sur le sol (son côté le plus fin à la verticale)
local function lyingPlacement(model, x, y, ground, heading)
    local min, max = GetModelDimensions(model)
    local size = max - min
    local rx, ry = 0.0, 0.0
    if size.x <= size.y and size.x <= size.z then ry = 90.0 elseif size.y <= size.z then rx = 90.0 end
    local probe = CreateObjectNoOffset(model, x, y, ground + 1.0, false, false, false)
    SetEntityVisible(probe, false, false)
    SetEntityCollision(probe, false, false)
    FreezeEntityPosition(probe, true)
    SetEntityRotation(probe, rx, ry, heading, 2, true)
    local lowest = math.huge
    for _, cx in ipairs({ min.x, max.x }) do
        for _, cy in ipairs({ min.y, max.y }) do
            for _, cz in ipairs({ min.z, max.z }) do
                local w = GetOffsetFromEntityInWorldCoords(probe, cx, cy, cz)
                if w.z < lowest then lowest = w.z end
            end
        end
    end
    local origin = GetEntityCoords(probe)
    DeleteEntity(probe)
    return vector3(origin.x, origin.y, origin.z + (ground + 0.01 - lowest)), rx, ry
end

-- =========================================================================
-- ACTIONS
-- =========================================================================
--- L'arme quitte les mains TOUT DE SUITE, avec le hash lu ici (jamais celui renvoyé par le serveur) ; rendue si le
--- serveur refuse (rp_scene:weapon:refused)
local pending = nil -- { weapon, ammo } : arme lâchée, en attente de la réponse du serveur
local function releaseWeapon(ped, weapon)
    local ammo = GetAmmoInPedWeapon(ped, weapon)
    pending = { weapon = weapon, ammo = ammo, at = GetGameTimer() }
    SetCurrentPedWeapon(ped, UNARMED, true)
    SetPedAmmo(ped, weapon, 0)
    RemoveWeaponFromPed(ped, weapon)
    lastWeapon = UNARMED
    return ammo
end

local function place(ped, weapon, model)
    loadAnim('pickup_object')
    TaskPlayAnim(ped, 'pickup_object', 'putdown_low', 8.0, -8.0, 900, 0, 0.0, false, false, false)
    Wait(450)
    local spot = GetOffsetFromEntityInWorldCoords(ped, 0.15, 0.55, 0.0)
    local found, ground = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 1.0, false)
    if not found then ground = spot.z - 0.98 end
    local heading = (GetEntityHeading(ped) + 90.0) % 360.0
    local pos, rx, ry = lyingPlacement(model, spot.x, spot.y, ground, heading)
    local ammo = releaseWeapon(ped, weapon)
    TriggerServerEvent('rp_scene:weapon:drop', {
        mode = 'place', weapon = weapon, model = model, ammo = ammo, civil = RZ.civilMode(),
        x = pos.x, y = pos.y, z = pos.z, rx = rx, ry = ry, rz = heading,
    })
end

local function throw(ped, weapon, model)
    local anim = W.ThrowAnim or { 'anim@heists@narcotics@trash', 'throw_b' }
    if loadAnim(anim[1]) then
        TaskPlayAnim(ped, anim[1], anim[2], 8.0, -8.0, W.ThrowAnimTime or 1200, 48, 0.0, false, false, false)
    end
    Wait(W.ThrowRelease or 550) -- l'arme quitte la main à ce moment du geste
    local hand = GetPedBoneCoords(ped, 57005, 0.0, 0.0, 0.0) -- main droite
    local dir = RZ.camDirection()
    local flat = math.sqrt(dir.x * dir.x + dir.y * dir.y)
    if flat < 0.2 then -- caméra trop verticale : devant le joueur
        local f = GetEntityForwardVector(ped)
        dir, flat = vector3(f.x, f.y, 0.0), 1.0
    end
    local speed = W.ThrowSpeed or 7.5
    local velocity = { x = dir.x / flat * speed, y = dir.y / flat * speed, z = W.ThrowUp or 3.0 }
    local start = { x = hand.x + dir.x / flat * 0.35, y = hand.y + dir.y / flat * 0.35, z = hand.z + 0.1 }
    local ammo = releaseWeapon(ped, weapon)
    TriggerServerEvent('rp_scene:weapon:drop', {
        mode = 'throw', weapon = weapon, model = model, ammo = ammo, civil = RZ.civilMode(),
        x = start.x, y = start.y, z = start.z, rx = 0.0, ry = 0.0, rz = GetEntityHeading(ped), velocity = velocity,
    })
end

local function perform(option)
    local ped = PlayerPedId()
    if busy or not canUse(ped) then return end
    local weapon = GetSelectedPedWeapon(ped)
    local model = GetWeapontypeModel(weapon)
    if not model or model == 0 or not IsModelInCdimage(model) then return RZ.notify('Cette arme ne peut pas être lâchée.') end
    busy = true
    CreateThread(function()
        if not loadModel(model) then busy = false return RZ.notify('Modèle de l\'arme introuvable.') end
        if option == 'throw' then throw(ped, weapon, model) else place(ped, weapon, model) end
        SetModelAsNoLongerNeeded(model)
        Wait(500)
        busy = false
    end)
end

-- =========================================================================
-- AIDE (rappel, puis choix jeter / poser) : boucle seulement quand elle s'affiche
-- =========================================================================
--- Aide dans l'interface (au thème du HUD) : envoyée seulement quand elle change
local lastHint = nil
local function hint(data)
    local key = data and json.encode(data) or ''
    if key == lastHint then return end
    lastHint = key
    SendNUIMessage({ action = 'weaponHint', data = data or { show = false } })
end

local function anyJustPressed(list)
    for _, c in ipairs(list) do if IsDisabledControlJustPressed(0, c) then return true end end
    return false
end

local function display()
    if displayRunning then return end
    displayRunning = true
    CreateThread(function()
        while choice or GetGameTimer() < reminderUntil do
            local ped = PlayerPedId()
            local now = GetGameTimer()
            local usable = canUse(ped)
            if choice and (not usable or GetSelectedPedWeapon(ped) ~= choice.weapon
                or now - choice.at > (W.ChoiceTimeout or 10000)) then
                choice = nil -- arme rangée / changée, ou plus de réponse : choix annulé
            end
            if not usable then reminderUntil = 0 end
            if choice then
                for _, c in ipairs(WHEEL_BLOCKED) do DisableControlAction(0, c, true) end
                if anyJustPressed(WHEEL_UP) or anyJustPressed(WHEEL_DOWN) then
                    choice.option = choice.option == 'throw' and 'place' or 'throw'
                    choice.at = now
                end
                if anyJustPressed(CANCEL) then choice = nil end
            end
            -- G du jeu (grenade, détonateur) : pas de double action
            DisableControlAction(0, 47, true)
            DisableControlAction(0, 58, true)
            if IsPauseMenuActive() or busy then
                hint(nil)
            elseif choice then
                hint({ show = true, key = keyName(), label = choice.option == 'throw' and 'Jeter son arme' or 'Poser son arme au sol',
                    alt = choice.option == 'throw' and 'Poser au sol' or 'Jeter' })
            elseif now < reminderUntil then
                hint({ show = true, key = keyName(), label = 'Lâcher son arme' })
            else
                hint(nil)
            end
            Wait(0)
        end
        hint(nil)
        displayRunning = false
    end)
end

--- Touche : 1er appui -> choix (jeter par défaut) ; 2e appui -> l'action choisie
local function onKey()
    local ped = PlayerPedId()
    if busy or not canUse(ped) then return end
    if choice then
        local option = choice.option
        choice, reminderUntil = nil, 0
        perform(option)
        return
    end
    choice = { option = 'throw', weapon = GetSelectedPedWeapon(ped), at = GetGameTimer() }
    reminderUntil = 0
    display()
end

RegisterCommand(COMMAND, function() if not RZ.spikesBusy() then onKey() end end, false) -- G : touche de la herse de Riven
RegisterKeyMapping(COMMAND, 'Mode civil : lâcher son arme (jeter / poser au sol)', 'keyboard', W.Key or 'G')

-- Arme sortie (mode civil) : rappel pendant 10 s
CreateThread(function()
    if W.Enabled == false then return end
    while true do
        local civil = W.CivilOnly == false or RZ.civilMode()
        if civil then
            local ped = PlayerPedId()
            local weapon = GetSelectedPedWeapon(ped)
            if weapon ~= lastWeapon then
                lastWeapon = weapon
                if canUse(ped) then
                    reminderUntil = GetGameTimer() + (W.ReminderTime or 10000)
                    display()
                end
            end
            Wait(250)
        else
            lastWeapon = UNARMED
            Wait(2000)
        end
    end
end)

-- =========================================================================
-- RÉPONSES DU SERVEUR
-- =========================================================================
--- L'objet de l'arme jetée : élan donné par le joueur qui l'a jetée, puis immobilisée une fois retombée
local function launch(netId, velocity)
    CreateThread(function()
        local timeout = GetGameTimer() + 1500
        while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < timeout do Wait(0) end
        if not NetworkDoesNetworkIdExist(netId) then return end
        local obj = NetToObj(netId)
        NetworkRequestControlOfEntity(obj)
        timeout = GetGameTimer() + 600
        while not NetworkHasControlOfEntity(obj) and GetGameTimer() < timeout do Wait(0) end
        local hasControl = NetworkHasControlOfEntity(obj)
        if hasControl then
            FreezeEntityPosition(obj, false)
            ActivatePhysics(obj)
            SetEntityVelocity(obj, velocity.x + 0.0, velocity.y + 0.0, velocity.z + 0.0)
            SetEntityAngularVelocity(obj, math.random(-6, 6) + 0.0, math.random(-6, 6) + 0.0, math.random(-10, 10) + 0.0)
        end
        -- retombée : immobile 3 vérifications de suite (ou 4 s au plus)
        local still, endAt = 0, GetGameTimer() + 4000
        while GetGameTimer() < endAt and still < 3 do
            Wait(100)
            if not DoesEntityExist(obj) then return end
            local v = GetEntityVelocity(obj)
            if #(v) < 0.08 then still = still + 1 else still = 0 end
        end
        local c, r = GetEntityCoords(obj), GetEntityRotation(obj, 2)
        if not hasControl then
            -- pas la main sur l'objet : il est posé là où il serait retombé (devant, au sol)
            local fx, fy = velocity.x * 0.45, velocity.y * 0.45
            local found, ground = GetGroundZFor_3dCoord(c.x + fx, c.y + fy, c.z + 1.0, false)
            c = vector3(c.x + fx, c.y + fy, (found and ground or c.z) + 0.03)
        end
        TriggerServerEvent('rp_scene:weapon:settled', netId, { x = c.x, y = c.y, z = c.z }, { x = r.x, y = r.y, z = r.z })
    end)
end

-- Confirmé par le serveur : l'arme est au sol (jetée : l'élan est donné à l'objet). Elle a déjà quitté les mains ;
-- par sécurité, retirée encore (hash local) si un autre script l'avait rendue entre-temps.
RegisterNetEvent('rp_scene:weapon:dropped', function(_, netId, mode, velocity)
    local ped = PlayerPedId()
    if pending and HasPedGotWeapon(ped, pending.weapon, false) then
        SetPedAmmo(ped, pending.weapon, 0)
        RemoveWeaponFromPed(ped, pending.weapon)
        SetCurrentPedWeapon(ped, UNARMED, true)
    end
    pending = nil
    lastWeapon = UNARMED
    if mode == 'throw' and netId and type(velocity) == 'table' then launch(netId, velocity) end
end)

-- Refusé par le serveur (trop d'armes au sol, endroit impossible…) : l'arme est rendue avec ses munitions
RegisterNetEvent('rp_scene:weapon:refused', function(message)
    local p = pending
    pending = nil
    if p then
        local ped = PlayerPedId()
        if not HasPedGotWeapon(ped, p.weapon, false) then GiveWeaponToPed(ped, p.weapon, p.ammo or 0, false, true) end
    end
    if message then RZ.notify(message) end
end)

-- Ramassée (œil de rp_interact) : l'arme et ses munitions
RegisterNetEvent('rp_scene:weapon:pickedUp', function(weapon, ammo)
    local ped = PlayerPedId()
    if loadAnim('pickup_object') then
        TaskPlayAnim(ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 900, 0, 0.0, false, false, false)
    end
    if HasPedGotWeapon(ped, weapon, false) then
        AddAmmoToPed(ped, weapon, tonumber(ammo) or 0)
    else
        GiveWeaponToPed(ped, weapon, tonumber(ammo) or 0, false, false)
    end
    RZ.notify('Arme ramassée.')
end)

--- Arme au sol (objet réseau marqué "rpDroppedWeapon")
function RZ.isDroppedWeapon(e)
    return e and e ~= 0 and DoesEntityExist(e) and NetworkGetEntityIsNetworked(e)
        and type(Entity(e).state.rpDroppedWeapon) == 'table'
end
