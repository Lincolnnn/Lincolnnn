--[[
    RP Teleport (ex onesync-tp) - téléportation entre joueurs et blips à travers TOUTE la carte avec OneSync :
    positions lues côté serveur (un client ne voit les joueurs qu'à ~424 m). Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_teleport'
author 'Lincolnnn'
description 'Téléportation (/goto, /bring, /back), liste des joueurs et blips à toute distance (OneSync) - standalone'
version '2.0.0'

shared_script 'config.lua'
server_script 'server.lua'
client_script 'client.lua'
