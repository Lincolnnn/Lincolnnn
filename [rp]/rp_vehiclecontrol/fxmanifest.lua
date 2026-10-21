--[[
    Vehicle Control - essence, dégâts réalistes, ceinture, moteur, portières, clignotants, poussée
    Aucun framework requis (ni ESX, ni QBCore, ni vRP).
    Lié au MDC (rp_mdc : car HUD et PLD) et au chat écrit (rp_chat : messages privés).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_vehiclecontrol'
author 'Lincolnnn'
description 'Vehicle Control : essence, dégâts, ceinture, motos (projection), moteur, portières, clignotants et poussée - standalone'
version '1.31.0'

ui_page 'html/index.html' -- message "pousser le véhicule" et sons du véhicule (le car HUD est dessiné par le MDC)

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/sounds/*.ogg', -- sons du véhicule (ceinture, carillons de ceinture et de portière, clignotants) : à déposer vous-même (voir LISEZMOI.txt)
}

shared_script 'config.lua'

client_scripts {
    'client/main.lua',      -- boucle du véhicule, chocs, liaison avec le car HUD du MDC
    'client/seatbelt.lua',  -- ceinture, alarme, éjection, sons synchronisés
    'client/chimes.lua',    -- carillon de ceinture (comme le son des clignotants)
    'client/bike.lua',      -- motos : projection lors des accidents
    'client/fuel.lua',      -- essence : consommation, réservoir percé, stations sur la carte
    'client/refuel.lua',    -- plein : pompe avec un vrai pistolet (trappe arrière gauche), jerrican
    'client/damage.lua',    -- dégâts réalistes, véhicule cassé
    'client/gunshots.lua',  -- tirs bien placés : moteur, réservoir
    'client/bodywork.lua',  -- dégâts visuels : pare-chocs, capot, coffre, portières, vitres, roues qui tombent
    'client/controls.lua',  -- moteur (O), portières (U / I)
    'client/signals.lua',   -- clignotants et warnings (flèches gauche / droite / bas)
    'client/gear.lua',      -- marche avant / marche arrière (flèche haut)
    'client/parked.lua',    -- feux stop à l'arrêt, position des roues gardée à la descente
    'client/push.lua',      -- pousser un véhicule (K)
    'client/hud.lua',       -- car HUD (en dernier)
}

server_script 'server/server.lua'
