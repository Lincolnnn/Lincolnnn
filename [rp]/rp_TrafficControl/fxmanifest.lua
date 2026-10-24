--[[
    RP TrafficControl - gestion du trafic par le réseau routier du jeu (nœuds de circulation)
    Aucun framework requis (ni ESX, ni QBCore, ni vRP). Interface NUI au style du MDC.
    Au lieu de supprimer les véhicules autour du joueur : mesures TEMPORAIRES sur un tronçon précis (une voie, un
    sens, la route entière) : fermeture (nœuds du jeu fermés, PNJ rabattus / demi-tour), ralentissement, arrêt.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_TrafficControl'
author 'Lincolnnn'
description 'Gestion du trafic voie par voie : fermeture (nœuds / PNJ rabattus), ralentissement, arrêt - standalone, NUI Vanilla JS'
version '1.4.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_script 'config.lua'

client_scripts {
    'client/theme.lua',     -- mode nuit des menus (réglé dans le MDC)
    'client/network.lua', -- mesures appliquées : nœuds, zones de vitesse, cartes, PNJ (voie, demi-tour, vitesse)
    'client/editor.lua',  -- outil de pose (voie / sens / route visés, aperçu de la bande et des nœuds)
    'client/menu.lua',    -- menu (NUI), commande /trafic
}

server_script 'server/server.lua'
