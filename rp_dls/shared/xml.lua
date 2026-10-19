--[[
    RP DLS - lecteur XML minimal (partagé client / serveur)
    -------------------------------------------------------
    Suffisant pour les fichiers de DLS (format carcols) : déclaration <?xml ?>, commentaires, balises
    ouvrantes / fermantes / auto-fermantes, attributs entre "" ou '', texte. Pas de DTD ni d'espaces de noms.
    Retourne un nœud racine { name, attrs, children, text } ; DLSXml.child / DLSXml.children pour y naviguer
    (noms de balises comparés sans tenir compte des majuscules).
]]

DLSXml = {}

local ENTITIES = { lt = '<', gt = '>', amp = '&', quot = '"', apos = "'" }

local function decode(s)
    return (s:gsub('&(#?x?)(%w+);', function(kind, code)
        if kind == '' then return ENTITIES[code] or ('&' .. code .. ';') end
        local n = tonumber(code, kind == '#x' and 16 or 10)
        return n and n < 128 and string.char(n) or ''
    end))
end

local function parseAttrs(s)
    local attrs = {}
    for key, _, value in s:gmatch('([%w_:%-%.]+)%s*=%s*(["\'])(.-)%2') do
        attrs[key:lower()] = decode(value)
    end
    return attrs
end

--- Analyse un texte XML. Retourne la racine, ou nil + message d'erreur
function DLSXml.parse(text)
    if type(text) ~= 'string' then return nil, 'fichier vide' end
    text = text:gsub('^\239\187\191', '')           -- BOM UTF-8
    text = text:gsub('<!%-%-.-%-%->', '')            -- commentaires
    text = text:gsub('<%?.-%?>', '')                 -- déclaration
    text = text:gsub('<!%[CDATA%[(.-)%]%]>', function(c) return (c:gsub('<', '&lt;'):gsub('>', '&gt;')) end)

    local root = { name = '#root', attrs = {}, children = {}, text = '' }
    local stack = { root }
    local pos = 1
    while true do
        local s, e, close, name, attrs, selfClose = text:find('<(/?)([%w_:%-%.]+)(.-)(/?)>', pos)
        if not s then break end
        local parent = stack[#stack]
        local between = text:sub(pos, s - 1)
        if between:find('%S') then parent.text = parent.text .. decode(between) end
        if close == '/' then
            if #stack <= 1 or parent.name:lower() ~= name:lower() then
                return nil, ('balise </%s> inattendue'):format(name)
            end
            parent.text = parent.text:match('^%s*(.-)%s*$')
            stack[#stack] = nil
        else
            local node = { name = name, attrs = parseAttrs(attrs), children = {}, text = '' }
            parent.children[#parent.children + 1] = node
            if selfClose ~= '/' then stack[#stack + 1] = node end
        end
        pos = e + 1
    end
    if #stack > 1 then return nil, ('balise <%s> non fermée'):format(stack[#stack].name) end
    return root
end

--- Premier enfant nommé `name` (sans tenir compte des majuscules)
function DLSXml.child(node, name)
    if not node then return nil end
    name = name:lower()
    for _, c in ipairs(node.children) do
        if c.name:lower() == name then return c end
    end
    return nil
end

--- Tous les enfants nommés `name` (tous les enfants si `name` est nil)
function DLSXml.children(node, name)
    local list = {}
    if not node then return list end
    name = name and name:lower()
    for _, c in ipairs(node.children) do
        if not name or c.name:lower() == name then list[#list + 1] = c end
    end
    return list
end

--- Valeur d'un enfant : attribut value="" (format carcols) ou texte de la balise
function DLSXml.value(node, name)
    local c = DLSXml.child(node, name)
    if not c then return nil end
    if c.attrs.value ~= nil then return c.attrs.value end
    if c.text ~= '' then return c.text end
    return nil
end
