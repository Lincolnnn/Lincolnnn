--[[
    Vehicle Control - liaison avec Riven Impact Dynamics (client)
    -------------------------------------------------------------
    riven/bridge.lua est chargé DANS la ressource de Riven (une ligne dans son fxmanifest, voir README) : il lit ici
    ses réglages (config.lua : Riven) et affiche lui-même les notifications de Riven, traduites, en message privé du
    chat. Il prévient ce script quand il est actif (événement rp_vehiclecontrol:rivenBridge).
    SECOURS (pont absent : ligne du fxmanifest oubliée…) : ce script fait ses propres notifications en français à partir
    de ce que Riven publie sans modification (ses voyants, sa ceinture) : moteur, surchauffe, boîte, freins, huile,
    fuite d'essence, direction, pneu, feu, ceinture ; les notifications du jeu (celles de Riven, en anglais) sont
    masquées tant que l'on est dans un véhicule (Riven.HideGameFeed).
    Performance : aucune boucle ; en secours, une native par image à bord (masquer les notifications du jeu).
]]

local R = VCConfig.Riven or {}

exports('rivenSettings', function()
    return {
        Lamps = R.Lamps ~= false,
        HideLamps = type(R.HideLamps) == 'table' and R.HideLamps or { 'belt' },
        Notify = R.Notify ~= false,
        MuteBelt = R.MuteBelt == true,
    }
end)

local bridge = false -- riven/bridge.lua actif dans la ressource de Riven
AddEventHandler('rp_vehiclecontrol:rivenBridge', function() bridge = true end)
TriggerEvent('rp_vehiclecontrol:rivenBridgePing') -- déjà installé avant notre démarrage : il répond

--- Notifications de secours (pont absent)
local function fallback() return VC.riven and R.Notify ~= false and R.Fallback ~= false and not bridge end
VC.rivenFallback = fallback -- pour les tests

-- Voyant qui s'allume -> notification (une fois, jusqu'à ce qu'il s'éteigne)
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

-- Ceinture de Riven (lue par seatbelt.lua) : attachée / détachée
function VC.rivenBeltChanged(on)
    if fallback() and R.MuteBelt ~= true then VC.chat(on and 'Ceinture attachée.' or 'Ceinture détachée.') end
end

-- Notifications du jeu (Riven, en anglais) masquées à bord, seulement en secours
local warned = false
VC.on('enter', function()
    if not VC.riven or bridge or warned then return end
    warned = true
    print(('^3[rp_vehiclecontrol] pont Riven absent : ajoutez la ligne \'@rp_vehiclecontrol/riven/bridge.lua\' aux client_scripts de %s (voir README). Notifications de secours en français.^7'):format(VC.rivenResource))
end)

VC.on('frame', function()
    if R.HideGameFeed ~= false and fallback() then ThefeedHideThisFrame() end
end)
