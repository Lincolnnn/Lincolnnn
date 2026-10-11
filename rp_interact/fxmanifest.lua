--[[
    RP Interact - menu d'interactions, fiches civiles (profils / véhicules) et "Eye Target"
    Aucun framework requis (ni ESX, ni QBCore, ni vRP).
    Lié au MDC (mdc_standalone : un joueur est "policier" quand il est dans une unité)
    et au chat écrit (rp_chat : /me automatiques, copie des résultats dans le chat).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_interact'
author 'Lincolnnn'
description 'Menu d\'interactions, fiches civiles et Eye Target standalone - NUI Vanilla JS'
version '1.5.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_script 'config.lua'

client_scripts {
    'client/main.lua',     -- NUI, menu d'interactions, fiches civiles, résultats
    'client/options.lua',  -- options de l'œil (environnement, véhicules, personnes)
    'client/target.lua',   -- Eye Target (visée, sélection, exécution)
    'client/civil.lua',    -- Mode civil (tips d'arrestation) et détection de la mise en joue (police)
    'client/police.lua',   -- Menottes, prendre par le bras, véhicules d'urgence, suppression d'éléments
}

server_scripts {
    'server/emotes.lua',   -- lecture des emotes du mode d'emotes (RPEMOTES / rpemotes)
    'server/server.lua',
}
