--[[
    MDC Standalone - Mobile Data Computer (ordinateur de police embarqué)
    Aucun framework requis (ni ESX, ni QBCore, ni vRP).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mdc_standalone'
author 'Lincolnnn'
description 'Mobile Data Computer (MDC) de police 100% standalone - NUI Vanilla JS'
version '1.13.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'config/blocks.json' -- blocs de localisation du HUD (lu par client/hud.lua)
}

client_scripts {
    'client/client.lua',
    'client/hud.lua'
}

server_scripts {
    'server/reports.lua', -- modèles des rapports (chargé avant server.lua)
    'server/server.lua'
}
