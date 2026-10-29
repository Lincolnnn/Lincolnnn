--[[
    RP Revive - réanimer son personnage après la mort : sur place ou dans un hôpital (Sandy Shores / Paleto Bay, au
    hasard), en laissant (si on le coche) son corps sur place. Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_revive'
author 'Lincolnnn'
description 'Réanimation sur place ou à l\'hôpital, corps laissé sur place (option) - standalone'
version '1.0.2'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_script 'config.lua'

client_scripts {
    'client/theme.lua',     -- mode nuit des menus (réglé dans le MDC)
    'client/client.lua',
}

server_script 'server/server.lua'
