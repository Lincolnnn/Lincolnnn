--[[
    RP Holster - client (rework, gestes et sons inspirés de « EUP Gun Holster Animation » de ChapterDonut)
    -------------------------------------------------------------------------------------------------------
    Un état « arme rangée / sortie » suivi en continu, pour les SEULES armes de la liste (Weapons, Groups) :
      SORTIE   (arme de la liste prise en main) : geste de la main au holster (Animation.Draw), le holster passe VIDE
               au milieu du geste (swapAt), son « unholster.ogg » ;
      RANGEMENT (arme de la liste rangée, toujours dans l'inventaire) : geste de retour (Animation.Holster), le holster
               passe PLEIN à la fin du geste (swapAt), son « holster.ogg ».
    Pendant le geste : ni tir, ni visée, ni roue des armes (Animation.BlockControls), comme un vrai dégainage.
    Sons entendus par les joueurs proches (relayés par le serveur, plus faibles avec la distance), holster porté ou
    non (Sound.RequireHolster) ; geste avec un holster de la liste porté (Animation.RequireHolster), à pied.
    Hors geste, le holster suit l'inventaire : arme de la liste en main -> VIDE ; rangée -> PLEIN ; aucune -> VIDE
    (EmptyWhenNoWeapon). Une arme hors liste ne touche jamais au holster. La texture portée est gardée.
    Performance : vérification toutes les CheckMs (250 ms) sans arme de la liste sur soi, ArmedCheckMs (100 ms) avec ;
    boucle par image seulement pendant un geste (~0,6 s).
]]

local C = HolsterConfig or {}
if C.Enabled == false then return end

local function u32(h) return (math.tointeger(tonumber(h) or 0) or 0) & 0xFFFFFFFF end
local MALE, FEMALE = u32(GetHashKey('mp_m_freemode_01')), u32(GetHashKey('mp_f_freemode_01'))
local offset = C.OneBased == false and 0 or 1
local A, SND = C.Animation or {}, C.Sound or {}

-- Gestes par défaut (ChapterDonut) si la configuration n'en donne pas
local DEFAULT_DRAW = { dict = 'reaction@intimidation@cop@unarmed', clip = 'intro', ms = 600, swapAt = 120 }
local DEFAULT_HOLSTER = { dict = 'reaction@intimidation@cop@unarmed', clip = 'outro', ms = 600, swapAt = 450 }
local DRAW = type(A.Draw) == 'table' and A.Draw.dict and A.Draw or DEFAULT_DRAW
local HOLSTER = type(A.Holster) == 'table' and A.Holster.dict and A.Holster or DEFAULT_HOLSTER

local HOLSTERS = {}
for _, h in ipairs(C.Holsters or {}) do
    if tonumber(h.full) and tonumber(h.empty) then
        HOLSTERS[#HOLSTERS + 1] = { gender = h.gender, component = h.component or C.Component or 7,
            full = math.floor(h.full) - offset, empty = math.floor(h.empty) - offset }
    end
end

local GROUPS, WEAPONS, EXCLUDED = {}, {}, {}
for _, g in ipairs(C.Groups or {}) do GROUPS[u32(GetHashKey(g))] = true end
for _, n in ipairs(C.Weapons or {}) do WEAPONS[u32(GetHashKey(n))] = true end
for _, n in ipairs(C.Excluded or {}) do EXCLUDED[u32(GetHashKey(n))] = true end
-- ni Weapons ni Groups : toutes les armes de poing (ancien comportement)
if next(WEAPONS) == nil and next(GROUPS) == nil then GROUPS[u32(GetHashKey('GROUP_PISTOL'))] = true end
local INVENTORY = {}
for _, n in ipairs(C.Inventory or {}) do INVENTORY[#INVENTORY + 1] = GetHashKey(n) end
for _, n in ipairs(C.Weapons or {}) do INVENTORY[#INVENTORY + 1] = GetHashKey(n) end

--- Arme qui se range dans le holster ? (seulement celles de la configuration)
local function holsterWeapon(hash)
    local h = u32(hash)
    if h == 0 or EXCLUDED[h] then return false end
    return WEAPONS[h] == true or (next(GROUPS) ~= nil and GROUPS[u32(GetWeapontypeGroup(hash))] == true)
end

local function hasHolsterWeapon(ped)
    for _, hash in ipairs(INVENTORY) do
        if holsterWeapon(hash) and HasPedGotWeapon(ped, hash, false) then return true end
    end
    return false
end

local function genderOf(ped)
    local model = u32(GetEntityModel(ped))
    return model == MALE and 'male' or (model == FEMALE and 'female' or nil)
end

--- Holster porté (ligne de la liste) et modèle actuel, ou nil
local function wornHolster(ped)
    local gender = genderOf(ped)
    if not gender then return nil end
    for _, h in ipairs(HOLSTERS) do
        if h.gender == nil or h.gender == gender then
            local d = GetPedDrawableVariation(ped, h.component)
            if d == h.full or d == h.empty then return h, d end
        end
    end
    return nil
end

local function setDrawable(ped, h, d)
    if GetPedDrawableVariation(ped, h.component) ~= d then
        SetPedComponentVariation(ped, h.component, d, GetPedTextureVariation(ped, h.component), 0)
    end
end

-- =========================================================================
-- SONS (soi + joueurs proches)
-- =========================================================================
local SOUND_FILES = { draw = SND.DrawFile or 'unholster.ogg', holster = SND.File or 'holster.ogg' }

local function playSound(kind, volume)
    SendNUIMessage({ action = 'play', data = { file = SOUND_FILES[kind] or SOUND_FILES.holster, volume = volume } })
end

local function holsterSound(kind)
    if SND.Enabled == false then return end
    playSound(kind, SND.Volume or 0.5)             -- soi : tout de suite
    TriggerServerEvent('rp_holster:sound', kind)   -- les joueurs proches (serveur)
end

-- Son d'un autre joueur : volume selon la distance
RegisterNetEvent('rp_holster:play', function(coords, kind)
    if SND.Enabled == false or type(coords) ~= 'table' or not tonumber(coords.x) then return end
    local range = SND.Range or 8.0
    local d = #(GetEntityCoords(PlayerPedId()) - vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0))
    if d > range then return end
    playSound(kind == 'draw' and 'draw' or 'holster', (SND.Volume or 0.5) * (1.0 - d / range))
end)

-- =========================================================================
-- GESTE (animation du haut du corps + commandes bloquées pendant le geste)
-- =========================================================================
local gesture = 0        -- n° du geste en cours (0 : aucun) ; un nouveau geste annule le précédent
local gestureUntil = 0   -- fin du geste (GetGameTimer)

local function blockControls()
    if A.BlockControls == false then return end
    CreateThread(function()
        while GetGameTimer() < gestureUntil do
            DisableControlAction(0, 24, true)  -- tir
            DisableControlAction(0, 25, true)  -- visée
            DisableControlAction(0, 37, true)  -- roue des armes
            DisableControlAction(0, 140, true) -- coups (corps à corps)
            DisablePlayerFiring(PlayerId(), true)
            Wait(0)
        end
    end)
end

local function canAnimate(ped)
    return A.Enabled ~= false and not IsPedInAnyVehicle(ped, false) and not IsPedRagdoll(ped)
        and not IsEntityDead(ped) and not IsPedSwimming(ped) and not IsPedFalling(ped)
end

--- Joue le geste `anim` ; `swap()` est appelé à anim.swapAt ms (changement du modèle de holster)
local function startGesture(ped, anim, animate, swap)
    gesture = gesture + 1
    local id = gesture
    local ms = math.floor(tonumber(anim.ms) or 600)
    local swapAt = math.floor(tonumber(anim.swapAt) or ms * 0.6)
    if animate then
        gestureUntil = GetGameTimer() + ms
        blockControls()
        CreateThread(function()
            RequestAnimDict(anim.dict)
            local deadline = GetGameTimer() + 1000
            while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < deadline do Wait(0) end
            if id ~= gesture or not HasAnimDictLoaded(anim.dict) then return end
            TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, ms, 48, 0.0, false, false, false) -- haut du corps : on marche
            RemoveAnimDict(anim.dict)
        end)
    else
        swapAt = 0
    end
    SetTimeout(swapAt, function() if id == gesture then swap() end end)
end

-- =========================================================================
-- BOUCLE
-- =========================================================================
local drawn = nil  -- arme de la liste sortie ? (nil : premier tour, pas de geste à la connexion)
local armed = false -- une arme de la liste sur soi : vérification plus rapide (geste au bon moment)

local function update()
    local ped = PlayerPedId()
    local inHand = holsterWeapon(GetSelectedPedWeapon(ped))
    local owned = inHand or hasHolsterWeapon(ped)
    armed = owned
    local h, current = wornHolster(ped)
    local before = drawn
    drawn = inHand

    if before ~= nil and inHand ~= before and not IsEntityDead(ped) then
        local holstering = not inHand
        if holstering and not owned then
            -- arme de la liste perdue (lâchée, retirée) : ni geste ni son, le holster suit l'inventaire plus bas
        else
            if h or SND.RequireHolster ~= true then holsterSound(holstering and 'holster' or 'draw') end
            local animate = canAnimate(ped) and (h ~= nil or A.RequireHolster == false)
            startGesture(ped, holstering and HOLSTER or DRAW, animate, function()
                local p = PlayerPedId()
                local hh = wornHolster(p)
                if not hh then return end
                local nowInHand = holsterWeapon(GetSelectedPedWeapon(p))
                if holstering and not nowInHand and hasHolsterWeapon(p) then setDrawable(p, hh, hh.full)
                elseif not holstering and nowInHand then setDrawable(p, hh, hh.empty) end
            end)
            return
        end
    end

    -- hors geste : le holster suit l'inventaire
    if not h or GetGameTimer() < gestureUntil then return end
    local wanted
    if inHand then wanted = h.empty
    elseif owned then wanted = h.full
    else wanted = C.EmptyWhenNoWeapon == false and current or h.empty end
    if wanted ~= current then setDrawable(ped, h, wanted) end
end

CreateThread(function()
    while true do
        update()
        Wait(armed and (C.ArmedCheckMs or 100) or (C.CheckMs or 250))
    end
end)

RPHolster = { update = update, wornHolster = wornHolster, holsterWeapon = holsterWeapon } -- tests
