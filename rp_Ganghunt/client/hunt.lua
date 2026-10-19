--[[
    RP Ganghunt - client : la chasse
    --------------------------------
    Le joueur qui lance la chasse fait apparaître les ennemis lui-même (il en garde le contrôle réseau : ils ne
    passent pas à un autre joueur). Une vague = le nombre d'ennemis choisi (1 à 30) : en convoi de véhicules s'ils
    sont cochés, l'hélicoptère au-dessus du même point s'il est coché, le reste à pied (spawn.lua). Leur
    comportement (repéré / recherche, poursuite, grenades, corps à corps) : ai.lua.
    Vague éliminée : la suivante quelques secondes plus tard ; dernière vague éliminée : chasse réussie ; joueur mort
    ou /ganghunt stop : chasse terminée, tous les ennemis et leurs véhicules retirés.
    HUD en haut au milieu : état (REPÉRÉ / ILS VOUS CHERCHENT), barre de la vague, barre de la chasse.
    Musique (option) : la musique de poursuite / recherche de la police du jeu (indice de recherche caché).
    Vagues : à la fin de la précédente (7 s après) ou après un délai choisi (même si la précédente n'est pas éliminée).
    Le joueur ne doit jamais être « ignoré » pendant une chasse (sinon ils cessent de tirer) : redonné chaque seconde.
    Performance : aucune chasse -> aucune boucle. Pendant une chasse : une vérification par seconde (+ une boucle par
    image seulement avec la musique, pour cacher les étoiles).
]]

GH = GH or {}
local Config = GanghuntConfig

local session = nil

function GH.active() return session ~= nil end
function GH.session() return session end

local function notify(text)
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started'
        and pcall(function() exports[chat]:addPrivate({ title = 'Ganghunt', text = text }) end) then
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end
GH.notify = notify

--- Un ennemi mort : compté une seule fois (barre de la vague et de la chasse)
function GH.countKill(s, h)
    if h.counted then return end
    h.counted = true
    s.killed = s.killed + 1
    if h.wave == s.wave then s.waveKilled = s.waveKilled + 1 end
end

-- =========================================================================
-- HUD (en haut au milieu)
-- =========================================================================
local function hud(s, alive)
    if not s then return SendNUIMessage({ action = 'hud', data = { show = false } }) end
    local now = GetGameTimer()
    local state = s.waiting and 'waiting' or s.alert
    SendNUIMessage({ action = 'hud', data = {
        show = true, faction = s.faction.label, wave = s.wave, waves = s.waves, alive = alive or s.alive or 0,
        waveTotal = s.spawning and s.waveSize or math.max(s.waveSpawned, s.waveKilled), waveKilled = s.waveKilled,
        huntTotal = s.waves * s.waveSize - s.short, huntKilled = s.killed, state = state,
        lost = state == 'search' and math.floor((now - (s.lastSeen or now)) / 1000) or nil,
        next = (s.waiting or (s.waveMode == 'timer' and s.wave < s.waves))
            and math.max(0, math.ceil(((s.nextWaveAt or now) - now) / 1000)) or nil,
    } })
end

-- =========================================================================
-- MUSIQUE : indice de recherche « fantôme » (musique de poursuite du jeu, étoiles cachées)
-- Repéré : étoiles pleines, poursuite signalée chaque seconde (musique de poursuite) ; recherche : étoiles qui
-- clignotent (musique de recherche) ; neutres : aucun indice. Pas d'indice remis sans arrêt : la musique ne
-- redémarre que quand il est de nouveau repéré.
-- =========================================================================
local function wantedOn(s)
    local player = PlayerId()
    if GetMaxWantedLevel() < s.stars then SetMaxWantedLevel(5) end
    if GetPlayerWantedLevel(player) < s.stars then
        SetPlayerWantedLevel(player, s.stars, false)
        SetPlayerWantedLevelNow(player, false)
    end
end

local function musicStart(s)
    local M = Config.Music or {}
    local player = PlayerId()
    s.stars = math.min(5, (s.category == 'forces' and (M.ForcesStars or 4) or (M.Stars or 3)) + (s.withHeli and 1 or 0))
    SetAudioFlag('WantedMusicDisabled', false)
    SetAudioFlag('WantedMusicOnMission', true)
    SetAudioFlag('PoliceScannerDisabled', true)
    SetDispatchCopsForPlayer(player, false)
    SetPoliceRadarBlips(false)
    CreateThread(function()
        while session == s do
            HideHudComponentThisFrame(1) -- étoiles : l'état est affiché par le HUD de la chasse
            -- repéré : signalé à CHAQUE image (sinon le jeu, ne voyant aucun policier, bascule sans cesse entre
            -- « vu » et « recherche » : minimap qui clignote rouge / bleu par à-coups, musique hachée)
            if s.alert == 'engaged' and GetPlayerWantedLevel(player) > 0 then ReportPoliceSpottedPlayer(player) end
            Wait(0)
        end
    end)
end

local function musicTick(s)
    local player = PlayerId()
    if s.alert == 'engaged' then
        wantedOn(s)
    elseif s.alert == 'calm' and GetPlayerWantedLevel(player) > 0 then
        ClearPlayerWantedLevel(player)
        SetPlayerWantedLevelNow(player, false)
    end
end

local function musicStop()
    local player = PlayerId()
    ClearPlayerWantedLevel(player)
    SetPlayerWantedLevelNow(player, false)
    SetDispatchCopsForPlayer(player, true)
    SetPoliceRadarBlips(true)
    SetAudioFlag('WantedMusicOnMission', false)
    SetAudioFlag('PoliceScannerDisabled', false)
end

--- Changement d'état : la musique suit (poursuite / recherche / rien)
function GH.onAlert(state)
    local s = session
    if not s or not s.music then return end
    local player = PlayerId()
    if state == 'engaged' then
        wantedOn(s)
        ReportPoliceSpottedPlayer(player)
    elseif state == 'search' then
        if GetPlayerWantedLevel(player) > 0 then ForceStartHiddenEvasion(player) end
    else
        ClearPlayerWantedLevel(player)
        SetPlayerWantedLevelNow(player, false)
    end
end

--- Chaque seconde : le jeu (ou un autre script, ex. rp_NPCcontrol) ne doit pas faire ignorer le joueur, sinon les
--- ennemis cessent de tirer (« police ignore player » vaut aussi pour les ennemis policiers / SWAT / militaires)
local function keepTargetable(s)
    local player = PlayerId()
    SetEveryoneIgnorePlayer(player, false)
    SetPoliceIgnorePlayer(player, false)
    -- sans la musique : jamais d'indice de recherche (ennemis policiers tués, etc.) -> pas de minimap rouge / bleu
    if not s.music then
        if GetMaxWantedLevel() ~= 0 then SetMaxWantedLevel(0) end
        if GetPlayerWantedLevel(player) > 0 then
            ClearPlayerWantedLevel(player)
            SetPlayerWantedLevelNow(player, false)
        end
    end
end

-- =========================================================================
-- VAGUES
-- =========================================================================
local function spawnWave(s)
    if not s or session ~= s then return end
    s.wave = s.wave + 1
    s.waiting, s.spawning = false, true
    s.waveKilled, s.waveSpawned = 0, 0
    GH.alertNewWave(s, GetGameTimer())
    hud(s)
    local remaining = s.waveSize
    local origin = nil
    if s.withVehicles then
        local reserve = s.withHeli and math.min(3, remaining - 1) or 0 -- la part de l'hélicoptère
        local placed
        placed, origin = GH.convoy(math.max(0, remaining - reserve))
        remaining = remaining - placed
    end
    if session ~= s then return end
    if s.withHeli and remaining > 0 then remaining = remaining - GH.crewHeli(math.min(3, remaining), origin) end
    if session ~= s then return end
    if remaining > 0 then GH.footGroups(remaining) end
    if session ~= s then return end
    s.spawning = false
    s.short = s.short + math.max(0, s.waveSize - s.waveSpawned) -- ennemis qui n'ont pas pu apparaître
    if s.waveMode == 'timer' then s.nextWaveAt = GetGameTimer() + s.waveTimer * 1000 end
    local tail = s.passive and not s.provoked and ' Ils n\'attaqueront que si vous les attaquez.' or ''
    notify(('Vague %d / %d : %d %s arrivent.%s'):format(s.wave, s.waves, s.waveSpawned, s.faction.label, tail))
    hud(s)
end

--- Fin de la chasse : tout est retiré (ennemis vivants ou morts, véhicules)
function GH.stop(message)
    if not session then return end
    local s = session
    session = nil
    for _, entity in ipairs(s.entities) do
        if DoesEntityExist(entity) then
            local blip = GetBlipFromEntity(entity)
            if blip and blip ~= 0 then RemoveBlip(blip) end
            SetEntityAsMissionEntity(entity, true, true)
            DeleteEntity(entity)
        end
    end
    GH.clearSearchBlip(s)
    if s.music then musicStop() end
    SetMaxWantedLevel(5) -- valeur du jeu (rp_NPCcontrol redonne aussitôt la sienne)
    LocalPlayer.state:set('rpGanghunt', false, false)
    TriggerServerEvent('rp_ganghunt:clear')
    TriggerEvent('rp_npccontrol:ganghunt', false) -- rp_NPCcontrol : ses réglages redonnés
    hud(nil)
    if message then notify(message) end
end

local function loop(s)
    CreateThread(function()
        while session == s do -- (une chasse arrêtée puis relancée : l'ancienne boucle s'arrête)
            if IsEntityDead(PlayerPedId()) then
                GH.stop('Vous êtes mort : la chasse est terminée.')
                break
            end
            local now = GetGameTimer()
            local alive = GH.think(now)
            if session ~= s then break end
            s.alive = alive
            if not s.spawning then
                if alive == 0 then GH.allDown(s) end -- (option « Neutres » : la suite arrive neutre)
                if alive == 0 and s.wave >= s.waves then
                    hud(s, 0)
                    GH.stop(('Chasse réussie : %d vague%s éliminée%s !'):format(s.waves, s.waves > 1 and 's' or '', s.waves > 1 and 's' or ''))
                    break
                end
                if s.waveMode == 'timer' then
                    -- après un délai : la vague suivante arrive à l'heure, éliminée ou non (place pour MaxAlive)
                    s.waiting = alive == 0
                    if now >= (s.nextWaveAt or 0) and alive + s.waveSize <= (Config.MaxAlive or 60) then
                        s.spawning = true
                        CreateThread(function() spawnWave(s) end)
                    end
                elseif alive == 0 and not s.waiting then
                    s.waiting = true
                    s.nextWaveAt = now + (Config.NextWaveDelay or 7000)
                    notify(('Vague %d éliminée. La suivante arrive…'):format(s.wave))
                    SetTimeout(Config.NextWaveDelay or 7000, function()
                        if session == s then CreateThread(function() spawnWave(s) end) end
                    end)
                end
            end
            keepTargetable(s)
            if s.music then musicTick(s) end
            hud(s, alive)
            Wait(Config.ManagerInterval or 1000)
        end
    end)
end

local function categoryOf(key)
    for _, category in ipairs(Config.Categories) do
        for _, f in ipairs(category.factions) do
            if f == key then return category.key end
        end
    end
    return 'gang'
end
local GRENADE_POOL = { gang = 'Gang', org = 'Org', forces = 'Forces' }

--- Lance une chasse : opts = { faction, waves, waveSize, weapons = { { name, pct } } | nil (aléatoire), vehicles,
--- heli, silencer, grenades, music, passive, waveMode = 'clear' | 'timer', waveTimer (s) }
function GH.start(opts)
    if session then return false, 'Une chasse est déjà en cours (/ganghunt stop pour l\'arrêter).' end
    local faction = Config.Factions[opts.faction]
    if not faction then return false, 'Faction inconnue.' end
    local waves = math.max(1, math.min(Config.MaxWaves or 10, math.floor(tonumber(opts.waves) or 1)))
    local waveSize = math.max(1, math.min(Config.MaxWaveSize or 30, math.floor(tonumber(opts.waveSize) or Config.WaveSize or 10)))
    local weapons = {}
    for _, w in ipairs(type(opts.weapons) == 'table' and opts.weapons or {}) do
        if #weapons >= (Config.MaxWeapons or 10) then break end
        local pct = tonumber(w.pct) or 0
        if GH.WEAPON_INFO[w.name] and pct > 0 then weapons[#weapons + 1] = { name = w.name, pct = pct } end
    end
    local WT = Config.WaveTimer or {}
    local timer = math.max(WT.Min or 15, math.min(WT.Max or 600, math.floor(tonumber(opts.waveTimer) or WT.Default or 60)))
    local category = categoryOf(opts.faction)
    local s = { faction = faction, key = opts.faction, category = GRENADE_POOL[category] and category or 'gang',
        waves = waves, waveSize = waveSize, wave = 0, weapons = weapons,
        withVehicles = opts.vehicles == true, withHeli = opts.heli == true,
        silencer = opts.silencer == true, grenades = opts.grenades == true, music = opts.music == true,
        passive = opts.passive == true, waveMode = opts.waveMode == 'timer' and 'timer' or 'clear', waveTimer = timer,
        hunters = {}, entities = {}, vehicles = {}, helis = {}, killed = 0, waveKilled = 0, waveSpawned = 0, short = 0,
        alert = opts.passive == true and 'calm' or 'engaged' }
    -- grenades de la faction : sa liste, sinon celle de sa catégorie
    s.faction = setmetatable({ grenades = faction.grenades or (Config.Grenades or {})[GRENADE_POOL[s.category]] }, { __index = faction })
    session = s
    GH.setHostile(not s.passive)
    -- rp_NPCcontrol : ne plus faire ignorer ce joueur (état gardé même si rp_NPCcontrol redémarre) + tout de suite
    LocalPlayer.state:set('rpGanghunt', true, false)
    TriggerEvent('rp_npccontrol:ganghunt', true)
    keepTargetable(s)
    if s.music then musicStart(s) end
    CreateThread(function()
        spawnWave(s)
        if session == s then loop(s) end
    end)
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and session then GH.stop() end
end)
