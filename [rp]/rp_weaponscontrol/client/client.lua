--[[
    RP Weapons Control - client
    ---------------------------
    TIREUR (arme à feu en main) : à chaque tir, recul de la caméra (type d'arme : Profiles), petite secousse, flash
    jaune au canon ; tirs rapides (Smoke.Shots dans Smoke.Window ms) : filet de fumée au bout du canon. Les tirs sont
    envoyés au serveur par paquets (Sync.Batch ms), qui les relaie aux joueurs proches (Sync.Range).
    JOUEURS AUTOUR : flash au canon du tireur, fumée, secousse s'ils sont proches (Shake.Range), acouphène s'ils sont
    tout près (Tinnitus.Range) : sifflement (html/) qui monte avec les tirs et redescend tout seul.
    Silencieux : ni flash, ni acouphène. Le tireur entend aussi un peu ses propres tirs (Tinnitus.Self).
    Performance : sans arme à feu en main, une vérification toutes les 250 ms ; arme en main : lecture du tir à chaque
    image (comme le jeu) ; effets seulement quand quelqu'un tire.
]]

local W = WeaponsConfig

local PROFILES = {}
for group, p in pairs(W.Profiles or {}) do PROFILES[GetHashKey(group)] = { key = group, p = p } end
local EXCLUDED = {}
for _, name in ipairs(W.Excluded or {}) do EXCLUDED[GetHashKey(name)] = true end

RPWeapons = {} -- pour les tests

--- Profil de l'arme (nil : pas une arme à feu concernée)
local function profileOf(weapon)
    if not weapon or weapon == 0 or EXCLUDED[weapon] then return nil end
    return PROFILES[GetWeapontypeGroup(weapon)]
end
RPWeapons.profileOf = profileOf

local function profileByKey(key) return (W.Profiles or {})[key] end

-- =========================================================================
-- EFFETS : flash, fumée, secousse, acouphène
-- =========================================================================
--- Position du bout du canon de l'arme tenue par ce personnage (sinon sa main droite)
local function muzzleOf(ped)
    local weapon = GetCurrentPedWeaponEntityIndex(ped)
    if weapon and weapon ~= 0 and DoesEntityExist(weapon) then
        local bone = GetEntityBoneIndexByName(weapon, 'gun_muzzle')
        if bone ~= -1 then return GetWorldPositionOfEntityBone(weapon, bone), weapon, bone end
        return GetEntityCoords(weapon), weapon, nil
    end
    return GetPedBoneCoords(ped, 57005, 0.0, 0.0, 0.0), nil, nil
end

--- Éclair jaune autour du canon (quelques images)
local function flash(ped)
    local F = W.Flash or {}
    if F.Enabled == false then return end
    CreateThread(function()
        local untilTime = GetGameTimer() + (F.Duration or 60)
        local c = F.Color or { 255, 186, 92 }
        repeat
            if not DoesEntityExist(ped) then return end
            local p = muzzleOf(ped)
            DrawLightWithRange(p.x, p.y, p.z, c[1], c[2], c[3], (F.Radius or 7.0) + 0.0, (F.Intensity or 7.0) + 0.0)
            Wait(0)
        until GetGameTimer() >= untilTime
    end)
end
RPWeapons.flash = flash

local smoking = {} -- [ped] = fin de la fumée en cours
--- Filet de fumée au bout du canon pendant Smoke.Duration ms
local function smoke(ped)
    local S = W.Smoke or {}
    if S.Enabled == false then return end
    local now = GetGameTimer()
    if smoking[ped] and smoking[ped] > now then smoking[ped] = now + (S.Duration or 6000) return end
    smoking[ped] = now + (S.Duration or 6000)
    CreateThread(function()
        local _, weapon, bone = muzzleOf(ped)
        if not weapon then smoking[ped] = nil return end
        RequestNamedPtfxAsset(S.Asset or 'core')
        local timeout = GetGameTimer() + 1500
        while not HasNamedPtfxAssetLoaded(S.Asset or 'core') and GetGameTimer() < timeout do Wait(0) end
        UseParticleFxAssetNextCall(S.Asset or 'core')
        local fx
        if bone then
            fx = StartParticleFxLoopedOnEntityBone(S.Name or 'ent_anim_cig_smoke', weapon, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, bone, (S.Scale or 1.6) + 0.0, false, false, false)
        else
            fx = StartParticleFxLoopedOnEntity(S.Name or 'ent_anim_cig_smoke', weapon, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, (S.Scale or 1.6) + 0.0, false, false, false)
        end
        while smoking[ped] and GetGameTimer() < smoking[ped] and DoesEntityExist(weapon) do Wait(250) end
        if fx then StopParticleFxLooped(fx, false) end
        smoking[ped] = nil
    end)
end
RPWeapons.smoke = smoke

--- Acouphène : intensité 0-1 (le NUI garde la plus forte et redescend tout seul)
local function tinnitus(amount)
    local T = W.Tinnitus or {}
    if T.Enabled == false or amount <= 0.02 then return end
    amount = math.min(1.0, amount)
    local duration = (T.MinDuration or 2500) + ((T.MaxDuration or 9000) - (T.MinDuration or 2500)) * amount
    SendNUIMessage({ action = 'tinnitus', data = { amount = amount, volume = T.Volume or 0.16, duration = math.floor(duration) } })
end
RPWeapons.tinnitus = tinnitus

-- =========================================================================
-- TIREUR : recul, effets, tirs rapides, envoi par paquets
-- =========================================================================
local pending = nil -- { count, key, suppressed, smoke, since }
local recent = {}   -- heures des derniers tirs (tirs rapides -> fumée)
local lastSmoke = -math.huge

local function recoil(ped, p)
    local R = W.Recoil or {}
    if R.Enabled == false then return end
    local mult = R.Speed or 1.0
    if GetFollowPedCamViewMode() == 4 then mult = mult * (R.FirstPerson or 1.15) end
    if IsPedInAnyVehicle(ped, false) then mult = mult * (R.Vehicle or 1.4) end
    local up = (p.recoil or 0.6) * mult
    local side = ((math.random() * 2) - 1) * (p.side or 0.25) * mult
    SetGameplayCamRelativePitch(GetGameplayCamRelativePitch() + up, 1.0)
    SetGameplayCamRelativeHeading(GetGameplayCamRelativeHeading() + side)
end

local function flush(force)
    if not pending then return end
    if not force and GetGameTimer() - pending.since < ((W.Sync or {}).Batch or 100) then return end
    TriggerServerEvent('rp_weaponscontrol:shots', { count = pending.count, key = pending.key,
        suppressed = pending.suppressed, smoke = pending.smoke })
    pending = nil
end

local function onShot(ped, weapon, entry)
    local p = entry.p
    local suppressed = IsPedCurrentWeaponSilenced(ped)
    recoil(ped, p)
    if p.shake and p.shake > 0 then ShakeGameplayCam((W.Shake or {}).Name or 'SMALL_EXPLOSION_SHAKE', p.shake * (suppressed and 0.5 or 1.0)) end
    if not suppressed then
        flash(ped)
        tinnitus((p.loudness or 0.8) * ((W.Tinnitus or {}).Self or 0.3) * 0.5)
    end
    -- tirs rapides : fumée au canon
    local now = GetGameTimer()
    local S = W.Smoke or {}
    recent[#recent + 1] = now
    while recent[1] and now - recent[1] > (S.Window or 3000) do table.remove(recent, 1) end
    local smokeNow = false
    if S.Enabled ~= false and #recent >= (S.Shots or 7) and now - lastSmoke > (S.Cooldown or 4000) then
        smokeNow, lastSmoke = true, now
        recent = {}
        smoke(ped)
    end
    pending = pending or { count = 0, key = entry.key, suppressed = suppressed, smoke = false, since = now }
    pending.count = pending.count + 1
    pending.smoke = pending.smoke or smokeNow
end
RPWeapons.onShot = onShot
RPWeapons.flush = flush

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local entry = nil
        if IsPedArmed(ped, 4) then
            local _, weapon = GetCurrentPedWeapon(ped, true)
            entry = profileOf(weapon)
            if entry then
                if IsPedShooting(ped) then onShot(ped, weapon, entry) end
                flush(false)
            end
        end
        if not entry then
            flush(true)
            recent = {}
        end
        Wait(entry and 0 or 250)
    end
end)

-- =========================================================================
-- TIRS DES AUTRES JOUEURS (relayés par le serveur, seulement ceux à portée)
-- =========================================================================
RegisterNetEvent('rp_weaponscontrol:shots', function(src, count, key, suppressed, withSmoke)
    local player = GetPlayerFromServerId(src)
    if player == -1 then return end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 or not DoesEntityExist(ped) or ped == PlayerPedId() then return end
    local p = profileByKey(key) or {}
    count = math.max(1, math.min(30, tonumber(count) or 1))
    local d = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped))
    local F = W.Flash or {}
    if not suppressed and d <= (F.Range or 90.0) then
        CreateThread(function()
            for i = 1, count do
                flash(ped)
                if i < count then Wait(math.floor(((W.Sync or {}).Batch or 100) / count)) end
            end
        end)
    end
    if withSmoke and d <= ((W.Smoke or {}).Range or 60.0) then smoke(ped) end
    local Sh = W.Shake or {}
    if Sh.Enabled ~= false and d <= (Sh.Range or 15.0) then
        local amount = (Sh.Amount or 0.12) * (p.loudness or 0.8) * (1.0 - d / (Sh.Range or 15.0)) * (suppressed and 0.4 or 1.0)
        if amount > 0.01 then ShakeGameplayCam(Sh.Name or 'SMALL_EXPLOSION_SHAKE', amount) end
    end
    local T = W.Tinnitus or {}
    if not suppressed and d <= (T.Range or 10.0) then
        tinnitus((p.loudness or 0.8) * (1.0 - d / (T.Range or 10.0)) * math.min(2.0, math.sqrt(count)))
    end
end)
