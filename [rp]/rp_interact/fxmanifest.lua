--[[
    RP Interact - menu d'interactions, fiches civiles (profils / véhicules) et "Eye Target"
    Aucun framework requis (ni ESX, ni QBCore, ni vRP).
    Lié au MDC (rp_mdc : un joueur est "policier" quand il est dans une unité)
    et au chat écrit (rp_chat : /me automatiques, copie des résultats dans le chat).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_interact'
author 'Lincolnnn'
description 'Menu d\'interactions, fiches civiles et Eye Target standalone - NUI Vanilla JS'
version '3.1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/img/*.png', -- logos des polices (bannières des menus)
}

shared_scripts {
    'config.lua',
}

client_scripts {
    'client/main.lua',     -- NUI, menu d'interactions, fiches civiles, résultats
    'client/kbmenu.lua',   -- menus au clavier (Menu Interaction, /eup) : touches, saisie de texte
    'client/options.lua',  -- options de l'œil (environnement, véhicules, personnes)
    'client/target.lua',   -- Eye Target (visée, sélection, exécution)
    'client/civil.lua',    -- Mode civil (tips d'arrestation) et détection de la mise en joue (police)
    'client/police.lua',   -- Menottes, prendre par le bras, suppression d'éléments
    'client/garage.lua',   -- Menu > Voiture > Spawn (data/vehicle.json) et Équipements (data/loadouts.json)
    'client/radio.lua',    -- Menu > Voiture > Radio : son synchronisé dans le véhicule
    'client/props.lua',    -- props posés (script "props") : déplacer / supprimer avec l'œil
    'client/eup.lua',      -- /eup : menu des tenues au clavier (data/outfits.json)
    'client/combat.lua',   -- arme à feu en main : ni coup de crosse / coup dans le vide, ni roulade
}

server_scripts {
    'server/emotes.lua',   -- lecture des emotes du mode d'emotes (RPEMOTES / rpemotes)
    'server/server.lua',
    'server/vehicles.lua', -- liste des véhicules, radio, équipements
}
