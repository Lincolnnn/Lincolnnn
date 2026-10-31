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
    LAMPE TOUJOURS ALLUMÉE (Flashlight) : allumée par le joueur, elle le reste (même arme baissée, en courant ; réglage
    du jeu réappliqué en permanence, d'autres scripts le remettant à false) et se rallume quand
    l'arme revient en main ; éteinte par le joueur, elle reste éteinte. Lampes de CartoonFlashlight : gérées par elle,
    leur état est gardé ici (exports flashlightWanted / setFlashlight).
    SÉLECTEUR DE TIR (FireMode) : touche B sur une arme automatique : coup par coup <-> automatique (petit clic, logo
    en bas au milieu de l'écran). Coup par coup : un tir par pression de la détente.
    EFFET DE TIR SUR LES BORDS (Suppression) : voile style « motion blur » sur les bords de l'écran (jamais au centre),
    au-dessus de toutes les interfaces : on tire, quelqu'un tire près de nous, on nous tire dessus (+ secousse, touché
    ou non), on est touché (+ bords légèrement rouges). Chaque tir l'étend ; il disparaît FadeOut ms après le dernier.
    Performance : sans arme à feu en main, une vérification toutes les 250 ms ; arme en main : lecture du tir à chaque
    image (comme le jeu) ; PNJ armés à moins de 10 m : lecture de leurs tirs à chaque image tant qu'il y en a ; lampe :
    une lecture toutes les 200 ms arme en main (500 ms sinon).
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
-- EFFET DE TIR SUR LES BORDS DE L'ÉCRAN (Suppression) : dessiné par le NUI (html/script.js), au-dessus de toutes les
-- interfaces pendant l'effet (z-index du NUI de ce script), remis à 0 quand il a disparu
-- =========================================================================
local SP = W.Suppression or {}
local SP_CFG = { -- réglages envoyés au NUI (aspect, tailles, durées)
    minCoverage = SP.MinCoverage or 0.05, maxCoverage = SP.MaxCoverage or 0.2, opacity = SP.Opacity or 0.9,
    blur = SP.Blur or 7, streaks = SP.Streaks or 0.55, grain = SP.Grain or 0.35, tint = SP.Tint or { 26, 28, 32 },
    hitColor = SP.HitColor or { 150, 8, 12 }, hitOpacity = SP.HitOpacity or 0.4, hitFade = SP.HitFade or 4500,
    fadeOut = SP.FadeOut or 5500, curve = SP.Curve or 0.5,
}
local spUntil, spOnTop = 0, false

-- ---- Vrai flou de l'image du jeu (GameBlur) : modificateur timecycle créé ici, posé dans l'emplacement « extra » ----
local GB = SP.GameBlur or {}
local TC_NAME = 'rp_wc_suppression'
local tcVars = nil  -- noms des variables du jeu : { intensity, radius, motion } ; false : introuvables
local gb = { peak = 0.0, last = 0, running = false }

--- Variables de flou du jeu, cherchées par leur nom (le préfixe peut changer selon les versions du jeu)
local function findTcVars()
    if tcVars ~= nil then return tcVars end
    local found = {}
    for i = 0, (GetTimecycleVarCount() or 0) - 1 do
        local name = GetTimecycleVarNameByIndex(i)
        if type(name) == 'string' then
            if name:find('blur_vignetting_intensity', 1, true) then found.intensity = name
            elseif name:find('blur_vignetting_radius', 1, true) then found.radius = name
            elseif name:find('motionblur', 1, true) then found.motion = name end
        end
    end
    if not found.intensity then
        print('^3[rp_weaponscontrol] Flou du jeu (GameBlur) : variable « blur_vignetting_intensity » introuvable, seul le voile est utilisé.^0')
        tcVars = false
        return tcVars
    end
    if GetTimecycleModifierIndexByName(TC_NAME) == -1 then CreateTimecycleModifier(TC_NAME) end
    tcVars = found
    return tcVars
end

local function gameBlurLevel(now)
    return gb.peak * math.max(0.0, 1.0 - (now - gb.last) / SP_CFG.fadeOut)
end

local function setGameBlur(level)
    local v = tcVars
    local intensity = (GB.Intensity or 1.0) * (level > 0 and level ^ SP_CFG.curve or 0.0) -- vite visible
    SetTimecycleModifierVar(TC_NAME, v.intensity, intensity, intensity)
    if v.radius then
        local r = (GB.RadiusMin or 0.35) + ((GB.RadiusMax or 0.9) - (GB.RadiusMin or 0.35)) * level
        SetTimecycleModifierVar(TC_NAME, v.radius, r, r)
    end
    if v.motion and (GB.MotionBlur or 0) > 0 then
        SetTimecycleModifierVar(TC_NAME, v.motion, GB.MotionBlur * level, GB.MotionBlur * level)
    end
    SetExtraTimecycleModifier(TC_NAME)
end

--- Le flou du jeu monte de `add` ; il redescend jusqu'à 0 en FadeOut ms (mise à jour ~30 fois par seconde, seulement
--- pendant l'effet), puis le modificateur est retiré (s'il est toujours le nôtre : rp_vehiclecontrol utilise aussi
--- l'emplacement « extra »)
local function gameBlur(add)
    if GB.Enabled == false or not findTcVars() then return end
    local now = GetGameTimer()
    gb.peak = math.min(1.0, gameBlurLevel(now) + add)
    gb.last = now
    if gb.running then return end
    gb.running = true
    CreateThread(function()
        local sent = -1.0
        while true do
            local level = gameBlurLevel(GetGameTimer())
            if level <= 0.0 then break end
            if math.abs(level - sent) > 0.01 then setGameBlur(level) sent = level end
            Wait(33)
        end
        setGameBlur(0.0)
        if GetExtraTimecycleModifierIndex() == GetTimecycleModifierIndexByName(TC_NAME) then ClearExtraTimecycleModifier() end
        gb.running = false
    end)
end
RPWeapons.gameBlur = gameBlur

--- L'effet monte de `add` (0-1) ; hit : bords rouges. Pas d'effet de post-traitement coloré du jeu (l'ancien « zoom »
--- RaceTurbo teintait l'image d'orange grisâtre) : seulement le flou et le voile.
local function suppress(add, hit)
    if SP.Enabled == false then return end
    add = math.max(0.0, math.min(1.0, add or 0.0))
    if add <= 0.0 and not hit then return end
    spUntil = GetGameTimer() + math.max(SP_CFG.fadeOut, hit and SP_CFG.hitFade or 0) + 300
    SendNUIMessage({ action = 'suppress', data = { add = add, hit = hit == true, cfg = SP_CFG } })
    gameBlur(add)
    if spOnTop or not SP.ZIndex then return end
    spOnTop = true
    SetNuiZindex(SP.ZIndex) -- au-dessus de tout (HUD, PLD, menus, MDC ; la minimap du jeu est sous le NUI)
    CreateThread(function()
        while GetGameTimer() < spUntil do Wait(500) end
        SetNuiZindex(0)
        spOnTop = false
    end)
end
RPWeapons.suppress = suppress

--- Direction d'un tir : du canon vers le point visé (rayon de la caméra, 150 m) ; { fx, fy, fz, tx, ty, tz }
local function aimOf(ped)
    local from = muzzleOf(ped)
    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(rx))
    local dx, dy, dz = -math.sin(rz) * c, math.cos(rz) * c, math.sin(rx)
    return { from.x, from.y, from.z, cam.x + dx * 150.0, cam.y + dy * 150.0, cam.z + dz * 150.0 }
end
RPWeapons.aimOf = aimOf

--- Le tir (aim) passe-t-il à moins de `radius` m de pos (devant le tireur) ?
local function passesNear(aim, pos, radius)
    if type(aim) ~= 'table' or #aim < 6 then return false end
    local fx, fy, fz, tx, ty, tz = aim[1], aim[2], aim[3], aim[4], aim[5], aim[6]
    local dx, dy, dz = tx - fx, ty - fy, tz - fz
    local len2 = dx * dx + dy * dy + dz * dz
    if len2 < 0.01 then return false end
    local t = ((pos.x - fx) * dx + (pos.y - fy) * dy + (pos.z - fz) * dz) / len2
    if t <= 0.0 then return false end -- derrière le tireur
    t = math.min(t, 1.0)
    local cx, cy, cz = fx + dx * t - pos.x, fy + dy * t - pos.y, fz + dz * t - pos.z
    return cx * cx + cy * cy + cz * cz <= radius * radius
end
RPWeapons.passesNear = passesNear

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
        suppressed = pending.suppressed, smoke = pending.smoke, aim = pending.aim })
    pending = nil
end

--- Secousse de tir ; rp_camshake (tremblement de marche) est mis en pause avant, sinon il appliquait son amplitude
--- (0.3 à 2.4) à cette secousse (0.03 environ) : premiers tirs 20 fois trop brusques
local function camShake(name, amp)
    TriggerEvent('rp_camshake:pause', 800)
    ShakeGameplayCam(name, amp)
end

local function onShot(ped, weapon, entry)
    local suppressed = IsPedCurrentWeaponSilenced(ped)
    recoil(ped, entry.w)
    local shake = entry.w.shake or entry.p.shake
    if shake and shake > 0 then camShake((W.Shake or {}).Name or 'SMALL_EXPLOSION_SHAKE', shake * (suppressed and 0.5 or 1.0)) end
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
    if SP.Enabled ~= false then
        pending.aim = aimOf(ped) -- direction du dernier tir : les joueurs visés le sentent
        suppress((SP.Own or 0.05) * (suppressed and 0.5 or 1.0))
    end
end
RPWeapons.onShot = onShot
RPWeapons.flush = flush

-- =========================================================================
-- SÉLECTEUR DE TIR : coup par coup / automatique (armes automatiques)
-- =========================================================================
local FM = W.FireMode or {}
local SELECT_GROUPS, SELECT_WEAPONS, SELECT_EXCLUDED = {}, {}, {}
for _, g in ipairs(FM.Groups or {}) do SELECT_GROUPS[u32(GetHashKey(g))] = true end
for _, n in ipairs(FM.Weapons or {}) do SELECT_WEAPONS[u32(GetHashKey(n))] = true end
for _, n in ipairs(FM.Excluded or {}) do SELECT_EXCLUDED[u32(GetHashKey(n))] = true end
local modes = {}       -- [arme] = 'semi' | 'auto' (réglé par le joueur)
local semiLock = false -- coup par coup : tir parti, la détente doit être relâchée
local badgeFor = nil   -- arme dont le logo est affiché

--- L'arme a-t-elle un sélecteur (arme automatique) ?
local function hasSelector(weapon)
    if FM.Enabled == false or not weapon or weapon == 0 then return false end
    local h = u32(weapon)
    if SELECT_EXCLUDED[h] or EXCLUDED[h] then return false end
    return SELECT_WEAPONS[h] == true or SELECT_GROUPS[u32(GetWeapontypeGroup(weapon))] == true
end

local function modeOf(weapon) return modes[u32(weapon)] or (FM.Default == 'semi' and 'semi' or 'auto') end
RPWeapons.hasSelector, RPWeapons.modeOf = hasSelector, modeOf

--- Logo en bas au milieu de l'écran : BadgeSeconds s après un appui sur la touche (Badge = true : tant que l'arme
--- à sélecteur est en main) ; arme rangée ou changée : retiré
local function badge(weapon, changed)
    local show = weapon and hasSelector(weapon) or false
    local key = show and u32(weapon) or nil
    if key == badgeFor and not changed then return end
    badgeFor = key
    SendNUIMessage({ action = 'firemode', data = { show = show, mode = show and modeOf(weapon) or nil,
        changed = changed == true, persistent = FM.Badge == true, seconds = FM.BadgeSeconds or 3,
        volume = FM.Volume or 0.35 } })
end

if FM.Enabled ~= false then
    RegisterCommand('rp_firemode', function()
        local ped = PlayerPedId()
        if IsPauseMenuActive() or not IsPedArmed(ped, 4) then return end
        local _, weapon = GetCurrentPedWeapon(ped, true)
        if not hasSelector(weapon) then return end
        modes[u32(weapon)] = modeOf(weapon) == 'auto' and 'semi' or 'auto'
        semiLock = false
        badge(weapon, true)
    end, false)
    RegisterKeyMapping('rp_firemode', 'Arme : coup par coup / automatique', 'keyboard', FM.Key or 'B')
end

CreateThread(function()
    if W.NoAutoReload ~= false then SetWeaponsNoAutoreload(true) end -- chargeur vide : recharger soi-même (R)
    while true do
        local ped = PlayerPedId()
        local entry, weapon = nil, nil
        if IsPedArmed(ped, 4) then
            local _, current = GetCurrentPedWeapon(ped, true)
            weapon = current
            entry = profileOf(weapon)
            if entry then
                -- coup par coup : après un tir, la détente est bloquée jusqu'à ce qu'elle soit relâchée
                local semi = hasSelector(weapon) and modeOf(weapon) == 'semi'
                if semiLock then
                    if semi then
                        DisableControlAction(0, 24, true)  -- tirer
                        DisableControlAction(0, 257, true) -- tirer (attaque 2)
                    end
                    if not semi or (not IsDisabledControlPressed(0, 24) and not IsDisabledControlPressed(0, 257)) then
                        semiLock = false
                    end
                end
                if IsPedShooting(ped) then
                    onShot(ped, weapon, entry)
                    if semi then semiLock = true end
                end
                flush(false)
            end
        end
        badge(entry and weapon or nil, false)
        if not entry then
            flush(true)
            recent = {}
            semiLock = false
        end
        Wait(entry and 0 or 250)
    end
end)

-- =========================================================================
-- LAMPE TOUJOURS ALLUMÉE (arme équipée d'une lampe, lampe de poche)
-- =========================================================================
local FL = W.Flashlight or {}
if FL.Enabled ~= false then
    if FL.KeepOnWhileMoving ~= false then SetFlashLightKeepOnWhileMoving(true) end -- pas seulement en visant
    local UNARMED = u32(GetHashKey('WEAPON_UNARMED'))
    local lit = {}        -- [arme] = lampe allumée par le joueur
    local current, since, restoring = nil, 0, false

    -- Lampes de CartoonFlashlight (ressource à part) : elle les gère (lampe tenue, lumière), on garde leur état
    local CARTOON = FL.Cartoon or {}
    local cartoonWeapons = {}
    for _, name in ipairs(CARTOON.Weapons or {}) do cartoonWeapons[u32(GetHashKey(name))] = true end
    local function cartoon(weapon)
        return cartoonWeapons[u32(weapon)] == true and CARTOON.Resource and GetResourceState(CARTOON.Resource) == 'started'
    end
    RPWeapons.cartoon = cartoon

    --- État voulu de la lampe d'une arme (jamais réglée : allumée pour une lampe de CartoonFlashlight, éteinte sinon)
    exports('flashlightWanted', function(weapon)
        local h = u32(weapon or 0)
        if lit[h] == nil then return cartoonWeapons[h] == true end
        return lit[h]
    end)
    --- Une autre ressource allume / éteint la lampe d'une arme (CartoonFlashlight, arme reprise sur un véhicule…) :
    --- gardé, et rallumée tout de suite si c'est l'arme en main
    local function setFlashlight(weapon, on)
        local h = u32(weapon or 0)
        if h == 0 then return end
        lit[h] = on == true
        if h == current and not cartoon(h) then since, restoring = GetGameTimer() - 300, on == true end
    end
    exports('setFlashlight', setFlashlight)
    AddEventHandler('rp_weaponscontrol:flashlight', setFlashlight)
    RPWeapons.setFlashlight = setFlashlight

    --- Moments où le jeu éteint la lampe tout seul : ce n'est pas le joueur
    local function unusual(ped)
        return IsPedInAnyVehicle(ped, true) or IsPedRagdoll(ped) or IsEntityDead(ped) or IsPedSwimming(ped)
            or IsPedClimbing(ped) or IsPedReloading(ped)
    end

    CreateThread(function()
        while true do
            local ped = PlayerPedId()
            local weapon = u32(GetSelectedPedWeapon(ped))
            local armed = weapon ~= 0 and weapon ~= UNARMED
            local now = GetGameTimer()
            if weapon ~= current then
                current, since, restoring = weapon, now, armed and lit[weapon] == true
            end
            if armed and cartoon(weapon) then
                -- lampe de CartoonFlashlight : sa propre lumière (jamais celle du jeu, qui doublerait)
            elseif armed then
                -- lampe allumée même arme baissée : réglage GLOBAL du jeu, remis à false par d'autres scripts
                -- (CartoonFlashlight le fait à chaque fois que sa lampe démarre / s'arrête) -> réappliqué ici
                if FL.KeepOnWhileMoving ~= false then SetFlashLightKeepOnWhileMoving(true) end
                local on = IsFlashLightOn(ped)
                if unusual(ped) then
                    since, restoring = now, lit[weapon] == true -- à la sortie : elle revient si elle était allumée
                elseif restoring then
                    if on then
                        restoring = false
                    elseif now - since > 300 then
                        SetFlashLightEnabled(ped, true)
                        if now - since > 3000 then restoring = false end -- arme sans lampe (accessoire retiré)
                    end
                elseif now - since > 800 then
                    lit[weapon] = on -- allumée ou éteinte par le joueur
                end
            end
            Wait(armed and 200 or 500)
        end
    end)
    RPWeapons.flashlights = lit -- pour les tests
end

-- =========================================================================
-- AIDE AU STYLE DU SERVEUR pour une autre ressource (CartoonFlashlight : aide de la lampe en haut à gauche) :
-- exports.rp_weaponscontrol:showHint(id, { title, lines = { { touche, texte } | 'texte' } }) à rappeler au moins
-- toutes les 300 ms tant qu'elle doit rester ; plus rappelée : retirée. Envoyée au NUI seulement si elle change.
-- =========================================================================
local hintShown, hintKey, hintUntil = false, nil, 0
exports('showHint', function(id, data)
    if type(data) ~= 'table' then return end
    hintUntil = GetGameTimer() + 350
    local key = tostring(id) .. '|' .. json.encode(data)
    if key ~= hintKey then
        hintKey = key
        SendNUIMessage({ action = 'hint', data = { show = true, title = data.title, lines = data.lines } })
    end
    if hintShown then return end
    hintShown = true
    CreateThread(function()
        while GetGameTimer() < hintUntil do Wait(100) end
        hintShown, hintKey = false, nil
        SendNUIMessage({ action = 'hint', data = { show = false } })
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if W.NoAutoReload ~= false then SetWeaponsNoAutoreload(false) end
    -- flou du jeu en cours : retiré
    if tcVars and GetExtraTimecycleModifierIndex() == GetTimecycleModifierIndexByName(TC_NAME) then ClearExtraTimecycleModifier() end
end)

-- Réglage du flou en jeu (F8) : « wc_blurtest » joue l'effet au maximum ; « wc_blurtest 0.4 » à 40 %
RegisterCommand('wc_blurtest', function(_, args)
    local level = math.max(0.05, math.min(1.0, tonumber(args[1]) or 1.0))
    local v = findTcVars()
    print(('[rp_weaponscontrol] Flou du jeu : %s'):format(v and ('%s / %s / %s'):format(v.intensity, v.radius or '-', v.motion or '-') or 'indisponible'))
    suppress(level, false)
end, false)

-- =========================================================================
-- PNJ ARMÉS PROCHES (acouphène, effet de tir sur les bords) : liste toutes les 250 ms, leurs tirs lus à chaque image
-- tant qu'il y en a. Un PNJ en combat contre le joueur qui tire : tir dans sa direction.
-- =========================================================================

--- Effet d'un tir d'un autre (joueur ou PNJ) à d m : tir proche, et tir dans notre direction (secousse)
local function shotAround(n, d, towardMe, suppressed)
    if SP.Enabled == false then return end
    local range = SP.Range or 25.0
    local add = 0.0
    if d <= range then add = (SP.Near or 0.035) * n * (1.0 - 0.7 * d / range) * (suppressed and 0.5 or 1.0) end
    if towardMe then
        add = add + (SP.Incoming or 0.12) * n
        if (SP.IncomingShake or 0) > 0 then camShake(SP.ShakeName or 'SMALL_EXPLOSION_SHAKE', SP.IncomingShake) end
    end
    suppress(add, false)
end
RPWeapons.shotAround = shotAround

CreateThread(function()
    local T = W.Tinnitus or {}
    local tinnitus = T.Enabled ~= false and T.Npc ~= false
    if not tinnitus and SP.Enabled == false then return end
    local range = math.max(tinnitus and (T.Range or 10.0) or 0.0, SP.Enabled ~= false and (SP.Range or 25.0) or 0.0)
    while true do
        local me = PlayerPedId()
        local origin = GetEntityCoords(me)
        local near = {}
        for _, ped in ipairs(GetGamePool('CPed')) do
            if ped ~= me and not IsPedAPlayer(ped) and not IsEntityDead(ped) and IsPedArmed(ped, 4)
                and #(GetEntityCoords(ped) - origin) <= range then
                near[#near + 1] = ped
            end
        end
        if #near == 0 then
            Wait(250)
        else
            local untilTime = GetGameTimer() + 250
            repeat
                for _, ped in ipairs(near) do
                    if DoesEntityExist(ped) and IsPedShooting(ped) then
                        local mine = PlayerPedId()
                        local d = #(GetEntityCoords(ped) - GetEntityCoords(mine))
                        local silenced = IsPedCurrentWeaponSilenced(ped)
                        if tinnitus and not silenced then heard(1, d) end
                        shotAround(1, d, IsPedInCombat(ped, mine), silenced)
                    end
                end
                Wait(0)
            until GetGameTimer() >= untilTime
        end
    end
end)

-- Touché par une balle (joueur ou PNJ) : effet, bords rouges, secousse. L'arme est cherchée parmi les arguments de
-- l'événement (leur ordre change selon les versions du jeu) : seulement une arme à feu concernée (pas le Taser, etc.)
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or SP.Enabled == false or type(args) ~= 'table' then return end
    if args[1] ~= PlayerPedId() then return end
    local gun = false
    for i = 3, #args do
        local v = args[i]
        if type(v) == 'number' and v ~= 0 and v ~= 1 and profileOf(v) then gun = true break end
    end
    if not gun then return end
    if (SP.HitShake or 0) > 0 then camShake(SP.ShakeName or 'SMALL_EXPLOSION_SHAKE', SP.HitShake) end
    suppress(SP.Hit or 0.22, true)
end)

-- =========================================================================
-- TIRS DES AUTRES JOUEURS (relayés par le serveur, seulement ceux à portée)
-- =========================================================================
RegisterNetEvent('rp_weaponscontrol:shots', function(src, count, key, suppressed, withSmoke, aim)
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
        if amount > 0.01 then camShake(Sh.Name or 'SMALL_EXPLOSION_SHAKE', amount) end
    end
    if not suppressed then heard(count, d) end
    -- effet sur les bords : tir proche ; tir dans notre direction (balle passée tout près, touché ou non) : + secousse
    local towardMe = passesNear(aim, GetEntityCoords(PlayerPedId()), SP.IncomingRadius or 2.5)
    shotAround(count, d, towardMe, suppressed)
end)
