--[[
    RP Interact - Voiture (spawn, radio) et Équipements (serveur)
    -------------------------------------------------------------
    - Fichiers JSON du dossier data/ (remplis à la main, relus avec la commande console "rpi_vehicles") :
      vehicle.json (véhicules du menu Voiture > Spawn), loadouts.json (armes du menu Équipements),
      outfits.json (tenues du menu /eup), modifoutfits.json (pièces de "Modifier ma tenue" par service). Seuls les véhicules de vehicle.json peuvent être demandés ;
      véhicules de police réservés aux policiers en service si SpawnPoliceOnly.
    - Radio et /musique : un état "rpiRadio" par source de son (véhicule, joueur, objet ; lieu : GlobalState.rpiPlaces)
      = { url, start (heure UTC de lancement, s), volume (0-100), queue (file "Écouter ensuite", 5 liens max),
      history (10 morceaux précédents, gardés même quand tout est fini), seq (n° du morceau), paused (position en
      pause, s), stopped (arrêtée / tout fini), music (/musique : créateur, type, coordonnées d'un lieu) }, lu par tous
      les clients (chacun joue le son selon sa distance, les vitres / portières, l'endroit). Véhicule : réglable par
      les places AVANT ou un joueur collé au véhicule ; musique : son créateur, le joueur qui la porte, ou quiconque
      à 6 m. Lancer, file, pause / reprise, début du morceau, précédent / déjà écoutés (même finis), suivant,
      arrêter, volume. À la fin d'un morceau (signalée par un joueur qui l'entend), le suivant démarre.
    - Équipements : armes de loadouts.json ; tenues de outfits.json (menu /eup, vérification de l'accès) ;
      pièces de modifoutfits.json (celles des polices non envoyées si les tenues de police sont réservées).
    Aucune boucle.
]]

local Config = InteractConfig
local S = RPIServer
-- Les deux polices du MDC (rp_mdc : Washington State Patrol, King County Sheriff Office), par nom ou par sigle
local SERVICES = {
    ['washington state patrol'] = 'wsp', wsp = 'wsp',
    ['king county sheriff office'] = 'kcso', ["king county sheriff's office"] = 'kcso', kcso = 'kcso',
}
-- Anciens services (équipements modifiés déjà enregistrés) : repris par la police la plus proche
local LEGACY_KEYS = { gsp = 'wsp', fcso = 'kcso', apd = 'wsp' }

-- =========================================================================
-- FICHIERS JSON (data/*.json) : remplis à la main, relus avec "rpi_vehicles" (console)
-- =========================================================================
local function trim(text) return (tostring(text or '')):gsub('^%s+', ''):gsub('%s+$', '') end

--- Champ d'un objet JSON, quelle que soit la casse de la clé ("Name", "name", "NAME")
local function field(object, name)
    if type(object) ~= 'table' then return nil end
    if object[name] ~= nil then return object[name] end
    local lower = name:lower()
    for k, v in pairs(object) do
        if type(k) == 'string' and k:lower() == lower then return v end
    end
    return nil
end

--- Clé qui commence chaque élément d'une liste ("Weapon" d'une arme, "spawnName" d'un véhicule…), sans tenir
--- compte des majuscules : motif Lua (« Weapon » -> "[Ww][Ee]…")
local ELEMENT_KEYS = { 'Weapon', 'spawnName', 'Service' }
local function anyCase(word) return (word:gsub('%a', function(c) return '[' .. c:upper() .. c:lower() .. ']' end)) end

--- Accolade ouvrante oubliée au début d'un élément (oubli fréquent en éditant à la main) :
---   }, "Weapon": "..."   ->   }, { "Weapon": "..."
--- Seulement quand le fichier ne se lit pas tel quel ; renvoie le texte réparé et le nombre d'accolades ajoutées
local function repairMissingBraces(raw)
    local added = 0
    for _, key in ipairs(ELEMENT_KEYS) do
        local n
        raw, n = raw:gsub('(}%s*,%s*)("' .. anyCase(key) .. '"%s*:)', '%1{ %2')
        added = added + n
    end
    return raw, added
end

--- Liste lue dans un fichier JSON (nil + message dans la console si absent / invalide)
local function readJsonList(path)
    local raw = LoadResourceFile(GetCurrentResourceName(), path)
    if not raw then
        print(('^3[RP Interact] %s introuvable.^0'):format(path))
        return nil
    end
    -- virgule en trop avant ] ou } (oubli fréquent en éditant à la main) : tolérée
    raw = raw:gsub(',(%s*[%]}])', '%1')
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        -- accolade « { » oubliée au début d'une arme / d'un véhicule : ajoutée, puis nouvel essai
        local fixed, added = repairMissingBraces(raw)
        if added > 0 then
            local ok2, data2 = pcall(json.decode, fixed)
            if ok2 and type(data2) == 'table' then
                print(('^3[RP Interact] %s : %d accolade(s) « { » oubliée(s) au début d\'un élément, ajoutée(s) pour la '
                    .. 'lecture (fichier lu). Corrigez le fichier : chaque élément commence par { et finit par },^0'):format(path, added))
                return data2
            end
        end
        print(('^1[RP Interact] %s : JSON invalide (accolade ou guillemet manquant…). Fichier ignoré. Détail : %s^0')
            :format(path, tostring(data):gsub('^.-:%d+: ', '')))
        return nil
    end
    return data
end

-- =========================================================================
-- VÉHICULES (data/vehicle.json ; à défaut, l'ancien data/vehicles.json)
--   { "vehicles": [ { "spawnName": "wspcharger", "Principale": "Police",
--       "subCategory": "Washington State Patrol", "menuName": "Dodge Charger 2020",
--       "extras": { "1": true }, "livery": 0, "windowTint": 1, "plateType": "NORTH_YANKTON", "plate": "WSP ####" } ] }
--   Principale : catégorie du menu (ex. Police, Civil) ; subCategory : groupe dans cette catégorie ;
--   extras : n° d'extra -> true (activé) / false (désactivé) ; s'il y en a, ceux qui ne sont pas listés sont
--   désactivés ; {} : extras d'origine du véhicule. Un même spawnName peut apparaître plusieurs fois (extras
--   différents). windowTint (facultatif) : teinte des vitres imposée, 0 aucune, 1 noir pur, 2 fumé foncé,
--   3 fumé clair, 4 d'origine, 5 limousine, 6 verte. plateType (facultatif) : style de plaque, par nom
--   (BLUE_ON_WHITE_1, BLUE_ON_WHITE_2, BLUE_ON_WHITE_3, YELLOW_ON_BLACK, YELLOW_ON_BLUE, NORTH_YANKTON) ou par
--   numéro du jeu (0 à 12 selon la version du jeu). plate (facultatif) : texte de la plaque, 8 caractères au plus
--   (lettres, chiffres, espaces) ; « # » = un chiffre au hasard, « ? » = une lettre au hasard (ex. "WSP ####" :
--   WSP 4821) ; sans plate : plaque du jeu. Ancien format accepté : [ { "Code", "Service", "Name", "Livery", "Extras": [1, 2] } ].
--   Catégorie "Police" : réservée aux policiers en service si SpawnPoliceOnly.
-- =========================================================================
local Vehicles, byId = {}, {}

--- Extras : { "1": true, "2": false } ou [1, 2] (ancien format) -> { on = { [n] = true|false }, strict = bool }
local function readExtras(raw)
    if type(raw) ~= 'table' then return nil end
    local extras, count = {}, 0
    if #raw > 0 then
        for _, n in ipairs(raw) do
            if tonumber(n) then extras[math.floor(tonumber(n))] = true; count = count + 1 end
        end
    else
        for k, v in pairs(raw) do
            local n = tonumber(k)
            if n and n >= 0 and n <= 20 then extras[math.floor(n)] = v == true or v == 1 or v == 'true'; count = count + 1 end
        end
    end
    if count == 0 then return nil end
    return extras
end

--- Style de plaque : nom (comme vMenu / FiveM) ou numéro du jeu -> numéro (SetVehicleNumberPlateTextIndex)
local PLATES = {
    BLUE_ON_WHITE_1 = 3, BLUE_ON_WHITE_2 = 0, BLUE_ON_WHITE_3 = 4, YELLOW_ON_BLACK = 1, YELLOW_ON_BLUE = 2,
    NORTH_YANKTON = 5, YANKTON = 5,
}
local function plateType(raw)
    local n = tonumber(raw)
    if not n and type(raw) == 'string' then n = PLATES[raw:upper():gsub('[%s%-]', '_')] end
    if not n or n < 0 or n > 12 then return nil end
    return math.floor(n)
end

--- Texte de plaque : 8 caractères au plus, lettres / chiffres / espaces, « # » et « ? » (tirés au hasard au spawn)
local function plateText(raw)
    if type(raw) ~= 'string' and type(raw) ~= 'number' then return nil end
    local text = tostring(raw):upper():gsub('[^A-Z0-9 #%?]', '')
    text = text:sub(1, 8)
    if text:gsub(' ', '') == '' then return nil end
    return text
end

--- Teinte des vitres : 0 à 6, sinon rien (teinte du véhicule)
local function windowTint(raw)
    local n = tonumber(raw)
    if not n or n < 0 or n > 6 then return nil end
    return math.floor(n)
end

local function loadVehicles()
    Vehicles, byId = {}, {}
    local file = LoadResourceFile(GetCurrentResourceName(), 'data/vehicle.json') and 'data/vehicle.json' or 'data/vehicles.json'
    local data = readJsonList(file)
    if not data then return end
    local list = type(field(data, 'vehicles')) == 'table' and field(data, 'vehicles') or data
    for i, v in ipairs(list) do
        local code = trim(field(v, 'spawnName') or field(v, 'Code'))
        local label = trim(field(v, 'menuName') or field(v, 'Name'))
        if code == '' or label == '' then
            print(('^3[RP Interact] vehicle.json : véhicule n°%d ignoré (spawnName ou menuName manquant).^0'):format(i))
        else
            local sub = trim(field(v, 'subCategory') or field(v, 'Service'))
            local category = trim(field(v, 'Principale'))
            if category == '' then category = SERVICES[sub:lower()] and 'Police' or 'Autres' end -- ancien format
            local entry = {
                id = #Vehicles + 1, code = code:lower(), label = label:sub(1, 80),
                category = category:sub(1, 40), sub = sub:sub(1, 60),
                service = SERVICES[sub:lower()] or (category:lower() == 'police' and 'police' or 'other'),
                police = category:lower() == 'police',
                livery = tonumber(field(v, 'livery') or field(v, 'Livery')),
                windowTint = windowTint(field(v, 'windowTint') or field(v, 'WindowTint')),
                plateIndex = plateType(field(v, 'plateType') or field(v, 'PlateType')),
                plateText = plateText(field(v, 'plate') or field(v, 'Plate') or field(v, 'plateText')),
                extras = readExtras(field(v, 'extras') or field(v, 'Extras')),
            }
            local tintRaw, plateRaw = field(v, 'windowTint') or field(v, 'WindowTint'), field(v, 'plateType') or field(v, 'PlateType')
            if tintRaw ~= nil and not entry.windowTint then
                print(('^3[RP Interact] vehicle.json : %s : windowTint "%s" ignoré (0 à 6).^0'):format(label, tostring(tintRaw)))
            end
            local textRaw = field(v, 'plate') or field(v, 'Plate') or field(v, 'plateText')
            if textRaw ~= nil and not entry.plateText then
                print(('^3[RP Interact] vehicle.json : %s : plate "%s" ignoré (lettres, chiffres, espaces, # et ?).^0')
                    :format(label, tostring(textRaw)))
            elseif type(textRaw) == 'string' and #textRaw:gsub('^%s+', ''):gsub('%s+$', '') > 8 then
                print(('^3[RP Interact] vehicle.json : %s : plate "%s" coupé à 8 caractères ("%s").^0')
                    :format(label, textRaw, entry.plateText))
            end
            if plateRaw ~= nil and not entry.plateIndex then
                print(('^3[RP Interact] vehicle.json : %s : plateType "%s" inconnu (BLUE_ON_WHITE_1, NORTH_YANKTON… ou 0 à 12).^0')
                    :format(label, tostring(plateRaw)))
            end
            Vehicles[#Vehicles + 1] = entry
            byId[entry.id] = entry
        end
    end
    local tints, plates = 0, 0
    for _, e in ipairs(Vehicles) do
        if e.windowTint then tints = tints + 1 end
        if e.plateIndex or e.plateText then plates = plates + 1 end
    end
    print(('^5[RP Interact]^0 %d véhicule(s) lu(s) dans %s (%d avec vitres teintées, %d avec plaque réglée)')
        :format(#Vehicles, file, tints, plates))
end

-- =========================================================================
-- ARMES (data/loadouts.json) et TENUES (data/outfits.json, menu /eup)
-- =========================================================================
local Loadouts, Outfits = {}, {}

local function loadLoadouts()
    Loadouts = {}
    for _, l in ipairs(readJsonList('data/loadouts.json') or {}) do
        local name = trim(field(l, 'Name'))
        if name ~= '' then
            local weapons = {}
            for _, w in ipairs(type(field(l, 'Weapons')) == 'table' and field(l, 'Weapons') or {}) do
                local weapon = trim(field(w, 'Weapon')):upper()
                if weapon ~= '' then
                    local components = {}
                    for _, c in ipairs(type(field(w, 'Components')) == 'table' and field(w, 'Components') or {}) do
                        components[#components + 1] = trim(c):upper()
                    end
                    weapons[#weapons + 1] = { weapon = weapon, ammo = math.floor(tonumber(field(w, 'Ammo')) or 0), components = components }
                end
            end
            Loadouts[#Loadouts + 1] = { name = name:sub(1, 80), replace = field(l, 'Replace') == true, weapons = weapons }
        end
    end
end

-- =========================================================================
-- ÉQUIPEMENTS PAR POLICE (equipment_services.json, fourni avec le script) : "Équipement WSP" / "Équipement KCSO"
-- du menu Équipements, et ce que chaque joueur peut personnaliser ("Customiser équipement")
--   [ { "Service", "Name", "Replace", "Weapons": [ { "Weapon", "Label", "Ammo", "Required", "Default", "Group",
--       "Components", "Options": [ { "Label", "Choices": [ { "Label", "Component" } ] } ], "Tints", "Tint" } ] } ]
--   "Group" : armes INTERCHANGEABLES (même nom de groupe, ex. "Arme principale") : le joueur en prend UNE SEULE ;
--   celle marquée "Required" est l'arme de dotation (donnée par défaut) et le groupe est obligatoire (une arme du groupe
--   toujours prise) ; sans "Required" dans le groupe : la première arme par défaut, et le joueur peut n'en prendre aucune.
--   "Tint" : teinte de départ de l'arme (numéro 0 à 7, ou nom : "noir", "vert", "or", "rose", "kaki", "bleu",
--   "orange", "platine") ; ex. le beanbag orange.
-- =========================================================================
local Services, serviceByKey = {}, {}
local TINT_COUNT = 8 -- teintes des armes classiques (0 à 7)
local TINT_NAMES = { noir = 0, black = 0, vert = 1, green = 1, ['or'] = 2, gold = 2, rose = 3, pink = 3, kaki = 4,
    army = 4, bleu = 5, police = 5, lspd = 5, orange = 6, platine = 7, platinum = 7 }

--- Teinte de départ ("Tint") : numéro 0 à 7 ou nom ; nil si absente / invalide
local function tintOf(value)
    local n = tonumber(value) or (type(value) == 'string' and TINT_NAMES[value:lower():gsub('%s', '')])
    n = n and math.floor(n)
    return n and n >= 0 and n < TINT_COUNT and n or nil
end

local function slug(text)
    return (text:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', ''))
end

local function loadServices()
    Services, serviceByKey = {}, {}
    for i, entry in ipairs(readJsonList('equipment_services.json') or {}) do
        local name = trim(field(entry, 'Name'))
        local serviceName = trim(field(entry, 'Service'))
        local code = SERVICES[serviceName:lower()]
        local key = code or slug(name)
        if name == '' or key == '' or serviceByKey[key] then
            print(('^3[RP Interact] equipment_services.json : équipement n°%d ignoré (Name manquant ou service en double).^0'):format(i))
        else
            local weapons, seen = {}, {}
            for _, w in ipairs(type(field(entry, 'Weapons')) == 'table' and field(entry, 'Weapons') or {}) do
                local weapon = trim(field(w, 'Weapon')):upper()
                if weapon ~= '' and not seen[weapon] then
                    seen[weapon] = true
                    -- Options : groupes du même nom réunis (« Magazine » 17 balles + « Magazine » 25 balles = un seul choix)
                    local groups, allowed, byLabel = {}, {}, {}
                    for _, group in ipairs(type(field(w, 'Options')) == 'table' and field(w, 'Options') or {}) do
                        local label = trim(field(group, 'Label')):sub(1, 60)
                        local index = byLabel[label:lower()]
                        for _, c in ipairs(type(field(group, 'Choices')) == 'table' and field(group, 'Choices') or {}) do
                            local component = trim(field(c, 'Component')):upper()
                            if component ~= '' and not allowed[component] then
                                if not index then
                                    groups[#groups + 1] = { label = label, choices = {} }
                                    index = #groups
                                    byLabel[label:lower()] = index
                                end
                                allowed[component] = index
                                local choices = groups[index].choices
                                choices[#choices + 1] = { label = trim(field(c, 'Label')):sub(1, 60), component = component }
                            end
                        end
                    end
                    -- Accessoires de base : seulement un par groupe d'options (les autres, hors options, toujours là)
                    local base, fixed, used = {}, {}, {}
                    for _, c in ipairs(type(field(w, 'Components')) == 'table' and field(w, 'Components') or {}) do
                        local component = trim(c):upper()
                        local g = allowed[component]
                        if component ~= '' then
                            if not g then
                                fixed[#fixed + 1] = component
                            elseif not used[g] then
                                used[g] = true
                                base[#base + 1] = component
                            end
                        end
                    end
                    local required = field(w, 'Required') == true
                    local setLabel = trim(field(w, 'Group')):sub(1, 40)
                    weapons[#weapons + 1] = {
                        setLabel = setLabel ~= '' and setLabel or nil, explicitDefault = field(w, 'Default') == true,
                        weapon = weapon, label = trim(field(w, 'Label')) ~= '' and trim(field(w, 'Label')):sub(1, 60) or weapon,
                        ammo = math.max(0, math.floor(tonumber(field(w, 'Ammo')) or 0)),
                        required = required, default = required or field(w, 'Default') ~= false,
                        components = base, fixed = fixed, groups = groups, allowed = allowed,
                        tints = field(w, 'Tints') == true or (tonumber(field(w, 'Tints')) or 0) > 0,
                        tint = tintOf(field(w, 'Tint')),
                    }
                end
            end
            -- Groupes d'armes interchangeables ("Group") : une seule arme prise ; l'arme "Required" est celle par défaut
            local sets, setOrder = {}, {}
            for _, w in ipairs(weapons) do
                if w.setLabel then
                    local k = w.setLabel:lower()
                    if not sets[k] then
                        sets[k] = { key = k, label = w.setLabel, members = {}, required = false }
                        setOrder[#setOrder + 1] = k
                    end
                    local set = sets[k]
                    set.members[#set.members + 1] = w.weapon
                    if w.required and not set.default then set.default = w.weapon end
                    set.required = set.required or w.required
                    w.set = k
                end
            end
            for _, k in ipairs(setOrder) do
                local set = sets[k]
                if not set.default then
                    for _, w in ipairs(weapons) do
                        if w.set == k and w.explicitDefault then set.default = w.weapon break end
                    end
                end
                set.default = set.default or set.members[1]
                for _, w in ipairs(weapons) do
                    if w.set == k then
                        w.required = false -- obligatoire : le groupe (une de ses armes), pas chaque arme
                        w.default = w.weapon == set.default
                    end
                end
            end
            local service = { key = key, code = code, name = name:sub(1, 80), replace = field(entry, 'Replace') ~= false,
                weapons = weapons, sets = sets }
            Services[#Services + 1] = service
            serviceByKey[key] = service
        end
    end
    -- Accessoires possibles de chaque arme (armes addon comprises), pour tous les scripts : coffre de rp_equipment
    -- (une arme rangée garde ses accessoires), /copyped. GlobalState.rpiWeaponComponents[ARME] = { label, components }
    local published = {}
    for _, service in ipairs(Services) do
        for _, w in ipairs(service.weapons) do
            local entry = published[w.weapon] or { label = w.label, components = {} }
            local seen = {}
            for _, c in ipairs(entry.components) do seen[c] = true end
            local function add(c) if not seen[c] then seen[c] = true; entry.components[#entry.components + 1] = c end end
            for _, c in ipairs(w.fixed) do add(c) end
            for c in pairs(w.allowed) do add(c) end
            table.sort(entry.components)
            published[w.weapon] = entry
        end
    end
    GlobalState.rpiWeaponComponents = published
end

-- Pièces d'une tenue : nom dans le fichier -> composant (component) ou accessoire (prop) du personnage
local OUTFIT_PARTS = {
    Hat = { prop = 0 }, Glasses = { prop = 1 }, Ear = { prop = 2 }, Watch = { prop = 6 }, Bracelet = { prop = 7 },
    Mask = { component = 1 }, UpperSkin = { component = 3 }, Pants = { component = 4 }, Parachute = { component = 5 },
    Shoes = { component = 6 }, Accessories = { component = 7 }, UnderCoat = { component = 8 }, Armor = { component = 9 },
    Decal = { component = 10 }, Top = { component = 11 },
}
local POLICE_GROUPS = {
    wsp = 'WSP', ['washington state patrol'] = 'WSP',
    kcso = 'KCSO', ['king county sheriff office'] = 'KCSO', ["king county sheriff's office"] = 'KCSO',
}

--- Pièces "modèle:texture" d'un objet (tenue ou pièce de "Modifier ma tenue") -> composants et accessoires,
--- comptés à partir de 0 ; accessoire à -1 : retiré
local function parseParts(o, oneBased)
    local components, props = {}, {}
    for part, target in pairs(OUTFIT_PARTS) do
        local value = field(o, part)
        local d, t = tostring(value or ''):match('^%s*(%-?%d+)%s*:%s*(%-?%d+)%s*$')
        d, t = tonumber(d), tonumber(t)
        if d then
            if oneBased then d, t = d - 1, math.max((t or 1) - 1, 0) end
            if target.prop then
                props[#props + 1] = { target.prop, d, t or 0 }
            else
                components[#components + 1] = { target.component, math.max(d, 0), t or 0 }
            end
        end
    end
    return components, props
end

local function genderOf(o)
    local gender = trim(field(o, 'Gender')):lower()
    return (gender == 'female' or gender == 'femme' or gender == 'f') and 'female'
        or ((gender == 'male' or gender == 'homme' or gender == 'm') and 'male' or nil)
end

local function loadOutfits()
    Outfits = {}
    local oneBased = not (Config.Eup and Config.Eup.OneBased == false)
    for i, o in ipairs(readJsonList('data/outfits.json') or {}) do
        local name = trim(field(o, 'Name'))
        if name == '' then
            print(('^3[RP Interact] outfits.json : tenue n°%d ignorée (Name manquant).^0'):format(i))
        else
            local gender = genderOf(o)
            local cate = trim(field(o, 'Cate')):lower()
            local group = trim(field(o, 'Category2'))
            local isPolice = cate == 'police'
            if isPolice then group = POLICE_GROUPS[group:lower()] or (group ~= '' and group:upper() or 'Autres') end
            local components, props = parseParts(o, oneBased)
            Outfits[#Outfits + 1] = {
                index = #Outfits + 1, name = name:sub(1, 80), gender = gender,
                cate = isPolice and 'police' or 'civil', group = group ~= '' and group:sub(1, 40) or nil,
                components = components, props = props,
            }
        end
    end
end

-- =========================================================================
-- MODIFIER MA TENUE (data/modifoutfits.json) : pièces proposées selon le service de la tenue mise, rangées en
-- CATÉGORIES (une pièce à la fois par catégorie, choisie dans une liste, comme les accessoires d'une arme) :
--   { "WSP": [ { "Category": "Gilets", "Items": [ { "Name": "Gilet haute visibilité", "Gender": "Male", "Armor": "110:1" },
--                                                  { "Name": "Gilet pare-balles", "Armor": "13:1" } ] },
--              { "Category": "Couvre-chefs", "Items": [ ... ] } ],
--     "KCSO": [ ... ], "Civil": [ ... ], "Tous": [ ... ] }   ("Tous" : proposées pour tous les services)
-- Ancien format accepté : pièces directement dans la liste, avec "Category" facultatif.
-- Une pièce = un nom + une ou plusieurs parties de tenue (mêmes noms que outfits.json : Hat, Armor, Top...).
-- =========================================================================
local ModOutfits = {}

--- Clé de service : "Civil", "Tous", "WSP", "KCSO" (noms complets acceptés) ou autre police (en majuscules)
local function serviceKey(text)
    local t = trim(text)
    local l = t:lower()
    if l == '' then return nil end
    if l == 'civil' or l == 'civils' then return 'Civil' end
    if l == 'tous' or l == 'all' or l == 'commun' then return 'Tous' end
    return POLICE_GROUPS[l] or t:upper():sub(1, 40)
end

local function loadModOutfits()
    ModOutfits = {}
    local oneBased = not (Config.Eup and Config.Eup.OneBased == false)
    local data = readJsonList('data/modifoutfits.json') or {}
    local keys = {}
    for k in pairs(data) do if type(k) == 'string' then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local service = serviceKey(k)
        -- Catégories { Category, Items } dépliées en pièces (la catégorie est donnée à chacune)
        local flat = {}
        for _, o in ipairs(type(data[k]) == 'table' and data[k] or {}) do
            local items = type(o) == 'table' and (field(o, 'Items') or field(o, 'Pieces') or field(o, 'Options')) or nil
            if type(items) == 'table' then
                local category = trim(field(o, 'Category'))
                local tab = trim(field(o, 'Tab')) -- onglet du menu (facultatif : sinon d'après le nom de la catégorie)
                for _, item in ipairs(items) do
                    if type(item) == 'table' then
                        if category ~= '' and trim(field(item, 'Category')) == '' then item.Category = category end
                        if tab ~= '' and trim(field(item, 'Tab')) == '' then item.Tab = tab end
                        flat[#flat + 1] = item
                    end
                end
            else
                flat[#flat + 1] = o
            end
        end
        for i, o in ipairs(flat) do
            local name = trim(field(o, 'Name'))
            local components, props = parseParts(o, oneBased)
            if name == '' or (#components == 0 and #props == 0) then
                print(('^3[RP Interact] modifoutfits.json : pièce n°%d de "%s" ignorée (%s).^0'):format(i, k,
                    name == '' and 'Name manquant' or 'aucune partie "modèle:texture"'))
            else
                local category = trim(field(o, 'Category'))
                local tab = trim(field(o, 'Tab'))
                ModOutfits[#ModOutfits + 1] = {
                    id = #ModOutfits + 1, name = name:sub(1, 80), service = service, gender = genderOf(o),
                    category = category ~= '' and category:sub(1, 40) or nil, tab = tab ~= '' and tab:sub(1, 40) or nil,
                    components = components, props = props,
                }
            end
        end
    end
end

local function loadAll()
    loadVehicles()
    loadLoadouts()
    loadServices()
    loadOutfits()
    loadModOutfits()
    print(('^5[RP Interact]^0 %d tenue(s) (data/outfits.json), %d pièce(s) à modifier (data/modifoutfits.json), %d lot(s) d\'armes (data/loadouts.json), %d équipement(s) de service (equipment_services.json)'):format(#Outfits, #ModOutfits, #Loadouts, #Services))
end

loadAll()
RegisterCommand('rpi_vehicles', function(src)
    if src == 0 or IsPlayerAceAllowed(src, Config.AdminAce) then loadAll() end
end, false)

local function isPolice(src) return S.policeUnit(src) ~= nil end

-- Permissions (config.lua : Permissions) : catégories réservées à certains joueurs
local DENIED = { ok = false, error = 'Accès réservé : vous n\'avez pas la permission.' }
local function allowed(src, section) return not S.hasPermission or S.hasPermission(src, section) end

S.on('vehicleList', function(src)
    if not allowed(src, 'car') then return DENIED end
    return { ok = true, vehicles = Vehicles, police = isPolice(src), policeOnly = Config.SpawnPoliceOnly ~= false }
end)

S.on('spawnVehicle', function(src, p)
    if not allowed(src, 'car') then return DENIED end
    local entry = byId[math.floor(tonumber(p.id) or -1)]
    if not entry and type(p.code) == 'string' then -- ancien appel : par spawn code
        for _, v in ipairs(Vehicles) do if v.code == p.code:lower() then entry = v break end end
    end
    if not entry then return { ok = false, error = 'Véhicule inconnu.' } end
    if entry.police and Config.SpawnPoliceOnly ~= false and not isPolice(src) then
        return { ok = false, error = 'Véhicule de police : rejoignez une unité dans le MDC.' }
    end
    return { ok = true, vehicle = entry }
end)

-- Véhicule apparu par le menu (client/garage.lua) : état rpiSpawned (protégé du « Clear Area » de vMenu par les
-- joueurs qui le contrôlent) et gardé par le serveur si son joueur se déconnecte. Seulement un véhicule que ce joueur
-- contrôle, apparu à moins de 30 m de lui.
RegisterNetEvent('rp_interact:vehicleSpawned', function(netId)
    local src = source
    local entity = type(netId) == 'number' and NetworkGetEntityFromNetworkId(netId) or 0
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return end
    if NetworkGetEntityOwner(entity) ~= src then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(entity)) > 30.0 then return end
    Entity(entity).state:set('rpiSpawned', true, true)
    SetEntityOrphanMode(entity, 2) -- gardé quand son joueur part (supprimé par /dv, l'œil, un nouveau spawn…)
end)

-- =========================================================================
-- RADIO DU VÉHICULE ET MUSIQUE (/musique) : une « source » de son = un véhicule, un joueur, un objet ou un lieu
--   id de la source : 'entity:<n° réseau>' (véhicule ou objet), 'player:<id serveur>', 'place:<n°>'.
--   État : véhicule / objet -> état de l'entité « rpiRadio » ; joueur -> état du joueur « rpiRadio » ;
--   lieu -> GlobalState.rpiPlaces[n°]. Champs : url, start, volume, seq, queue, history, paused, stopped
--   (morceaux finis / radio arrêtée : historique gardé pour revenir en arrière), loop (lecture en boucle : un seul
--   morceau -> il recommence ; une file -> toute la playlist tourne), music (/musique : { owner, kind, label, x, y, z }),
--   intensity (/musique : 0 douce, 1 normale, 2 forte, 3 très forte : basses / résonance), range (/musique : périmètre
--   audible choisi, m ; nil = selon le volume).
-- =========================================================================
local MUSIC = Config.Music or {}

local function vehicleFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
    return entity
end

--- Places avant (conducteur, passager avant) ou joueur collé au véhicule (œil, portière avant ouverte)
local function canUseRadio(src, vehicle)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    if GetPedInVehicleSeat(vehicle, -1) == ped or GetPedInVehicleSeat(vehicle, 0) == ped then return true end
    if GetVehiclePedIsIn(ped, false) == vehicle then return false end -- à l'arrière
    return #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= 4.0
end

local function validUrl(url)
    if type(url) ~= 'string' then return nil end
    url = trim(url)
    if #url > 400 or not url:match('^https?://[%w%-%.]+') or url:find('[%s<>"\']') then return nil end
    return url
end

local MAX_QUEUE = Config.RadioQueueMax or 10
local settingsOf -- (plus bas)
local MAX_HISTORY = Config.RadioHistory or 10 -- morceaux précédents gardés (revenir en arrière, même finis)
local trackSeq = 0 -- n° unique de chaque morceau lancé (deux morceaux peuvent démarrer dans la même seconde)

local function copyList(list, max)
    local out = {}
    for i, url in ipairs(type(list) == 'table' and list or {}) do
        if i > max then break end
        out[#out + 1] = url
    end
    return out
end
local function copyQueue(current) return copyList(current and current.queue, MAX_QUEUE) end
local function copyHistory(current)
    local list = type(current) == 'table' and type(current.history) == 'table' and current.history or {}
    local out = {}
    for i = math.max(1, #list - MAX_HISTORY + 1), #list do out[#out + 1] = list[i] end -- les plus récents
    return out
end

--- Morceau en cours (ni arrêté, ni fini)
local function isOn(current) return current ~= nil and not current.stopped and type(current.url) == 'string' end

--- État de la radio (champs absents : repris de `base`, l'état actuel) ; `new = true` : nouveau morceau.
--- `paused` : position (s) du morceau en pause, sinon nil.
local function radioState(base, fields)
    base = base or {}
    local r = {
        url = fields.url or base.url, start = fields.start or base.start,
        volume = fields.volume or base.volume or 60, by = fields.by or base.by,
        queue = fields.queue or copyQueue(base), history = fields.history or copyHistory(base),
        seq = base.seq, paused = base.paused, music = fields.music or base.music,
        loop = base.loop, intensity = base.intensity, range = base.range,
    }
    if fields.loop ~= nil then r.loop = fields.loop or nil end
    if fields.intensity ~= nil then r.intensity = fields.intensity end
    if fields.range ~= nil then r.range = fields.range or nil end
    if fields.new then
        trackSeq = trackSeq + 1
        r.seq, r.paused = trackSeq, nil
    end
    if fields.paused ~= nil then r.paused = fields.paused or nil end
    return r
end

local function pushHistory(history, url)
    if type(url) ~= 'string' then return history end
    for i = #history, 1, -1 do
        if history[i] == url then table.remove(history, i) end -- pas de doublon (boucle, relance)
    end
    history[#history + 1] = url
    while #history > MAX_HISTORY do table.remove(history, 1) end
    return history
end

--- Réglages gardés d'un morceau à l'autre, même arrêtée (volume, boucle, musique, intensité, périmètre)
settingsOf = function(current)
    current = type(current) == 'table' and current or {}
    return { volume = current.volume or 60, music = current.music, loop = current.loop, intensity = current.intensity,
        range = current.range }
end

--- Arrêtée (morceaux finis ou bouton Arrêter) : plus de son, mais l'historique reste (revenir en arrière, relancer)
local function stoppedState(current)
    local history = copyHistory(current)
    if isOn(current) then pushHistory(history, current.url) end
    local stopped = settingsOf(current)
    stopped.stopped, stopped.history, stopped.queue = true, history, {}
    return stopped
end

-- ---- Sources ----
local function places()
    local t = GlobalState.rpiPlaces
    return type(t) == 'table' and t or {}
end
local placeSeq = 0
local owners = {} -- [joueur] = id de sa source /musique

--- Source d'après son id : { id, kind ('vehicle' | 'prop' | 'player' | 'place'), entity, get(), set(v), pos() }
local function sourceOf(id)
    if type(id) ~= 'string' then return nil end
    local kind, n = id:match('^(%a+):(%d+)$')
    n = tonumber(n)
    if not kind then return nil end
    if kind == 'entity' then
        local entity = NetworkGetEntityFromNetworkId(n)
        if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
        local t = GetEntityType(entity)
        if t ~= 2 and t ~= 3 then return nil end
        local state = Entity(entity).state
        return { id = id, kind = t == 2 and 'vehicle' or 'prop', entity = entity,
            get = function() return type(state.rpiRadio) == 'table' and state.rpiRadio or nil end,
            set = function(v) state:set('rpiRadio', v or false, true) end,
            pos = function() return GetEntityCoords(entity) end }
    elseif kind == 'player' then
        local ped = GetPlayerPed(n)
        if not ped or ped == 0 then return nil end
        local state = Player(n).state
        return { id = id, kind = 'player', player = n,
            get = function() return type(state.rpiRadio) == 'table' and state.rpiRadio or nil end,
            set = function(v) state:set('rpiRadio', v or false, true) end,
            pos = function() return GetEntityCoords(GetPlayerPed(n)) end }
    elseif kind == 'place' then
        local key = tostring(n)
        if not places()[key] then return nil end
        return { id = id, kind = 'place',
            get = function() return places()[key] end,
            set = function(v)
                local all = places()
                if v then
                    v.music = v.music or (all[key] and all[key].music)
                    all[key] = v
                else
                    all[key] = nil
                end
                GlobalState.rpiPlaces = all
            end,
            pos = function()
                local m = (places()[key] or {}).music or {}
                return vector3(tonumber(m.x) or 0.0, tonumber(m.y) or 0.0, tonumber(m.z) or 0.0)
            end }
    end
    return nil
end

local function near(src, pos, distance)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and pos and #(GetEntityCoords(ped) - pos) <= distance
end

--- Qui règle : véhicule -> places avant (ou collé au véhicule) ; musique -> son créateur, le joueur qui la porte, ou
--- quiconque à ControlDistance m (tapage : un policier peut baisser / couper)
local function canControl(src, source, current)
    if source.kind == 'vehicle' then return canUseRadio(src, source.entity) end
    local music = current and current.music or {}
    if music.owner == src or (source.kind == 'player' and source.player == src) then return true end
    return near(src, source.pos(), MUSIC.ControlDistance or 6.0)
end

--- Retire complètement une source /musique (plus de son, plus d'historique) ; objet apparu pour elle : supprimé
local function removeMusic(source)
    local current = source.get()
    local music = current and current.music or {}
    if music.owner and owners[music.owner] == source.id then owners[music.owner] = nil end
    source.set(false)
    if music.spawned and source.entity and DoesEntityExist(source.entity) then DeleteEntity(source.entity) end
end

-- Objets que /musique peut faire apparaître (config.lua : Music.SpawnProps)
local SPAWN_MODELS = {}
for _, p in ipairs(MUSIC.SpawnProps or {}) do
    if p.model then SPAWN_MODELS[GetHashKey(p.model) & 0xFFFFFFFF] = true end
end

--- Objet apparu à l'instant par ce joueur pour /musique (modèle de la liste, créé par lui) : supprimable avec la musique
local function spawnedBy(src, entity)
    if not SPAWN_MODELS[GetEntityModel(entity) & 0xFFFFFFFF] then return false end
    local ok, first = pcall(NetworkGetFirstEntityOwner, entity)
    return not ok or first == src
end

--- Lance `url` ; le morceau en cours passe dans l'historique (s'il y en a un)
local function playTrack(source, current, url, fields)
    fields = fields or {}
    local history = copyHistory(current)
    if isOn(current) and not fields.noHistory then pushHistory(history, current.url) end
    source.set(radioState(isOn(current) and current or settingsOf(current), {
        url = url, start = os.time(), volume = fields.volume, by = fields.by, music = fields.music,
        queue = fields.queue, history = history, new = true,
    }))
end

--- Morceau suivant de la file "Écouter ensuite" ; file vide : arrêtée (historique gardé).
--- En boucle : un seul morceau -> il recommence ; une file -> le morceau fini repart en fin de file (playlist en boucle)
local function playNext(source, current)
    local queue = copyQueue(current)
    if current.loop and isOn(current) then
        if #queue == 0 then
            return playTrack(source, current, current.url, { queue = {}, noHistory = true })
        end
        local nextUrl = table.remove(queue, 1)
        queue[#queue + 1] = current.url
        return playTrack(source, current, nextUrl, { queue = queue }) -- aussi dans « Déjà écoutés » (revenir en arrière)
    end
    local nextUrl = table.remove(queue, 1)
    if nextUrl then
        playTrack(source, current, nextUrl, { queue = queue })
    else
        source.set(stoppedState(current))
    end
end

-- /musique : intensité (0 douce .. 3 très forte) et périmètre audible (m, borné ; 0 / nil = selon le volume)
local function intensityOf(v)
    local n = math.tointeger(tonumber(v))
    if not n then return nil end
    return math.max(0, math.min(3, n))
end
local function rangeValue(v)
    v = tonumber(v)
    if not v or v <= 0 then return false end -- false : selon le volume
    return math.floor(math.max(5.0, math.min(MUSIC.MaxRange or 150.0, v)) + 0.5)
end

local function volumeOf(v, default) return math.floor(math.max(0, math.min(100, tonumber(v) or default or 60))) end

--- /musique : nouvelle source (sur soi, ici, sur un objet) ; l'ancienne du joueur est retirée
local function createMusic(src, p)
    if MUSIC.Enabled == false then return { ok = false, error = 'La musique est désactivée sur ce serveur.' } end
    local url = validUrl(p.url)
    if not url then return { ok = false, error = 'Lien invalide (adresse http:// ou https://).' } end
    local anchor = type(p.anchor) == 'table' and p.anchor or {}
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false } end
    local reach = MUSIC.PlaceDistance or 8.0
    local total = 0
    for _ in pairs(owners) do total = total + 1 end
    if not owners[src] and total >= (MUSIC.MaxTotal or 30) then
        return { ok = false, error = 'Trop de musiques sur le serveur en ce moment.' }
    end
    local source, music
    if anchor.kind == 'player' then
        if owners[src] and owners[src] ~= 'player:' .. src then
            local old = sourceOf(owners[src]); if old then removeMusic(old) end
        end
        source = sourceOf('player:' .. src)
        music = { owner = src, kind = 'player', label = 'sur ' .. (GetPlayerName(src) or 'un joueur') }
    elseif anchor.kind == 'prop' and tonumber(anchor.netId) then
        local entity = NetworkGetEntityFromNetworkId(math.tointeger(tonumber(anchor.netId)) or -1)
        if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 3 then
            return { ok = false, error = 'Objet introuvable.' }
        end
        if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > reach then return { ok = false, error = 'Objet trop loin.' } end
        local id = 'entity:' .. math.tointeger(tonumber(anchor.netId))
        if owners[src] ~= id and type(Entity(entity).state.rpiRadio) == 'table' then
            return { ok = false, error = 'Cet objet joue déjà de la musique.' }
        end
        if owners[src] and owners[src] ~= id then local old = sourceOf(owners[src]); if old then removeMusic(old) end end
        source = sourceOf(id)
        local spawned = anchor.spawned == true and spawnedBy(src, entity)
        music = { owner = src, kind = 'prop', label = spawned and 'sur un objet posé' or 'sur un objet', spawned = spawned or nil }
        if spawned then SetEntityOrphanMode(entity, 2) end -- gardé si son joueur part (supprimé avec la musique)
    elseif anchor.kind == 'place' or anchor.kind == 'prop' then
        -- lieu (ou objet du décor, non synchronisé : à sa place)
        local pos = vector3(tonumber(anchor.x) or 0.0, tonumber(anchor.y) or 0.0, tonumber(anchor.z) or 0.0)
        if #(GetEntityCoords(ped) - pos) > reach then return { ok = false, error = 'Endroit trop loin.' } end
        if owners[src] then local old = sourceOf(owners[src]); if old then removeMusic(old) end end
        placeSeq = placeSeq + 1
        local key = tostring(placeSeq)
        music = { owner = src, kind = anchor.kind == 'prop' and 'prop' or 'place',
            label = anchor.kind == 'prop' and 'sur un objet du décor' or 'à un endroit', x = pos.x, y = pos.y, z = pos.z }
        local all = places()
        all[key] = { stopped = true, volume = 60, history = {}, queue = {}, music = music }
        GlobalState.rpiPlaces = all
        source = sourceOf('place:' .. key)
    else
        return { ok = false, error = 'Choisissez où jouer la musique.' }
    end
    if not source then return { ok = false, error = 'Impossible de créer la musique ici.' } end
    owners[src] = source.id
    local current = source.get()
    playTrack(source, current, url, { volume = volumeOf(p.volume, 60), by = src, music = music })
    -- réglages choisis en préparant la musique : intensité, périmètre, boucle
    local fields = { intensity = intensityOf(p.intensity) or 1, range = rangeValue(p.range), loop = p.loop == true }
    source.set(radioState(source.get(), fields))
    return { ok = true, source = source.id }
end

S.on('radio', function(src, p)
    -- Source visée : p.source ('entity:12', 'player:5', 'place:3') ; ancien format : p.netId (véhicule)
    local id = type(p.source) == 'string' and p.source or (type(p.netId) == 'number' and ('entity:' .. p.netId)) or nil
    if p.action == 'create' then
        if not allowed(src, 'music') then return DENIED end
        local res = createMusic(src, p)
        if res.ok then
            local source = sourceOf(res.source)
            res.radio = source and source.get() or false
        end
        return res
    end
    local source = sourceOf(id)
    if not source then return { ok = false, error = 'Source du son introuvable.' } end
    if not allowed(src, source.kind == 'vehicle' and 'car' or 'music') then return DENIED end
    local current = source.get()
    -- joueur / objet sans musique : se crée seulement avec /musique (action « create »)
    if source.kind ~= 'vehicle' and not current then return { ok = false, error = 'Aucune musique ici.' } end

    -- Fin d'un morceau (signalée par un joueur qui l'entend) : morceau suivant de la file
    if p.action == 'ended' then
        if not isOn(current) or current.seq ~= tonumber(p.seq) or current.paused then return { ok = true } end -- déjà passé
        if not near(src, source.pos(), (Config.RadioMaxRange or 110.0) + 20.0) then return { ok = false } end
        playNext(source, current)
        return { ok = true }
    end

    -- Le joueur est passé directement dans un autre véhicule (rp_vehiclecontrol) : la radio de l'ancien, laissé
    -- vide à l'avant, est arrêtée (joueur encore à proximité)
    if p.action == 'swapStop' then
        if source.kind ~= 'vehicle' or not isOn(current) then return { ok = true } end
        if not near(src, source.pos(), 30.0) then return { ok = false } end
        for seat = -1, 0 do
            local occupant = GetPedInVehicleSeat(source.entity, seat)
            if occupant ~= 0 and IsPedAPlayer(occupant) then return { ok = false } end -- quelqu'un y est encore
        end
        source.set(stoppedState(current))
        return { ok = true }
    end

    if not canControl(src, source, current) then
        return { ok = false, error = source.kind == 'vehicle' and 'Seules les places avant peuvent régler la radio.'
            or 'Approchez-vous de la musique pour la régler.' }
    end
    local function needOn() return not isOn(current) and { ok = false, error = 'Aucun morceau en cours.' } or nil end
    if p.action == 'play' then
        local url = validUrl(p.url)
        if not url then return { ok = false, error = 'Lien invalide (adresse http:// ou https://).' } end
        playTrack(source, current, url, { volume = volumeOf(p.volume, current and current.volume), by = src })
    elseif p.action == 'queue' then
        -- "+" : ajouté à la file "Écouter ensuite" (rien en cours : lancé tout de suite)
        local url = validUrl(p.url)
        if not url then return { ok = false, error = 'Lien invalide (adresse http:// ou https://).' } end
        if not isOn(current) then
            playTrack(source, current, url, { volume = volumeOf(p.volume, current and current.volume), by = src })
        else
            local queue = copyQueue(current)
            if #queue >= MAX_QUEUE then return { ok = false, error = ('File pleine (%d morceaux au maximum).'):format(MAX_QUEUE) } end
            queue[#queue + 1] = url
            source.set(radioState(current, { queue = queue }))
        end
    elseif p.action == 'unqueue' then
        if needOn() then return needOn() end
        local queue = copyQueue(current)
        local index = math.tointeger(tonumber(p.index))
        if not index or not queue[index] then return { ok = false, error = 'Morceau introuvable.' } end
        table.remove(queue, index)
        source.set(radioState(current, { queue = queue }))
    elseif p.action == 'next' then
        if needOn() then return needOn() end
        playNext(source, current)
    elseif p.action == 'pause' then
        -- Pause / reprise : même morceau, repris là où il était (pour tout le monde)
        if needOn() then return needOn() end
        if current.paused then
            source.set(radioState(current, { start = os.time() - current.paused, paused = false }))
        else
            local position = math.max(0, os.time() - (tonumber(current.start) or os.time()))
            source.set(radioState(current, { paused = position }))
        end
    elseif p.action == 'restart' then
        -- Retour au début du morceau (relancé pour tout le monde, pas d'entrée dans l'historique)
        if needOn() then return needOn() end
        playTrack(source, current, current.url, { queue = copyQueue(current), noHistory = true })
    elseif p.action == 'previous' then
        -- Morceau précédent, même après la fin de tout (radio arrêtée) : le morceau en cours revient en tête de file
        local history = copyHistory(current)
        local previous = table.remove(history)
        if not previous then return { ok = false, error = 'Aucun morceau précédent.' } end
        local queue = copyQueue(current)
        if isOn(current) then
            table.insert(queue, 1, current.url)
            while #queue > MAX_QUEUE do table.remove(queue) end
        end
        local base = isOn(current) and current or settingsOf(current)
        source.set(radioState(base, { url = previous, start = os.time(), queue = queue, history = history, new = true }))
    elseif p.action == 'replay' then
        -- Un morceau de l'historique (« Déjà écoutés »), même fini : relancé ; le morceau en cours passe dans l'historique
        local history = copyHistory(current)
        local index = math.tointeger(tonumber(p.index))
        local url = index and history[index]
        if not url then return { ok = false, error = 'Morceau introuvable.' } end
        table.remove(history, index)
        if isOn(current) then pushHistory(history, current.url) end
        local base = isOn(current) and current or settingsOf(current)
        source.set(radioState(base, { url = url, start = os.time(), queue = copyQueue(current), history = history, new = true }))
    elseif p.action == 'stop' then
        if not current then return { ok = true, radio = false } end
        source.set(stoppedState(current))
    elseif p.action == 'moveObject' then
        -- Objet apparu pour /musique, re-déplacé avec l'œil (n'importe quel joueur à côté) : la musique continue
        local music = current and current.music or {}
        if source.kind ~= 'prop' or not music.spawned or not source.entity then
            return { ok = false, error = 'Seul un objet apparu pour la musique se déplace ainsi.' }
        end
        local to = vector3(tonumber(p.x) or 0.0, tonumber(p.y) or 0.0, tonumber(p.z) or 0.0)
        if not near(src, to, (MUSIC.PlaceRange or 6.0) + 4.0) or not near(src, source.pos(), 15.0) then
            return { ok = false, error = 'Trop loin.' }
        end
        SetEntityCoords(source.entity, to.x, to.y, to.z, false, false, false, false)
        SetEntityHeading(source.entity, (tonumber(p.heading) or 0.0) % 360.0)
        return { ok = true, radio = current }
    elseif p.action == 'remove' then
        -- /musique : retirer la source (plus de son, plus d'historique)
        if source.kind == 'vehicle' then return { ok = false, error = 'Action inconnue.' } end
        removeMusic(source)
        return { ok = true, radio = false, removed = true }
    elseif p.action == 'loop' then
        -- Lecture en boucle (bouton) : un morceau seul tourne en boucle ; avec une file, toute la playlist
        if not current then return { ok = false, error = 'Aucun morceau en cours.' } end
        local on = p.value
        if on == nil then on = not current.loop end
        source.set(radioState(current, { loop = on == true }))
    elseif p.action == 'intensity' or p.action == 'range' then
        if source.kind == 'vehicle' then return { ok = false, error = 'Réglage réservé à /musique.' } end
        if not current then return { ok = false, error = 'Aucun morceau en cours.' } end
        if p.action == 'intensity' then
            local n = intensityOf(p.value)
            if not n then return { ok = false, error = 'Intensité invalide.' } end
            source.set(radioState(current, { intensity = n }))
        else
            source.set(radioState(current, { range = rangeValue(p.value) }))
        end
    elseif p.action == 'volume' then
        if not current then return { ok = false, error = 'Aucun morceau en cours.' } end
        source.set(radioState(current, { volume = volumeOf(p.volume or p.value, current.volume) }))
    else
        return { ok = false, error = 'Action inconnue.' }
    end
    return { ok = true, radio = source.get() or false }
end)

-- Créateur déconnecté : ses musiques posées (lieu, objet) s'arrêtent (Music.RemoveOnDrop) ; celle portée par lui
-- disparaît avec lui
AddEventHandler('playerDropped', function()
    local src = source
    local id = owners[src]
    owners[src] = nil
    if not id or MUSIC.RemoveOnDrop == false then return end
    local s = sourceOf(id)
    if s and s.kind ~= 'player' then removeMusic(s) end
end)

-- =========================================================================
-- ÉQUIPEMENTS : armes (data/loadouts.json) et tenues (data/outfits.json, menu /eup)
-- =========================================================================
-- ---- Équipements modifiés : propres à chaque joueur (licence Rockstar), PERMANENTS, nommés par lui ----
--   data/custom_equipment.json : { [licence] = { nextId, list = { { id, name, key (service), weapons, updatedAt } } } }
--   Les boutons "Équipement WSP / KCSO" donnent TOUJOURS l'équipement de base ; les équipements modifiés sont
--   dans la page "Équipements modifiés".
local CUSTOM_FILE = 'data/custom_equipment.json'
local MAX_CUSTOM = Config.MaxCustomEquipment or 10
local Custom, customLocked = {}, false

--- Ancien format (un équipement personnalisé par service, sans nom) : converti en équipements modifiés nommés
local function migrate(entry)
    if type(entry) ~= 'table' then return nil end
    if type(entry.list) == 'table' then
        for _, item in ipairs(entry.list) do
            if type(item) == 'table' and LEGACY_KEYS[item.key] then item.key = LEGACY_KEYS[item.key] end
        end
        return entry
    end
    local out, nextId = { list = {} }, 1
    for key, saved in pairs(entry) do
        if type(saved) == 'table' and type(saved.weapons) == 'table' then
            key = LEGACY_KEYS[key] or key
            local service = serviceByKey[key]
            out.list[#out.list + 1] = { id = nextId, key = key, weapons = saved.weapons, updatedAt = saved.updatedAt,
                name = ('%s (personnalisé)'):format(service and service.name or key:upper()) }
            nextId = nextId + 1
        end
    end
    out.nextId = nextId
    return out
end

local function loadCustom()
    Custom, customLocked = {}, false
    local raw = LoadResourceFile(GetCurrentResourceName(), CUSTOM_FILE)
    if not raw or not raw:match('%S') then return end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == 'table' then
        for licence, entry in pairs(data) do Custom[licence] = migrate(entry) end
    else
        customLocked = true -- illisible : rien n'est écrasé
        print(('^1[RP Interact] %s illisible (JSON invalide) : les équipements modifiés ne seront pas enregistrés.^0'):format(CUSTOM_FILE))
    end
end
loadCustom()

local function saveCustom()
    if customLocked then return false end
    return SaveResourceFile(GetCurrentResourceName(), CUSTOM_FILE, json.encode(Custom, { indent = true }), -1)
end

--- Choix d'un joueur nettoyés : seulement les armes / accessoires / teintes prévus pour ce service
local function cleanChoices(service, choices)
    choices = type(choices) == 'table' and type(choices.weapons) == 'table' and choices.weapons or {}
    local out = {}
    for _, w in ipairs(service.weapons) do
        local c = type(choices[w.weapon]) == 'table' and choices[w.weapon] or nil
        if c then
            local components, used = {}, {}
            for _, component in ipairs(type(c.components) == 'table' and c.components or {}) do
                component = type(component) == 'string' and component:upper() or ''
                local g = w.allowed[component]
                if g and not used[g] then -- un seul accessoire par groupe (ex. un chargeur)
                    used[g] = true
                    components[#components + 1] = component
                end
            end
            local tint = math.floor(tonumber(c.tint) or (w.tint or 0))
            if not w.tints or tint < 0 or tint >= TINT_COUNT then tint = w.tint or 0 end
            out[w.weapon] = { on = w.required or c.on == true, components = components, tint = tint }
        end
    end
    return { weapons = out }
end

--- Choix complets (armes absentes : réglage de base) ; `saved` : choix enregistrés, revérifiés (un accessoire
--- retiré du fichier depuis n'est plus donné, une arme ajoutée apparaît avec son réglage de base)
local function fullChoices(service, saved)
    local cleaned = saved and cleanChoices(service, saved) or { weapons = {} }
    local weapons = {}
    for _, w in ipairs(service.weapons) do
        weapons[w.weapon] = cleaned.weapons[w.weapon] or { on = w.default, components = w.components, tint = w.tint or 0 }
    end
    -- Groupes "Group" : une seule arme prise (celle de dotation si plusieurs le sont, ex. ancien enregistrement) ;
    -- groupe obligatoire sans arme prise : l'arme de dotation
    for _, set in pairs(service.sets or {}) do
        local chosen = nil
        for _, name in ipairs(set.members) do
            if weapons[name].on and (not chosen or name == set.default) then chosen = name end
        end
        if not chosen and set.required then chosen = set.default end
        for _, name in ipairs(set.members) do weapons[name].on = name == chosen end
    end
    return { weapons = weapons }
end

--- Tous les accessoires possibles d'une arme (fixes + ceux des choix) : l'aperçu retire ceux qui ne sont plus choisis
local function allComponents(w)
    local all = {}
    for component in pairs(w.allowed) do all[#all + 1] = component end
    for _, component in ipairs(w.fixed) do
        if not w.allowed[component] then all[#all + 1] = component end
    end
    table.sort(all)
    return all
end

--- Armes à donner (lot final) selon les choix ; `preview` : avec la liste de tous les accessoires possibles de
--- chaque arme et les armes du service non prises (aperçu en direct de Customiser équipement)
local function buildLoadout(service, choices, name, preview)
    local weapons, off = {}, {}
    for _, w in ipairs(service.weapons) do
        local c = choices.weapons[w.weapon] or { on = w.default, components = w.components, tint = w.tint or 0 }
        if w.required or c.on then
            local components = {}
            for _, component in ipairs(w.fixed) do components[#components + 1] = component end
            for _, component in ipairs(c.components or {}) do components[#components + 1] = component end
            weapons[#weapons + 1] = { weapon = w.weapon, ammo = w.ammo, components = components, tint = (w.tints and c.tint) or w.tint,
                all = preview and allComponents(w) or nil }
        elseif preview then
            off[#off + 1] = w.weapon
        end
    end
    return { name = name or service.name, replace = service.replace, weapons = weapons, off = preview and off or nil }
end

local function policeOnlyError(src)
    if not allowed(src, 'equipment') then return DENIED end
    if Config.EquipmentPoliceOnly ~= false and not isPolice(src) then
        return { ok = false, error = 'Réservé à la police : rejoignez une unité dans le MDC.' }
    end
    return nil
end

--- Équipement modifié n° `id` de ce joueur (et son service), nil s'il n'existe pas / plus
local function customOf(src, id)
    local mine = Custom[S.identifier(src)]
    id = tonumber(id)
    if not mine or not id then return nil end
    for i, entry in ipairs(mine.list) do
        if entry.id == id then return entry, serviceByKey[entry.key], i end
    end
    return nil
end

--- Liste affichée dans "Équipements modifiés" (seulement ceux dont le service existe encore)
local function customList(src)
    local list = {}
    local mine = Custom[S.identifier(src)]
    for _, entry in ipairs(mine and mine.list or {}) do
        local service = serviceByKey[entry.key]
        if service then
            list[#list + 1] = { id = entry.id, name = entry.name, key = entry.key, code = service.code, service = service.name }
        end
    end
    return list
end

local function cleanName(name, service)
    name = type(name) == 'string' and name:gsub('[%c<>]', ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '') or ''
    if name == '' then name = ('%s modifié'):format(service.name) end
    return name:sub(1, 40)
end

S.on('loadoutList', function(src)
    local list = {}
    for i, l in ipairs(Loadouts) do list[#list + 1] = { index = i, name = l.name } end
    local services = {}
    for _, service in ipairs(Services) do services[#services + 1] = { key = service.key, code = service.code, name = service.name } end
    return { ok = true, loadouts = list, services = services, customs = customList(src), maxCustom = MAX_CUSTOM,
        police = isPolice(src), policeOnly = Config.EquipmentPoliceOnly ~= false }
end)

S.on('equipment', function(src, p)
    local denied = policeOnlyError(src)
    if denied then return denied end
    if p.kind == 'service' then
        -- Bouton "Équipement WSP / KCSO" : toujours l'équipement de base du service
        local service = serviceByKey[type(p.key) == 'string' and p.key or '']
        if not service then return { ok = false, error = 'Équipement inconnu.' } end
        return { ok = true, loadout = buildLoadout(service, fullChoices(service, nil)) }
    end
    if p.kind == 'custom' then
        local entry, service = customOf(src, p.id)
        if not entry or not service then return { ok = false, error = 'Équipement modifié introuvable.' } end
        return { ok = true, custom = true, loadout = buildLoadout(service, fullChoices(service, entry), entry.name) }
    end
    local loadout = p.kind == 'loadout' and Loadouts[tonumber(p.index) or 0] or nil
    if not loadout then return { ok = false, error = 'Équipement inconnu.' } end
    return { ok = true, loadout = loadout }
end)

--- Page "Customiser équipement" : armes du service, accessoires et teintes possibles, choix de départ : l'équipement
--- de base (`key`) ou un équipement modifié du joueur (`id`)
S.on('equipmentCustom', function(src, p)
    local denied = policeOnlyError(src)
    if denied then return denied end
    local service, entry
    if p.id then
        entry, service = customOf(src, p.id)
        if not entry or not service then return { ok = false, error = 'Équipement modifié introuvable.' } end
    else
        service = serviceByKey[type(p.key) == 'string' and p.key or '']
        if not service then return { ok = false, error = 'Équipement inconnu.' } end
    end
    local choices = fullChoices(service, entry)
    local weapons = {}
    for _, w in ipairs(service.weapons) do
        local set = w.set and service.sets[w.set] or nil
        weapons[#weapons + 1] = { weapon = w.weapon, label = w.label, required = w.required, groups = w.groups,
            tints = w.tints, choice = choices.weapons[w.weapon],
            set = set and set.key or nil, setLabel = set and set.label or nil, setRequired = set and set.required or nil,
            setDefault = set and set.default == w.weapon or nil }
    end
    return { ok = true, key = service.key, code = service.code, service = service.name, weapons = weapons,
        id = entry and entry.id or nil, name = entry and entry.name or '', suggested = ('%s modifié'):format(service.name) }
end)

--- Customiser : aperçu en direct ("preview" : les armes sont données à chaque changement), "Enregistrer" (nommé, gardé pour toujours, propre au joueur : nouvel
--- équipement modifié, ou mise à jour de celui en cours de modification) ou "Supprimer"
S.on('equipmentCustomSave', function(src, p)
    local denied = policeOnlyError(src)
    if denied then return denied end
    local licence = S.identifier(src)
    local entry, service, index
    if p.id then
        entry, service, index = customOf(src, p.id)
        if not entry or not service then return { ok = false, error = 'Équipement modifié introuvable.' } end
    else
        service = serviceByKey[type(p.key) == 'string' and p.key or '']
        if not service then return { ok = false, error = 'Équipement inconnu.' } end
    end
    if p.action == 'delete' then
        if not entry then return { ok = false, error = 'Équipement modifié introuvable.' } end
        if customLocked then return { ok = false, error = 'Enregistrement bloqué : fichier illisible (voir console serveur).' } end
        table.remove(Custom[licence].list, index)
        saveCustom()
        return { ok = true, deleted = true, customs = customList(src) }
    end
    local choices = fullChoices(service, cleanChoices(service, p.choices))
    local name = cleanName(p.name, service)
    if p.action == 'save' then
        if customLocked then return { ok = false, error = 'Enregistrement bloqué : fichier illisible (voir console serveur).' } end
        Custom[licence] = Custom[licence] or { nextId = 1, list = {} }
        local mine = Custom[licence]
        if entry then
            entry.name, entry.weapons, entry.updatedAt = name, choices.weapons, os.time()
        else
            if #mine.list >= MAX_CUSTOM then
                return { ok = false, error = ('%d équipements modifiés maximum : supprimez-en un.'):format(MAX_CUSTOM) }
            end
            entry = { id = mine.nextId or (#mine.list + 1), name = name, key = service.key, weapons = choices.weapons, updatedAt = os.time() }
            mine.nextId = entry.id + 1
            mine.list[#mine.list + 1] = entry
        end
        if not saveCustom() then return { ok = false, error = 'Enregistrement impossible (dossier data ?).' } end
        return { ok = true, saved = true, id = entry.id, name = entry.name, customs = customList(src),
            loadout = buildLoadout(service, choices, entry.name) }
    end
    -- "preview" : aperçu en direct (chaque changement) ; "apply" : équiper sans enregistrer
    return { ok = true, saved = false, id = entry and entry.id or nil,
        loadout = buildLoadout(service, choices, name, p.action == 'preview') }
end)

--- Menu /eup : toutes les tenues (le client garde celles de son personnage homme / femme)
S.on('eupList', function(src)
    local policeOnly = Config.Eup and Config.Eup.PoliceOnly == true
    local unit = S.policeUnit(src)
    local locked = policeOnly and not unit or false
    -- Pièces de "Modifier ma tenue" : celles des polices retirées si les tenues de police sont réservées
    local mods = ModOutfits
    if locked then
        mods = {}
        for _, m in ipairs(ModOutfits) do
            if m.service == 'Civil' or m.service == 'Tous' then mods[#mods + 1] = m end
        end
    end
    return { ok = true, outfits = Outfits, mods = mods, policeLocked = locked,
        service = unit and serviceKey(unit.agencyShort or unit.agency) or nil }
end)

S.on('eupWear', function(src, p)
    local outfit = Outfits[tonumber(p.index) or 0]
    if not outfit then return { ok = false, error = 'Tenue inconnue.' } end
    if outfit.cate == 'police' and Config.Eup and Config.Eup.PoliceOnly == true and not isPolice(src) then
        return { ok = false, error = 'Tenues de police réservées aux policiers en service (unité du MDC).' }
    end
    return { ok = true, outfit = outfit }
end)
