--[[
    RP Chat - /modiftouche : changer les touches de nos scripts sans passer par le menu pause (client)
    ---------------------------------------------------------------------------------------------------
    FiveM ne permet pas à un script de changer la touche d'un raccourci (RegisterKeyMapping) : seul le menu pause le
    peut. Ici, pour le joueur qui le demande :
      - un NOUVEAU raccourci est créé sur la touche choisie (Raccourcis clavier > FiveM : « Touche perso : … »), il
        lance la même action que l'original ;
      - l'ANCIENNE touche ne fait plus rien : chaque script charge keyguard.lua, qui demande à ce chat
        (export keyAllowed) si sa commande peut partir ; elle ne part plus que par la nouvelle touche, par le chat
        (/mdc tapé dans le chat) ou par un autre script ;
      - le choix est gardé chez le joueur (KVP rpchat_keys) et refait à chaque connexion.
    Catalogue des scripts et de leurs spécificités : touches.lua. Aucune boucle.
]]

local KVP = 'rpchat_keys'
local SCRIPTS = RPChatKeyScripts or {}
local ALIASES = RPChatKeyAliases or {}

local actions = {}    -- ['MDC.ouvrir'] = { script, action }
local overrides = {}  -- ['MDC.ouvrir'] = 'F5'
local blocked = {}    -- [commande sans + / -] = true : l'ancienne touche ne la lance plus
local allowedAt = {}  -- [commande] = GetGameTimer() : lancée par la nouvelle touche ou par le chat
local registered = {} -- [nom du nouveau raccourci] = true

local function fold(s)
    s = tostring(s or ''):lower()
    for a, b in pairs({ ['é'] = 'e', ['è'] = 'e', ['ê'] = 'e', ['ë'] = 'e', ['à'] = 'a', ['â'] = 'a', ['î'] = 'i', ['ï'] = 'i',
        ['ô'] = 'o', ['ù'] = 'u', ['û'] = 'u', ['ç'] = 'c', ['œ'] = 'oe' }) do s = s:gsub(a, b) end
    return (s:gsub('[%s%-_\'’]', ''))
end
local function base(cmd) return (tostring(cmd or ''):gsub('^[%+%-]', '')) end

for _, script in ipairs(SCRIPTS) do
    for _, action in ipairs(script.actions or {}) do
        actions[script.name .. '.' .. action.id] = { script = script, action = action }
    end
end

local function system(text, kind)
    if RPChatSystem then return RPChatSystem(text, kind) end -- message dans le chat (client/client.lua)
    print('[Touches] ' .. text)
end

--- La commande peut-elle partir ? (keyguard.lua des autres scripts) : oui, sauf si le joueur a déplacé sa touche et
--- qu'elle ne vient ni de la nouvelle touche ni du chat
local function allowed(cmd)
    local b = base(cmd)
    if not blocked[b] then return true end
    return allowedAt[b] ~= nil and GetGameTimer() - allowedAt[b] < 500
end
exports('keyAllowed', allowed)

RPChatKeys = { allowed = allowed }
--- Commande tapée dans le chat (/mdc…) : jamais bloquée
function RPChatKeys.typed(command) allowedAt[base(command)] = GetGameTimer() end

local function run(cmd)
    allowedAt[base(cmd)] = GetGameTimer()
    ExecuteCommand(cmd)
end

--- Nouveau raccourci sur `key` pour cette action (créé une fois par touche ; inactif si la touche a changé depuis)
local function bind(id, key)
    local entry = actions[id]
    local a = entry.action
    local name = ('rpk_%s_%s'):format((fold(id):gsub('%.', '_')), key:lower())
    if registered[name] then return end
    registered[name] = true
    local label = ('Touche perso : %s %s — %s'):format(entry.script.name, a.id, a.label)
    local device = a.device or (key:match('^MOUSE_') and 'mouse_button' or 'keyboard')
    if a.hold then
        RegisterCommand('+' .. name, function() if overrides[id] == key then run('+' .. a.cmd) end end, false)
        RegisterCommand('-' .. name, function() if overrides[id] == key then run('-' .. a.cmd) end end, false)
        RegisterKeyMapping('+' .. name, label, device, key)
    else
        RegisterCommand(name, function() if overrides[id] == key then run(a.cmd) end end, false)
        RegisterKeyMapping(name, label, device, key)
    end
end

local function apply(id, key)
    local a = actions[id].action
    overrides[id] = key
    blocked[a.cmd] = key and true or nil
    if key then bind(id, key) end
end

local function save()
    SetResourceKvp(KVP, json.encode(overrides))
end

--- Nom de touche FiveM ('Z', 'F5', 'LSHIFT', 'MOUSE_RIGHT'…) ou nil
local VALID = {}
for _, k in ipairs({ 'SPACE', 'RETURN', 'BACK', 'TAB', 'CAPITAL', 'LSHIFT', 'RSHIFT', 'LCONTROL', 'RCONTROL', 'LMENU', 'RMENU',
    'UP', 'DOWN', 'LEFT', 'RIGHT', 'HOME', 'END', 'PAGEUP', 'PAGEDOWN', 'INSERT', 'DELETE', 'MULTIPLY', 'ADD', 'SUBTRACT',
    'DECIMAL', 'DIVIDE', 'MOUSE_LEFT', 'MOUSE_RIGHT', 'MOUSE_MIDDLE', 'MOUSE_EXTRABTN1', 'MOUSE_EXTRABTN2' }) do VALID[k] = true end
local function keyName(text)
    local k = tostring(text or ''):upper():gsub('[%s%-_]', '')
    k = ALIASES[k] or ALIASES[fold(text):upper()] or k
    if VALID[k] or k:match('^[A-Z]$') or k:match('^[0-9]$') then return k end
    local f = tonumber(k:match('^F(%d%d?)$'))
    if f and f >= 1 and f <= 24 then return k end
    local n = tonumber(k:match('^NUMPAD(%d)$'))
    if n then return k end
    return nil
end

local function currentKey(id)
    return overrides[id] or actions[id].action.key
end

local function findScript(text)
    local f = fold(text)
    for _, s in ipairs(SCRIPTS) do
        if fold(s.name) == f then return s end
    end
    return nil
end

local function started(script) return GetResourceState(script.res) == 'started' end

local function listScripts()
    local names = {}
    for _, s in ipairs(SCRIPTS) do
        if started(s) then names[#names + 1] = s.name end
    end
    system(('Scripts : %s. Tapez /modiftouche [script] pour ses touches.'):format(table.concat(names, ', ')))
    system('Utilisation : /modiftouche [script] [spécificité] [touche]  (ex. /modiftouche MDC ouvrir F5) ; « defaut » : touche d\'origine.')
end

local function listActions(s)
    local parts = {}
    for _, a in ipairs(s.actions) do
        local id = s.name .. '.' .. a.id
        local key = currentKey(id)
        parts[#parts + 1] = ('%s = %s%s'):format(a.id, key ~= '' and key or 'aucune', overrides[id] and ' (perso)' or '')
    end
    system(('%s (%s) : %s.'):format(s.name, s.label, table.concat(parts, ' ; ')))
end

--- Touches déjà utilisées par une autre spécificité (avertissement seulement)
local function conflicts(id, key)
    local list = {}
    for other, e in pairs(actions) do
        if other ~= id and currentKey(other) == key and started(e.script) then list[#list + 1] = e.script.name .. ' ' .. e.action.id end
    end
    table.sort(list)
    return list
end

RegisterCommand('modiftouche', function(_, args)
    if not args[1] then return listScripts() end
    local s = findScript(args[1])
    if not s then return system(('Script inconnu : « %s ». /modiftouche pour la liste.'):format(args[1]), 'error') end
    if not started(s) then return system(('%s n\'est pas démarré sur ce serveur.'):format(s.name), 'error') end
    if not args[2] then return listActions(s) end
    local a
    for _, x in ipairs(s.actions) do if fold(x.id) == fold(args[2]) then a = x end end
    if not a then
        local ids = {}
        for _, x in ipairs(s.actions) do ids[#ids + 1] = x.id end
        return system(('%s : spécificité inconnue « %s ». Possibles : %s.'):format(s.name, args[2], table.concat(ids, ', ')), 'error')
    end
    local id = s.name .. '.' .. a.id
    if not args[3] then
        return system(('%s %s (%s) : touche %s. /modiftouche %s %s [touche] pour la changer.'):format(s.name, a.id, a.label,
            currentKey(id) ~= '' and currentKey(id) or 'aucune', s.name, a.id))
    end
    if fold(args[3]) == 'defaut' or fold(args[3]) == 'default' or fold(args[3]) == 'reset' then
        apply(id, nil)
        save()
        return system(('%s %s : touche d\'origine (%s).'):format(s.name, a.id, a.key ~= '' and a.key or 'aucune'), 'success')
    end
    local key = keyName(args[3])
    if not key then
        return system(('Touche inconnue : « %s ». Exemples : A à Z, 0 à 9, F1 à F12, ESPACE, ENTREE, MAJ, CTRL, ALT, HAUT, BAS, GAUCHE, DROITE, NUMPAD0, CLICDROIT.'):format(args[3]), 'error')
    end
    if key == 'ESCAPE' then return system('Échap ne peut pas être utilisée.', 'error') end
    apply(id, key)
    save()
    local c = conflicts(id, key)
    system(('%s %s : nouvelle touche %s (enregistrée, pour vous seulement ; l\'ancienne touche ne fait plus rien).'):format(s.name, a.id, key), 'success')
    if #c > 0 then system(('Attention : %s est aussi la touche de %s.'):format(key, table.concat(c, ', ')), 'error') end
end, false)

-- Connexion / redémarrage : touches gardées refaites
do
    local ok, data = pcall(json.decode, GetResourceKvpString(KVP) or '')
    for id, key in pairs(ok and type(data) == 'table' and data or {}) do
        if actions[id] and type(key) == 'string' and keyName(key) then apply(id, keyName(key)) end
    end
end

RPChatKeys.overrides = function() return overrides end -- (tests)
