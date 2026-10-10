--[[
    RP Chat - chat écrit rôleplay (remplace le chat d'origine de FiveM)
    Aucun framework requis (ni ESX, ni QBCore, ni vRP).
    Commandes : /nomrp, /me, /info, /qst, /rep
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_chat'
author 'Lincolnnn'
description 'Chat écrit rôleplay standalone (commandes police / RP) - NUI Vanilla JS'
version '1.2.0'

-- Remplace la ressource "chat" d'origine : les ressources qui dépendent de "chat"
-- (ou qui envoient "chat:addMessage") fonctionnent avec ce chat.
provide 'chat'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_script 'config.lua'

client_scripts {
    'client/client.lua',
    'client/overhead.lua',
}

server_scripts {
    'server/server.lua',
}
