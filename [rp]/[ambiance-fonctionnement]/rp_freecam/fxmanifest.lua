--[[
    RP Freecam - /freecam : mode photo. Petit menu au clavier : caméra libre, minimap / HUD du jeu / interfaces des
    scripts masqués, personnage caché, zoom (molette), vitesse, inclinaison. Pour tous les joueurs. Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_freecam'
author 'Lincolnnn'
description '/freecam : caméra libre et mode photo (minimap / HUD masqués, zoom, inclinaison) - standalone'
version '1.1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
}

shared_script 'config.lua'
client_scripts {
    'client/theme.lua',   -- mode nuit (réglé dans le MDC)
    'client/client.lua',
}
