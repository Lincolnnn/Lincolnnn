--[[
    RP Permissions - rôles Discord -> permissions du serveur (ACE) et liste blanche
    Inspiré de DiscordWhitelist (FAXES, CC0 1.0) : réécrit en Lua, sans Node ni dépendance.
]]
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_permissions'
description 'Rôles Discord (Admin, Membre, Joueur non-officiel) -> groupes ACE, liste blanche à la connexion'
version '1.0.0'

shared_script 'config.lua'
server_script 'server/server.lua'
