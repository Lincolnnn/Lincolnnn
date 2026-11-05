--[[
    RP Adrénaline - blessé par balle : 8 s de recherche des tirs autour (50 m), puis adrénaline haute (fusillade : chutes
    à partir de 50 à 70 s) ou basse (hors fusillade : chutes dès la fin des 8 s), tirages toutes les 8 s, % de chute
    et d'arme lâchée selon les balles reçues, démarche blessée dès la 2e chute. Arrêt soigné ou 1 min 30 après.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_adrenaline'
author 'Lincolnnn'
description 'Blessé par balle : adrénaline haute ou basse selon les tirs autour, chutes et arme lâchée - standalone'
version '3.0.1'

dependency 'rp_weaponscontrol' -- tirs entendus et balles reçues (événements locaux)

shared_script 'config.lua'
client_script 'client.lua'
