--[[
    RP Stages - stages d'éclairage des véhicules de police par extras : stages 1, 2, 3 (réponse, seul avec la sirène),
    Traffic Advisor gauche / droite et Steady Burn, véhicule par véhicule (spawn code). Synchronisé entre les joueurs.
    Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_stages'
author 'Lincolnnn'
description 'Stages des véhicules de police (extras) : stages 1 / 2 / 3, TA gauche / droite, Steady Burn, sirène au stage 3 - standalone'
version '1.0.0'

ui_page 'html/index.html' -- indicateur des stages (conducteur)

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_scripts {
    'config.lua',
    'shared/logic.lua',
}

client_scripts {
    'keyguard.lua',      -- /modiftouche (rp_chat) : l'ancienne touche déplacée ne fait plus rien (AVANT les autres)
    'client/client.lua',
}

server_scripts {
    'server/server.lua',
}
