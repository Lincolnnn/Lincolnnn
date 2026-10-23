--[[
    RP Interact - Mode civil et tips d'arrestation
    ----------------------------------------------
    MODE CIVIL (case à cocher dans Menu > Civil, gardée chez le joueur) : options visuelles
    propres au rôle de civil. La première : les TIPS D'ARRESTATION, un mini menu NON interactif
    en haut au milieu de l'écran qui rappelle les touches :
        H = Mains en l'air (/e serendre17)   J = À genoux (/e serendre3)   L = S'allonger (/e serendre6)
        X = arrêter l'emote
    Les touches sont des raccourcis de la commande "/e …" du mode d'emotes du serveur (RPEMOTES).
    X arrête l'emote par le mode d'emotes lui-même (export EmoteCancel) : pas de conflit avec le X de
    RPEMOTES, jamais le message "No emote to cancel".
    Il apparaît :
      - quand un policier (joueur dans une unité du MDC) met le civil en joue avec une arme
        (visée directe ou à moins de 5 m autour de lui) ;
      - ou à la demande : Menu > Civil > Tips arrestation.
    Il ne se ferme QUE par la touche Échap (rappel écrit en petit sur le mini menu) : il reste affiché
    quand le policier arrête de viser.
    Les touches ne font l'emote QUE pendant que le mini menu est affiché.

    DÉTECTION CÔTÉ POLICIER (fiable, sans dépendre d'une touche) : tant que le policier est en service
    (unité du MDC), une vérification légère de la visée toutes les 250 ms ; pendant qu'il vise avec une
    arme à feu, détection des joueurs visés toutes les 150 ms. Hors service : aucune boucle.
]]

local Config = InteractConfig
local KVP_KEY = 'rpi_civil_mode'

local civilMode = GetResourceKvpString(KVP_KEY) == '1'
-- shown : tips affichés (ouverts par une mise en joue ou par le menu) ; ils ne se ferment QU'AVEC
-- la touche Échap (jamais d'eux-mêmes, même quand le policier arrête de viser).
-- aimed : un policier vise le joueur en ce moment (titre rouge).
local tips = { shown = false, aimed = false }

-- Partagé avec le MDC (ce joueur uniquement, non répliqué) : page "Créations" en mode civil uniquement
LocalPlayer.state:set('rpiCivilMode', civilMode, false)

function RPI.civilMode() return civilMode end
function RPI.tipsManual() return civilMode and tips.shown end

--- Touche réellement choisie par le joueur pour une commande (raccourci FiveM)
local function keyLabel(command, default)
    local ok, button = pcall(GetControlInstructionalButton, 0, GetHashKey(command) | 0x80000000, true)
    if ok and type(button) == 'string' and button:sub(1, 2) == 't_' then return button:sub(3) end
    return default
end

local function tipsVisible()
    return civilMode and tips.shown
end

-- Touches fixes, lues image par image (petite boucle active seulement tant que les tips sont affichés) :
--   X     : arrêter l'emote en cours
--   Échap : fermer les tips. Le menu pause / la carte du jeu s'ouvrent au RELÂCHEMENT d'Échap : les
--           commandes de pause restent bloquées jusqu'à ce que la touche soit relâchée (+ quelques
--           images), puis la boucle s'arrête.
local STOP_KEY = 73                    -- X
local PAUSE_KEYS = { 199, 200, 322 }   -- pause (P), pause (Échap), Échap (selon la configuration)
local keyLoopRunning = false
local renderTips

local function closeTips()
    tips.shown, tips.aimed = false, false
    renderTips()
end

local function blockPause()
    for _, control in ipairs(PAUSE_KEYS) do DisableControlAction(0, control, true) end
end

local function escPressed()
    return IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322)
end

local function escHeld()
    return IsDisabledControlPressed(0, 200) or IsDisabledControlPressed(0, 322)
end

local function startKeyLoop()
    if keyLoopRunning then return end
    keyLoopRunning = true
    CreateThread(function()
        while tipsVisible() do
            Wait(0)
            if not RPI.uiOpen() and not RPI.kbActive() then -- Échap d'un menu au clavier : pour le menu
                blockPause()
                if escPressed() then
                    closeTips()
                elseif IsControlJustPressed(0, STOP_KEY) and not (RPI.isCuffed and RPI.isCuffed()) then
                    RPI.cancelEmote()
                end
            end
        end
        -- Fermés avec Échap : pause bloquée jusqu'au relâchement de la touche (max 3 s), puis 10 images
        local untilTime, extra = GetGameTimer() + 3000, 10
        while extra > 0 and GetGameTimer() < untilTime and not tipsVisible() do
            blockPause()
            if IsPauseMenuActive() then SetPauseMenuActive(false) end
            if not escHeld() then extra = extra - 1 end
            Wait(0)
        end
        keyLoopRunning = false
        if tipsVisible() then renderTips() end -- rouverts entre-temps : la boucle repart
    end)
end

renderTips = function()
    local keys = {}
    for i, s in ipairs(Config.Surrender) do
        keys[i] = { key = keyLabel(s.command, s.key), label = s.label }
    end
    keys[#keys + 1] = { key = 'X', label = 'Arrêter l\'emote', stop = true }
    local show = tipsVisible()
    SendNUIMessage({ action = 'tips', data = { show = show, aimed = tips.aimed, keys = keys } })
    if show then startKeyLoop() end
end

local function setCivilMode(enabled)
    civilMode = enabled == true
    SetResourceKvp(KVP_KEY, civilMode and '1' or '0')
    LocalPlayer.state:set('rpiCivilMode', civilMode, false) -- MDC : page "Créations" en mode civil uniquement
    if not civilMode then tips.shown, tips.aimed = false, false end
    renderTips()
end

--- Bouton du menu : ouvre les tips (ou les ferme s'ils sont déjà affichés)
local function toggleManualTips()
    tips.shown = not tips.shown
    if not tips.shown then tips.aimed = false end
    renderTips()
    return tips.shown
end

-- ---- Menu d'interactions ----
RegisterNUICallback('setCivilMode', function(data, cb)
    setCivilMode(type(data) == 'table' and data.enabled == true)
    cb({ ok = true, civilMode = civilMode })
end)

RegisterNUICallback('toggleTips', function(_, cb)
    if not civilMode then return cb({ ok = false, error = 'Activez d\'abord le mode civil.' }) end
    local visible = toggleManualTips()
    -- Le menu se ferme pour que les touches répondent (elles ne marchent pas quand une fenêtre a le focus)
    if visible then RPI.closeMenu() end
    cb({ ok = true, visible = visible })
end)

-- ---- Touches des emotes (actives seulement quand les tips sont affichés) ----
for _, s in ipairs(Config.Surrender) do
    RegisterCommand(s.command, function()
        if tipsVisible() and not RPI.uiOpen() then RPI.playEmote(s.emote) end -- = taper "/e …"
    end, false)
    RegisterKeyMapping(s.command, ('Civil : %s (tips d\'arrestation)'):format(s.label), 'keyboard', s.key)
end

-- ---- Mise en joue par un policier (prévenu par le serveur : début / fin) ----
-- Début : les tips s'affichent (titre rouge). Fin : ils RESTENT affichés (titre normal) jusqu'à Échap.
RegisterNetEvent('rp_interact:client:aimed', function(aimed)
    if aimed then
        tips.shown, tips.aimed = true, true
    elseif tips.aimed then
        tips.aimed = false
    else
        return
    end
    renderTips()
end)

-- =========================================================================
-- CÔTÉ POLICIER : qui est mis en joue ?
-- =========================================================================

--- Joueurs visés : visée directe, ou à moins de AimRadius mètres de la ligne de visée
local function aimTargets()
    local me = PlayerId()
    local ped = PlayerPedId()
    if not IsPlayerFreeAiming(me) or not IsPedArmed(ped, 4) then return {} end -- 4 = armes à feu

    local cam = GetFinalRenderedCamCoord()
    local dir = RPI.camDirection(GetFinalRenderedCamRot(2))
    local _, aimedEntity = GetEntityPlayerIsFreeAimingAt(me)
    local list = {}
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= me then
            local target = GetPlayerPed(player)
            local pos = GetEntityCoords(target)
            local rel = pos - cam
            local along = rel.x * dir.x + rel.y * dir.y + rel.z * dir.z -- distance le long de la visée
            if target == aimedEntity
                or (along > 0 and along <= Config.AimRange and #(pos - (cam + dir * along)) <= Config.AimRadius) then
                list[#list + 1] = GetPlayerServerId(player)
            end
        end
    end
    table.sort(list)
    return list
end
RPI.aimTargets = aimTargets

local aimWatching = false
local AIM_INTERVAL, IDLE_INTERVAL = 150, 250

--- Tant que le joueur est policier en service : la visée est surveillée (aucune touche nécessaire,
--- fonctionne aussi avec une manette ou un raccourci de visée modifié)
local function startAimWatch()
    if aimWatching or not RPI.isPolice() then return end
    aimWatching = true
    CreateThread(function()
        local lastKey, lastSent = '', 0
        while RPI.isPolice() do
            local aiming = IsPlayerFreeAiming(PlayerId())
            local list = aiming and aimTargets() or {}
            local key = table.concat(list, ',')
            local now = GetGameTimer()
            -- Envoi au changement, puis confirmation régulière tant que la visée dure
            if key ~= lastKey or (key ~= '' and now - lastSent >= Config.AimRefresh) then
                TriggerServerEvent('rp_interact:server:aiming', list)
                lastKey, lastSent = key, now
            end
            Wait(aiming and AIM_INTERVAL or IDLE_INTERVAL)
        end
        if lastKey ~= '' then TriggerServerEvent('rp_interact:server:aiming', {}) end
        aimWatching = false
    end)
end
RPI.onDuty(startAimWatch)
startAimWatch()
