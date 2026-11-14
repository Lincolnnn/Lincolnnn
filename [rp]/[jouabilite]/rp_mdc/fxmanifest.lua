--[[
    MDC Standalone - Mobile Data Computer (ordinateur de police embarqué)
    Aucun framework requis (ni ESX, ni QBCore, ni vRP).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_mdc'
author 'Lincolnnn'
description 'Mobile Data Computer (MDC) de police sans framework - MySQL (oxmysql), MDC Web du dispatch, NUI Vanilla JS'
version '3.0.0'

dependency 'oxmysql' -- base de données MySQL / MariaDB (voir README)

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/blockeditor.js', -- panneau de /blocs (admins)
    'html/img/*.png', -- logos des polices (WSP, KCSO)
    'html/sounds/*.mp3', -- sons du MDC (appels, BOLO, unités, fiches liées, recherches, clic, clavier)
    'html/sounds/*.wav',
    'config/blocs.json',      -- blocs de localisation du PLD (lu par client/hud.lua)
    'config/washington.json', -- noms du PLD : État de Washington (lu par client/streetnames.lua)
}

client_scripts {
    'keyguard.lua',         -- /modiftouche (rp_chat) : l'ancienne touche déplacée ne fait plus rien (AVANT les autres)
    'client/client.lua',
    'client/streetnames.lua',     -- noms du PLD : config/washington.json (rues, quartiers, villes, polices)
    'client/blockeditor.lua',     -- /blocs (admins) : créer les blocs du PLD (point / carré) et copier leurs lignes
    'client/hud.lua',
    'client/carhud.lua' -- car HUD : relais des données de Vehicle Control (rp_vehiclecontrol)
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- MySQL / MariaDB (ressource oxmysql)
    'server/db.lua',       -- base de données : migrations, file d'écriture, chargement (avant server.lua)
    'server/web.lua',      -- pont avec le MDC Web du dispatch (API HTTP + événements)
    'config/licenses.lua', -- permis de conduire (Washington, États voisins, Canada) et nationalités
    'server/offenses.lua', -- infractions de l'État de Washington (RCW) et classifications
    'server/reports.lua',  -- modèles des rapports (chargé avant server.lua)
    'server/server.lua'
}
