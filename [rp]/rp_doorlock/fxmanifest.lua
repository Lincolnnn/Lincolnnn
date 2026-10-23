--[[
    RP Doorlock - portes verrouillées / déverrouillées par les joueurs avec l'œil (rp_interact), enfoncées à coups de
    pied par les policiers en service (MDC). Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_doorlock'
author 'Lincolnnn'
description 'Portes à verrouiller / déverrouiller, à frapper, enfoncées par la police - standalone'
version '1.0.0'

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
