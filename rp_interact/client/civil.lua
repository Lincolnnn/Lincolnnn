--[[
    RP Interact - Mode civil et tips d'arrestation
    ----------------------------------------------
    MODE CIVIL (case à cocher dans Menu > Civil, gardée chez le joueur) : options visuelles
    propres au rôle de civil. La première : les TIPS D'ARRESTATION, un mini menu NON interactif
    en haut au milieu de l'écran qui rappelle les touches :
        H = Mains en l'air (/e serendre17)   J = À genoux (/e serendre3)   L = S'allonger (/e serendre6)
    Il apparaît :
      - quand un policier (joueur dans une unité du MDC) met le civil en joue avec une arme
        (visée directe ou à moins de 5 m autour de lui) ;
      - ou à la demande : Menu > Civil > Tips arrestation.
    Les touches ne font l'emote QUE pendant que le mini menu est affiché.

    DÉTECTION CÔTÉ POLICIER : une boucle (200 ms) tourne uniquement pendant que le policier
    maintient le clic droit (visée), et seulement s'il est dans une unité du MDC.
]]

local Config = InteractConfig
local KVP_KEY = 'rpi_civil_mode'

local civilMode = GetResourceKvpString(KVP_KEY) == '1'
local tips = { aimed = false, manual = false, aimToken = 0, manualToken = 0 }

function RPI.civilMode() return civilMode end
function RPI.tipsManual() return tips.manual end

--- Touche réellement choisie par le joueur pour une commande (raccourci FiveM)
local function keyLabel(command, default)
    local ok, button = pcall(GetControlInstructionalButton, 0, GetHashKey(command) | 0x80000000, true)
    if ok and type(button) == 'string' and button:sub(1, 2) == 't_' then return button:sub(3) end
    return default
end

local function tipsVisible()
    return civilMode and (tips.aimed or tips.manual)
end

local function renderTips()
    local keys = {}
    for i, s in ipairs(Config.Surrender) do
        keys[i] = { key = keyLabel(s.command, s.key), label = s.label }
    end
    SendNUIMessage({ action = 'tips', data = { show = tipsVisible(), aimed = tips.aimed, keys = keys } })
end

local function setCivilMode(enabled)
    civilMode = enabled == true
    SetResourceKvp(KVP_KEY, civilMode and '1' or '0')
    if not civilMode then tips.manual = false end
    renderTips()
end

--- Tips ouverts / fermés depuis le menu (fermeture automatique après TipsManualDuration)
local function toggleManualTips()
    tips.manual = not tips.manual
    tips.manualToken = tips.manualToken + 1
    if tips.manual then
        local token = tips.manualToken
        SetTimeout(Config.TipsManualDuration, function()
            if tips.manualToken == token and tips.manual then
                tips.manual = false
                renderTips()
            end
        end)
    end
    renderTips()
    return tips.manual
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
        if tipsVisible() and not RPI.uiOpen() then ExecuteCommand(s.emote) end
    end, false)
    RegisterKeyMapping(s.command, ('Civil : %s (tips d\'arrestation)'):format(s.label), 'keyboard', s.key)
end

-- ---- Mise en joue par un policier (prévenu par le serveur : début / fin) ----
RegisterNetEvent('rp_interact:client:aimed', function(aimed)
    tips.aimToken = tips.aimToken + 1
    if aimed then
        tips.aimed = true
        renderTips()
    elseif tips.aimed then
        -- Les tips restent un court instant après la fin de la mise en joue
        local token = tips.aimToken
        SetTimeout(Config.TipsAimDelay, function()
            if tips.aimToken == token then
                tips.aimed = false
                renderTips()
            end
        end)
    end
end)

-- =========================================================================
-- CÔTÉ POLICIER : qui est mis en joue ?
-- =========================================================================
local aimWatching = false

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

RegisterCommand('+rpi_aimwatch', function()
    if aimWatching or not RPI.isPolice() then return end
    aimWatching = true
    CreateThread(function()
        local lastKey, lastSent = '', 0
        while aimWatching do
            local list = aimTargets()
            local key = table.concat(list, ',')
            local now = GetGameTimer()
            -- Envoi au changement, puis confirmation régulière tant que la visée dure
            if key ~= lastKey or (key ~= '' and now - lastSent >= Config.AimRefresh) then
                TriggerServerEvent('rp_interact:server:aiming', list)
                lastKey, lastSent = key, now
            end
            Wait(200)
        end
        if lastKey ~= '' then TriggerServerEvent('rp_interact:server:aiming', {}) end
    end)
end, false)
RegisterCommand('-rpi_aimwatch', function() aimWatching = false end, false)
RegisterKeyMapping('+rpi_aimwatch', 'Police : mise en joue (tips d\'arrestation du civil)', 'MOUSE_BUTTON', Config.AimWatchKey)
