--[[
    RP Stamina - client
    -------------------
    Toutes les CheckMs ms : armes de l'INVENTAIRE (config.lua : Weapons, lues avec HasPedGotWeapon ; type d'arme lu
    dans le jeu) -> secondes de sprint possibles :
      - POLICE (LocalPlayer.state.mdcUnit : dans une unité du MDC) : nombre d'armes longues (fusils à pompe, fusils
        d'assaut) -> Police.Sprint ; dès qu'il a une arme sur lui (même seulement une arme de poing) ;
      - CIVIL : la plus lourde des armes portées (Civil) ; armes de poing : aucun poids.
    Pendant le sprint, l'endurance baisse d'une seconde par seconde ; à zéro, le sprint est bloqué (touche de sprint
    coupée) : course normale, illimitée, jusqu'à ResumeAt d'endurance. Sprint arrêté : récupération (Regen).
    L'endurance du jeu est gardée pleine tant que ce système est actif (lui seul limite le sprint).
    Barre en haut au milieu de l'écran (NUI). Sans arme qui pèse : rien (endurance du jeu).
    Performance : sans arme qui pèse, une lecture de l'inventaire par seconde ; sinon une vérification toutes les
    100 ms, et à chaque image seulement quand le sprint est bloqué.
]]

local C = StaminaConfig or {}
if C.Enabled == false then return end

local function u32(h) return (math.tointeger(tonumber(h) or 0) or 0) & 0xFFFFFFFF end
local function gkey(name) return u32(GetHashKey(name)) end

local WEAPONS = {}
for _, name in ipairs(C.Weapons or {}) do WEAPONS[#WEAPONS + 1] = { name = name, hash = GetHashKey(name) } end

local P, CV, R = C.Police or {}, C.Civil or {}, C.Regen or {}
local LONG = {}
for _, g in ipairs(P.LongGroups or { 'GROUP_SHOTGUN', 'GROUP_RIFLE' }) do LONG[gkey(g)] = true end
local CIVIL = {}
for g, seconds in pairs(CV.Groups or {}) do CIVIL[gkey(g)] = { seconds = seconds, key = g } end
local MELEE = gkey('GROUP_MELEE')
local MELEE_LONG = {}
for _, n in ipairs(CV.MeleeLongWeapons or {}) do MELEE_LONG[gkey(n)] = true end
local UNARMED = gkey('WEAPON_UNARMED')

local LABELS = {
    GROUP_RIFLE = 'Fusil d\'assaut', GROUP_SHOTGUN = 'Fusil à pompe', GROUP_SMG = 'Pistolet-mitrailleur',
    GROUP_MG = 'Mitrailleuse', GROUP_THROWN = 'Arme de jet', GROUP_HEAVY = 'Arme lourde', GROUP_SNIPER = 'Fusil de précision',
    meleeLong = 'Arme blanche longue', meleeShort = 'Arme blanche',
}

local function debug(text, ...) if C.Debug then print(('[rp_stamina] ' .. text):format(...)) end end

local function isPolice()
    local unit = LocalPlayer.state.mdcUnit
    return unit ~= nil and unit ~= false and unit ~= ''
end

--- Secondes de sprint et libellé d'après l'inventaire ; nil : aucune arme qui pèse (endurance du jeu)
local function profileOf(ped)
    if isPolice() then
        local long = 0
        for _, w in ipairs(WEAPONS) do
            if HasPedGotWeapon(ped, w.hash, false) and LONG[u32(GetWeapontypeGroup(w.hash))] then long = long + 1 end
        end
        if long == 0 then return nil end -- pas d'arme longue : pas de limite (endurance du jeu)
        local sprint = P.Sprint or { [1] = 10, [2] = 7 }
        local top = 0
        for k in pairs(sprint) do if k > top then top = k end end
        local seconds = sprint[math.min(long, top)] or sprint[1] or 10
        return { seconds = seconds, label = ('police, %d arme(s) longue(s)'):format(long), police = true, long = long }
    end
    local best, label = nil, nil
    for _, w in ipairs(WEAPONS) do
        if HasPedGotWeapon(ped, w.hash, false) then
            local group = u32(GetWeapontypeGroup(w.hash))
            local seconds, key
            if group == MELEE then
                if MELEE_LONG[u32(w.hash)] then seconds, key = CV.MeleeLong or 40, 'meleeLong'
                else seconds, key = CV.MeleeShort or 70, 'meleeShort' end
            elseif CIVIL[group] then
                seconds, key = CIVIL[group].seconds, CIVIL[group].key
            end
            if seconds and (not best or seconds < best) then best, label = seconds, LABELS[key] or key end
        end
    end
    if not best then return nil end
    return { seconds = best, label = label, police = false }
end

-- =========================================================================
-- ENDURANCE
-- =========================================================================
local profile = nil
local budget, maxBudget = 0.0, 0.0
local exhausted = false
local lastUi, shownUntil, uiKey = 0, 0, nil

local function sendUi(show, now, sprinting)
    local ratio = maxBudget > 0 and budget / maxBudget or 1.0
    local B = C.Bar or {}
    if show and not B.AlwaysShow then
        if sprinting or ratio < 0.999 or exhausted then shownUntil = now + (B.HideAfter or 3) * 1000 end
        show = now < shownUntil
    end
    local key = show and ('%d|%s'):format(math.floor(ratio * 100 + 0.5), tostring(exhausted)) or 'hide'
    if key == uiKey then return end
    uiKey = key
    SendNUIMessage({ action = 'stamina', data = { show = show, ratio = ratio, exhausted = exhausted,
        seconds = math.floor(budget + 0.5), resume = C.ResumeAt or 0.25 } })
end

--- Notification : une arme se met à peser (prise, ou plus lourde que la précédente)
local function notifyWeight(new, old)
    local N = C.Notify or {}
    if N.Enabled == false or not new or (old and new.seconds >= old.seconds) then return end
    uiKey = nil -- la barre se réaffiche avec la notification
    SendNUIMessage({ action = 'staminaNotice', data = { text = new.police and N.Police or N.Civil, seconds = N.Seconds or 4 } })
end

local function setProfile(new, now)
    if new and profile and new.seconds == profile.seconds then profile = new return end
    notifyWeight(new, profile)
    local ratio = maxBudget > 0 and budget / maxBudget or 1.0
    profile = new
    if new then
        maxBudget = new.seconds + 0.0
        budget = maxBudget * ratio -- même part d'endurance quand le poids change (arme rangée / prise)
        debug('%s : %d s de sprint', new.label, new.seconds)
    else
        budget, maxBudget, exhausted = 0.0, 0.0, false
        debug('aucune arme qui pèse : endurance du jeu')
    end
    shownUntil = now + ((C.Bar or {}).HideAfter or 3) * 1000
end

CreateThread(function()
    local lastCheck, last = -1000000, GetGameTimer()
    while true do
        local now = GetGameTimer()
        local dt = math.min(1.0, (now - last) / 1000)
        last = now
        local ped = PlayerPedId()
        if now - lastCheck >= (C.CheckMs or 1000) then
            lastCheck = now
            setProfile(not IsEntityDead(ped) and profileOf(ped) or nil, now)
        end
        if not profile then
            sendUi(false, now, false)
            Wait(C.CheckMs or 1000)
        else
            RestorePlayerStamina(PlayerId(), 1.0) -- l'endurance du jeu ne coupe pas le sprint avant celle-ci
            local onFoot = not IsPedInAnyVehicle(ped, false) and not IsPedSwimming(ped)
            if exhausted then DisableControlAction(0, 21, true) end -- touche de sprint coupée : course normale
            local sprinting = onFoot and not exhausted and IsPedSprinting(ped)
            if sprinting then
                budget = budget - dt
                if budget <= 0 then
                    budget, exhausted = 0.0, true
                    debug('essoufflé : plus de sprint')
                end
            else
                local full = (onFoot and IsPedRunning(ped)) and (R.Run or 45) or (R.Idle or 20)
                budget = math.min(maxBudget, budget + maxBudget / math.max(1, full) * dt)
                if exhausted and budget >= maxBudget * (C.ResumeAt or 0.25) then
                    exhausted = false
                    debug('sprint de nouveau possible')
                end
            end
            if now - lastUi >= 100 then
                lastUi = now
                sendUi(true, now, sprinting)
            end
            Wait(exhausted and 0 or 100)
        end
    end
end)

exports('state', function()
    return { active = profile ~= nil, seconds = budget, max = maxBudget, exhausted = exhausted,
        label = profile and profile.label or nil }
end)

RPStamina = { profileOf = profileOf, state = function() return profile, budget, maxBudget, exhausted end } -- tests
