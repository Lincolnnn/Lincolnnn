--[[
    RP Police Cards - cartes aide-mémoire affichées à l'écran (carte Miranda, alphabet phonétique de la police)
    sans bloquer le joueur : il marche, conduit et ouvre ses autres menus. Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_policecards'
author 'Lincolnnn'
description 'Carte Miranda et alphabet phonétique de la police à l\'écran (non bloquant) - standalone'
version '1.1.1'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/img/*.webp', -- miranda.webp (fournie par le serveur), alphabet.webp (Adam, Boy, Charles…)
}

shared_script 'config.lua'
client_scripts {
    'keyguard.lua',         -- /modiftouche (rp_chat) : l'ancienne touche déplacée ne fait plus rien (AVANT les autres)
    'client/client.lua',
}
