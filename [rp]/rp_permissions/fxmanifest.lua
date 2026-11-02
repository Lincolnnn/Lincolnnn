--[[
    RP Permissions - rôles Discord -> permissions du serveur (ACE) et liste blanche
    Inspiré de DiscordWhitelist (FAXES, CC0 1.0) : réécrit en Lua, sans Node ni dépendance.
]]
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_permissions'
description 'Rôles Discord (Admin, Membre, Joueur non-officiel) -> groupes ACE, liste blanche à la connexion'
version '1.4.0'

-- config.lua côté SERVEUR seulement (il contient le token du bot : jamais envoyé aux joueurs)
server_scripts {
    'config.lua',
    'server/server.lua',
    'server/discord_*.lua', -- statut du serveur sur Discord (discord_status.lua, StatusConfig) : chargé s'il est là
}
