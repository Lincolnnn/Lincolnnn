--[[
    RP Weapons Control - recul des armes, effets au tir, acouphènes, flash de bouche et fumée du canon, synchronisés
    avec les joueurs autour. Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_weaponscontrol'
author 'Lincolnnn'
description 'Recul, effets au tir, flash et fumée du canon synchronisés, posture normale à la 1re personne, lampe toujours allumée et renforcée, sélecteur de tir, effet de tir sur les bords de l\'écran - standalone'
version '1.9.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/script.js',
}

shared_script 'config.lua'
client_script 'client/client.lua'
server_script 'server/server.lua'
