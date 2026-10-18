--[[
    RP RoleplayZone - scènes de roleplay à fouiller, préparées par les civils, et « œil d'aigle » des policiers
    Aucun framework requis (ni ESX, ni QBCore, ni vRP). Interface NUI au style du MDC (comme rp_TrafficControl).
      - ZONE DE RECHERCHE : grand cercle (15 à 60 m) ; un policier qui y entre voit la description du civil en haut
        au milieu de l'écran, entend un court son d'intrigue et voit le cercle sur sa carte, jusqu'à ce qu'il en sorte ;
      - PÉRIMÈTRE À FOUILLER : petit lieu (sol, recoin…), non lié à un objet ;
      - OBJET À FOUILLER : un props du décor ;
      - ARME LÂCHÉE (mode civil) : jetée ou posée au sol, ramassée uniquement avec l'œil de rp_interact ;
      - ŒIL D'AIGLE (policiers) : onde « radar » de 15 m qui fait ressortir les contours en blanc ; ce qui est à
        fouiller reste en surbrillance (4 s) ; une zone à moins de 100 m est pointée (caméra + flèche).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_RoleplayZone'
author 'Lincolnnn'
description 'Zones de recherche, périmètres et objets à fouiller, armes lâchées, œil d\'aigle - standalone, NUI Vanilla JS'
version '1.2.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_script 'config.lua'

client_scripts {
    'client/shared.lua',   -- outils (demandes au serveur, droits, cercle qui épouse le terrain)
    'client/world.lua',    -- scènes appliquées : zone (message, son, carte), fouilles, protection, armes lâchées
    'client/selector.lua', -- mode sélection (cercle blanc qui suit le terrain, objet visé en surbrillance)
    'client/eagle.lua',    -- œil d'aigle (onde radar, contours, caméra et flèche vers la zone)
    'client/weapon.lua',   -- mode civil : lâcher son arme (rappel, jeter / poser à la molette)
    'client/menu.lua',     -- menu (NUI), commande /scene
}

server_script 'server/server.lua'
