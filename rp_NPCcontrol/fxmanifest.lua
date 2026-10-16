--[[
    RP NPC Control - gestion des PNJ du serveur : plus de police / pompiers / ambulanciers du jeu (ni eux ni leurs
    véhicules), plus d'indice de recherche, PNJ qui ignorent les joueurs (ni peur, ni réaction aux fusillades et
    explosions), densité du trafic et des piétons réglable de 0.0 (aucun) à 3.0 (triple). Aucun framework requis.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_NPCcontrol'
author 'Lincolnnn'
description 'Contrôle des PNJ : services d\'urgence du jeu supprimés, indice de recherche, PNJ ignorent les joueurs, densité - standalone'
version '1.3.0'

shared_scripts {
    'config.lua',
}

client_scripts {
    'client/client.lua',
}

server_scripts {
    'server/server.lua',
}
