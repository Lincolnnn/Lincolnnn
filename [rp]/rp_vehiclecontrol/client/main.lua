--[[
    Vehicle Control - noyau (client)
    --------------------------------
    Une seule boucle suit le véhicule du joueur et appelle les modules (ceinture, essence, dégâts,
    moteur, portières, clignotants, poussée) :
      - 'enter' / 'leave' / 'seat' : montée, descente (avec la vitesse juste avant et le choc en cours ;
        swap = passé directement dans un autre véhicule, ex. un véhicule qu'il vient de faire apparaître ;
        gone = l'ancien n'existe plus), changement de place ;
      - 'frame' : à chaque image, UNIQUEMENT à bord d'un véhicule (ceinture, véhicule poussé,
        puissance réduite d'un moteur abîmé, détection des chocs) ;
      - 'tick'  : toutes les 100 ms à bord (essence, dégâts, alarme de ceinture, car HUD) ;
      - 'impact' : choc violent (vitesse avant le choc, perte de vitesse, vitesse du véhicule, ce qui a
        été percuté : { severity = 'light' | 'heavy', kind = 'ped' | 'vehicle' | 'object' | 'world', entity },
        secousse = plus grand changement de vitesse en MPH, toutes directions : aussi quand le véhicule est
        percuté à l'arrêt ou par l'arrière, sans perdre de vitesse) ;
      - 'idle'  : toutes les 500 ms à pied (pompes, jerrican, véhicule à pousser).

    Car HUD : dessiné par le MDC (rp_mdc, Paramètres > HUD & Display), qui reçoit les données
    par l'événement local "mdc:carHud". Sans le MDC, tout fonctionne mais rien n'est affiché.

    Performance : à pied, une vérification toutes les 500 ms (~0.00 ms) ; à bord, ~0.02 ms.
]]

local Config = VCConfig

VC = {
    MPH = 2.236936,  -- m/s -> MPH
    vehicle = 0,     -- véhicule où se trouve le joueur
    model = nil,     -- son modèle et son identifiant réseau (reconnaître un véhicule tout neuf au même numéro)
    net = 0,
    seat = nil,      -- -1 conducteur, 0 passager avant, 1+ arrière
    hud = {},        -- données du car HUD remplies par les modules
}

-- Riven Impact Dynamics installé (config.lua : Riven) : les modules qui feraient doublon ne se chargent pas
do
    local R = Config.Riven or {}
    VC.rivenResource = R.Resource or 'riven-impact-dynamics'
    -- dossier renommé : retrouvé par le nom écrit dans son fxmanifest (name 'Riven Impact Dynamics')
    if GetResourceState(VC.rivenResource) == 'missing' then
        for i = 0, GetNumResources() - 1 do
            local res = GetResourceByFindIndex(i)
            if res and (GetResourceMetadata(res, 'name', 0) or ''):lower() == 'riven impact dynamics' then
                VC.rivenResource = res
                break
            end
        end
    end
    -- installé sur le serveur (démarré, en train de démarrer, ou pas encore démarré : server.cfg le lance après ce
    -- script) ; absent : sans lui
    local state = GetResourceState(VC.rivenResource)
    VC.riven = R.Mode == true or (R.Mode ~= false and state ~= 'missing' and state ~= 'unknown')
    if VC.riven then print(('[rp_vehiclecontrol] %s détecté : accidents, carrosserie, verre, débris, terrain, blessures et ceinture gérés par lui'):format(VC.rivenResource)) end
end

local hooks = { enter = {}, leave = {}, seat = {}, frame = {}, tick = {}, impact = {}, idle = {} }

function VC.on(event, fn) table.insert(hooks[event], fn) end

-- Une erreur dans un module (native absente de la version du jeu…) ne doit jamais arrêter la boucle du véhicule
-- (car HUD, moteur, ceinture…) : elle est signalée une fois dans la console F8, les autres modules continuent.
local reported = {}
local function emit(event, ...)
    for i, fn in ipairs(hooks[event]) do
        local ok, err = pcall(fn, ...)
        if not ok then
            local key = event .. '#' .. i .. ':' .. tostring(err)
            if not reported[key] then
                reported[key] = true
                print(('^1[rp_vehiclecontrol] erreur dans un module (%s) : %s^7'):format(event, tostring(err)))
            end
        end
    end
end
VC.emit = emit

-- =========================================================================
-- OUTILS
-- =========================================================================
--- Envoi au car HUD du MDC (carHud, beltSound, beltBeep, carNotice)
function VC.toHud(action, data)
    TriggerEvent('mdc:carHud', action, data)
end

-- =========================================================================
-- ŒIL de rp_interact (Config.TargetProviders) : options de plusieurs modules (nettoyage des débris, poussée)
--   VC.addTarget({ options = function(info) -> { label, options = {...} } | nil, select = function(id, info) })
-- =========================================================================
local targets = {}
function VC.addTarget(t) targets[#targets + 1] = t end

exports('targetOptions', function(info)
    local label, options = nil, {}
    for _, t in ipairs(targets) do
        local ok, res = pcall(t.options, info)
        if ok and type(res) == 'table' and type(res.options) == 'table' then
            label = label or res.label
            for _, o in ipairs(res.options) do options[#options + 1] = o end
        end
    end
    if #options == 0 then return nil end
    return { label = label, options = options }
end)

exports('targetSelect', function(id, info)
    for _, t in ipairs(targets) do
        if t.select and t.select(id, info) then return end
    end
end)

--- Message PRIVÉ dans le chat (rp_chat), ex. "Plein interrompu."
function VC.chat(text)
    local chat = GlobalState.rpChatResource or Config.ChatResource
    if GetResourceState(chat) == 'started'
        and pcall(function() exports[chat]:addPrivate({ title = 'Véhicule', text = text }) end) then
        return
    end
    -- Sans rp_chat : chat d'origine (message affiché chez ce joueur uniquement)
    TriggerEvent('chat:addMessage', { args = { 'Véhicule', text }, color = { 140, 200, 255 } })
end

--- Touche réellement associée à une commande (raccourcis FiveM), ex. "O"
function VC.keyLabel(command, fallback)
    local ok, label = pcall(GetControlInstructionalButton, 0, GetHashKey(command) | 0x80000000, true)
    if ok and type(label) == 'string' and label:sub(1, 2) == 't_' then return label:sub(3) end
    return fallback
end

-- État d'un véhicule (moteur, frein, portières, essence, cassé, clignotants…) : état du véhicule en
-- réseau ("state bag", écrit par le serveur et lu par tous) ; véhicule local (non synchronisé) : gardé ici.
-- Une valeur qui vient d'être demandée au serveur est utilisée tout de suite par ce client, le temps que
-- le serveur la renvoie (dès que l'état du véhicule change, ou au plus PENDING_MS) : la touche répond
-- immédiatement.
local PENDING_MS = 2500
local localStates = {}
local pending = {} -- [véhicule] = { [clé] = { value, before, untilTime } }

local function stored(vehicle, key)
    if NetworkGetEntityIsNetworked(vehicle) then return Entity(vehicle).state[key] end
    return localStates[vehicle] and localStates[vehicle][key]
end

function VC.state(vehicle, key)
    local value = stored(vehicle, key)
    local p = pending[vehicle] and pending[vehicle][key]
    if p then
        -- Le serveur a répondu (l'état a changé) ou délai dépassé : l'état du véhicule fait foi
        if value == p.before and GetGameTimer() < p.untilTime then return p.value end
        pending[vehicle][key] = nil
    end
    return value
end

--- Valeur en attente, sans envoi (ex. essence envoyée par fuel.lua)
function VC.setPending(vehicle, key, value)
    pending[vehicle] = pending[vehicle] or {}
    pending[vehicle][key] = { value = value, before = stored(vehicle, key), untilTime = GetGameTimer() + PENDING_MS }
end

--- Oublie ce qui est gardé ici pour ce numéro de véhicule (véhicule supprimé : le jeu peut redonner son numéro
--- à un véhicule tout neuf, qui ne doit rien hériter de l'ancien)
function VC.forget(vehicle)
    pending[vehicle], localStates[vehicle] = nil, nil
end

--- Véhicule qui vient d'apparaître de la main du joueur (script : véhicule de mission créé par ce client),
--- par opposition à un véhicule ambiant (circulation, garé) ou laissé par un autre joueur
function VC.isFreshSpawn(vehicle)
    local population = GetEntityPopulationType(vehicle)
    if population ~= 6 and population ~= 7 then return false end
    return not NetworkGetEntityIsNetworked(vehicle) or NetworkGetEntityOwner(vehicle) == PlayerId()
end

function VC.setState(vehicle, key, value)
    if NetworkGetEntityIsNetworked(vehicle) then
        VC.setPending(vehicle, key, value)
        TriggerServerEvent('rp_vehiclecontrol:state', VehToNet(vehicle), key, value)
    else
        localStates[vehicle] = localStates[vehicle] or {}
        localStates[vehicle][key] = value
    end
end

-- =========================================================================
-- SONS (NUI de ce script, html/sounds/*.ogg) : volume réglé dans le MDC
-- (Paramètres > HUD & Display > volume des sons du véhicule), sinon SoundVolume
-- =========================================================================
function VC.volume()
    local mdc = GlobalState.mdcResource or 'rp_mdc'
    if GetResourceState(mdc) == 'started' then
        local ok, volume = pcall(function() return exports[mdc]:carSoundVolume() end)
        if ok and type(volume) == 'number' then return math.max(0.0, math.min(1.0, volume)) end
    end
    return Config.SoundVolume or 0.7
end

--- Joue un son une fois (volume 0..1, multiplié par le réglage du joueur, ou par `setting` s'il est donné) ;
--- `muffled` : étouffé (entendu de l'extérieur du véhicule, portières fermées)
function VC.sound(name, volume, setting, muffled)
    SendNUIMessage({ action = 'sound', data = {
        name = name, volume = (volume or 1.0) * (tonumber(setting) or VC.volume()), muffled = muffled == true,
    } })
end

--- Son répété (clignotant, alarme) : `names` joués à tour de rôle toutes les `interval` ms ; volume 0 = arrêt
--- (coupé net). `loop` : un seul fichier joué en boucle sans interruption (interval ignoré). Volume au-delà de 1
--- possible ; `muffled` : étouffé.
--- Moteur allumé ? État voulu "vcEngine" (le même pour tous, stable même véhicule laissé vide, quand le jeu
--- le coupe un instant avant que Vehicle Control le relance) ou moteur qui tourne
function VC.engineOn(vehicle)
    return VC.state(vehicle, 'vcEngine') == true or GetIsVehicleEngineRunning(vehicle)
end

--- Diagnostic des sons (console F8) : setr vc_debug_sound 1
function VC.debugSound(text)
    if GetConvarInt('vc_debug_sound', 0) == 1 then print(('[rp_vehiclecontrol] %s'):format(text)) end
end

-- Diagnostic du lecteur du NUI (démarrage, arrêt, relance, lecteur audio suspendu) : setr vc_debug_sound 1
RegisterNUICallback('soundDebug', function(data, cb)
    cb('ok')
    if GetConvarInt('vc_debug_sound', 0) == 1 and type(data) == 'table' then
        print(('[rp_vehiclecontrol] NUI : %s'):format(tostring(data.text)))
    end
end)

--- `keep` : boucle toujours en cours même à volume 0 (hors de portée) : gardée muette, sans jamais s'arrêter,
--- et réentendue là où elle en est ; sans `keep`, volume 0 = arrêt. `resend` : simple renvoi du même état
--- (le NUI le traite pareil : rien ne change s'il joue déjà, relancé s'il l'avait perdu).
function VC.soundLoop(id, names, interval, volume, loop, muffled, keep, resend)
    SendNUIMessage({ action = 'soundLoop', data = {
        id = id, names = names, interval = interval, volume = (volume or 0.0) * VC.volume(), loop = loop == true,
        muffled = muffled == true, keep = keep == true, resend = resend == true,
    } })
end

-- =========================================================================
-- SONS DU VÉHICULE ENTENDUS AUTOUR (clignotants, ceinture, carillon)
--   à bord : 100 % ; dehors, depuis la carrosserie : jusqu'à VehicleSounds.RangeOpen m avec une portière
--   ouverte, VehicleSounds.RangeClosed m tout fermé (et alors étouffé, moins fort)
-- =========================================================================
local Sounds = Config.VehicleSounds

--- Une portière (ou le coffre / le capot) ouverte ?
function VC.doorsOpen(vehicle)
    for door = 0, 5 do
        if GetVehicleDoorAngleRatio(vehicle, door) > 0.05 then return true end
    end
    return false
end

--- Distance (m) entre un point et la carrosserie du véhicule (0 : dedans / contre)
function VC.distanceToBody(vehicle, pos)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local p = GetOffsetFromEntityGivenWorldCoords(vehicle, pos.x, pos.y, pos.z)
    local dx = math.max(min.x - p.x, 0.0, p.x - max.x)
    local dy = math.max(min.y - p.y, 0.0, p.y - max.y)
    local dz = math.max(min.z - p.z, 0.0, p.z - max.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Volume (0..1) et étouffement d'un son venant de ce véhicule, pour ce joueur
function VC.hearVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0.0, false end
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) == vehicle then return 1.0, false end
    local open = VC.doorsOpen(vehicle)
    local range = open and Sounds.RangeOpen or Sounds.RangeClosed
    local distance = VC.distanceToBody(vehicle, GetEntityCoords(ped))
    if distance >= range then return 0.0, not open end
    local factor = 1.0 - distance / range
    if open then return factor * Sounds.OpenVolume, false end
    return factor * Sounds.ClosedVolume, true
end

function VC.isDriver() return VC.vehicle ~= 0 and VC.seat == -1 end

local function seatOf(ped, vehicle)
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then return seat end
    end
    return nil
end

-- =========================================================================
-- CE QUI A ÉTÉ PERCUTÉ (au moment du choc ; recherche seulement à cet instant)
--   léger : piéton, moto / vélo, objet de la liste LightModels (ou inconnu, selon UnknownObject)
--   fort  : autre véhicule, objet de la liste HeavyModels, ou rien de mobile : décor fixe (mur…)
-- =========================================================================
local Damage = Config.Damage
local modelSeverity = {}
for _, name in ipairs(Damage.LightModels or {}) do modelSeverity[GetHashKey(name)] = 'light' end
for _, name in ipairs(Damage.HeavyModels or {}) do modelSeverity[GetHashKey(name)] = 'heavy' end

local HIT_MS = 600  -- durée pendant laquelle les dégâts reçus sont attribués à ce choc
local lastHit = nil -- { vehicle, severity, kind, entity, untilTime }

--- Entité au contact du véhicule (la plus « lourde ») : severity, entity
local function touching(vehicle, pool, range, classify)
    local pos = GetEntityCoords(vehicle)
    local found, foundEntity = nil, nil
    for _, entity in ipairs(GetGamePool(pool)) do
        if entity ~= vehicle and #(GetEntityCoords(entity) - pos) <= range and IsEntityTouchingEntity(vehicle, entity)
            -- remorque attelée, objet porté… : toujours au contact, ce n'est pas un choc
            and not IsEntityAttachedToEntity(entity, vehicle) and not IsEntityAttachedToEntity(vehicle, entity) then
            local severity = classify(entity)
            if severity == 'heavy' then return 'heavy', entity end
            if severity and not found then found, foundEntity = severity, entity end
        end
    end
    return found, foundEntity
end

--- Ce que le véhicule vient de percuter : { severity = 'light' | 'heavy', kind, entity }
function VC.classifyHit(vehicle)
    local ped = PlayerPedId()
    local severity, entity = touching(vehicle, 'CVehicle', 12.0, function(other)
        return Damage.LightVehicleClasses[GetVehicleClass(other)] and 'light' or 'heavy'
    end)
    if severity then return { severity = severity, kind = 'vehicle', entity = entity } end
    severity, entity = touching(vehicle, 'CObject', 10.0, function(object)
        return modelSeverity[GetEntityModel(object)] or Damage.UnknownObject or 'light'
    end)
    if severity then return { severity = severity, kind = 'object', entity = entity } end
    severity, entity = touching(vehicle, 'CPed', 6.0, function(other)
        if other == ped or GetVehiclePedIsIn(other, false) == vehicle then return nil end
        return 'light'
    end)
    if severity then return { severity = severity, kind = 'ped', entity = entity } end
    return { severity = 'heavy', kind = 'world' } -- mur, bâtiment, rocher, décor fixe
end

--- Choc en cours / tout juste reçu par ce véhicule ; s'il vient de toucher quelque chose sans choc
--- enregistré (petite vitesse), il est reconnu maintenant ; nil : aucun choc (balles, explosion…)
function VC.currentHit(vehicle)
    local now = GetGameTimer()
    if lastHit and lastHit.vehicle == vehicle and now <= lastHit.untilTime then return lastHit end
    if not HasEntityCollidedWithAnything(vehicle) then return nil end
    local hit = VC.classifyHit(vehicle)
    lastHit = { vehicle = vehicle, severity = hit.severity, kind = hit.kind, entity = hit.entity, untilTime = now + HIT_MS }
    return lastHit
end

-- =========================================================================
-- CHOCS : perte de vitesse brutale pendant un contact (mur, objet fixe, véhicule)
-- =========================================================================
local history = {}  -- vitesses des 400 dernières ms : { t, speed }
local crash = nil   -- choc en cours : { before, min, untilTime, velocity, hit, jolt }
local lastVelocity = vector3(0.0, 0.0, 0.0)

local function recentPeak(now)
    local peak = 0.0
    for i = #history, 1, -1 do
        local h = history[i]
        if now - h.t > 400 then break end
        if h.speed > peak then peak = h.speed end
    end
    return peak
end

local function detectImpact(vehicle)
    local now = GetGameTimer()
    local speed = GetEntitySpeed(vehicle) * VC.MPH
    local velocity = GetEntityVelocity(vehicle)
    if not crash and HasEntityCollidedWithAnything(vehicle) then
        local before = math.max(recentPeak(now), speed)
        -- secousse : changement brutal de vitesse (aussi percuté à l'arrêt ou par l'arrière)
        local jump = #(velocity - lastVelocity) * VC.MPH
        if before > 5.0 or jump > 4.0 then
            lastHit = nil -- nouveau choc : reconnu maintenant
            crash = { before = before, min = speed, untilTime = now + 250, velocity = lastVelocity, hit = VC.currentHit(vehicle), jolt = 0.0 }
        end
    end
    if crash then
        if speed < crash.min then crash.min = speed end
        local jolt = #(velocity - crash.velocity) * VC.MPH
        if jolt > crash.jolt then crash.jolt, crash.after = jolt, velocity end
        -- Fin du choc : 250 ms écoulées, ou véhicule arrêté net
        if now >= crash.untilTime or crash.min < 2.0 then
            emit('impact', vehicle, crash.before, crash.before - crash.min, crash.velocity, crash.hit, crash.jolt, crash.after)
            crash = nil
        end
    end
    VC.inCrash = crash ~= nil -- choc en cours (les modules ne relèvent pas l'état du véhicule pendant ce temps)
    history[#history + 1] = { t = now, speed = speed }
    if #history > 60 then table.remove(history, 1) end
    lastVelocity = velocity
end

-- =========================================================================
-- BOUCLE PRINCIPALE
-- =========================================================================
--- swap : passé directement dans un autre véhicule (nouveau véhicule apparu, sans descendre, l'ancien étant
--- supprimé ou non) ;
--- gone : l'ancien véhicule n'existe plus, ou son numéro est déjà celui du nouveau (ne plus y toucher)
local function leave(swap, gone)
    local vehicle, seat = VC.vehicle, VC.seat
    -- Dernier état de la course (ex. désarçonné d'une moto par le jeu au moment du choc) :
    -- { peak = vitesse la plus haute des 400 dernières ms (MPH), crash = choc en cours ou nil, velocity,
    --   swap, gone }
    gone = gone == true or not DoesEntityExist(vehicle)
    local info = { peak = recentPeak(GetGameTimer()), crash = crash, velocity = lastVelocity, swap = swap == true, gone = gone }
    VC.vehicle, VC.seat, VC.model, VC.net = 0, nil, nil, 0
    history, crash, lastHit = {}, nil, nil
    if gone then VC.forget(vehicle) end
    emit('leave', vehicle, seat, info)
    -- Autres ressources (radio du véhicule de rp_interact…) : l'ancien véhicule, toujours là, s'arrête aussi
    if info.swap and not gone and NetworkGetEntityIsNetworked(vehicle) then
        TriggerEvent('rp_vehiclecontrol:swapped', VehToNet(vehicle), seat)
    end
end

--- Toujours le même véhicule ? Le jeu peut redonner le numéro d'un véhicule supprimé à un véhicule tout neuf
--- (nouveau véhicule qui remplace l'ancien) : modèle ou identifiant réseau différents = autre véhicule
local function sameVehicle(vehicle)
    if vehicle ~= VC.vehicle or GetEntityModel(vehicle) ~= VC.model then return false end
    local net = NetworkGetEntityIsNetworked(vehicle) and VehToNet(vehicle) or 0
    if VC.net ~= 0 and net ~= 0 and net ~= VC.net then return false end
    if net ~= 0 then VC.net = net end -- devenu réseau en cours de route : toujours le même
    return true
end

-- Sorti du véhicule SANS en descendre (véhicule supprimé pour en faire apparaître un autre, mis directement dans
-- un nouveau véhicule…) : la sortie attend jusqu'à SWAP_WINDOW ms. Si le joueur se retrouve entre-temps dans un
-- autre véhicule, c'est un changement de véhicule (swap : tout ce qui concernait l'ancien s'arrête, le nouveau
-- part de zéro). Une vraie descente (touche F), une éjection, une chute de moto (corps inerte), un joueur
-- sorti de force ou la mort : sortie immédiate. (Pas IsPedFalling : un personnage dont le véhicule est supprimé
-- tombe de la hauteur du siège.)
local SWAP_WINDOW = 1000
local exitSeenAt = 0  -- dernière fois que le personnage descendait / était désarçonné (à bord)

local function realExit(ped, now)
    return now - exitSeenAt < 1500 or IsPedRagdoll(ped) or IsEntityDead(ped) or IsPedBeingJacked(ped)
end

CreateThread(function()
    Wait(0) -- tous les fichiers du script chargés (modules enregistrés)
    local lastTick = 0
    local outSince = nil -- sorti sans descendre depuis (ms) : changement de véhicule possible
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 then
            outSince = nil
            if GetIsTaskActive(ped, 2) or IsPedRagdoll(ped) then exitSeenAt = GetGameTimer() end -- descend / désarçonné
            if not sameVehicle(vehicle) then
                -- Passé directement dans un autre véhicule : tout ce qui concernait l'ancien s'arrête
                -- (gone : l'ancien n'existe plus, ou son numéro est déjà celui du nouveau)
                if VC.vehicle ~= 0 then leave(true, vehicle == VC.vehicle) end
                VC.vehicle, VC.seat = vehicle, seatOf(ped, vehicle)
                VC.model = GetEntityModel(vehicle)
                VC.net = NetworkGetEntityIsNetworked(vehicle) and VehToNet(vehicle) or 0
                lastTick = 0
                emit('enter', ped, vehicle, VC.seat)
            else
                local seat = seatOf(ped, vehicle)
                if seat ~= VC.seat then
                    local previous = VC.seat
                    VC.seat = seat
                    emit('seat', ped, vehicle, seat, previous)
                end
            end
            detectImpact(vehicle)
            emit('frame', ped, vehicle)
            local now = GetGameTimer()
            if now - lastTick >= 100 then
                local dt = lastTick == 0 and 0.1 or (now - lastTick) / 1000
                lastTick = now
                emit('tick', ped, vehicle, dt)
            end
            Wait(0)
        else
            if VC.vehicle ~= 0 then
                local now = GetGameTimer()
                outSince = outSince or now
                if realExit(ped, now) or now - outSince >= SWAP_WINDOW then
                    outSince = nil
                    leave()
                end
            end
            if VC.vehicle ~= 0 then
                Wait(0) -- un nouveau véhicule va-t-il apparaître ? (au plus SWAP_WINDOW ms)
            else
                emit('idle', ped)
                Wait(500)
            end
        end
    end
end)

-- =========================================================================
-- CAR HUD (MDC) : envoyé seulement quand il change
-- =========================================================================
local lastKey = nil

local HUD_KEYS = { 'inVehicle', 'show', 'mode', 'engine', 'speed', 'rpm', 'fuel', 'belt', 'alarm', 'broken', 'damaged', 'paused', 'gear', 'park' }

local function sendHud(data)
    local parts = {}
    for i, k in ipairs(HUD_KEYS) do parts[i] = tostring(data[k]) end
    local key = table.concat(parts, '|')
    if key == lastKey then return end
    lastKey = key
    VC.toHud('carHud', data)
end

-- Enregistré en dernier (fichier hud.lua) : les modules ont déjà rempli VC.hud.
--   - conducteur : car HUD complet (vitesse, accélération, essence, ceinture, moteur très abîmé / détruit), toujours
--     affiché ; moteur coupé, tout est grisé (engine = false), il s'illumine au démarrage ;
--   - passagers : uniquement le logo de la ceinture.
function VC.sendHud(vehicle)
    local driver = VC.seat == -1
    local running = GetIsVehicleEngineRunning(vehicle)
    local speed = GetEntitySpeed(vehicle) * VC.MPH
    local rpm = running and GetVehicleCurrentRpm(vehicle) or 0.0
    rpm = math.max(0.0, math.min(1.0, (rpm - 0.2) / 0.8)) -- ralenti ~0.2 -> 0 %, régime maximal -> 100 %
    local h = VC.hud
    -- Riven : ses voyants (au-dessus du car HUD, riven/bridge.lua) montrent les dégâts ; pas de logo moteur ici
    local broken = not VC.riven and VC.state(vehicle, 'vcBroken') == true
    local show = driver or h.belt ~= nil -- passager sans ceinture (moto…) : rien
    local data = {
        inVehicle = true,
        show = show,
        mode = driver and 'driver' or 'passenger',
        engine = running,                                  -- moteur coupé : car HUD grisé
        speed = math.floor(speed + 0.5),
        rpm = math.floor(rpm * 50 + 0.5) / 50,
        fuel = h.fuel and math.floor(h.fuel + 0.5) or nil, -- nil : pas de réservoir (jauge masquée)
        alarm = h.alarm == true,
        broken = broken,                                   -- logo rouge : moteur détruit (palier 2)
        damaged = not VC.riven and not broken and VC.state(vehicle, 'vcDamaged') == true, -- logo orange : très abîmé (palier 1)
        paused = IsPauseMenuActive() or IsScreenFadedOut(),
    }
    if h.belt ~= nil then data.belt = h.belt end -- absent : pas de ceinture (logo masqué)
    if driver and h.gear then data.gear = h.gear end -- 'D' / 'R' (client/gear.lua) ; absent : pas de rapport
    if driver and h.park then data.park = true end   -- frein de parking de Riven serré : « P » (client/riven.lua)
    sendHud(data)
end

function VC.hideHud()
    sendHud({ inVehicle = false, show = false })
end

-- MDC (re)démarré / NUI rechargé : état renvoyé à la prochaine mise à jour
AddEventHandler('mdc:hudReady', function() lastKey = nil end)
