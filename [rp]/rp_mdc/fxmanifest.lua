--[[
    MDC Standalone - Mobile Data Computer (ordinateur de police embarqué)
    Aucun framework requis (ni ESX, ni QBCore, ni vRP).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_mdc'
author 'Lincolnnn'
description 'Mobile Data Computer (MDC) de police 100% standalone - NUI Vanilla JS'
version '2.1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'config/blocks.json' -- blocs de localisation du HUD (lu par client/hud.lua)
}

client_scripts {
    'client/client.lua',
    'config/atlanta_streets.lua', -- noms d'Atlanta (rues, quartiers) : SEULE source des noms du PLD
    'client/streetnames.lua',     -- applique config/atlanta_streets.lua (PLD, Position actuelle, exports)
    'client/hud.lua',
    'client/carhud.lua' -- car HUD : relais des données de Vehicle Control (rp_vehiclecontrol)
}

server_scripts {
    'server/reports.lua', -- modèles des rapports (chargé avant server.lua)
    'server/server.lua'
}
