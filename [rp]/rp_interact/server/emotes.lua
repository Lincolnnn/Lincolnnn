--[[
    RP Interact - Emotes lues dans le mode d'emotes du serveur (RPEMOTES / rpemotes / rpemotes-reborn)
    ---------------------------------------------------------------------------------------------------
    Les emotes utilisées par ce script (menotté2, tenirlebras, serendre17 / 3 / 6…) sont
    lancées avec la commande du mode d'emotes ("/e nom"). Pour savoir si l'emote est toujours jouée
    (et la relancer sans en jouer une AUTRE), il faut son animation exacte : le serveur la lit
    directement dans les fichiers du mode d'emotes, au démarrage (et quand il redémarre).

    Résultat publié pour tous les clients : GlobalState.rpiEmotes = {
        resource = 'rpemotes',                  -- nom réel de la ressource (pour ses exports)
        list = { ['menotté2'] = { dict, clip, loop, moving, scenario } , ... },
    }
    Une emote introuvable n'est pas bloquante : le client utilise alors les animations de secours de
    config.lua (SeatedAnim) seulement s'il n'y a aucun mode d'emotes, et sinon ne relance
    l'emote que si le mode d'emotes indique qu'aucune emote n'est jouée.
]]

local Config = InteractConfig

-- Fichiers connus des différentes versions de rpemotes (en plus de ceux du fxmanifest)
local KNOWN_FILES = {
    'client/AnimationList.lua', 'client/AnimationListCustom.lua', 'client/CustomEmotes.lua',
    'AnimationList.lua', 'AnimationListCustom.lua', 'CustomEmotes.lua',
    'shared/AnimationList.lua', 'shared/AnimationListCustom.lua', 'config.lua',
}

--- Nom de l'emote d'une commande ("e menotté2" -> "menotté2")
local function emoteName(command)
    if type(command) ~= 'string' then return nil end
    local name = command:match('^%s*/?e%s+(%S+)') or command:match('^%s*(%S+)%s*$')
    return name and name:lower() or nil
end

--- Emotes à rechercher : celles de config.lua (Emotes + Surrender)
local function wantedEmotes()
    local list, seen = {}, {}
    local function add(command)
        local name = emoteName(command)
        if name and name ~= 'c' and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    for key, command in pairs(Config.Emotes or {}) do
        if key ~= 'cancel' then add(command) end
    end
    for _, s in ipairs(Config.Surrender or {}) do add(s.emote) end
    return list
end

--- Ressource du mode d'emotes : Config.EmotesResource, sinon détection automatique
local function findEmoteResource()
    local wanted = Config.EmotesResource
    if type(wanted) == 'string' and wanted ~= '' and wanted ~= 'auto' then
        return GetResourceState(wanted) ~= 'missing' and wanted or nil
    end
    local best, bestScore = nil, 0
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name and GetResourceState(name) ~= 'missing' then
            local lower = name:lower()
            local score = (lower == 'rpemotes' and 4) or (lower:find('rpemotes', 1, true) and 3)
                or (lower:find('dpemotes', 1, true) and 2) or (lower:find('emote', 1, true) and 1) or 0
            if score > bestScore then best, bestScore = name, score end
        end
    end
    return best
end

--- Fichiers Lua à lire : ceux du fxmanifest (sans les jokers), les fichiers connus, Config.EmoteFiles
local function filesOf(resource)
    local list, seen = {}, {}
    local function add(path)
        if type(path) == 'string' and path:sub(-4) == '.lua' and not seen[path] then
            seen[path] = true
            list[#list + 1] = path
        end
    end
    for _, key in ipairs({ 'client_script', 'shared_script', 'file' }) do
        for i = 0, GetNumResourceMetadata(resource, key) - 1 do
            local entry = GetResourceMetadata(resource, key, i)
            if entry and entry:find('*', 1, true) then
                -- Joker ("client/*.lua") : on essaie les noms connus dans ce dossier
                local dir = entry:match('^(.-)[^/]*$') or ''
                for _, known in ipairs(KNOWN_FILES) do add(dir .. known:match('[^/]+$')) end
            else
                add(entry)
            end
        end
    end
    for _, path in ipairs(KNOWN_FILES) do add(path) end
    for _, path in ipairs(Config.EmoteFiles or {}) do add(path) end
    return list
end

local function escapePattern(text)
    return (text:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%0'))
end

--- Bloc { ... } (accolades équilibrées) qui commence à la position `start` (une "{")
local function blockAt(content, start)
    local depth = 0
    for i = start, math.min(#content, start + 6000) do
        local c = content:sub(i, i)
        if c == '{' then
            depth = depth + 1
        elseif c == '}' then
            depth = depth - 1
            if depth == 0 then return content:sub(start, i) end
        end
    end
    return nil
end

--- Définition d'une emote dans un fichier : ["nom"] = { "dict", "anim", "Label", AnimationOptions = {...} }
--- (ou dict = "...", anim = "..." selon les versions ; "Scenario" pour les scénarios)
local function parseEmote(content, name)
    local key = escapePattern(name)
    for _, quote in ipairs({ '"', "'" }) do
        local pattern = '%[%s*' .. quote .. key .. quote .. '%s*%]%s*=%s*{'
        local _, finish = content:lower():find(pattern)
        if finish then
            local block = blockAt(content, finish)
            if block then
                local dict, clip = block:match('^{%s*["\']([^"\']+)["\']%s*,%s*["\']([^"\']+)["\']')
                if not dict then
                    dict = block:match('[%s,{]dict%s*=%s*["\']([^"\']+)["\']')
                    clip = block:match('[%s,{]anim%s*=%s*["\']([^"\']+)["\']')
                end
                if dict and clip then
                    local scenario = dict == 'Scenario' or dict == 'MaleScenario' or dict == 'ScenarioObject'
                    return {
                        dict = dict, clip = clip, scenario = scenario or nil,
                        loop = block:find('EmoteLoop%s*=%s*true') ~= nil,
                        moving = block:find('EmoteMoving%s*=%s*true') ~= nil,
                    }
                end
            end
        end
    end
    return nil
end

-- =========================================================================
-- INDEX COMPLET des emotes (pour /copyped : reconnaître l'animation que joue le joueur et la recopier, avec les
-- props de l'emote). Construit à la première demande, gardé jusqu'au prochain redémarrage du mode d'emotes.
-- Envoyé au client qui le demande, une fois (événement "latent" : en arrière-plan, sans gêner le jeu).
-- =========================================================================
local fullIndex = nil -- { { n = nom, d = dict, c = clip, s = scénario, l = boucle, m = haut du corps, p = props } }

local function numbers(text)
    local list = {}
    for n in (text or ''):gmatch('%-?%d*%.?%d+') do list[#list + 1] = tonumber(n) end
    return list
end

--- Props d'une emote : AnimationOptions Prop / PropBone / PropPlacement (et SecondProp…)
local function propsOf(block)
    local props = {}
    for _, prefix in ipairs({ '[%s,{]', 'Second' }) do
        local model = block:match(prefix .. 'Prop%s*=%s*["\']([^"\']+)["\']')
        if model then
            local bone = tonumber(block:match(prefix .. 'PropBone%s*=%s*(%-?%d+)'))
            local placement = block:match(prefix .. 'PropPlacement%s*=%s*(%b{})')
            props[#props + 1] = { model, bone or 60309, numbers(placement) }
        end
    end
    return #props > 0 and props or nil
end

local function emoteFiles(resource)
    local contents = {}
    for _, path in ipairs(filesOf(resource)) do
        local content = LoadResourceFile(resource, path)
        if content then contents[#contents + 1] = content end
    end
    return contents
end

local function buildIndex()
    if fullIndex then return fullIndex end
    fullIndex = {}
    local resource = findEmoteResource()
    if not resource then return fullIndex end
    local seen = {}
    local contents = emoteFiles(resource)
    -- dernier fichier lu en premier : sa définition l'emporte (fichiers "custom" de rpemotes)
    for i = #contents, 1, -1 do
        local content = contents[i]
        for name, start in content:gmatch('%[%s*["\']([^"\'%]]+)["\']%s*%]%s*=%s*(){') do
            local key = name:lower()
            if not seen[key] then
                local block = blockAt(content, start)
                local dict, clip
                if block then dict, clip = block:match('^{%s*["\']([^"\']+)["\']%s*,%s*["\']([^"\']+)["\']') end
                if dict and clip then
                    seen[key] = true
                    local scenario = dict == 'Scenario' or dict == 'MaleScenario' or dict == 'ScenarioObject'
                    fullIndex[#fullIndex + 1] = {
                        n = name, d = dict, c = clip, s = scenario or nil,
                        l = block:find('EmoteLoop%s*=%s*true') ~= nil or nil,
                        m = block:find('EmoteMoving%s*=%s*true') ~= nil or nil,
                        p = propsOf(block),
                    }
                end
            end
        end
    end
    print(('^5[RP Interact]^0 /copyped : %d emote(s) indexée(s) dans "%s".'):format(#fullIndex, resource))
    return fullIndex
end

local indexAsked = {}
RegisterNetEvent('rp_interact:emoteIndex', function()
    local src = source
    local now = GetGameTimer()
    if indexAsked[src] and now - indexAsked[src] < 10000 then return end
    indexAsked[src] = now
    TriggerLatentClientEvent('rp_interact:emoteIndex', src, 250000, buildIndex())
end)
AddEventHandler('playerDropped', function() indexAsked[source] = nil end)

local function scan()
    fullIndex = nil -- reconstruit à la prochaine demande
    local resource = findEmoteResource()
    if not resource then
        GlobalState.rpiEmotes = { list = {} }
        print('^3[RP Interact] Aucun mode d\'emotes trouvé (RPEMOTES / rpemotes) : animations de secours de config.lua utilisées.^0')
        return
    end

    local wanted = wantedEmotes()
    local found, missing = {}, {}
    local contents = {}
    for _, path in ipairs(filesOf(resource)) do
        local content = LoadResourceFile(resource, path)
        if content then contents[#contents + 1] = content end
    end
    -- Les fichiers "custom" sont lus en dernier par rpemotes : la dernière définition l'emporte
    for _, name in ipairs(wanted) do
        for _, content in ipairs(contents) do
            local emote = parseEmote(content, name)
            if emote then found[name] = emote end
        end
        if not found[name] then missing[#missing + 1] = name end
    end

    GlobalState.rpiEmotes = { resource = resource, list = found }
    local names = {}
    for name, e in pairs(found) do names[#names + 1] = ('%s (%s / %s)'):format(name, e.dict, e.clip) end
    table.sort(names)
    print(('^5[RP Interact]^0 Emotes lues dans "%s" (%d fichier(s)) : %s'):format(resource, #contents,
        #names > 0 and table.concat(names, ', ') or 'aucune'))
    if #missing > 0 then
        print(('^3[RP Interact] Emote(s) introuvable(s) dans "%s" : %s. Vérifiez le nom dans config.lua (Emotes, Surrender) ou ajoutez le fichier qui les définit dans EmoteFiles.^0')
            :format(resource, table.concat(missing, ', ')))
    end
end

CreateThread(scan)

-- Le mode d'emotes (re)démarre après ce script : nouvelle lecture
AddEventHandler('onResourceStart', function(name)
    if name ~= GetCurrentResourceName() and name:lower():find('emote', 1, true) then scan() end
end)

-- Pour les tests / la console : "rpi_emotes" relit les fichiers et affiche le résultat
RegisterCommand('rpi_emotes', function(src)
    if src == 0 or IsPlayerAceAllowed(src, Config.AdminAce) then scan() end
end, false)

RPIEmotes = { scan = scan, parse = parseEmote, name = emoteName, index = buildIndex }
