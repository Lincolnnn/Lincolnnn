--[[
    RP Ganghunt - vagues d'ennemis qui traquent le joueur qui les appelle (/ganghunt)
    Aucun framework requis (ni ESX, ni QBCore, ni vRP). Menu NUI au style des autres scripts (MDC, TrafficControl).
    Gang (Bikers, Ballas, Families, Vagos), Organisation (Chinois, Arméniens, Coréens, Mexicains, Salvadoriens,
    Merryweather) ou Forces (Police, Armée, Sheriff, NOOSE) ; vagues de 10, armes réparties en pourcentages ou
    aléatoires, véhicules et hélicoptère de la faction. Ils ne s'entretuent pas et traquent le joueur partout.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_Ganghunt'
author 'Lincolnnn'
description 'Ganghunt : vagues d\'ennemis (gangs, organisations, forces) qui traquent le joueur - standalone, NUI Vanilla JS'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_script 'config.lua'

client_scripts {
    'client/hunt.lua', -- vagues : apparition, traque, nettoyage
    'client/menu.lua', -- menu (NUI), commande /ganghunt
}

server_script 'server/server.lua'
