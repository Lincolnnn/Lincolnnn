--[[
    RP DLS - adaptation FiveM de DLS (Dynamic Lighting System, GTA V solo) : tous les stages des véhicules DLS
    (stage 1, 2, 3, custom, Steady Burn / Cruise, Traffic Advisor, Wail Setup…), synchronisés entre joueurs,
    à partir des fichiers de véhicules de DLS tels quels. Sons de sirène, air horn, manuelle, scan.
    Aucun framework requis (ni ESX, ni QBCore, ni vRP).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_dls'
author 'Lincolnnn'
description 'DLS pour FiveM : stages de gyrophares des véhicules DLS, Traffic Advisor, sirènes - synchronisé, standalone'
version '2.1.2'

ui_page 'html/index.html' -- panneau de commande (stages, TA, sirène)

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'img/glow.png',                -- halo des gyrophares dessinés
    'dls/*.xml',                   -- fichiers de véhicules DLS (nom du fichier = nom du modèle)
    'dls/trafficadvisory/*.xml',   -- groupes de motifs du Traffic Advisor
    'dls/packs/**/*.meta',         -- packs de véhicules : carcols.meta et carvariations.meta (sous-dossiers compris)
}

shared_scripts {
    'config.lua',
    'shared/xml.lua',   -- lecteur XML
    'shared/dls.lua',   -- lecture des fichiers DLS (v1), packs (carcols / carvariations)
    'shared/dlsv2.lua', -- lecture des fichiers DLS v2
}

client_scripts {
    'client/main.lua',      -- état "dls" des véhicules (synchronisé)
    'client/render.lua',    -- stages dessinés à partir du XML (halos, éclairage, projecteurs)
    'client/dlsv2.lua',     -- moteur DLS v2 : déclencheurs, modes actifs, sons
    'client/vehicles.lua',  -- application aux véhicules proches : gyrophares d'origine, sons, blackout
    'client/controls.lua',  -- touches du conducteur, modes spéciaux
    'client/ui.lua',        -- panneau NUI (en dernier)
}

server_script 'server/server.lua'
