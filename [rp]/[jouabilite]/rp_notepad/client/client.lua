--[[
    RP Notepad - client
    -------------------
    /notepad (ou la touche) : bloc-notes ouvert (écriture, souris), animation et props (bloc + crayon, vus par tous).
    À nouveau : fermé. Bouton œil : « mode visuel » (le bloc reste affiché, sans curseur : on marche, plus
    d'animation) ; la touche revient à l'écriture.
    PAGES GARDÉES chez le joueur (KVP du client) : texte de chaque page, dessins, dernière page utilisée et
    animation choisie ; à l'ouverture, retour à la dernière page utilisée (curseur à la fin du texte).
    Exports : transcript() (texte des pages, pour la note de l'unité du MDC), pages().
    Aucune boucle : seulement des événements.
]]

local C = NotepadConfig or {}
local KVP_DATA, KVP_DRAW = 'rp_notepad:data', 'rp_notepad:draw:'
local MAX = C.MaxPages or 30

local state = 0        -- 0 fermé, 1 écriture (curseur, animation), 2 visuel (on marche)
local props = {}
local playing = nil    -- animation en cours { dict, anim }

-- =========================================================================
-- PAGES (KVP du client : gardées d'une session à l'autre)
-- =========================================================================
local function loadData()
    local data = { page = 1, anim = (C.Anims or {})[1] and C.Anims[1].id or 'none', texts = {} }
    local raw = GetResourceKvpString(KVP_DATA)
    if raw then
        local ok, saved = pcall(json.decode, raw)
        if ok and type(saved) == 'table' then
            data.page = math.max(1, math.min(MAX, math.tointeger(tonumber(saved.page)) or 1))
            if type(saved.anim) == 'string' then data.anim = saved.anim end
            for i = 1, MAX do
                local t = type(saved.texts) == 'table' and saved.texts[i]
                data.texts[i] = type(t) == 'string' and t:sub(1, 4000) or ''
            end
        end
    end
    return data
end

local data = loadData()

local function saveData()
    local count = 0
    for i = 1, MAX do if (data.texts[i] or '') ~= '' then count = i end end
    local texts = {}
    for i = 1, math.max(count, data.page) do texts[i] = data.texts[i] or '' end
    SetResourceKvp(KVP_DATA, json.encode({ page = data.page, anim = data.anim, texts = texts }))
end

local function drawingOf(i) return GetResourceKvpString(KVP_DRAW .. i) or '' end

-- =========================================================================
-- ANIMATION ET PROPS
-- =========================================================================
local function animDef(id)
    for _, a in ipairs(C.Anims or {}) do if a.id == id then return a end end
    return (C.Anims or {})[1]
end

local function stopAnim()
    local ped = PlayerPedId()
    if playing then StopAnimTask(ped, playing.dict, playing.anim, 2.0) end
    playing = nil
    for _, obj in ipairs(props) do if DoesEntityExist(obj) then DeleteObject(obj) end end
    props = {}
end

local function loadModel(name)
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function playAnim()
    stopAnim()
    local def = animDef(data.anim)
    if not def then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end -- assis au volant : on écrit sans geste
    if def.dict then
        RequestAnimDict(def.dict)
        local deadline = GetGameTimer() + 1500
        while not HasAnimDictLoaded(def.dict) and GetGameTimer() < deadline do Wait(0) end
        if HasAnimDictLoaded(def.dict) then -- pack d'animations absent : props seulement
            TaskPlayAnim(ped, def.dict, def.anim, 8.0, -8.0, -1, 49, 0.0, false, false, false)
            playing = { dict = def.dict, anim = def.anim }
            RemoveAnimDict(def.dict)
        end
    end
    local c = GetEntityCoords(ped)
    for _, p in ipairs(def.props or {}) do
        local model = loadModel(p.model)
        if model then
            local obj = CreateObject(model, c.x, c.y, c.z + 0.2, true, true, false)
            SetModelAsNoLongerNeeded(model)
            SetEntityCollision(obj, false, false)
            AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, p.bone), p.pos[1], p.pos[2], p.pos[3],
                p.rot[1], p.rot[2], p.rot[3], true, true, false, true, 1, true)
            props[#props + 1] = obj
        end
    end
end

-- =========================================================================
-- OUVERTURE / FERMETURE
-- =========================================================================
local function openWriting()
    state = 1
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'mode', data = { visual = false } })
    CreateThread(playAnim)
end

local function open()
    if IsPauseMenuActive() or IsEntityDead(PlayerPedId()) then return end
    local pages = {}
    local last = data.page
    for i = 1, MAX do if (data.texts[i] or '') ~= '' or drawingOf(i) ~= '' then last = math.max(last, i) end end
    for i = 1, last do pages[i] = { text = data.texts[i] or '', drawing = drawingOf(i) } end
    local anims = {}
    for _, a in ipairs(C.Anims or {}) do anims[#anims + 1] = { id = a.id, label = a.label } end
    SendNUIMessage({ action = 'open', data = { pages = pages, page = data.page, anim = data.anim, anims = anims,
        lines = C.Lines or 13, maxPages = MAX } })
    openWriting()
end

local function close()
    if state == 0 then return end
    state = 0
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    stopAnim()
end

local function toggle()
    if state == 0 then open()
    elseif state == 2 then openWriting() -- mode visuel : retour à l'écriture
    else close() end
end
RegisterCommand(C.Command or 'notepad', toggle, false)
for _, alias in ipairs(C.Aliases or {}) do RegisterCommand(alias, toggle, false) end
RegisterKeyMapping(C.Command or 'notepad', 'Bloc-notes : ouvrir / fermer', 'keyboard', C.Key or 'F2')
TriggerEvent('chat:addSuggestion', '/' .. (C.Command or 'notepad'), 'Bloc-notes (écrire, dessiner ; pages gardées)')

-- =========================================================================
-- NUI
-- =========================================================================
RegisterNUICallback('close', function(_, cb) cb({ ok = true }) close() end)

RegisterNUICallback('visual', function(_, cb)
    cb({ ok = true })
    if state ~= 1 then return end
    state = 2
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'mode', data = { visual = true } })
    stopAnim()
end)

RegisterNUICallback('anim', function(d, cb)
    cb({ ok = true })
    if type(d) ~= 'table' or not animDef(d.id) or animDef(d.id).id ~= d.id then return end
    data.anim = d.id
    saveData()
    if state == 1 then CreateThread(playAnim) end
end)

--- Enregistrement (pendant la frappe / le dessin) : textes, page en cours, dessins modifiés
RegisterNUICallback('save', function(d, cb)
    cb({ ok = true })
    if type(d) ~= 'table' then return end
    data.page = math.max(1, math.min(MAX, math.tointeger(tonumber(d.page)) or data.page))
    if type(d.texts) == 'table' then
        for i = 1, MAX do
            local t = d.texts[i]
            data.texts[i] = type(t) == 'string' and t:sub(1, 4000) or ''
        end
    end
    if type(d.drawings) == 'table' then
        for k, v in pairs(d.drawings) do
            local i = math.tointeger(tonumber(k))
            if i and i >= 1 and i <= MAX then
                if type(v) == 'string' and v:sub(1, 22) == 'data:image/png;base64,' and #v < 600000 then
                    SetResourceKvp(KVP_DRAW .. i, v)
                else
                    DeleteResourceKvp(KVP_DRAW .. i)
                end
            end
        end
    end
    saveData()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if state ~= 0 then SetNuiFocus(false, false) end
    stopAnim()
end)

AddEventHandler('gameEventTriggered', function(name, args)
    if state ~= 0 and name == 'CEventNetworkEntityDamage' and args[1] == PlayerPedId() and IsEntityDead(PlayerPedId()) then close() end
end)

-- =========================================================================
-- EXPORTS (MDC : « Retranscription du notepad » dans la note de l'unité)
-- =========================================================================
--- Texte des pages écrites, dans l'ordre ; « — Page n — » devant chacune s'il y en a plusieurs
local function transcript()
    local written = {}
    for i = 1, MAX do
        local t = (data.texts[i] or ''):gsub('%s+$', '')
        if t ~= '' then written[#written + 1] = { i = i, text = t } end
    end
    if #written == 1 then return written[1].text end
    local parts = {}
    for _, w in ipairs(written) do parts[#parts + 1] = ('— Page %d —\n%s'):format(w.i, w.text) end
    return table.concat(parts, '\n')
end
exports('transcript', transcript)
exports('pages', function()
    local out = {}
    for i = 1, MAX do out[i] = data.texts[i] or '' end
    return out, data.page
end)
exports('isOpen', function() return state ~= 0 end)

RPNotepad = { transcript = transcript, data = function() return data end, open = open, close = close } -- tests
