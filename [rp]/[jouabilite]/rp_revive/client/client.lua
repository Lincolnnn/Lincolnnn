--[[
    RP Revive - client
    ------------------
    Mort : un écran s'affiche (après Delay secondes, les choix s'activent) :
      - RÉANIMER SUR PLACE : là où est le corps ;
      - RÉANIMER À L'HÔPITAL : un des hôpitaux de Config.Hospitals, AU HASARD (Sandy Shores ou Paleto Bay) ;
      - case LAISSER MON CORPS SUR PLACE (secondaire) : une copie du personnage (même apparence, tenue comprise) reste
        allongée là où il est mort, pour tout le monde ; l'œil de rp_interact y trouve la description du profil civil
        actif (inspection, fouille, détail notoire), sauf l'odeur détectée automatiquement.
    Souris ou clavier (E : sur place, H : hôpital, C : laisser le corps). Réanimé par un autre script (secours…) :
    l'écran se ferme tout seul. La réapparition automatique de spawnmanager est coupée (DisableAutoSpawn), et re-coupée
    quand le gamemode la réactive (chargement de la carte, redémarrage, toutes les 5 s, à la mort).
    Performance : une vérification « suis-je mort ? » toutes les 500 ms (une native), rien d'autre.
]]

local R = ReviveConfig
local dead = false
local readyAt = 0
local busy = false

local function notify(text)
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started'
        and pcall(function() exports[chat]:addPrivate({ title = 'Réanimation', text = text }) end) then
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end

local function showMenu(show)
    SetNuiFocus(show, show)
    SendNUIMessage({ action = 'death', data = show and {
        show = true, delay = math.max(0, tonumber(R.Delay) or 0), keys = R.Keys or {},
        corpse = (R.Corpse or {}).Enabled ~= false,
        hospitals = (function() local l = {} for i, h in ipairs(R.Hospitals or {}) do l[i] = h.label end return l end)(),
    } or { show = false } })
end

local function onDeath()
    dead, busy = true, false
    readyAt = GetGameTimer() + math.floor((tonumber(R.Delay) or 0) * 1000)
    showMenu(true)
end

-- =========================================================================
-- CORPS LAISSÉ SUR PLACE : copie du personnage (réseau), tuée là où était le corps, puis immobile
-- =========================================================================
local function leaveCorpse(ped, pos, rot)
    local clone = ClonePed(ped, true, false, true)
    if not clone or clone == 0 then return end
    SetEntityAsMissionEntity(clone, true, true)
    SetEntityCoordsNoOffset(clone, pos.x, pos.y, pos.z, false, false, false)
    SetEntityRotation(clone, rot.x, rot.y, rot.z, 2, true)
    SetBlockingOfNonTemporaryEvents(clone, true)
    SetPedCanRagdoll(clone, true)
    SetEntityHealth(clone, 0) -- il retombe là où était le corps
    local netId = NetworkGetNetworkIdFromEntity(clone)
    SetNetworkIdCanMigrate(netId, true)
    TriggerServerEvent('rp_revive:corpse', netId)
    SetTimeout(4000, function()
        if DoesEntityExist(clone) then FreezeEntityPosition(clone, true) end -- ne glisse plus
    end)
end

-- =========================================================================
-- RÉANIMER : sur place ou dans un hôpital au hasard
-- =========================================================================
local function revive(where, corpse)
    local ped = PlayerPedId()
    local pos, heading, rot = GetEntityCoords(ped), GetEntityHeading(ped), GetEntityRotation(ped, 2)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if corpse and (R.Corpse or {}).Enabled ~= false then leaveCorpse(ped, pos, rot) end

    local dest, label
    if where == 'hospital' and #(R.Hospitals or {}) > 0 then
        local h = R.Hospitals[math.random(1, #R.Hospitals)]
        dest, label = h.coords, h.label
    elseif vehicle ~= 0 then
        local side = GetOffsetFromEntityInWorldCoords(vehicle, -2.2, 0.0, 0.0) -- à côté du véhicule
        dest = vector4(side.x, side.y, side.z, heading)
    else
        dest = vector4(pos.x, pos.y, pos.z, heading)
    end

    DoScreenFadeOut(400)
    local timeout = GetGameTimer() + 2000
    while not IsScreenFadedOut() and GetGameTimer() < timeout do Wait(0) end
    showMenu(false)
    RequestCollisionAtCoord(dest.x, dest.y, dest.z)
    NetworkResurrectLocalPlayer(dest.x, dest.y, dest.z, dest.w, true, false)
    ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, dest.x, dest.y, dest.z, false, false, false)
    SetEntityHeading(ped, dest.w)
    ClearPedTasksImmediately(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    SetPlayerInvincible(PlayerId(), false)
    ClearPlayerWantedLevel(PlayerId())
    timeout = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do Wait(0) end
    DoScreenFadeIn(600)
    dead, busy = false, false
    TriggerServerEvent('rp_revive:revived', where == 'hospital' and 'hospital' or 'here')
    -- (pas de message : l'écran de mort se ferme, le joueur voit où il est)
end
RPRevive = { revive = revive, leaveCorpse = leaveCorpse } -- pour les tests

RegisterNUICallback('revive', function(data, cb)
    cb({ ok = true })
    if not dead or busy or type(data) ~= 'table' then return end
    if GetGameTimer() < readyAt then return end
    busy = true
    CreateThread(function() revive(data.where == 'hospital' and 'hospital' or 'here', data.corpse == true) end)
end)

-- =========================================================================
-- MORT ? (500 ms) ; réanimé par un autre script : l'écran se ferme
-- =========================================================================
-- Réapparition automatique de spawnmanager (point au hasard ~2 s après la mort) : coupée, et RE-coupée, car le gamemode
-- (basic-gamemode…) la réactive à chaque chargement de la carte (onClientMapStart : setAutoSpawn(true)) ou en redémarrant
local function noAutoSpawn()
    if R.DisableAutoSpawn == false or GetResourceState('spawnmanager') ~= 'started' then return end
    pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
end
RPRevive.noAutoSpawn = noAutoSpawn

AddEventHandler('onClientMapStart', function()
    noAutoSpawn()
    SetTimeout(1000, noAutoSpawn) -- après le gamemode, qui la réactive au même moment
    SetTimeout(5000, noAutoSpawn)
end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then SetTimeout(500, noAutoSpawn) end -- spawnmanager / gamemode (re)démarré
end)
AddEventHandler('playerSpawned', function() SetTimeout(500, noAutoSpawn) end)

CreateThread(function()
    noAutoSpawn()
    local nextCheck = 0
    while true do
        local isDead = IsEntityDead(PlayerPedId())
        local now = GetGameTimer()
        -- sécurité : re-coupée toutes les 5 s (un autre script a pu la réactiver)
        if now >= nextCheck then nextCheck = now + 5000; noAutoSpawn() end
        if isDead and not dead then
            noAutoSpawn() -- tout de suite (spawnmanager attend ~2 s après la mort)
            onDeath()
        elseif dead and not isDead and not busy then
            dead = false
            showMenu(false)
        end
        Wait(500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and dead then SetNuiFocus(false, false) end
end)
