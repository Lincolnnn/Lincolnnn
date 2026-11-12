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
version '1.2.1'

shared_scripts {
    'config.lua',
}

client_scripts {
    'keyguard.lua',         -- /modiftouche (rp_chat) : l'ancienne touche déplacée ne fait plus rien (AVANT les autres)
    'client/client.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
}
