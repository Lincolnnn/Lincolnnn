--[[
    RP Weapons Control - recul des armes, effets au tir, flash de bouche et fumée du canon, synchronisés
    avec les joueurs autour. Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_weaponscontrol'
author 'Lincolnnn'
description 'Recul, effets au tir, flash et fumée du canon synchronisés, lampe toujours allumée et renforcée, sélecteur de tir, effet de tir sur les bords de l\'écran - standalone'
version '1.13.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/script.js',
    'textures/beam.png', -- faisceau visible des lampes (le même que rp_spotlight)
    'textures/glow.png', -- lueur / halo de la lampe
}

shared_script 'config.lua'
client_scripts {
    'client/client.lua',
    'client/flashlight.lua', -- lampes : lumière, faisceau visible, lueur, éblouissement, stroboscope
}
server_script 'server/server.lua'
