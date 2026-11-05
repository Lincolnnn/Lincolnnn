--[[
    RP Holster - holsters EUP (teef) : modèle « plein » (arme rangée dans le holster) et « vide » (arme sortie)
    changés automatiquement selon les armes configurées, avec animation et son. Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_holster'
author 'Lincolnnn'
description 'Holster EUP plein quand l\'arme est rangée, vide quand elle est sortie - standalone'
version '1.2.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/sounds/*.ogg', -- holster.ogg (à déposer) : son en sortant / rangeant l'arme
    'html/sounds/*.mp3', -- (autre format possible : config.lua, Sound.File)
    'html/sounds/*.wav',
}

shared_script 'config.lua'
client_script 'client/client.lua'
server_script 'server/server.lua' -- son relayé aux joueurs proches
