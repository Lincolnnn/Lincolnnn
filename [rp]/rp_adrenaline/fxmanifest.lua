--[[
    RP Adrénaline - blessé par balle : chutes (ragdoll) au hasard pendant un moment, plus ou moins longtemps selon le
    nombre de tirs autour (adrénaline), et l'arme à feu tenue lâchée au sol une fois sur trois à chaque chute (reprise
    avec l'œil). Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_adrenaline'
author 'Lincolnnn'
description 'Blessé par balle : chutes aléatoires selon l\'adrénaline (tirs autour) et arme lâchée - standalone'
version '1.0.0'

dependency 'rp_weaponscontrol' -- tirs entendus et balles reçues (événements locaux)

shared_script 'config.lua'
client_script 'client.lua'
