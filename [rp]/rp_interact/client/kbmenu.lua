--[[
    RP Interact - Menus au clavier (client)
    ---------------------------------------
    Boucle de touches commune au Menu Interaction (client/main.lua) et au menu des tenues /eup (client/eup.lua).
    Les menus n'ont PAS le focus du NUI : le joueur continue de bouger pendant qu'ils sont ouverts.
      flèches haut / bas (maintenues : défilement), Entrée : valider, flèche droite : ouvrir / valeur suivante,
      flèche gauche : valeur précédente (sinon retour), Retour arrière : revenir, Échap : fermer.
    Un seul menu au clavier à la fois : en ouvrir un ferme l'autre.
    Saisie de texte (secteur, lien de la radio, nom d'un équipement) : le NUI demande le clavier ("kbTyping") le
    temps de la saisie (focus clavier sans curseur), puis le rend.
    L'affichage et la navigation sont dans le NUI (html/script.js : KbMenu) ; ce fichier lit les touches.
    Performance : boucle à chaque image UNIQUEMENT pendant qu'un menu est ouvert ; aucune sinon.
]]

local KB = { name = nil, onClose = nil, session = 0, typing = false }

-- Touches (contrôles du jeu) -> touche envoyée au NUI
local KEYS = {
    { controls = { 172 }, key = 'up', repeats = true },           -- flèche haut
    { controls = { 173 }, key = 'down', repeats = true },         -- flèche bas
    { controls = { 175 }, key = 'right', repeats = true },        -- flèche droite
    { controls = { 174 }, key = 'left', repeats = true },         -- flèche gauche
    { controls = { 176, 191 }, key = 'select' },                  -- Entrée
    { controls = { 177, 194 }, key = 'back' },                    -- Retour arrière
    { controls = { 200, 322 }, key = 'close' },                   -- Échap
}
-- Désactivées pendant qu'un menu est ouvert (pause, armes, téléphone, sélection d'arme, Entrée du jeu…)
local DISABLED = { 18, 24, 25, 37, 44, 140, 141, 142, 257, 263, 172, 173, 174, 175, 176, 177, 187, 188, 189, 190,
    191, 194, 199, 200, 201, 322, 14, 15, 16, 17, 27 }
local REPEAT_DELAY, REPEAT_RATE = 350, 80 -- ms : défilement en maintenant une flèche

local function send(key)
    SendNUIMessage({ action = 'kbKey', data = { menu = KB.name, key = key } })
end

local function keyLoop()
    KB.session = KB.session + 1
    local mine = KB.session
    CreateThread(function()
        local held, nextRepeat = nil, 0
        while KB.name and KB.session == mine do
            for _, control in ipairs(DISABLED) do DisableControlAction(0, control, true) end
            -- Une fenêtre (fiche civile, liste de l'œil) ou l'œil a la main, ou une saisie est en cours : pas de touches
            if not KB.typing and not RPI.uiOpen() and not (RPI.targetActive and RPI.targetActive()) and not IsPauseMenuActive() then
                local now = GetGameTimer()
                local pressedAny, sent = false, {}
                for _, k in ipairs(KEYS) do
                    for _, control in ipairs(k.controls) do
                        -- Une touche peut répondre à plusieurs contrôles (Entrée : 176 et 191) : une fois par image
                        if IsDisabledControlJustPressed(0, control) and not sent[k.key] then
                            sent[k.key] = true
                            send(k.key)
                            if k.repeats then held, nextRepeat = k, now + REPEAT_DELAY end
                        end
                        if k == held and IsDisabledControlPressed(0, control) then pressedAny = true end
                    end
                end
                if held and not pressedAny then held = nil end
                if held and now >= nextRepeat then
                    nextRepeat = now + REPEAT_RATE
                    send(held.key)
                end
            else
                held = nil
            end
            if IsEntityDead(PlayerPedId()) and KB.name then RPI.kbClose(KB.name) end
            Wait(0)
        end
    end)
end

--- Ouvre le menu au clavier `name` ; onClose() est appelée quand il se ferme (par RPI.kbClose ou un autre menu)
function RPI.kbOpen(name, onClose)
    if KB.name and KB.name ~= name then RPI.kbClose(KB.name) end
    local running = KB.name == name
    KB.name, KB.onClose = name, onClose
    if not running then keyLoop() end
end

function RPI.kbClose(name)
    if not KB.name or (name and KB.name ~= name) then return end
    local onClose = KB.onClose
    KB.name, KB.onClose = nil, nil
    if KB.typing then
        KB.typing = false
        RPI.applyFocus()
    end
    if onClose then onClose() end
end

--- Un menu au clavier est-il ouvert ? (`name` : celui-là)
function RPI.kbActive(name)
    if name then return KB.name == name end
    return KB.name ~= nil
end

function RPI.kbTyping() return KB.typing end

-- Saisie de texte dans un menu : le NUI prend le clavier (sans curseur) le temps de la saisie
RegisterNUICallback('kbTyping', function(data, cb)
    local typing = type(data) == 'table' and data.active == true and KB.name ~= nil
    if typing ~= KB.typing then
        KB.typing = typing
        RPI.applyFocus()
    end
    cb({ ok = true })
end)
