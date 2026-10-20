--[[
    RP DLS - état des véhicules (client)
    ------------------------------------
    Un seul état par véhicule, "dls" (state bag du véhicule, écrit par le serveur, lu par tous les clients) :
      s    stage de gyrophares : 0 éteint, 1, 2, 3, 4 (custom 1), 5 (custom 2)
      ta   Traffic Advisor : 0 éteint, 1 gauche, 2 diverge, 3 droite, 4 warn ; tap : n° du motif
      sb   Steady Burn / Cruise          int  plafonnier        bo  blackout (tous feux éteints)
      tone sirène : 0 coupée, 1, 2, 3 (Warning), 4 (Warning 2), 5 (air horn à la place de la sirène)
      aux  deuxième sirène (ton 1)       horn air horn par-dessus la sirène
      cr   cruise (DLS v2 : n° du mode)  td   takedown (n° du mode)  al  alley : 1 gauche, 2 droite, 3 les deux
    Chaque client applique cet état aux véhicules proches (gyrophares, sons) : tout le monde voit et entend la
    même chose. Le conducteur voit ses changements tout de suite (valeur en attente jusqu'à la réponse du serveur).
]]

DLSC = {}
local Config = DLSConfig

DLSC.EMPTY = { s = 0, ta = 0, tap = 0, sb = false, int = false, bo = false, tone = 0, aux = false, horn = false, cr = 0, td = 0, al = 0 }
local KEYS = { 's', 'ta', 'tap', 'sb', 'int', 'bo', 'tone', 'aux', 'horn', 'cr', 'td', 'al' }

local PENDING_MS = 1500
local pending = {}     -- [véhicule] = { value, before, untilTime }
local localStates = {} -- [véhicule] = état (véhicule non synchronisé : créé localement par un script)

--- Modèle DLS du véhicule ; véhicule d'urgence sans fichier : modèle générique (SirenControlNonDLS) ; sinon nil
function DLSC.modelOf(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local model = DLS.models[GetEntityModel(vehicle)]
    if model then return model end
    if Config.SirenControlNonDLS and GetVehicleClass(vehicle) == 18 then return DLS.generic end
    return nil
end

local function stored(vehicle)
    if NetworkGetEntityIsNetworked(vehicle) then
        local value = Entity(vehicle).state.dls
        return type(value) == 'table' and value or nil
    end
    return localStates[vehicle]
end

--- État du véhicule (nil : jamais touché par un joueur, laissé au jeu)

--- Copie modifiable de l'état (valeurs par défaut pour un véhicule jamais touché)
function DLSC.copy(vehicle)
    local current = DLSC.get(vehicle) or DLSC.EMPTY
    local copy = {}
    for _, k in ipairs(KEYS) do
        local v = current[k]
        if v == nil then v = DLSC.EMPTY[k] end
        copy[k] = v
    end
    return copy
end

local function same(a, b)
    if a == nil or b == nil then return a == b end
    for _, k in ipairs(KEYS) do
        if a[k] ~= b[k] then return false end
    end
    return true
end

--- État du véhicule (nil : jamais touché par un joueur, laissé au jeu)
function DLSC.get(vehicle)
    local value = stored(vehicle)
    local p = pending[vehicle]
    if p then
        -- (chaque lecture du state bag donne une nouvelle table : comparaison valeur par valeur)
        if same(value, p.before) and GetGameTimer() < p.untilTime then return p.value end
        pending[vehicle] = nil
    end
    return value
end

local listeners = {}
--- Appelé à chaque changement d'état d'un véhicule : fn(vehicle, state)
function DLSC.onChange(fn) listeners[#listeners + 1] = fn end
local function changed(vehicle, state)
    for _, fn in ipairs(listeners) do fn(vehicle, state) end
end
DLSC.changed = changed

--- Nouvel état complet du véhicule, envoyé au serveur (appliqué tout de suite ici)
function DLSC.set(vehicle, state)
    local current = DLSC.get(vehicle)
    if current and same(current, state) then return end
    if NetworkGetEntityIsNetworked(vehicle) then
        pending[vehicle] = { value = state, before = stored(vehicle), untilTime = GetGameTimer() + PENDING_MS }
        TriggerServerEvent('rp_dls:set', VehToNet(vehicle), state)
    else
        localStates[vehicle] = state
    end
    changed(vehicle, state)
end

--- Change quelques valeurs de l'état : DLSC.update(vehicle, { tone = 0 })
function DLSC.update(vehicle, changes)
    local state = DLSC.copy(vehicle)
    for k, v in pairs(changes) do state[k] = v end
    DLSC.set(vehicle, state)
    return state
end

--- Oublie ce qui est gardé pour ce numéro de véhicule (supprimé : le numéro peut être redonné)
function DLSC.forget(vehicle)
    pending[vehicle], localStates[vehicle] = nil, nil
end

-- État reçu du serveur : appliqué tout de suite (sons, gyrophares) sans attendre le prochain passage
AddStateBagChangeHandler('dls', nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if not vehicle or vehicle == 0 then return end
    if pending[vehicle] and type(value) == 'table' and same(pending[vehicle].value, value) then pending[vehicle] = nil end
    -- (le state bag n'est mis à jour qu'après ce gestionnaire : la nouvelle valeur est passée directement)
    SetTimeout(0, function()
        if DoesEntityExist(vehicle) then changed(vehicle, DLSC.get(vehicle)) end
    end)
end)

-- Le serveur a refusé un changement (pas conducteur…) : l'état du serveur fait foi tout de suite
RegisterNetEvent('rp_dls:refused', function(netId)
    local vehicle = NetToVeh(netId)
    if vehicle and vehicle ~= 0 then
        pending[vehicle] = nil
        changed(vehicle, DLSC.get(vehicle))
    end
end)

--- Résultat d'une native « vrai / faux » : selon la version, le jeu renvoie true / false ou 1 / 0 (un 1 comparé
--- à true est toujours différent : toujours passer par ici avant de comparer)
function DLSC.bool(value)
    return value == true or value == 1
end

--- Ce client commande-t-il le véhicule (propriétaire réseau, ou véhicule local) ?
function DLSC.owns(vehicle)
    return not NetworkGetEntityIsNetworked(vehicle) or NetworkGetEntityOwner(vehicle) == PlayerId()
end

--- Le joueur conduit-il ce véhicule ?
function DLSC.isDriver(vehicle)
    local ped = PlayerPedId()
    return vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
end

--- Petit son de l'interface du jeu (changement de stage…), comme DLS
function DLSC.beep(name)
    PlaySoundFrontend(-1, name or 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

-- Fichiers trouvés par le serveur (dls/*.xml, dls/packs/) : les mêmes que lui ; sans réponse, config.lua seule
CreateThread(function()
    local deadline = GetGameTimer() + 15000
    while not GlobalState.rpDlsFiles and GetGameTimer() < deadline do Wait(100) end
    DLS.load(GlobalState.rpDlsFiles)
end)

-- Liste changée (ressource de véhicules démarrée après rp_dls) : tout est relu
AddStateBagChangeHandler('rpDlsFiles', 'global', function(_, _, value)
    if type(value) == 'table' then SetTimeout(0, function() DLS.load(value) end) end
end)
