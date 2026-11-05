--[[
    RP Adrénaline - client
    ----------------------
    Écoute rp_weaponscontrol (événements locaux) : 'rp_weaponscontrol:shotNear' (n tirs entendus, distance) et
    'rp_weaponscontrol:bulletHit' (touché par balle).
    Balle reçue : recherche des tirs pendant Analysis.Seconds s (aucune chute) ; à la fin, adrénaline haute (fusillade)
    ou basse (hors fusillade), config.lua ; tirages au sort de chutes (ragdoll) jusqu'à Duration s après la fin de la
    recherche, ou soigné (vie au maximum) / mort / réapparu. À chaque chute, l'arme à feu tenue tombe au sol avec le %
    du scénario (exports.rp_vehicleprops:dropHeldWeapon, reprise avec l'œil). Dès la 2e chute : démarche blessée,
    remise à la fin.
    Performance : aucune boucle hors blessure ; pendant un épisode, une vérification toutes les 250 ms.
]]

local C = AdrenalineConfig
local A = C.Analysis or {}
local H, Lo = C.High or {}, C.Low or {}
local W = C.Walk

local shots = {}   -- { at, n } : tirs entendus récemment
local ep = nil     -- épisode en cours
local running = false

local function debug(text, ...) if C.Debug then print(('[rp_adrenaline] ' .. text):format(...)) end end

--- Tirs entendus entre `from` et `to` (ms)
local function shotsBetween(from, to)
    local n = 0
    for _, s in ipairs(shots) do if s.at >= from and s.at <= to then n = n + s.n end end
    return n
end

--- Scénario d'après les tirs autour : 'high' (fusillade) | 'low' (hors fusillade)
local function levelOf(around)
    if around >= (H.MinShots or 10) then return 'high' end
    if around < (Lo.MaxShots or 5) then return 'low' end
    return C.Fallback == 'high' and 'high' or 'low'
end

--- { Chance, Drop } pour ce scénario et ce nombre de balles
local function stageOf(level, bullets)
    local list = (level == 'high' and H.Stages) or Lo.Stages or {}
    local best = list[1]
    for _, s in ipairs(list) do if bullets >= (s.Bullets or 0) then best = s end end
    return best or { Chance = 50, Drop = 50 }
end

local function between(a, b) -- s -> ms, au hasard
    a, b = math.floor((a or 0) * 1000), math.floor((b or a or 0) * 1000)
    if b < a then a, b = b, a end
    return math.random(a, b)
end

-- =========================================================================
-- DÉMARCHE BLESSÉE
-- =========================================================================
local function setWalk(injured)
    if not W or not ep then return end
    if injured == (ep.walk == true) then return end
    ep.walk = injured
    if W.Mode == 'native' then
        local ped = PlayerPedId()
        if injured then
            RequestAnimSet(W.Clipset or 'move_m@injured')
            local deadline = GetGameTimer() + 1000
            while not HasAnimSetLoaded(W.Clipset or 'move_m@injured') and GetGameTimer() < deadline do Wait(0) end
            SetPedMovementClipset(ped, W.Clipset or 'move_m@injured', 0.2)
        else
            ResetPedMovementClipset(ped, 0.2)
        end
    else
        ExecuteCommand(injured and (W.Injured or 'walk injured') or (W.Reset or 'walk reset'))
        -- RPEMOTES (PersistentWalk) retient « injured » et la remet à la réapparition : remise à zéro à ce moment-là
        if injured then SetResourceKvpInt('walkInjured', 1) end
    end
    debug('démarche : %s', injured and 'blessée' or 'normale')
end

--- Une chute : à pied, vivant ; l'arme à feu tenue (s'il en tient une) tombe avec `dropPct` %
local function fall(dropPct)
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedInAnyVehicle(ped, true) or IsPedRagdoll(ped) or IsPedSwimming(ped) then return false end
    if (dropPct or 0) > 0 and IsPedArmed(ped, 4) and math.random(1, 100) <= dropPct
        and GetResourceState('rp_vehicleprops') == 'started' then
        pcall(function() exports.rp_vehicleprops:dropHeldWeapon() end)
    end
    local t = C.RagdollTime or { 1200, 2600 }
    local duration = math.random(t[1], t[2])
    SetPedToRagdoll(ped, duration, duration, 0, false, false, false)
    debug('chute (%d ms, %d %% de lâcher l\'arme)', duration, dropPct or 0)
    return true
end

--- Fin de la recherche des tirs : choix du scénario et du premier tirage
local function decide(now)
    local around = shotsBetween(ep.firstHit - (A.Lead or 1) * 1000, ep.analysisEnd)
    ep.shots = around
    ep.level = levelOf(around)
    if ep.level == 'high' then
        ep.nextRoll = ep.analysisEnd + between((H.Start or { 50, 70 })[1], (H.Start or { 50, 70 })[2])
    else
        ep.nextRoll = now -- effet de surprise : dès la fin des 8 s
    end
    debug('fin de la recherche : %d balle(s), %d tir(s) à moins de %.0f m -> adrénaline %s', ep.bullets, around,
        A.Range or 50.0, ep.level == 'high' and 'HAUTE (fusillade)' or 'BASSE (hors fusillade)')
end

local function finish(reason)
    debug('fin : %s', reason)
    setWalk(false)
    ep = nil
end

local function run()
    if running then return end
    running = true
    CreateThread(function()
        while ep do
            local now = GetGameTimer()
            local ped = PlayerPedId()
            local health, max = GetEntityHealth(ped), GetEntityMaxHealth(ped)
            if health < max then ep.hurt = true end
            if IsEntityDead(ped) then finish('mort')
            elseif ep.hurt and health >= max then finish('soigné (vie au maximum)')
            elseif now >= ep.stopAt then finish('1 min 30 après la recherche')
            else
                if not ep.level and now >= ep.analysisEnd then decide(now) end
                if ep.level and now >= ep.nextRoll then
                    local s = stageOf(ep.level, ep.bullets)
                    if math.random(1, 100) <= (s.Chance or 50) and fall(s.Drop or 0) then
                        ep.falls = ep.falls + 1
                        if W and ep.falls >= (W.From or 2) then setWalk(true) end
                    end
                    local every = (ep.level == 'high' and H.Every or Lo.Every) or 8
                    ep.nextRoll = ep.nextRoll + math.max(1, every) * 1000
                end
            end
            if ep then Wait(250) end
        end
        running = false
    end)
end

local function onBullet()
    local now = GetGameTimer()
    if ep then
        ep.bullets = ep.bullets + 1 -- compte pour les tirages suivants (chance de chute, d'arme lâchée)
        debug('balle reçue : %d balle(s)', ep.bullets)
        return
    end
    local analysisEnd = now + (A.Seconds or 8) * 1000
    ep = { firstHit = now, analysisEnd = analysisEnd, stopAt = analysisEnd + (C.Duration or 90) * 1000, bullets = 1,
        falls = 0, hurt = false } -- hurt : vie passée sous le maximum (une balle arrêtée par le gilet ne compte pas)
    debug('balle reçue : recherche des tirs pendant %d s', A.Seconds or 8)
    run()
end

AddEventHandler('rp_weaponscontrol:shotNear', function(n, d)
    if (tonumber(d) or 999) > (A.Range or 50.0) then return end
    local now = GetGameTimer()
    shots[#shots + 1] = { at = now, n = math.max(1, math.floor(tonumber(n) or 1)) }
    -- gardés le temps d'une recherche (+ marge) ; au plus 600
    local keep = ((A.Seconds or 8) + (A.Lead or 1) + 5) * 1000
    while shots[1] and (now - shots[1].at > keep or #shots > 600) do table.remove(shots, 1) end
end)

AddEventHandler('rp_weaponscontrol:bulletHit', onBullet)

-- Réapparu / réanimé (rp_revive) : l'épisode s'arrête ; démarche blessée retenue par RPEMOTES : remise à zéro (une fois)
-- Démarche blessée restée à la connexion / réapparition (RPEMOTES la remet depuis sa sauvegarde) : retirée
local INJURED = {}
for _, name in ipairs((W and W.Injuries) or { 'move_m@injured', 'move_f@injured' }) do
    INJURED[GetHashKey(name) & 0xFFFFFFFF] = true
end
local function clearStaleWalk()
    if not W or W.ClearOnSpawn == false then return end
    for _, delay in ipairs({ 1000, 3000, 6000 }) do -- RPEMOTES pose sa démarche juste après l'apparition
        SetTimeout(delay, function()
            if ep and ep.walk then return end
            local ped = PlayerPedId()
            if INJURED[(GetPedMovementClipset(ped) or 0) & 0xFFFFFFFF] then
                ResetPedMovementClipset(ped, 0.2)
                debug('démarche blessée restée (sauvegarde RPEMOTES) : retirée')
            end
        end)
    end
end

AddEventHandler('playerSpawned', function()
    if ep then finish('réapparu') end
    DeleteResourceKvp('walkInjured') -- ancienne version
    clearStaleWalk()
end)
clearStaleWalk() -- redémarrage de la ressource, joueur déjà en jeu

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and ep then setWalk(false) end
end)

-- Pour les tests et les autres scripts
RPAdrenaline = {
    level = function() return ep and ep.level end,
    state = function() return ep end,
    levelOf = levelOf, stageOf = stageOf, fall = fall,
}
exports('level', function() return ep and ep.level end) -- 'high' | 'low' | nil (recherche en cours ou rien)
