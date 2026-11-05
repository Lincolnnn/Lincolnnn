--[[
    RP Holster - client
    -------------------
    Toutes les CheckMs ms : si le joueur porte un holster de la liste (modèle plein ou vide, sur sa partie de tenue),
    le modèle voulu est posé :
      - arme de la liste (Weapons) EN MAIN -> holster VIDE ;
      - arme de la liste dans l'inventaire, pas en main -> holster PLEIN ;
      - aucune arme de la liste -> VIDE (EmptyWhenNoWeapon).
    SEULES les armes de Weapons (et des groupes de Groups, s'il y en a) comptent : sortir une autre arme ne vide pas
    le holster. En sortant / rangeant une arme de la liste : animation (main au holster, à pied) et son « holster.ogg »
    entendu par les joueurs proches (relayé par le serveur).
    La texture portée est gardée ; la tenue est synchronisée par le jeu (vue par tous).
    Performance : une lecture de la tenue toutes les 250 ms ; inventaire lu seulement quand un holster est porté.
]]

local C = HolsterConfig or {}
if C.Enabled == false then return end

local function u32(h) return (math.tointeger(tonumber(h) or 0) or 0) & 0xFFFFFFFF end
local MALE, FEMALE = u32(GetHashKey('mp_m_freemode_01')), u32(GetHashKey('mp_f_freemode_01'))
local offset = C.OneBased == false and 0 or 1
local A, SND = C.Animation or {}, C.Sound or {}

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

--- Holster porté (ligne de la liste) ou nil
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

-- =========================================================================
-- ANIMATION ET SON
-- =========================================================================
local function playAnim(ped, anim)
    if A.Enabled == false or type(anim) ~= 'table' or not anim.dict then return end
    if IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) or IsEntityDead(ped) or IsPedSwimming(ped) then return end
    CreateThread(function()
        RequestAnimDict(anim.dict)
        local deadline = GetGameTimer() + 1000
        while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < deadline do Wait(0) end
        if not HasAnimDictLoaded(anim.dict) then return end
        TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, anim.ms or 500, 48, 0.0, false, false, false)
        RemoveAnimDict(anim.dict)
    end)
end

local function playSound(volume)
    SendNUIMessage({ action = 'play', data = { file = SND.File or 'holster.ogg', volume = volume } })
end

local function holsterSound()
    if SND.Enabled == false then return end
    playSound(SND.Volume or 0.5)                 -- soi : tout de suite
    TriggerServerEvent('rp_holster:sound')       -- les joueurs proches (serveur)
end

-- Son d'un autre joueur : volume selon la distance
RegisterNetEvent('rp_holster:play', function(coords)
    if SND.Enabled == false or type(coords) ~= 'table' or not tonumber(coords.x) then return end
    local range = SND.Range or 8.0
    local d = #(GetEntityCoords(PlayerPedId()) - vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0))
    if d > range then return end
    playSound((SND.Volume or 0.5) * (1.0 - d / range))
end)

-- =========================================================================
-- BOUCLE
-- =========================================================================
local lastInHand = nil   -- arme de la liste en main au tour précédent (nil : premier tour, pas d'animation)
local holdUntil = 0      -- rangement en cours : holster rempli à la fin du geste

local function setDrawable(ped, h, d)
    SetPedComponentVariation(ped, h.component, d, GetPedTextureVariation(ped, h.component), 0)
end

local function update()
    local ped = PlayerPedId()
    local inHand = holsterWeapon(GetSelectedPedWeapon(ped))
    local h, current = wornHolster(ped)
    local before = lastInHand
    lastInHand = inHand
    if not h then return end
    local now = GetGameTimer()

    if before ~= nil and inHand and not before then
        -- sortie de l'arme : main au holster, son, holster vide
        holdUntil = 0
        playAnim(ped, A.Draw)
        holsterSound()
    elseif before and not inHand and hasHolsterWeapon(ped) then
        -- rangement : main au holster, son ; le holster se remplit à la fin du geste
        playAnim(ped, A.Holster)
        holsterSound()
        holdUntil = now + math.floor(((A.Holster or {}).ms or 500) * 0.6)
        SetTimeout(math.max(0, holdUntil - now), function()
            local p = PlayerPedId()
            local hh, cur = wornHolster(p)
            if hh and not holsterWeapon(GetSelectedPedWeapon(p)) and hasHolsterWeapon(p) and cur ~= hh.full then setDrawable(p, hh, hh.full) end
        end)
    end
    if now < holdUntil then return end

    local wanted
    if inHand then wanted = h.empty
    elseif hasHolsterWeapon(ped) then wanted = h.full
    else wanted = C.EmptyWhenNoWeapon == false and current or h.empty end
    if wanted ~= current then setDrawable(ped, h, wanted) end
end

CreateThread(function()
    while true do
        update()
        Wait(C.CheckMs or 250)
    end
end)

RPHolster = { update = update, wornHolster = wornHolster, holsterWeapon = holsterWeapon } -- tests
