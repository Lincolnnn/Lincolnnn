--[[
    RP PlateColors - couleur du texte (lettres et chiffres) des plaques d'immatriculation via carcols.ymt.
    Aucun framework requis. Voir README.md (deux méthodes : ressource serveur et méthode garantie update.rpf).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_platecolors'
author 'Lincolnnn'
description 'Couleur du texte des plaques d\'immatriculation (carcols.ymt) - standalone'
version '1.0.0'

files {
    'data/carcols.ymt',
}

data_file 'CARCOLS_FILE' 'data/carcols.ymt'

client_scripts {
    'config.lua',
    'client.lua',
}
