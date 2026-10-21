--[[
    RP Interact - Menu des tenues /eup (client)
    -------------------------------------------
    Ouvert par la commande /eup (chat écrit, même sans nom RP) ou par Menu Interaction > Équipements >
    "Accéder aux tenues". Tenues de data/outfits.json (lues par le serveur), classées :
      Police > Atlanta Police Department (APD) / Fayette County Sheriff Office (FCSO) /
               Georgia State Patrol (GSP) (+ autres services du fichier) ; Civil.
    Seules les tenues du personnage (homme / femme, personnage multijoueur) sont listées.
    Menu au CLAVIER, sans la souris (le joueur peut continuer à bouger) :
      flèches haut / bas (maintenues : défilement), Entrée ou flèche droite : ouvrir / mettre la tenue,
      Retour arrière ou flèche gauche : revenir, Échap : fermer.
    L'affichage et la navigation sont dans le NUI (html/script.js) ; ce fichier lit les touches.
    Performance : boucle à chaque image UNIQUEMENT pendant que le menu est ouvert ; aucune sinon.
]]

local Config = InteractConfig
local E = Config.Eup or {}
local MALE, FEMALE = GetHashKey('mp_m_freemode_01'), GetHashKey('mp_f_freemode_01')

local open = false
local loading = false
local session = 0 -- n° d'ouverture : une seule boucle même si le menu est refermé puis rouvert dans la même image

-- Touches (contrôles du jeu) -> touche envoyée au NUI
local KEYS = {
    { controls = { 172 }, key = 'up', repeats = true },           -- flèche haut
    { controls = { 173 }, key = 'down', repeats = true },         -- flèche bas
    { controls = { 175 }, key = 'right' },                        -- flèche droite
    { controls = { 176, 191 }, key = 'select' },                  -- Entrée
    { controls = { 174 }, key = 'back' },                         -- flèche gauche
    { controls = { 177, 194 }, key = 'back' },                    -- Retour arrière
    { controls = { 200, 322 }, key = 'close' },                   -- Échap
}
-- Désactivées pendant que le menu est ouvert (pause, armes, téléphone, sélection d'arme…)
local DISABLED = { 24, 25, 37, 44, 140, 141, 142, 257, 263, 172, 173, 174, 175, 176, 177, 191, 194, 199, 200, 322, 14, 15, 16, 17, 27 }
local REPEAT_DELAY, REPEAT_RATE = 350, 80 -- ms : défilement en maintenant une flèche

local function gender()
    local model = GetEntityModel(PlayerPedId())
    if model == MALE then return 'male' end
    if model == FEMALE then return 'female' end
    return nil
end

local function close()
    if not open then return end
    open = false
    SendNUIMessage({ action = 'eup', data = { open = false } })
end

local function keyLoop()
    session = session + 1
    local mine = session
    CreateThread(function()
        local held, nextRepeat = nil, 0
        while open and session == mine do
            for _, control in ipairs(DISABLED) do DisableControlAction(0, control, true) end
            -- Une autre fenêtre (menu, fiche, œil) a la main : pas de touches pour ce menu
            if not RPI.uiOpen() and not (RPI.targetActive and RPI.targetActive()) and not IsPauseMenuActive() then
                local now = GetGameTimer()
                local pressedAny, sent = false, {}
                for _, k in ipairs(KEYS) do
                    for _, control in ipairs(k.controls) do
                        -- Une touche peut répondre à plusieurs contrôles (Entrée : 176 et 191) : une fois par image
                        if IsDisabledControlJustPressed(0, control) and not sent[k.key] then
                            sent[k.key] = true
                            SendNUIMessage({ action = 'eupKey', data = { key = k.key } })
                            if k.repeats then held, nextRepeat = k, now + REPEAT_DELAY end
                        end
                        if k == held and IsDisabledControlPressed(0, control) then pressedAny = true end
                    end
                end
                if held and not pressedAny then held = nil end
                if held and now >= nextRepeat then
                    nextRepeat = now + REPEAT_RATE
                    SendNUIMessage({ action = 'eupKey', data = { key = held.key } })
                end
            end
            if IsEntityDead(PlayerPedId()) then close() end
            Wait(0)
        end
    end)
end

function RPI.openEup()
    if open or loading then return end
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
        open = true
        SendNUIMessage({ action = 'eup', data = {
            open = true, outfits = list, gender = sex, policeLocked = res.policeLocked == true,
        } })
        keyLoop()
    end)
end

--- Met la tenue (pièces envoyées par le serveur : { n°, modèle, texture }, déjà comptées à partir de 0)
local function wear(outfit)
    local ped = PlayerPedId()
    for _, c in ipairs(outfit.components or {}) do
        SetPedComponentVariation(ped, c[1], c[2], c[3], 0)
    end
    for _, p in ipairs(outfit.props or {}) do
        if p[2] < 0 then ClearPedProp(ped, p[1]) else SetPedPropIndex(ped, p[1], p[2], p[3], true) end
    end
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
        RPI.notify(('Tenue : %s'):format(res.outfit.name), 'success')
    end)
end)

RegisterNUICallback('eupClose', function(_, cb)
    cb({ ok = true })
    close()
end)

RegisterCommand(E.Command or 'eup', function()
    if open then close() else RPI.openEup() end
end, false)
