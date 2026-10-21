--[[
    RP PlateColors - couleur du texte (lettres et chiffres) des plaques d'immatriculation, sans carcols.ymt :
    texte du jeu masqué et redessiné par le script dans la couleur de chaque type de plaque.
    Aucun framework requis. Éditeur en jeu (NUI Vanilla JS) : position par modèle et couleurs.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_platecolors'
author 'Lincolnnn'
description 'Couleur du texte des plaques d\'immatriculation (texte redessiné, éditeur en jeu) - standalone, NUI Vanilla JS'
version '2.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'assets/plate_font.png',
    'assets/plate_font_outline.png',
    'assets/blank_font.png',
    'assets/flat_n.png',
}

shared_script 'config.lua'

client_scripts {
    'client/plates.lua',  -- police du jeu masquée, texte redessiné en couleur, placement automatique
    'client/editor.lua',  -- éditeur /plaqueedit (position par modèle, couleurs)
}

server_script 'server/server.lua'
