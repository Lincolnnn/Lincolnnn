--[[
    RP Overhead IDs - numéro (ID serveur) et nom des joueurs au-dessus des têtes, seulement pendant qu'une touche est
    maintenue. Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_overheadids'
author 'Lincolnnn'
description 'Numéros et noms des joueurs au-dessus des têtes en maintenant une touche - standalone'
version '1.0.0'

shared_scripts {
    'config.lua',
}

client_scripts {
    'client/client.lua',
}
