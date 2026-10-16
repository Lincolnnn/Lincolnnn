--[[
    RP Equipment - équipement des véhicules de police (portières avant / coffre) et râtelier d'armes longues
    Aucun framework requis (ni ESX, ni QBCore, ni vRP).
    Lié au MDC (mdc_standalone : un joueur est "policier" quand il est dans une unité) et, si présent, à
    rp_interact (data/vehicles.json : service de chaque véhicule) et rp_chat (messages privés).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_equipment'
author 'Lincolnnn'
description 'Équipement des véhicules de police, râtelier d\'armes longues et coffre (plots, fusées) - standalone, NUI Vanilla JS'
version '1.5.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_script 'config.lua'
client_scripts {
    'client/client.lua',
    'client/traffic.lua',
}
server_script 'server/server.lua'
