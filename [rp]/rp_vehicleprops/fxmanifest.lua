--[[
    RP VehicleProps - objets collés sur les véhicules (sac, arme, radio, carton…), posés avec l'œil de rp_interact
    Aucun framework requis (ni ox_lib, ni ox_target, ni ESX, ni QBCore). Interface NUI au style du MDC.
    Œil (Alt) sur un véhicule : « Ajouter un objet », « Déplacer un objet », « Retirer un objet » ; arme ou lampe en
    main : la poser sur le véhicule (surface visée, accessoires, lampe allumée), la lampe au sol ; la reprendre.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_vehicleprops'
author 'Lincolnnn'
description 'Objets collés sur les véhicules, posés et réglés avec l\'œil de rp_interact - standalone, NUI Vanilla JS'
version '1.7.1'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_script 'config.lua'

client_scripts {
    'client/theme.lua',   -- mode nuit des menus (réglé dans le MDC)
    'client/client.lua',  -- objets posés (chez tous), œil, éditeur
    'client/held.lua',    -- arme / lampe tenue : posée sur un véhicule (accessoires, lampe) ou la lampe au sol
    'client/lostprops.lua', -- chapeau / lunettes : tombés ou posés sur un véhicule, vus et repris par tous
}

server_scripts {
    'server/server.lua',
    'server/held.lua',    -- arme / lampe posée : état du véhicule "rpWeapons", lampes au sol
    'server/wear.lua',    -- chapeaux / lunettes au sol ou sur un véhicule, vus et repris par tous
}
