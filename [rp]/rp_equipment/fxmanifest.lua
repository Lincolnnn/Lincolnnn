--[[
    RP Equipment - équipement des véhicules de police (portières avant / coffre) et râtelier d'armes longues
    Aucun framework requis (ni ESX, ni QBCore, ni vRP).
    Lié au MDC (rp_mdc : un joueur est "policier" quand il est dans une unité) et, si présent, à
    rp_interact (data/vehicle.json : police de chaque véhicule) et rp_chat (messages privés).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_equipment'
author 'Lincolnnn'
description 'Équipement des véhicules de police, râtelier d\'armes longues et coffre (plots, fusées) - standalone, NUI Vanilla JS'
version '1.11.1'

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
    'client/traffic.lua',
    'client/spikes.lua',    -- herse de riven_spikes : prise / rangée au coffre, jamais « rangée dans la poche »
}
server_script 'server/server.lua'
