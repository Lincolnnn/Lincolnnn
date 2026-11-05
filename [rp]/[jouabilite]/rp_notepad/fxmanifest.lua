--[[
    RP Notepad - bloc-notes en jeu (écriture manuscrite, dessin, pages), avec animation et props. Les pages sont
    gardées chez le joueur ; à l'ouverture, retour à la dernière page utilisée. Retranscription dans la note de
    l'unité du MDC (rp_mdc). Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_notepad'
author 'Lincolnnn'
description 'Bloc-notes en jeu (texte manuscrit, dessin, pages gardées) + retranscription dans le MDC - standalone'
version '1.1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/fonts/Kalam-Regular.ttf', -- police manuscrite Kalam (SIL Open Font License, html/fonts/OFL-Kalam.txt)
}

shared_script 'config.lua'
client_scripts {
    'client/theme.lua',   -- mode nuit (réglé dans le MDC)
    'client/client.lua',
}
