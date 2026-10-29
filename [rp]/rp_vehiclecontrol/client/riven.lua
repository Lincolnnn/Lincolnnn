--[[
    Vehicle Control - liaison avec Riven Impact Dynamics (client)
    -------------------------------------------------------------
    riven/bridge.lua est chargé DANS la ressource de Riven (une ligne dans son fxmanifest, voir README) : il lit ici
    ses réglages (config.lua : Riven) et affiche lui-même les notifications de Riven, traduites, en message privé du
    chat. Il prévient ce script quand il est actif (événement rp_vehiclecontrol:rivenBridge).
    Ici, avec ou sans le pont :
      - CEINTURE et FREIN DE PARKING : ce script les lit chez Riven (export IsSeatbeltOn, état « rivenParkingBrake »
        du véhicule) et écrit lui-même « Ceinture attachée. », « Frein de parking serré. »… en message privé du chat
        (le pont coupe ceux de Riven : jamais en double) ; frein de parking serré : « P » sur le car HUD du MDC ;
      - NOTIFICATIONS DU JEU supprimées à bord (Riven.HideGameFeed) : celles de Riven en anglais ne s'affichent plus,
        même sans le pont.
    Sans le pont (ligne du fxmanifest oubliée…), SECOURS : notifications en français quand un voyant de Riven s'allume
    (moteur, surchauffe, boîte, freins, huile, fuite d'essence, direction, pneu, feu).
    Performance : rien à pied ; à bord : une lecture du frein de parking toutes les 250 ms, deux natives par image.
]]

local R = VCConfig.Riven or {}

exports('rivenSettings', function()
    return {
        Lamps = R.Lamps ~= false,
        HideLamps = type(R.HideLamps) == 'table' and R.HideLamps or { 'belt' },
        Notify = R.Notify ~= false,
        MuteBelt = R.MuteBelt ~= false, MuteTyres = R.MuteTyres ~= false,
        OwnBelt = true, OwnPark = true, -- ceinture et frein de parking : messages écrits par ce script
    }
end)

local bridge = false -- riven/bridge.lua actif dans la ressource de Riven
AddEventHandler('rp_vehiclecontrol:rivenBridge', function() bridge = true end)
TriggerEvent('rp_vehiclecontrol:rivenBridgePing') -- déjà installé avant notre démarrage : il répond

--- Notifications de secours (pont absent)
local function fallback() return VC.riven and R.Notify ~= false and R.Fallback ~= false and not bridge end
VC.rivenFallback = fallback -- pour les tests

local function notify(text) if VC.riven and R.Notify ~= false then VC.chat(text) end end

-- =========================================================================
-- VOYANTS (secours) : voyant qui s'allume -> notification (une fois, jusqu'à ce qu'il s'éteigne)
-- =========================================================================
local LAMPS = {
    engine = { amber = 'Moteur endommagé : il peut caler.', red = 'Moteur gravement endommagé.' },
    temp = 'Le moteur surchauffe : radiateur touché.',
    trans = 'Boîte de vitesses endommagée.',
    brake = 'Freins endommagés : le freinage est réduit.',
    oil = 'Pression d\'huile basse : le moteur souffre.',
    fuel = 'Fuite d\'essence : le réservoir se vide.',
    steer = 'Direction faussée : le véhicule tire d\'un côté.',
    tyre = 'Pneu crevé ou qui se dégonfle.',
    fire = 'Le véhicule prend feu : sortez !',
}
local lit = {} -- [id] = niveau déjà annoncé

AddEventHandler('riven-impact-dynamics:lamps', function(list)
    if type(list) ~= 'table' then return end
    local now = {}
    for _, lamp in ipairs(list) do
        if type(lamp) == 'table' and lamp.id then now[lamp.id] = lamp.level or 'amber' end
    end
    for id, level in pairs(now) do
        local text = LAMPS[id]
        if type(text) == 'table' then text = text[level] or text.amber end
        -- moteur : l'orange puis le rouge sont annoncés ; les autres : une fois
        if text and lit[id] ~= level and not (lit[id] and type(LAMPS[id]) ~= 'table') and fallback() then VC.chat(text) end
        lit[id] = level
    end
    for id in pairs(lit) do if not now[id] then lit[id] = nil end end
end)

-- =========================================================================
-- CEINTURE (lue par seatbelt.lua) : attachée / détachée
-- =========================================================================
function VC.rivenBeltChanged(on)
    if R.MuteBelt == false then notify(on and 'Ceinture attachée.' or 'Ceinture détachée.') end
end

-- =========================================================================
-- FREIN DE PARKING de Riven : « P » sur le car HUD, messages
-- =========================================================================
local PARK_KEY = R.ParkStateKey or 'rivenParkingBrake'
local park = { vehicle = 0, on = nil, at = 0 }

--- Frein de parking serré sur ce véhicule (Riven : son export, sinon l'état synchronisé du véhicule)
function VC.rivenPark(vehicle)
    local ok, on = pcall(function() return exports[VC.rivenResource]:IsParkingBrakeOn(vehicle) end)
    if ok and type(on) == 'boolean' then return on end
    return VC.state(vehicle, PARK_KEY) == true
end

local function setPark(vehicle, on, announce)
    if park.vehicle == vehicle and park.on == on then return end
    local changed = park.vehicle == vehicle and park.on ~= nil
    park.vehicle, park.on = vehicle, on
    VC.hud.park = on or nil
    if changed and announce and R.MutePark == false and VC.seat == -1 then
        notify(on and 'Frein de parking serré.' or 'Frein de parking desserré.')
    end
end

-- Riven prévient tout de suite celui qui le serre / desserre (l'état synchronisé suit un peu après)
AddEventHandler('crash:parkingBrakeChanged', function(vehicle, on)
    if VC.riven and vehicle == VC.vehicle then setPark(vehicle, on == true, true) end
end)

VC.on('enter', function(_, vehicle)
    if not VC.riven then return end
    park = { vehicle = 0, on = nil, at = 0 }
    setPark(vehicle, VC.rivenPark(vehicle), false) -- déjà serré en montant : « P », sans message
end)

VC.on('tick', function(_, vehicle)
    if not VC.riven then return end
    local now = GetGameTimer()
    if now - park.at < 250 then return end
    park.at = now
    setPark(vehicle, VC.rivenPark(vehicle), true)
end)

VC.on('leave', function()
    park = { vehicle = 0, on = nil, at = 0 }
    VC.hud.park = nil
end)

-- =========================================================================
-- NOTIFICATIONS DU JEU (Riven, en anglais) : supprimées à bord
-- =========================================================================
local warned = false
VC.on('enter', function()
    if not VC.riven or bridge or warned then return end
    warned = true
    print(('^3[rp_vehiclecontrol] pont Riven absent : ajoutez la ligne \'@rp_vehiclecontrol/riven/bridge.lua\' aux client_scripts de %s (voir README). Notifications de secours en français.^7'):format(VC.rivenResource))
end)

local lastFeed = nil
VC.on('frame', function()
    if not VC.riven or R.HideGameFeed == false then return end
    ThefeedHideThisFrame()
    -- chaque nouvelle notification est retirée (elle ne réapparaît pas en descendant du véhicule)
    local id = ThefeedGetCurrentNotification()
    if id and id ~= lastFeed then
        if lastFeed ~= nil and id > 0 then ThefeedRemoveItem(id) end
        lastFeed = id
    end
end)

VC.on('leave', function()
    lastFeed = nil
    if VC.riven and R.HideGameFeed ~= false then ThefeedFlushQueue() end
end)
