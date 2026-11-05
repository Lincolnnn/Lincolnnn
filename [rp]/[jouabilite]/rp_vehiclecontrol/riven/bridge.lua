--[[
    Vehicle Control - pont avec Riven Impact Dynamics (client, chargé DANS la ressource de Riven)
    ----------------------------------------------------------------------------------------------
    Une seule ligne à ajouter à la fin de riven-impact-dynamics/fxmanifest.lua (voir README) :
        client_script '@rp_vehiclecontrol/riven/bridge.lua'
    Ce fichier ne change rien au code de Riven ni à sa licence : il attend que Riven ait démarré (licence vérifiée
    par Riven lui-même ; refusée, il ne fait rien), puis :
      - VOYANTS : les petits logos de dégâts de Riven (ses propres icônes, dessinées par son NUI) sont placés juste
        au-dessus du car HUD du MDC et liés à lui : même position, même taille (Paramètres du MDC > HUD : déplacé,
        agrandi, ils suivent), affichés seulement quand le car HUD l'est. Le voyant de ceinture est retiré (le car
        HUD a déjà le sien). Ils n'apparaissent, comme chez Riven, que lorsque le véhicule est abîmé ;
      - NOTIFICATIONS : celles de Riven (notifications du jeu, en anglais) deviennent des messages privés du chat en
        français (rp_chat), titre « Véhicule », comme celles de nos scripts. Ses textes à l'écran (portière coincée,
        barre de réparation) sont traduits aussi.
    Console F8 : « pont Riven actif » quand tout est en place (sinon : la ligne du fxmanifest manque ou Riven n'a pas
    démarré). rp_vehiclecontrol le sait aussi (événement rp_vehiclecontrol:rivenBridge) : ses notifications de
    secours (sans ce pont) se coupent.
    Ceinture et frein de parking : messages écrits par rp_vehiclecontrol (client/riven.lua), ceux de Riven coupés ici.
    Réglages : rp_vehiclecontrol/config.lua, Riven (Lamps, HideLamps, Notify, MuteBelt).
    Performance : aucune boucle ; un envoi au NUI de Riven seulement quand le car HUD bouge ou apparaît.
]]

local VC_RESOURCE = 'rp_vehiclecontrol'

-- Réglages par défaut (remplacés par ceux de rp_vehiclecontrol/config.lua s'il est démarré)
local settings = { Lamps = true, HideLamps = { 'belt' }, Notify = true, MuteBelt = false }
local settingsLoaded = false

local function loadSettings()
    if settingsLoaded or GetResourceState(VC_RESOURCE) ~= 'started' then return end
    local ok, res = pcall(function() return exports[VC_RESOURCE]:rivenSettings() end)
    if ok and type(res) == 'table' then settings, settingsLoaded = res, true end
end

print('^5[rp_vehiclecontrol] pont Riven chargé dans ' .. GetCurrentResourceName() .. ' : en attente du démarrage de Riven^7')

-- =========================================================================
-- TRADUCTION
-- =========================================================================
local TYRES = { ['front left'] = 'avant gauche', ['front right'] = 'avant droit',
    ['rear left'] = 'arrière gauche', ['rear right'] = 'arrière droit' }

local BELT = { ['Seatbelt fastened.'] = true, ['Seatbelt unfastened.'] = true }
-- Frein de parking : rp_vehiclecontrol écrit lui-même ces messages (« P » sur le car HUD), ceux de Riven sont coupés
local PARK = { ['Parking brake set.'] = true, ['Parking brake released.'] = true,
    ['Rolled over: parking brake set automatically.'] = true, ['Crash: parking brake set automatically.'] = true }

local EXACT = {
    ['Seatbelt fastened.'] = 'Ceinture attachée.',
    ['Seatbelt unfastened.'] = 'Ceinture détachée.',
    ['This vehicle has no seatbelts.'] = 'Ce véhicule n\'a pas de ceinture.',
    ['Parking brake set.'] = 'Frein à main serré.',
    ['Parking brake released.'] = 'Frein à main desserré.',
    ['Stop the vehicle to use the parking brake.'] = 'Arrêtez le véhicule pour serrer le frein à main.',
    ['The parking brake is on.'] = 'Le frein à main est serré.',
    ['The parking brake isn\'t set - the car will roll.'] = 'Le frein à main n\'est pas serré : le véhicule va rouler.',
    ['Rolled over: parking brake set automatically.'] = 'Tonneau : frein à main serré automatiquement.',
    ['Crash: parking brake set automatically.'] = 'Accident : frein à main serré automatiquement.',
    ['Severe rollover. The vehicle is wrecked and heavily damaged.'] = 'Tonneau violent : le véhicule est détruit.',
    ['Rollover damage. Steering, suspension and cooling took a major hit.'] = 'Tonneau : direction, suspensions et refroidissement très touchés.',
    ['The door is jammed. Hold F to force it.'] = 'La portière est coincée. Maintenez F pour la forcer.',
    ['Your door is jammed. Hold F to force it open.'] = 'Votre portière est coincée. Maintenez F pour la forcer.',
    ['Get in a vehicle first.'] = 'Montez d\'abord dans un véhicule.',
    ['You need to be in a vehicle.'] = 'Vous devez être dans un véhicule.',
    ['Get in the driver\'s seat of a vehicle first.'] = 'Prenez d\'abord la place du conducteur.',
    ['Get in the driver seat of the car you want to burn.'] = 'Prenez la place du conducteur du véhicule à brûler.',
    ['Effect settings are turned off on this server.'] = 'Les réglages des effets sont désactivés sur ce serveur.',
    ['The engine stalled. Hold accelerate to try to restart it.'] = 'Le moteur a calé. Maintenez l\'accélérateur pour le relancer.',
    ['The engine cranks but won\'t catch...'] = 'Le démarreur tourne, mais le moteur ne part pas…',
    ['The engine sputters back to life.'] = 'Le moteur toussote et repart.',
    ['The engine is destroyed. It won\'t turn over.'] = 'Le moteur est détruit : il ne démarre plus.',
    ['The engine cut out.'] = 'Le moteur s\'est coupé.',
    ['The tank has leaked dry.'] = 'Le réservoir s\'est entièrement vidé.',
    ['Leaking fuel caught fire!'] = 'L\'essence qui fuit a pris feu !',
    ['Fire under the hood. Get out!'] = 'Feu sous le capot : sortez !',
    ['Not while it\'s on fire.'] = 'Pas pendant qu\'il brûle.',
    ['No vehicle nearby.'] = 'Aucun véhicule à proximité.',
    ['No vehicle close enough to inspect.'] = 'Aucun véhicule assez proche pour l\'inspecter.',
    ['This vehicle type is ignored by Riven Impact Dynamics.'] = 'Ce type de véhicule n\'a pas de dégâts réalistes.',
    ['That tyre is already flat or losing air.'] = 'Ce pneu est déjà crevé ou se dégonfle.',
    ['Stopped.'] = 'Arrêté.',
    ['Stop the car and close its doors first.'] = 'Arrêtez le véhicule et fermez ses portières d\'abord.',
    ['Stand next to a car to fit snow chains.'] = 'Placez-vous à côté d\'un véhicule pour poser les chaînes.',
    ['Get out to fit or remove snow chains.'] = 'Descendez pour poser ou retirer les chaînes.',
    ['Fitting snow chains...'] = 'Pose des chaînes…',
    ['Taking the snow chains off...'] = 'Retrait des chaînes…',
    ['Snow chains removed.'] = 'Chaînes retirées.',
    ['A snow chain snapped off. Chains are for slow driving.'] = 'Une chaîne a cassé : avec des chaînes, on roule doucement.',
    ['Stand at the front of the car to work on it.'] = 'Placez-vous devant le véhicule pour travailler dessus.',
    ['Get out and stand at the front of the car.'] = 'Descendez et placez-vous devant le véhicule.',
    ['Repair cancelled.'] = 'Réparation annulée.',
    ['It\'s already been patched up. It needs a proper mechanic now.'] = 'Déjà réparé de fortune : il lui faut maintenant un vrai garagiste.',
    ['Nothing here needs patching up.'] = 'Rien à réparer ici.',
    ['You don\'t have what you need to fix this.'] = 'Vous n\'avez pas ce qu\'il faut pour réparer ça.',
    ['You need a breather before patching up another car.'] = 'Soufflez un peu avant de réparer un autre véhicule.',
    ['Patched up. It\'ll get you to a mechanic, no further.'] = 'Réparation de fortune faite : il vous mènera jusqu\'au garagiste, pas plus loin.',
    ['Vehicle repaired.'] = 'Véhicule réparé.',
    ['This vehicle has no windscreen.'] = 'Ce véhicule n\'a pas de pare-brise.',
    ['No ground found in front of you.'] = 'Aucun sol trouvé devant vous.',
    ['Crash debris cleared (on your screen).'] = 'Débris d\'accident retirés (chez vous).',
    ['Riven impact warnings on.'] = 'Voyants de dégâts affichés.',
    ['Riven impact warnings off.'] = 'Voyants de dégâts masqués.',
    ['Impact sounds on.'] = 'Sons des chocs activés.',
    ['Impact sounds off.'] = 'Sons des chocs désactivés.',
    ['Impact effect settings saved.'] = 'Réglages des effets enregistrés.',
    ['Impact effect settings reset to the server defaults.'] = 'Réglages des effets remis par défaut.',
    ['Impact warning position editing is disabled on this server.'] = 'Les voyants suivent le car HUD : déplacez-le dans les Paramètres du MDC.',
    ['Some crash models are missing. Check F8 and the resource stream folder.'] = 'Des modèles d\'accident manquent : voir la console F8 et le dossier stream de Riven.',
    ['3D crash models loaded correctly.'] = 'Modèles 3D d\'accident chargés.',
    -- barre de progression
    ['Patching up the engine'] = 'Réparation de fortune du moteur',
    ['Forcing the door'] = 'Ouverture forcée de la portière',
}

local function tyre(name) return TYRES[name] or name end

-- { motif du texte anglais, fonction qui rend le français }
local PATTERNS = {
    { '^Unfasten your seatbelt first %((.-)%)%.$', function(key) return ('Détachez d\'abord votre ceinture (%s).'):format(key) end },
    { '^Engine fire started%. Burnt out in about (%d+) s%. Get out!$', function(s) return ('Le moteur prend feu : véhicule calciné dans %s s environ. Sortez !'):format(s) end },
    { '^Tyre pressure dropping %- (.+)$', function(t) return ('Pneu %s : il se dégonfle.'):format(tyre(t)) end },
    { '^Tyre shredded %- on the rim, (.+)$', function(t) return ('Pneu %s déchiqueté : sur la jante.'):format(tyre(t)) end },
    { '^Flat tyre %- (.+)$', function(t) return ('Pneu %s crevé.'):format(tyre(t)) end },
    { '^Plugging tyre %- (.+)$', function(t) return ('Réparation du pneu %s'):format(tyre(t)) end },
    { '^Test: (.-) tyre picked up a nail%.$', function(t) return ('Test : le pneu %s a pris un clou.'):format(tyre(t)) end },
    { '^Snow chains fitted%. Keep it under (%d+) km/h%.$', function(k) return ('Chaînes posées : ne dépassez pas %s km/h.'):format(k) end },
    -- « débris retirés par … » (touche / commande de Riven) : notification générale supprimée (rien d'affiché)
    { '^Crash debris cleared by (.-) %((%d+) pieces here%)%.$', function() return nil end },
    { '^Impact sound volume set to (%d+)%.$', function(v) return ('Volume des sons des chocs : %s.'):format(v) end },
    { '^Impact sound volume is (%d+)%. Use /impactvolume 0%-100%.$', function(v) return ('Volume des sons des chocs : %s (/impactvolume 0-100).'):format(v) end },
    { '^Riven Impact Dynamics: (.+)$', function(f) return ('Dégâts réalistes : %s'):format(f) end },
}

--- Texte d'une notification du jeu sans ses codes de couleur (~r~, ~w~, ~n~…)
local function plain(text)
    return (text:gsub('~n~', ' '):gsub('~[%a]~', ''):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', ''))
end

--- Texte français (texte d'origine sans couleurs s'il n'est pas connu) ; muet : rien à afficher
local function translate(text)
    local p = plain(text)
    -- ceinture / frein de parking : écrits par rp_vehiclecontrol (OwnBelt / OwnPark), sinon traduits ici
    if BELT[p] and (settings.MuteBelt == true or (settingsLoaded and settings.OwnBelt)) then return p, true end
    if PARK[p] and settingsLoaded and settings.OwnPark then return p, true end
    -- pneus (crevé, se dégonfle, sur la jante) : le voyant de Riven le montre déjà (Riven.MuteTyres)
    if settings.MuteTyres ~= false and (p:find('^Tyre pressure dropping') or p:find('^Flat tyre') or p:find('^Tyre shredded')) then
        return p, true
    end
    if EXACT[p] then return EXACT[p], false end
    for _, entry in ipairs(PATTERNS) do
        local caps = { p:match(entry[1]) }
        if caps[1] then
            local fr = entry[2](table.unpack(caps))
            if fr == nil then return p, true end -- muet
            return fr, false
        end
    end
    return p, false
end

-- =========================================================================
-- VOYANTS AU-DESSUS DU CAR HUD
-- =========================================================================
local car = { visible = false } -- { visible, x, y, w, h, scale } : car HUD (fractions de l'écran), envoyé par le MDC
local lastOn, lastList = false, {}
local origLamps = nil

--- Envoie au NUI de Riven la place de ses voyants : centrés au-dessus du car HUD, à sa taille
local function sendPosition()
    if settings.Lamps == false or not car.x then return end
    local scale = math.max(0.5, math.min(2.0, tonumber(car.scale) or 1.0))
    SendNUIMessage({
        type = 'position', style = 'hud', hudLayout = 'row', preview = false,
        hudX = ('%.2fvw'):format(((car.x + (car.w or 0.0) / 2.0) - 0.5) * 100.0),
        hudBottom = ('%.2fvh'):format((1.0 - car.y) * 100.0 + 0.6 * scale),
        hudSize = ('%.2fvh'):format(1.9 * scale),
        hudGap = ('%.2fvh'):format(0.55 * scale),
        hide = settings.HideLamps or {},
    })
end

local function lampsShown() return settings.Lamps == false or car.visible == true end

AddEventHandler('rp_mdc:carHudRect', function(rect)
    if type(rect) ~= 'table' then return end
    local wasVisible = car.visible
    car = { visible = rect.visible == true, x = tonumber(rect.x), y = tonumber(rect.y), w = tonumber(rect.w),
        h = tonumber(rect.h), scale = tonumber(rect.scale) }
    if not origLamps then return end
    if car.visible then sendPosition() end
    if wasVisible ~= car.visible then origLamps(lastOn and lampsShown(), lastList) end
end)

-- =========================================================================
-- INSTALLATION (dès que Riven a démarré)
-- =========================================================================
local installed = false
-- rp_vehiclecontrol (re)démarré après nous : il demande si le pont est là
AddEventHandler('rp_vehiclecontrol:rivenBridgePing', function()
    if installed then TriggerEvent('rp_vehiclecontrol:rivenBridge') end
end)

local function install()
    loadSettings()
    local UI = Config and Config.UI
    if settings.Lamps ~= false and UI then
        UI.Style = 'hud'
        UI.HudResource = GlobalState.mdcResource or 'rp_mdc' -- car HUD : voyants qu'il a déjà retirés (HideLamps)
        UI.HideWithHud = settings.HideLamps or { 'belt' }
        UI.PositionEditor = false -- leur place suit le car HUD
    end

    origLamps = Crash.UI.Lamps
    Crash.UI.Lamps = function(on, list)
        lastOn, lastList = on, list or {}
        return origLamps(on and lampsShown(), list)
    end
    local origBulb = Crash.UI.BulbCheck
    if origBulb then
        Crash.UI.BulbCheck = function(...)
            local args = { ... }
            CreateThread(function()
                Wait(400) -- le car HUD apparaît en même temps que l'on monte
                if lampsShown() then origBulb(table.unpack(args)) end
            end)
        end
    end

    local origNotify = Crash.Notify
    --- Message privé du chat (rp_chat), comme nos scripts ; sans rp_chat : chat d'origine ; sans chat : jeu
    local function deliver(text)
        local chat = GlobalState.rpChatResource or 'rp_chat'
        if GetResourceState(chat) == 'started'
            and pcall(function() exports[chat]:addPrivate({ title = 'Véhicule', text = text }) end) then
            return
        end
        if GetResourceState('chat') == 'started' then
            return TriggerEvent('chat:addMessage', { args = { 'Véhicule', text }, color = { 140, 200, 255 } })
        end
        origNotify(text)
    end
    Crash.Notify = function(text)
        if type(text) ~= 'string' then return origNotify(text) end
        loadSettings()
        if settings.Notify == false then return origNotify(text) end
        local fr, mute = translate(text)
        if mute or fr == '' then return end
        local ok, err = pcall(deliver, fr)
        if not ok then
            print(('^1[rp_vehiclecontrol] pont Riven, notification : %s^7'):format(tostring(err)))
            origNotify(fr)
        end
    end
    if Crash.UI.Hint then
        local origHint = Crash.UI.Hint
        Crash.UI.Hint = function(text) return origHint(type(text) == 'string' and translate(text) or text) end
    end
    if Crash.UI.Progress then
        local origProgress = Crash.UI.Progress
        Crash.UI.Progress = function(label, ...)
            return origProgress(type(label) == 'string' and (translate(label)) or label, ...)
        end
    end

    installed = true
    TriggerEvent('rp_vehiclecontrol:rivenBridge') -- rp_vehiclecontrol : notifications de secours coupées
    print('^2[rp_vehiclecontrol] pont Riven actif : voyants au-dessus du car HUD, notifications en français dans le chat^7')
    TriggerEvent('rp_mdc:carHudRectRequest') -- place actuelle du car HUD
    -- Riven envoie sa propre place au démarrage et quand son style change (toutes les 2 s) : la nôtre après lui
    SetTimeout(1000, sendPosition)
    SetTimeout(3000, sendPosition)
end

CreateThread(function()
    local deadline = GetGameTimer() + 600000
    while GetGameTimer() < deadline do
        if type(Crash) == 'table' and type(Crash.Notify) == 'function' and type(Crash.UI) == 'table'
            and type(Crash.UI.Lamps) == 'function' then
            local ok, err = pcall(install)
            if not ok then print(('^1[rp_vehiclecontrol] pont Riven : %s^7'):format(tostring(err))) end
            return
        end
        Wait(500)
    end
    print('^3[rp_vehiclecontrol] pont Riven : Riven n\'a pas démarré (licence ?) : voyants et notifications non reliés^7')
end)
