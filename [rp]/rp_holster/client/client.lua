--[[
    RP Holster - client
    -------------------
    Toutes les CheckMs ms : si le joueur porte un holster de la liste (modèle plein ou vide, sur sa partie de tenue),
    le modèle voulu est posé :
      - arme de poing EN MAIN -> holster VIDE ;
      - arme de poing dans l'inventaire, pas en main -> holster PLEIN ;
      - aucune arme de poing -> VIDE (EmptyWhenNoWeapon).
    La texture portée est gardée ; la tenue est synchronisée par le jeu (vue par tous).
    Performance : une lecture de la tenue toutes les 250 ms ; inventaire lu seulement quand un holster est porté.
]]

local C = HolsterConfig or {}
if C.Enabled == false then return end

local function u32(h) return (math.tointeger(tonumber(h) or 0) or 0) & 0xFFFFFFFF end
local MALE, FEMALE = u32(GetHashKey('mp_m_freemode_01')), u32(GetHashKey('mp_f_freemode_01'))
local offset = C.OneBased == false and 0 or 1

local HOLSTERS = {}
for _, h in ipairs(C.Holsters or {}) do
    if tonumber(h.full) and tonumber(h.empty) then
        HOLSTERS[#HOLSTERS + 1] = { gender = h.gender, component = h.component or C.Component or 7,
            full = math.floor(h.full) - offset, empty = math.floor(h.empty) - offset }
    end
end

local GROUPS, WEAPONS, EXCLUDED = {}, {}, {}
for _, g in ipairs(C.Groups or { 'GROUP_PISTOL' }) do GROUPS[u32(GetHashKey(g))] = true end
for _, n in ipairs(C.Weapons or {}) do WEAPONS[u32(GetHashKey(n))] = true end
for _, n in ipairs(C.Excluded or {}) do EXCLUDED[u32(GetHashKey(n))] = true end
local INVENTORY = {}
for _, n in ipairs(C.Inventory or {}) do INVENTORY[#INVENTORY + 1] = GetHashKey(n) end
for _, n in ipairs(C.Weapons or {}) do INVENTORY[#INVENTORY + 1] = GetHashKey(n) end

--- Arme qui se range dans le holster ?
local function holsterWeapon(hash)
    local h = u32(hash)
    if h == 0 or EXCLUDED[h] then return false end
    return WEAPONS[h] == true or GROUPS[u32(GetWeapontypeGroup(hash))] == true
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

local function update()
    local ped = PlayerPedId()
    local h, current = wornHolster(ped)
    if not h then return end
    local inHand = holsterWeapon(GetSelectedPedWeapon(ped))
    local wanted
    if inHand then wanted = h.empty
    elseif hasHolsterWeapon(ped) then wanted = h.full
    else wanted = C.EmptyWhenNoWeapon == false and current or h.empty end
    if wanted ~= current then
        SetPedComponentVariation(ped, h.component, wanted, GetPedTextureVariation(ped, h.component), 0)
    end
end

CreateThread(function()
    while true do
        update()
        Wait(C.CheckMs or 250)
    end
end)

RPHolster = { update = update, wornHolster = wornHolster, holsterWeapon = holsterWeapon } -- tests
