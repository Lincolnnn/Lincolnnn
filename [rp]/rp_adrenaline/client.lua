--[[
    RP Adrénaline - client
    ----------------------
    Écoute rp_weaponscontrol (événements locaux) : 'rp_weaponscontrol:shotNear' (n tirs entendus, distance) et
    'rp_weaponscontrol:bulletHit' (touché par balle).
    Première balle : recherche des tirs pendant Analysis.Seconds s (aucune chute) ; à la fin, scénario haute ou basse
    adrénaline (config.lua) ; chutes (ragdoll) jusqu'à Duration s après la fin de la recherche, ou soigné (vie au
    maximum) / mort / réapparu. À chaque chute, l'arme à feu tenue tombe au sol avec le % du scénario
    (exports.rp_vehicleprops:dropHeldWeapon, reprise avec l'œil).
    Performance : aucune boucle hors blessure ; pendant un épisode, une vérification toutes les 250 ms.
]]

local C = AdrenalineConfig
local A = C.Analysis or {}
local H, Lo = C.High or {}, C.Low or {}

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

--- Scénario d'après les balles reçues et les tirs autour : 'high' | 'low'
local function levelOf(bullets, around)
    if bullets >= (H.MinBullets or 3) and around >= (H.MinShots or 15) then return 'high' end
    if bullets <= (Lo.MaxBullets or 4) and around < (Lo.MaxShots or 8) then return 'low' end
    return C.Fallback == 'high' and 'high' or 'low'
end

--- Ligne de High.Stages pour ce nombre de balles (la plus haute atteinte ; la première sinon)
local function stageOf(bullets)
    local list = H.Stages or {}
    local best = list[1]
    for _, s in ipairs(list) do if bullets >= (s.Bullets or 0) then best = s end end
    return best or { From = 50, To = 70, Drop = 65 }
end

local function between(a, b) -- s -> ms, au hasard
    a, b = math.floor((a or 0) * 1000), math.floor((b or a or 0) * 1000)
    if b < a then a, b = b, a end
    return math.random(a, b)
end

--- Une chute : à pied, vivant ; l'arme à feu tenue tombe avec `dropPct` %. false si impossible maintenant.
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

--- Fin de la recherche des tirs : choix du scénario
local function decide(now)
    local around = shotsBetween(ep.firstHit - (A.Lead or 1) * 1000, ep.analysisEnd)
    ep.shots = around
    ep.level = levelOf(ep.bullets, around)
    if ep.level == 'high' then
        local s = stageOf(ep.bullets)
        ep.drop = s.Drop or 65
        ep.fallAt = ep.firstHit + between(s.From or 50, s.To or 70)
    else
        ep.drop = Lo.Drop or 65
        ep.nextRoll = now -- premier tirage dès la fin des 15 s
    end
    debug('fin de la recherche : %d balle(s), %d tir(s) à moins de %.0f m -> adrénaline %s', ep.bullets, around,
        A.Range or 50.0, ep.level == 'high' and 'HAUTE' or 'BASSE')
end

--- Prochain tirage au sort (adrénaline basse, ou haute après la première chute)
local function rollEvery()
    if ep.level == 'high' then return (H.AfterFirst or {}).Every or 7 end
    return Lo.Every or 7
end
local function rollChance()
    if ep.level == 'high' then return (H.AfterFirst or {}).Chance or 55 end
    return Lo.Chance or 55
end

local function finish(reason)
    debug('fin : %s', reason)
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
                if ep.level == 'high' and ep.fallAt then
                    -- première chute de l'adrénaline haute : attend d'être à pied
                    if now >= ep.fallAt and fall(ep.drop) then
                        ep.fallAt = nil
                        local after = H.AfterFirst
                        if after then ep.nextRoll = now + (after.Every or 7) * 1000 end
                    end
                elseif ep.nextRoll and now >= ep.nextRoll then
                    if math.random(1, 100) <= rollChance() then fall(ep.drop) end
                    local jitter = ep.level == 'low' and (Lo.Jitter or 0) or 0
                    ep.nextRoll = ep.nextRoll + math.max(1000, rollEvery() * 1000 + between(-jitter, jitter))
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
        ep.bullets = ep.bullets + 1
        if ep.level == 'high' and ep.fallAt then
            -- plus de balles avant la première chute : elle peut arriver plus tôt, arme plus souvent lâchée
            local s = stageOf(ep.bullets)
            ep.drop = math.max(ep.drop or 0, s.Drop or 0)
            ep.fallAt = math.min(ep.fallAt, ep.firstHit + between(s.From or 50, s.To or 70))
        end
        debug('balle reçue : %d balle(s)', ep.bullets)
        return
    end
    local analysisEnd = now + (A.Seconds or 15) * 1000
    ep = { firstHit = now, analysisEnd = analysisEnd, stopAt = analysisEnd + (C.Duration or 90) * 1000, bullets = 1,
        hurt = false } -- hurt : vie passée sous le maximum (une balle arrêtée par le gilet ne compte pas)
    debug('première balle : recherche des tirs pendant %d s', A.Seconds or 15)
    run()
end

AddEventHandler('rp_weaponscontrol:shotNear', function(n, d)
    if (tonumber(d) or 999) > (A.Range or 50.0) then return end
    local now = GetGameTimer()
    shots[#shots + 1] = { at = now, n = math.max(1, math.floor(tonumber(n) or 1)) }
    -- gardés le temps d'une recherche (+ marge) ; au plus 600
    local keep = ((A.Seconds or 15) + (A.Lead or 1) + 5) * 1000
    while shots[1] and (now - shots[1].at > keep or #shots > 600) do table.remove(shots, 1) end
end)

AddEventHandler('rp_weaponscontrol:bulletHit', onBullet)

-- Réapparu / réanimé (rp_revive) : l'épisode s'arrête
AddEventHandler('playerSpawned', function() if ep then finish('réapparu') end end)

-- Pour les tests et les autres scripts
RPAdrenaline = {
    level = function() return ep and ep.level end,
    state = function() return ep end,
    levelOf = levelOf, stageOf = stageOf, fall = fall,
}
exports('level', function() return ep and ep.level end) -- 'high' | 'low' | nil (recherche en cours ou rien)
