--[[
    RP Adrénaline - client
    ----------------------
    Écoute rp_weaponscontrol (événements locaux, aucune boucle) : 'rp_weaponscontrol:shotNear' (tirs entendus, distance)
    et 'rp_weaponscontrol:bulletHit' (touché par balle). À chaque balle reçue : niveau d'adrénaline d'après les balles
    reçues et les tirs autour ; une période de chutes démarre (ou est relevée / prolongée). Pendant la période : une
    attente au hasard (Every), puis une chute (ragdoll) à pied, et 1 fois sur DropChance l'arme à feu tenue tombe au sol
    (exports.rp_vehicleprops:dropHeldWeapon, reprise avec l'œil). Aucune boucle hors période.
]]

local C = AdrenalineConfig
local LEVELS = { low = 1, medium = 2, high = 3 }
local shots = {}   -- { at, n }
local hits = {}    -- heures des balles reçues
local episode = nil -- { level, untilTime }
local running = false

local function debug(text, ...) if C.Debug then print(('[rp_adrenaline] ' .. text):format(...)) end end

local function prune(list, window, now)
    while list[1] and now - (type(list[1]) == 'table' and list[1].at or list[1]) > window do table.remove(list, 1) end
end

local function shotCount(now)
    prune(shots, (C.ShotWindow or 30) * 1000, now)
    local n = 0
    for _, s in ipairs(shots) do n = n + s.n end
    return n
end

--- Niveau d'après les balles reçues et les tirs autour (nil : rien)
local function levelOf(bullets, around)
    local H, Lo, M = C.High or {}, C.Low or {}, C.Medium or {}
    if bullets >= (H.MinBullets or 2) and around > (H.MinShots or 10) then return 'high' end
    if bullets >= (Lo.MinBullets or 1) and around < (Lo.MaxShots or 5) then return 'low' end
    if bullets >= (M.MinBullets or 1) then return 'medium' end
    return nil
end

local function settings(level)
    return (level == 'high' and C.High) or (level == 'low' and C.Low) or C.Medium or {}
end

local function randomBetween(range, default)
    local a, b = (range or default)[1], (range or default)[2]
    return math.random(math.floor(a * 1000), math.floor(b * 1000))
end

--- Une chute : à pied, vivant ; l'arme à feu tenue tombe 1 fois sur DropChance
local function fall()
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedInAnyVehicle(ped, true) or IsPedRagdoll(ped) or IsPedSwimming(ped) then return false end
    local chance = tonumber(C.DropChance) or 3
    if chance > 0 and IsPedArmed(ped, 4) and math.random(1, chance) == 1
        and GetResourceState('rp_vehicleprops') == 'started' then
        pcall(function() exports.rp_vehicleprops:dropHeldWeapon() end)
    end
    local t = (C.RagdollTime or { 1200, 2600 })
    local duration = math.random(t[1], t[2])
    SetPedToRagdoll(ped, duration, duration, 0, false, false, false)
    debug('chute (%d ms)', duration)
    return true
end

local function run()
    if running then return end
    running = true
    CreateThread(function()
        while episode and GetGameTimer() < episode.untilTime do
            Wait(randomBetween(settings(episode.level).Every, { 3, 10 }))
            if not episode or GetGameTimer() >= episode.untilTime then break end
            if IsEntityDead(PlayerPedId()) then episode = nil break end
            fall()
        end
        episode, running = nil, false
    end)
end

local function onBullet()
    local now = GetGameTimer()
    hits[#hits + 1] = now
    prune(hits, (C.BulletWindow or 20) * 1000, now)
    local around = shotCount(now)
    local level = levelOf(#hits, around)
    debug('balle reçue : %d balle(s), %d tir(s) à moins de %.0f m -> %s', #hits, around, C.ShotRange or 30.0, tostring(level))
    if not level then return end
    local untilTime = now + (settings(level).Duration or 15) * 1000
    if episode then
        -- période en cours : jamais abaissée, prolongée si la nouvelle finit plus tard
        if LEVELS[episode.level] > LEVELS[level] then level = episode.level end
        untilTime = math.max(untilTime, episode.untilTime)
    end
    episode = { level = level, untilTime = untilTime }
    run()
end

AddEventHandler('rp_weaponscontrol:shotNear', function(n, d)
    if (tonumber(d) or 999) > (C.ShotRange or 30.0) then return end
    local now = GetGameTimer()
    shots[#shots + 1] = { at = now, n = math.max(1, math.floor(tonumber(n) or 1)) }
    if #shots > 400 then table.remove(shots, 1) end
end)

AddEventHandler('rp_weaponscontrol:bulletHit', onBullet)

-- Réapparu / soigné (rp_revive) : la période s'arrête
AddEventHandler('playerSpawned', function() episode, hits = nil, {} end)

RPAdrenaline = { level = function() return episode and episode.level end, levelOf = levelOf, fall = fall } -- tests
