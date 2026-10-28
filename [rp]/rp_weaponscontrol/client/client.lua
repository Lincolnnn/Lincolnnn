--[[
    RP Weapons Control - client
    ---------------------------
    TIREUR (arme à feu en main) : à chaque tir, RECUL de la caméra (Recoil.Step degré par image jusqu'à la valeur de
    l'arme, Weapons ; à la 3e personne, pas en drive-by), SECOUSSE (Weapons : shake), flash jaune au canon ; tirs
    rapides (Smoke.Shots dans Smoke.Window ms) : filet de fumée au bout du canon. Pas de rechargement automatique.
    Les tirs sont envoyés au serveur par paquets (Sync.Batch ms), qui les relaie aux joueurs proches (Sync.Range).
    JOUEURS AUTOUR : flash au canon du tireur, fumée, petite secousse s'ils sont proches (Shake.Range).
    ACOUPHÈNE (léger) : seulement quand ça tire beaucoup tout près : Tinnitus.Shots tirs en Tinnitus.Window ms par des
    tireurs à moins de Tinnitus.Range m (soi-même, un autre joueur ou un PNJ). Silencieux : ni flash, ni acouphène.
    Performance : sans arme à feu en main, une vérification toutes les 250 ms ; arme en main : lecture du tir à chaque
    image (comme le jeu) ; PNJ armés à moins de 10 m : lecture de leurs tirs à chaque image tant qu'il y en a.
]]

local W = WeaponsConfig

--- Empreinte du jeu sur 32 bits non signés : les natives renvoient tantôt un nombre négatif, tantôt positif pour la
--- même arme ; comparées sous cette forme, elles se retrouvent toujours
local function u32(h) return (math.tointeger(h) or math.floor(tonumber(h) or 0)) & 0xFFFFFFFF end

local PROFILES = {}
for group, p in pairs(W.Profiles or {}) do PROFILES[u32(GetHashKey(group))] = { key = group, p = p } end
local WEAPONS = {}
for name, w in pairs(W.Weapons or {}) do WEAPONS[u32(GetHashKey(name))] = w end
local EXCLUDED = {}
for _, name in ipairs(W.Excluded or {}) do EXCLUDED[u32(GetHashKey(name))] = true end

RPWeapons = { u32 = u32 } -- pour les tests

--- Arme à feu concernée : { key = groupe, p = valeurs du groupe, w = valeurs de l'arme } ; nil sinon
local function profileOf(weapon)
    if not weapon or weapon == 0 then return nil end
    local h = u32(weapon)
    if EXCLUDED[h] then return nil end
    local group = PROFILES[u32(GetWeapontypeGroup(weapon))]
    if not group then return nil end
    return { key = group.key, p = group.p, w = WEAPONS[h] or group.p }
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

-- =========================================================================
-- ACOUPHÈNE : seulement quand ça tire beaucoup tout près (soi, joueurs, PNJ)
-- =========================================================================
local nearShots = {} -- heures des tirs entendus de près (tireur à moins de Tinnitus.Range m)
local lastRing = -math.huge

--- n tirs entendus, tireur à d mètres : l'acouphène part quand il y en a assez dans la fenêtre
local function heard(n, d)
    local T = W.Tinnitus or {}
    if T.Enabled == false or d > (T.Range or 10.0) then return end
    local now = GetGameTimer()
    for _ = 1, math.max(1, n or 1) do nearShots[#nearShots + 1] = now end
    while nearShots[1] and now - nearShots[1] > (T.Window or 10000) do table.remove(nearShots, 1) end
    local need = T.Shots or 10
    if #nearShots < need or now - lastRing < (T.Cooldown or 12000) then return end
    lastRing = now
    local amount = math.min(1.0, 0.5 + (#nearShots - need) / (need * 2)) -- plus il y a de tirs, plus il dure
    local duration = (T.MinDuration or 2500) + ((T.MaxDuration or 6000) - (T.MinDuration or 2500)) * amount
    SendNUIMessage({ action = 'tinnitus', data = { amount = amount, volume = T.Volume or 0.05, duration = math.floor(duration) } })
    nearShots = {}
end
RPWeapons.heard = heard

-- =========================================================================
-- TIREUR : recul, effets, tirs rapides, envoi par paquets
-- =========================================================================
local pending = nil -- { count, key, suppressed, smoke, since }
local recent = {}   -- heures des derniers tirs (tirs rapides -> fumée)
local lastSmoke = -math.huge
local kicking = 0   -- remontée de la caméra restant à faire (degrés)

--- Recul (comme le script de Lyrad / Blumlaut) : la caméra remonte de Step degré par image jusqu'à la valeur de l'arme
local function recoil(ped, w)
    local R = W.Recoil or {}
    if R.Enabled == false or not w.recoil or w.recoil <= 0 then return end
    if not R.DriveBy and IsPedDoingDriveby(ped) then return end
    if not R.FirstPerson and GetFollowPedCamViewMode() == 4 then return end
    local start = kicking <= 0
    kicking = kicking + w.recoil * (R.Multiplier or 1.0)
    if not start then return end
    CreateThread(function()
        local step = R.Step or 0.1
        while kicking > 0 do
            Wait(0)
            SetGameplayCamRelativePitch(GetGameplayCamRelativePitch() + math.min(step, kicking), R.Smooth or 0.2)
            kicking = kicking - step
        end
        kicking = 0
    end)
end
RPWeapons.recoil = recoil

local function flush(force)
    if not pending then return end
    if not force and GetGameTimer() - pending.since < ((W.Sync or {}).Batch or 100) then return end
    TriggerServerEvent('rp_weaponscontrol:shots', { count = pending.count, key = pending.key,
        suppressed = pending.suppressed, smoke = pending.smoke })
    pending = nil
end

local function onShot(ped, weapon, entry)
    local suppressed = IsPedCurrentWeaponSilenced(ped)
    recoil(ped, entry.w)
    local shake = entry.w.shake or entry.p.shake
    if shake and shake > 0 then ShakeGameplayCam((W.Shake or {}).Name or 'SMALL_EXPLOSION_SHAKE', shake * (suppressed and 0.5 or 1.0)) end
    if not suppressed then
        flash(ped)
        heard(1, 0.0)
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
    if W.NoAutoReload ~= false then SetWeaponsNoAutoreload(true) end -- chargeur vide : recharger soi-même (R)
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

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and W.NoAutoReload ~= false then SetWeaponsNoAutoreload(false) end
end)

-- =========================================================================
-- PNJ ARMÉS TOUT PRÈS (acouphène) : liste toutes les 250 ms, leurs tirs lus à chaque image tant qu'il y en a
-- =========================================================================
CreateThread(function()
    local T = W.Tinnitus or {}
    if T.Enabled == false or T.Npc == false then return end
    while true do
        local me = PlayerPedId()
        local origin = GetEntityCoords(me)
        local near = {}
        for _, ped in ipairs(GetGamePool('CPed')) do
            if ped ~= me and not IsPedAPlayer(ped) and not IsEntityDead(ped) and IsPedArmed(ped, 4)
                and #(GetEntityCoords(ped) - origin) <= (T.Range or 10.0) then
                near[#near + 1] = ped
            end
        end
        if #near == 0 then
            Wait(250)
        else
            local untilTime = GetGameTimer() + 250
            repeat
                for _, ped in ipairs(near) do
                    if DoesEntityExist(ped) and IsPedShooting(ped) and not IsPedCurrentWeaponSilenced(ped) then
                        heard(1, #(GetEntityCoords(ped) - GetEntityCoords(PlayerPedId())))
                    end
                end
                Wait(0)
            until GetGameTimer() >= untilTime
        end
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
        local amount = (Sh.Amount or 0.08) * (p.loudness or 0.8) * (1.0 - d / (Sh.Range or 15.0)) * (suppressed and 0.4 or 1.0)
        if amount > 0.01 then ShakeGameplayCam(Sh.Name or 'SMALL_EXPLOSION_SHAKE', amount) end
    end
    if not suppressed then heard(count, d) end
end)
