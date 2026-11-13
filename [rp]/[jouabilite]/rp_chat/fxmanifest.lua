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
version '1.27.0'

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
    'keyguard.lua',         -- /modiftouche (rp_chat) : l'ancienne touche déplacée ne fait plus rien (AVANT les autres)
    'touches.lua',          -- /modiftouche : scripts, spécificités et touches d'origine (catalogue)
    'client/theme.lua',     -- mode nuit des menus (réglé dans le MDC)
    'client/client.lua',
    'client/overhead.lua',
    'client/keybinds.lua',  -- /modiftouche : nouvelles touches du joueur (gardées)
}

server_scripts {
    'server/server.lua',
}
