--[[
    RP Weapons Control - recul des armes, effets au tir, acouphènes, flash de bouche et fumée du canon, synchronisés
    avec les joueurs autour. Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_weaponscontrol'
author 'Lincolnnn'
description 'Recul, effets au tir, acouphènes, flash et fumée du canon synchronisés - standalone'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/script.js',
}

shared_script 'config.lua'
client_script 'client/client.lua'
server_script 'server/server.lua'
