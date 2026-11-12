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
version '2.21.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/img/*.png', -- logos des polices (WSP, KCSO)
    'html/sounds/*.mp3', -- sons du MDC (appels, BOLO, unités, fiches liées, recherches, clic, clavier)
    'html/sounds/*.wav',
    'config/blocs.json',      -- blocs de localisation du PLD (lu par client/hud.lua)
    'config/washington.json', -- noms du PLD : État de Washington (lu par client/streetnames.lua)
}

client_scripts {
    'client/client.lua',
    'client/streetnames.lua',     -- noms du PLD : config/washington.json (rues, quartiers, villes, polices)
    'client/hud.lua',
    'client/carhud.lua' -- car HUD : relais des données de Vehicle Control (rp_vehiclecontrol)
}

server_scripts {
    'config/licenses.lua', -- permis de conduire (Washington, États voisins, Canada) et nationalités
    'server/offenses.lua', -- infractions de l'État de Washington (RCW) et classifications
    'server/reports.lua',  -- modèles des rapports (chargé avant server.lua)
    'server/server.lua'
}
