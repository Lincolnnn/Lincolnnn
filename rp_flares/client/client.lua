--[[
    RP Flares - client
    ------------------
    - Fusée de détresse en main (WEAPON_FLARE) : la touche (G par défaut) la POSE au sol, debout, allumée. Le joueur la
      garde dans ses armes : il peut en poser autant qu'il veut (FlareConfig.MaxPerPlayer pour limiter).
    - Fusée posée : objet créé par le serveur (visible par tous, gardé même si le joueur se déconnecte), marqué
      "rpFlare" (sommet de la fusée) ; on la retire avec l'œil de rp_interact ("Retirer la fusée").
    - Chaque client dessine la flamme (particules) et une LUMIÈRE rouge vive qui vacille, bien plus forte et plus
      large la nuit.
    - Fusée en main : aide en haut à gauche ("G Poser la fusée au sol" / "Utiliser le target pour la reprendre").
    Performance : arme en main vérifiée toutes les 500 ms (aide à chaque image seulement fusée en main) ; aucune
    autre boucle sans fusée connue. Fusées posées dans les environs : vérification toutes les secondes ;
    lumière dessinée à chaque image seulement quand une fusée est à moins de Light.Distance m.
]]

local Config = FlareConfig
local L, E = Config.Light, Config.Effect
local WEAPON = GetHashKey(Config.Weapon)
local PLACE_ANIM = { 'pickup_object', 'pickup_low' }
local placing = false

local function notify(text)
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started'
        and pcall(function() exports[chat]:addPrivate({ title = 'Fusée', text = text }) end) then
        return
    end
    TriggerEvent('chat:addMessage', { args = { 'Fusée', text }, color = { 255, 120, 90 } })
end
RegisterNetEvent('rp_flares:notify', notify)

local function loadModel(hash)
    RequestModel(hash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    return HasModelLoaded(hash)
end

local function modelName()
    if IsModelInCdimage(GetHashKey(Config.Model)) then return Config.Model end
    return Config.FallbackModel
end

--- Fusée debout : redressée selon sa forme (son plus grand côté à la verticale), le bas posé sur le sol.
--- Mesuré sur un objet invisible propre à ce client (le sens des rotations du jeu n'a pas à être deviné).
--- Retourne la position de l'objet, sa rotation (x, y) et le sommet de la fusée.
local function uprightPlacement(hash, x, y, ground)
    local min, max = GetModelDimensions(hash)
    local size = max - min
    local rx, ry, axis = 0.0, 0.0, 'z'
    if size.x >= size.y and size.x > size.z then
        ry, axis = 90.0, 'x'
    elseif size.y > size.z then
        rx, axis = 90.0, 'y'
    end
    local probe = CreateObjectNoOffset(hash, x, y, ground + 1.0, false, false, false)
    SetEntityVisible(probe, false, false)
    SetEntityCollision(probe, false, false)
    FreezeEntityPosition(probe, true)
    SetEntityRotation(probe, rx, ry, 0.0, 2, true)
    local a = vector3(axis == 'x' and min.x or 0.0, axis == 'y' and min.y or 0.0, axis == 'z' and min.z or 0.0)
    local b = vector3(axis == 'x' and max.x or 0.0, axis == 'y' and max.y or 0.0, axis == 'z' and max.z or 0.0)
    local endA = GetOffsetFromEntityInWorldCoords(probe, a.x, a.y, a.z)
    local endB = GetOffsetFromEntityInWorldCoords(probe, b.x, b.y, b.z)
    local origin = GetEntityCoords(probe)
    DeleteEntity(probe)
    local bottom, top = endA, endB
    if endB.z < endA.z then bottom, top = endB, endA end
    local shift = ground - bottom.z -- le bas de la fusée sur le sol
    return vector3(origin.x, origin.y, origin.z + shift), rx, ry, vector3(top.x, top.y, top.z + shift)
end

local function groundBelow(pos)
    local found, z = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.0, false)
    if found then return z end
    return pos.z - 0.98
end

local function place()
    local ped = PlayerPedId()
    if placing or IsPauseMenuActive() or IsPedInAnyVehicle(ped, true) or IsEntityDead(ped) or IsPedRagdoll(ped)
        or IsPedSwimming(ped) or GetSelectedPedWeapon(ped) ~= WEAPON then
        return
    end
    placing = true
    CreateThread(function()
        local name = modelName()
        local hash = GetHashKey(name)
        if not loadModel(hash) then
            placing = false
            return notify('Modèle de la fusée introuvable.')
        end
        RequestAnimDict(PLACE_ANIM[1])
        local timeout = GetGameTimer() + 1000
        while not HasAnimDictLoaded(PLACE_ANIM[1]) and GetGameTimer() < timeout do Wait(10) end
        TaskPlayAnim(ped, PLACE_ANIM[1], PLACE_ANIM[2], 8.0, -8.0, Config.PlaceTime or 900, 0, 0.0, false, false, false)
        Wait(math.floor((Config.PlaceTime or 900) / 2))
        local spot = GetOffsetFromEntityInWorldCoords(ped, 0.0, Config.PlaceDistance or 0.7, 0.0)
        local pos, rx, ry, top = uprightPlacement(hash, spot.x, spot.y, groundBelow(spot))
        SetModelAsNoLongerNeeded(hash)
        TriggerServerEvent('rp_flares:place', {
            model = name, x = pos.x, y = pos.y, z = pos.z, rx = rx, ry = ry,
            top = { x = top.x, y = top.y, z = top.z },
        })
        Wait(math.floor((Config.PlaceTime or 900) / 2))
        placing = false
    end)
end

RegisterCommand('rp_flare_place', place, false)
RegisterKeyMapping('rp_flare_place', 'Fusée de détresse : poser au sol (fusée en main)', 'keyboard', Config.Key or 'G')

-- =========================================================================
-- AIDE EN HAUT À GAUCHE, fusée en main : la touche (celle réellement choisie par le joueur) et comment la reprendre.
-- Performance : vérification de l'arme en main toutes les 500 ms ; aide redonnée à chaque image seulement pendant
-- que la fusée est en main.
-- =========================================================================
local KEY = ('~INPUT_%X~'):format((GetHashKey('rp_flare_place') | 0x80000000) & 0xFFFFFFFF)

local function holdingFlare(ped)
    return GetSelectedPedWeapon(ped) == WEAPON and not IsPedInAnyVehicle(ped, true) and not IsEntityDead(ped)
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if Config.Help ~= false and holdingFlare(ped) then
            local text = ('%s %s~n~%s'):format(KEY, Config.HelpPlace or 'Poser la fusée au sol',
                Config.HelpTake or 'Utiliser le target pour la reprendre')
            while holdingFlare(PlayerPedId()) do
                -- (une action d'essence à la pompe / trappe affiche déjà sa propre aide : pas de clignotement)
                if not IsPauseMenuActive() and not LocalPlayer.state.vcFuelPrompt then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName(text)
                    EndTextCommandDisplayHelp(0, false, false, -1)
                end
                Wait(0)
            end
        end
        Wait(500)
    end
end)

-- =========================================================================
-- FUSÉES POSÉES : flamme et lumière (tous les joueurs)
-- =========================================================================
local flares = {}   -- [nom du state bag] = { top, fx, level, target, nextFlicker, lost }
local running = false

local function stopFx(f)
    if f.fx then
        StopParticleFxLooped(f.fx, false)
        f.fx = nil
    end
end

local function startFx(f)
    if not E or E.Enabled == false then return end
    if not HasNamedPtfxAssetLoaded(E.Asset) then
        RequestNamedPtfxAsset(E.Asset) -- chargé : flamme lancée au passage suivant
        return
    end
    UseParticleFxAssetNextCall(E.Asset)
    f.fx = StartParticleFxLoopedAtCoord(E.Name, f.top.x, f.top.y, f.top.z, 0.0, 0.0, 0.0, E.Scale or 1.0, false, false, false, false)
end

local function isNight()
    local h = GetClockHours()
    if L.NightFrom > L.NightTo then return h >= L.NightFrom or h < L.NightTo end
    return h >= L.NightFrom and h < L.NightTo
end

--- Lumière d'une fusée (à chaque image) : vacille doucement, comme une flamme
local function drawLight(f, night, now)
    if now >= f.nextFlicker then
        f.nextFlicker = now + math.random(60, 140)
        f.target = 1.0 - (L.Flicker or 0.0) * math.random()
    end
    f.level = f.level + (f.target - f.level) * 0.35
    local c = L.Color
    local x, y, z = f.top.x, f.top.y, f.top.z + (L.Height or 0.15)
    if night then
        DrawLightWithRangeAndShadow(x, y, z, c[1], c[2], c[3], L.Night.Range, L.Night.Intensity * f.level, L.Shadows or 0.0)
        if (L.Night.GlowRange or 0) > 0 then
            DrawLightWithRange(x, y, z, c[1], c[2], c[3], L.Night.GlowRange, L.Night.GlowIntensity * f.level)
        end
    else
        DrawLightWithRange(x, y, z, c[1], c[2], c[3], L.Day.Range, L.Day.Intensity * f.level)
    end
end

local function loop()
    if running then return end
    running = true
    CreateThread(function()
        local nextCheck, visible, night = 0, {}, false
        while next(flares) do
            local now = GetGameTimer()
            if now >= nextCheck then
                nextCheck = now + 1000
                local pos = GetEntityCoords(PlayerPedId())
                visible, night = {}, isNight()
                for bag, f in pairs(flares) do
                    local entity = GetEntityFromStateBagName(bag)
                    if entity and entity ~= 0 and DoesEntityExist(entity) then
                        f.lost = nil
                        local d = #(f.top - pos)
                        if d <= L.Distance then visible[#visible + 1] = f end
                        if d <= (E.Distance or 120.0) then
                            if not f.fx then startFx(f) end
                        else
                            stopFx(f)
                        end
                    else
                        -- Retirée ou hors de portée réseau : éteinte ; oubliée après 10 s (reprise par son état à son retour)
                        stopFx(f)
                        f.lost = f.lost or now
                        if now - f.lost > 10000 then flares[bag] = nil end
                    end
                end
            end
            if #visible > 0 then
                for _, f in ipairs(visible) do drawLight(f, night, now) end
                Wait(0)
            else
                Wait(math.max(0, nextCheck - now))
            end
        end
        running = false
    end)
end

AddStateBagChangeHandler('rpFlare', nil, function(bagName, _, value)
    local old = flares[bagName]
    if old then stopFx(old) end
    if type(value) == 'table' and type(value.top) == 'table' then
        flares[bagName] = {
            top = vector3(value.top.x + 0.0, value.top.y + 0.0, value.top.z + 0.0),
            level = 1.0, target = 1.0, nextFlicker = 0,
        }
        loop()
    else
        flares[bagName] = nil
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, f in pairs(flares) do stopFx(f) end
end)
