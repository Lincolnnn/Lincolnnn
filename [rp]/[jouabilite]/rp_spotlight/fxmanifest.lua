--[[
    RP Spotlight - projecteurs de portière des véhicules de police (côté conducteur et, sur certains modèles, côté
    passager avant), configurés véhicule par véhicule, vus par tous les joueurs. Aucun framework.
    Écrit pour ce serveur (le script px_spotlight fourni est chiffré : il n'a été ni lu ni repris).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_spotlight'
author 'Lincolnnn'
description 'Projecteurs de portière par véhicule (conducteur / passager avant), faisceau visible, éblouissement, visée, verrouillage'
version '1.4.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'textures/beam.png', -- faisceau visible (dégradé fait pour ce script)
    'textures/glow.png', -- halo de la lampe
}

shared_script 'config.lua'
client_scripts {
    'client/theme.lua',
    'client/client.lua',
}
server_script 'server/server.lua'
