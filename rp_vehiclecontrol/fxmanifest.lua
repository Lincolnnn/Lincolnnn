--[[
    Vehicle Control - essence, dégâts réalistes, ceinture, moteur, portières, frein de parcage
    Aucun framework requis (ni ESX, ni QBCore, ni vRP).
    Lié au MDC (mdc_standalone : car HUD et PLD) et au chat écrit (rp_chat : messages privés).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_vehiclecontrol'
author 'Lincolnnn'
description 'Vehicle Control : essence, dégâts, ceinture, moteur, portières et frein de parcage - standalone'
version '1.2.0'

ui_page 'html/index.html' -- message "pousser le véhicule" et sons du véhicule (le car HUD est dessiné par le MDC)

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/sounds/*.ogg', -- sons du véhicule (ceinture, carillon, clignotants), remplaçables
}

shared_script 'config.lua'

client_scripts {
    'client/main.lua',      -- boucle du véhicule, chocs, liaison avec le car HUD du MDC
    'client/seatbelt.lua',  -- ceinture, alarme, éjection, sons synchronisés
    'client/fuel.lua',      -- essence : consommation, pompes, jerrican
    'client/damage.lua',    -- dégâts réalistes, véhicule cassé
    'client/controls.lua',  -- moteur (O), portières (U / I), frein de parcage (L)
    'client/signals.lua',   -- clignotants et warnings (flèches gauche / droite / bas)
    'client/push.lua',      -- pousser un véhicule (K)
    'client/hud.lua',       -- car HUD (en dernier)
}

server_script 'server/server.lua'
