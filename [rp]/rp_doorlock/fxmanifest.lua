--[[
    RP Doorlock - portes verrouillées / déverrouillées par les joueurs en mode civil avec l'œil (rp_interact),
    enfoncées par les policiers en service (MDC) avec une barre de réussite. Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_doorlock'
author 'Lincolnnn'
description 'Portes à verrouiller / déverrouiller, à frapper, enfoncées par la police - standalone'
version '1.1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_scripts {
    'config.lua',
    'shared.lua',
}

client_scripts {
    'models.lua',          -- modèles de portes du jeu
    'client/client.lua',
}

server_scripts {
    'server/server.lua',
}
