--[[
    RP TrafficControl - gestion du trafic par le réseau routier du jeu (nœuds de circulation)
    Aucun framework requis (ni ESX, ni QBCore, ni vRP). Interface NUI au style du MDC.
    Au lieu de supprimer les véhicules autour du joueur : fermeture TEMPORAIRE des nœuds de circulation
    (route barrée : les PNJ et le GPS prennent une déviation), limitation de vitesse et arrêt du trafic par zone.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_TrafficControl'
author 'Lincolnnn'
description 'Gestion du trafic : routes barrées (déviation par les nœuds), limitations de vitesse, arrêt du trafic - standalone, NUI Vanilla JS'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_script 'config.lua'

client_scripts {
    'client/network.lua', -- mesures appliquées au réseau routier de ce joueur (nœuds, zones de vitesse, cartes)
    'client/editor.lua',  -- outil de pose (visée au sol, accroche à la route, aperçu des nœuds)
    'client/menu.lua',    -- menu (NUI), commande /trafic
}

server_script 'server/server.lua'
