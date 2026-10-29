--[[
    RP Interact - Menu des tenues /eup (client)
    -------------------------------------------
    Ouvert par la commande /eup (chat écrit, même sans nom RP) ou par Menu Interaction > Équipements >
    "Accéder aux tenues". Tenues de data/outfits.json (lues par le serveur), classées :
      Washington State Patrol (WSP) / King County Sheriff Office (KCSO) (+ autres polices du fichier) ; Civil.
    Seules les tenues du personnage (homme / femme, personnage multijoueur) sont listées.
    MODIFIER MA TENUE (sous la liste) : pièces de data/modifoutfits.json du service de la tenue mise (la dernière
      tenue mise avec /eup ; à défaut, la police de l'unité du MDC ; sinon Civil), plus celles de "Tous". La tenue
      actuelle est lue sur le personnage : une pièce déjà portée est cochée ; Entrée la met, ou la retire (la pièce
      de la tenue d'origine revient ; un accessoire de la tenue d'origine est enlevé). "Remettre la tenue d'origine" :
      la tenue telle qu'elle était (mise avec /eup, ou à la première ouverture de "Modifier ma tenue").
    Menu au CLAVIER, sans la souris (le joueur peut continuer à bouger), touches lues par client/kbmenu.lua :
      flèches haut / bas (maintenues : défilement), Entrée ou flèche droite : ouvrir / mettre la tenue,
      Retour arrière ou flèche gauche : revenir, Échap : fermer.
    L'affichage et la navigation sont dans le NUI (html/script.js).
    Aucune boucle dans ce fichier.
]]

local Config = InteractConfig
local E = Config.Eup or {}
local MALE, FEMALE = GetHashKey('mp_m_freemode_01'), GetHashKey('mp_f_freemode_01')

local open = false
local loading = false
local mods = {}          -- pièces de "Modifier ma tenue" (pour ce personnage), par id
local wornService = nil  -- service de la dernière tenue mise avec /eup ('WSP', 'KCSO', 'Civil'...)
local wornName = nil
local base = nil         -- tenue d'origine : { c = { [n°] = { modèle, texture } }, p = { [n°] = { modèle, texture } } }

local COMPONENTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local PROPS = { 0, 1, 2, 6, 7 }

local function gender()
    local model = GetEntityModel(PlayerPedId())
    if model == MALE then return 'male' end
    if model == FEMALE then return 'female' end
    return nil
end

local function close()
    if not open then return end
    open = false
    RPI.kbClose('eup')
    SendNUIMessage({ action = 'eup', data = { open = false } })
end

function RPI.openEup()
    if open or loading or RPI.spikesGuard() then return end
    local sex = gender()
    if not sex then
        return RPI.notify('Tenues disponibles uniquement avec un personnage multijoueur (homme / femme).', 'error')
    end
    loading = true
    RPI.request('eupList', {}, function(res)
        loading = false
        if not res or not res.ok then return RPI.notify(res and res.error or 'Tenues indisponibles.', 'error') end
        local list = {}
        for _, o in ipairs(res.outfits or {}) do
            if o.gender == nil or o.gender == sex then
                list[#list + 1] = { index = o.index, name = o.name, cate = o.cate, group = o.group }
            end
        end
        mods = {}
        local pieces = {}
        for _, m in ipairs(res.mods or {}) do
            if m.gender == nil or m.gender == sex then
                mods[m.id] = m
                pieces[#pieces + 1] = { id = m.id, name = m.name, service = m.service, category = m.category }
            end
        end
        open = true
        RPI.kbOpen('eup', close) -- ferme le Menu Interaction s'il est ouvert
        SendNUIMessage({ action = 'eup', data = {
            open = true, outfits = list, gender = sex, policeLocked = res.policeLocked == true,
            mods = pieces, service = wornService or res.service or 'Civil', wornName = wornName,
        } })
    end)
end

local function setProp(ped, id, d, t)
    if d < 0 then ClearPedProp(ped, id) else SetPedPropIndex(ped, id, d, t, true) end
end

--- Met la tenue ou la pièce (pièces envoyées par le serveur : { n°, modèle, texture }, déjà comptées à partir de 0)
local function wear(outfit)
    local ped = PlayerPedId()
    for _, c in ipairs(outfit.components or {}) do
        SetPedComponentVariation(ped, c[1], c[2], c[3], 0)
    end
    for _, p in ipairs(outfit.props or {}) do setProp(ped, p[1], p[2], p[3]) end
end

--- Tenue actuelle du personnage
local function readPed()
    local ped, out = PlayerPedId(), { c = {}, p = {} }
    for _, id in ipairs(COMPONENTS) do
        out.c[id] = { GetPedDrawableVariation(ped, id), GetPedTextureVariation(ped, id) }
    end
    for _, id in ipairs(PROPS) do
        local d = GetPedPropIndex(ped, id)
        out.p[id] = { d, d < 0 and 0 or GetPedPropTextureIndex(ped, id) }
    end
    return out
end

local function same(cur, d, t, prop)
    if not cur then return false end
    if prop and d < 0 then return cur[1] < 0 end
    return cur[1] == d and cur[2] == t
end

--- La pièce est-elle entièrement portée ?
local function isWorn(m, cur)
    for _, c in ipairs(m.components or {}) do if not same(cur.c[c[1]], c[2], c[3]) then return false end end
    for _, p in ipairs(m.props or {}) do if not same(cur.p[p[1]], p[2], p[3], true) then return false end end
    return true
end

local function wornList()
    local cur, ids = readPed(), {}
    for id, m in pairs(mods) do if isWorn(m, cur) then ids[#ids + 1] = id end end
    table.sort(ids)
    return ids
end

RegisterNUICallback('eupWear', function(data, cb)
    cb({ ok = true })
    if not open then return end
    local index = type(data) == 'table' and tonumber(data.index) or nil
    if not index then return end
    RPI.request('eupWear', { index = index }, function(res)
        if not res or not res.ok or type(res.outfit) ~= 'table' then
            return RPI.notify(res and res.error or 'Tenue indisponible.', 'error')
        end
        if res.outfit.gender and res.outfit.gender ~= gender() then
            return RPI.notify('Cette tenue n\'est pas faite pour ce personnage.', 'error')
        end
        wear(res.outfit)
        base = readPed()
        wornService = res.outfit.cate == 'police' and (res.outfit.group or 'Autres') or 'Civil'
        wornName = res.outfit.name
        SendNUIMessage({ action = 'eupWorn', data = { service = wornService, wornName = wornName } })
        RPI.notify(('Tenue : %s'):format(res.outfit.name), 'success')
    end)
end)

-- ---- Modifier ma tenue ----
RegisterNUICallback('eupModState', function(_, cb)
    if not open then return cb({ ok = false }) end
    base = base or readPed() -- pas de tenue mise avec /eup : la tenue actuelle devient la tenue d'origine
    cb({ ok = true, worn = wornList() })
end)

RegisterNUICallback('eupMod', function(data, cb)
    local m = open and type(data) == 'table' and mods[tonumber(data.id) or 0] or nil
    if not m then return cb({ ok = false }) end
    base = base or readPed()
    local ped, cur = PlayerPedId(), readPed()
    if not isWorn(m, cur) then
        wear(m)
        RPI.notify(('Ajouté : %s'):format(m.name), 'success')
    else
        -- Retirer : la pièce de la tenue d'origine revient (un accessoire déjà dans la tenue d'origine est enlevé)
        local changed = false
        for _, c in ipairs(m.components or {}) do
            local o = base.c[c[1]]
            if o and not same(o, c[2], c[3]) then SetPedComponentVariation(ped, c[1], o[1], o[2], 0); changed = true end
        end
        for _, p in ipairs(m.props or {}) do
            local o = base.p[p[1]]
            if o and not same(o, p[2], p[3], true) then setProp(ped, p[1], o[1], o[2]) else ClearPedProp(ped, p[1]) end
            changed = true
        end
        if changed then RPI.notify(('Retiré : %s'):format(m.name), 'success')
        else RPI.notify('Cette pièce fait partie de la tenue d\'origine : choisissez-en une autre pour la remplacer.', 'error') end
    end
    cb({ ok = true, worn = wornList() })
end)

RegisterNUICallback('eupModReset', function(_, cb)
    if not open then return cb({ ok = false }) end
    if base then
        local ped = PlayerPedId()
        for id, v in pairs(base.c) do SetPedComponentVariation(ped, id, v[1], v[2], 0) end
        for id, v in pairs(base.p) do setProp(ped, id, v[1], v[2]) end
        RPI.notify('Tenue d\'origine remise.', 'success')
    end
    cb({ ok = true, worn = wornList() })
end)

RegisterNUICallback('eupClose', function(_, cb)
    cb({ ok = true })
    close()
end)

RegisterCommand(E.Command or 'eup', function()
    if open then close() else RPI.openEup() end
end, false)
