--[[
    RP Ganghunt - vagues d'ennemis qui traquent le joueur qui les appelle (/ganghunt)
    Aucun framework requis (ni ESX, ni QBCore, ni vRP). Menu NUI au style des autres scripts (MDC, TrafficControl).
    Gang (Bikers, Ballas, Families, Vagos), Organisation (Chinois, Arméniens, Coréens, Mexicains, Salvadoriens,
    Merryweather) ou Forces (Police, Armée, Sheriff, NOOSE) ; 1 à 10 vagues de 1 à 30 ennemis, armes réparties en
    pourcentages ou aléatoires (armes spéciales comprises), convoi de véhicules et hélicoptère de la faction,
    silencieux, grenades, musique de recherche du jeu. Ils ne s'entretuent pas, traquent le joueur et le cherchent
    quand ils le perdent de vue (comme la police du jeu).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_Ganghunt'
author 'Lincolnnn'
description 'Ganghunt : vagues d\'ennemis (gangs, organisations, forces) qui traquent le joueur - standalone, NUI Vanilla JS'
version '1.2.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_script 'config.lua'

client_scripts {
    'client/spawn.lua', -- apparition : positions sûres, convoi, hélicoptère, armes, silencieux, grenades
    'client/ai.lua',    -- comportement : repéré / recherche (comme la police du jeu), poursuite, grenades, corps à corps
    'client/hunt.lua',  -- la chasse : vagues, musique, HUD, fin
    'client/menu.lua',  -- menu (NUI), commande /ganghunt
}

server_script 'server/server.lua'
