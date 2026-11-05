--[[
    RP Interact - Arme tenue : capture et restitution, pour les autres ressources
    -----------------------------------------------------------------------------
    exports.rp_interact:captureWeapon() -> arme en main, telle quelle, ou nil :
        { hash, label, ammo, tint, components = { 'COMPONENT_…' }, componentTints = { [nom] = teinte }, light, torch }
        Accessoires : ceux de l'arme dans equipment_services.json (GlobalState.rpiWeaponComponents, armes addon
        comprises) et les accessoires connus du jeu ; light : sa lampe est allumée (lampe de l'arme, ou lampe de
        CartoonFlashlight) ; torch : c'est une lampe de poche.
    exports.rp_interact:giveWeapon(data, equip) : la rend à l'identique (munitions, teinte, accessoires) et rallume sa
        lampe si elle l'était (rp_weaponscontrol : lampe toujours allumée).
    Utilisé par rp_vehicleprops (arme posée sur un véhicule). Aucune boucle.
]]

local GENERIC = {
    'COMPONENT_AT_PI_FLSH', 'COMPONENT_AT_PI_FLSH_02', 'COMPONENT_AT_PI_FLSH_03', 'COMPONENT_AT_PI_SUPP',
    'COMPONENT_AT_PI_SUPP_02', 'COMPONENT_AT_PI_RAIL', 'COMPONENT_AT_PI_RAIL_02', 'COMPONENT_AT_PI_COMP',
    'COMPONENT_AT_PI_COMP_02', 'COMPONENT_AT_PI_COMP_03',
    'COMPONENT_AT_AR_FLSH', 'COMPONENT_AT_AR_FLSH_REH', 'COMPONENT_AT_AR_AFGRIP', 'COMPONENT_AT_AR_AFGRIP_02',
    'COMPONENT_AT_AR_SUPP', 'COMPONENT_AT_AR_SUPP_02', 'COMPONENT_AT_SR_SUPP', 'COMPONENT_AT_SR_SUPP_03',
    'COMPONENT_AT_SCOPE_MACRO', 'COMPONENT_AT_SCOPE_MACRO_02', 'COMPONENT_AT_SCOPE_SMALL', 'COMPONENT_AT_SCOPE_MEDIUM',
    'COMPONENT_AT_SIGHTS', 'COMPONENT_AT_SCOPE_MACRO_MK2', 'COMPONENT_AT_SCOPE_SMALL_MK2', 'COMPONENT_AT_SCOPE_MEDIUM_MK2',
}
for i = 1, 8 do GENERIC[#GENERIC + 1] = ('COMPONENT_AT_MUZZLE_%02d'):format(i) end

local FLASHLIGHTS = {}
for _, name in ipairs({ 'WEAPON_FLASHLIGHT', 'WEAPON_POCKETLIGHT' }) do FLASHLIGHTS[GetHashKey(name) & 0xFFFFFFFF] = true end

local GROUP_LABELS = {
    GROUP_PISTOL = 'Arme de poing', GROUP_SMG = 'Pistolet-mitrailleur', GROUP_RIFLE = 'Fusil', GROUP_MG = 'Mitrailleuse',
    GROUP_SHOTGUN = 'Fusil à pompe', GROUP_SNIPER = 'Fusil de précision', GROUP_STUNGUN = 'Taser', GROUP_MELEE = 'Objet',
    GROUP_NIGHTSTICK = 'Matraque', GROUP_HEAVY = 'Arme lourde',
}
local GROUP_OF = {}
for name, label in pairs(GROUP_LABELS) do GROUP_OF[GetHashKey(name) & 0xFFFFFFFF] = label end

--- Arme de equipment_services.json (GlobalState publié par le serveur) : { label, components } ou nil
local function interactWeapon(hash)
    local list = GlobalState.rpiWeaponComponents
    if type(list) ~= 'table' then return nil end
    for name, w in pairs(list) do
        if type(name) == 'string' and (GetHashKey(name) & 0xFFFFFFFF) == hash and type(w) == 'table' then return w end
    end
    return nil
end

local function isTorch(hash) return FLASHLIGHTS[hash & 0xFFFFFFFF] == true end

--- Lampe allumée : lampe de CartoonFlashlight (son état publié) ou lampe du jeu
local function lightOn(ped, hash)
    local cartoon = LocalPlayer.state.cartoonFlashlight
    if type(cartoon) == 'table' and (tonumber(cartoon.weapon) or 0) & 0xFFFFFFFF == hash & 0xFFFFFFFF then
        return cartoon.light == true
    end
    return IsFlashLightOn(ped)
end

local function captureWeapon()
    local ped = PlayerPedId()
    local hash = GetSelectedPedWeapon(ped)
    if not hash or hash == 0 or hash == GetHashKey('WEAPON_UNARMED') then return nil end
    local addon = interactWeapon(hash & 0xFFFFFFFF)
    local components, tints, seen = {}, {}, {}
    local function test(name, known)
        if type(name) ~= 'string' or seen[name] then return end
        seen[name] = true
        local c = GetHashKey(name)
        -- accessoire d'une arme addon : le jeu ne le connaît pas toujours pour DoesWeaponTakeWeaponComponent
        if (known or DoesWeaponTakeWeaponComponent(hash, c)) and HasPedGotWeaponComponent(ped, hash, c) then
            components[#components + 1] = name
            local ok, tint = pcall(GetPedWeaponComponentTintIndex, ped, hash, c)
            if ok and type(tint) == 'number' and tint >= 0 then tints[name] = tint end
        end
    end
    for _, name in ipairs(addon and addon.components or {}) do test(name, true) end
    for _, name in ipairs(GENERIC) do test(name, false) end
    local label = addon and addon.label
    if not label then
        label = isTorch(hash) and 'Lampe torche' or GROUP_OF[GetWeapontypeGroup(hash) & 0xFFFFFFFF] or 'Arme'
    end
    return {
        hash = hash & 0xFFFFFFFF, label = label, ammo = GetAmmoInPedWeapon(ped, hash), tint = GetPedWeaponTintIndex(ped, hash),
        components = components, componentTints = tints, light = lightOn(ped, hash), torch = isTorch(hash),
    }
end
exports('captureWeapon', captureWeapon)
RPI.captureWeapon = captureWeapon

local function giveWeapon(data, equip)
    if type(data) ~= 'table' or not tonumber(data.hash) then return false end
    local ped = PlayerPedId()
    local hash = math.tointeger(tonumber(data.hash)) or 0
    if hash > 0x7FFFFFFF then hash = hash - 0x100000000 end -- empreinte signée pour les natives
    local ammo = math.max(0, math.floor(tonumber(data.ammo) or 0))
    if HasPedGotWeapon(ped, hash, false) then AddAmmoToPed(ped, hash, ammo)
    else GiveWeaponToPed(ped, hash, ammo, false, equip ~= false) end
    for _, name in ipairs(type(data.components) == 'table' and data.components or {}) do
        if type(name) == 'string' then
            local c = GetHashKey(name)
            GiveWeaponComponentToPed(ped, hash, c)
            local tint = type(data.componentTints) == 'table' and tonumber(data.componentTints[name])
            if tint then pcall(SetPedWeaponComponentTintIndex, ped, hash, c, tint) end
        end
    end
    local tint = tonumber(data.tint)
    if tint and tint >= 0 then SetPedWeaponTintIndex(ped, hash, tint) end
    if equip ~= false then SetCurrentPedWeapon(ped, hash, true) end
    -- lampe : rp_weaponscontrol (toujours allumée) la rallume et la garde ; CartoonFlashlight lit cet état
    TriggerEvent('rp_weaponscontrol:flashlight', hash, data.light == true)
    if data.light == true and GetResourceState('rp_weaponscontrol') ~= 'started' then
        SetTimeout(400, function() SetFlashLightEnabled(PlayerPedId(), true) end)
    end
    return true
end
exports('giveWeapon', giveWeapon)
RPI.giveWeapon = giveWeapon
