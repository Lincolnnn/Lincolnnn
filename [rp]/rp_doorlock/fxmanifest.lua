--[[
    RP Doorlock - portes verrouillées / déverrouillées avec l'œil (rp_interact) par les joueurs qui ne sont pas
    policiers en service, enfoncées par tout le monde avec une barre de réussite (porte cassée ensuite). Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_doorlock'
author 'Lincolnnn'
description 'Portes à verrouiller / déverrouiller, à frapper, à enfoncer (porte forcée) - standalone'
version '1.2.0'

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
