--[[
    RP vMenu Keys - touches de vMenu imposées par le serveur (plus de vMenu sur V). Aucune modification de vMenu.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_vmenukeys'
author 'Lincolnnn'
description 'Touche d\'ouverture et noclip de vMenu imposées par le serveur, quel que soit son permissions.cfg - standalone'
version '1.0.0'

shared_scripts {
    'config.lua',
}

client_scripts {
    'client/client.lua',
}

server_scripts {
    'server/server.lua',
}
