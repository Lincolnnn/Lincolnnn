--[[
    RP Adrénaline - blessé par balle : 15 s de recherche des tirs autour, puis adrénaline haute (chute retardée de 50 à
    70 s selon les balles reçues) ou basse (chutes au hasard toutes les 7 s), arme à feu lâchée au sol à chaque chute
    selon un pourcentage (reprise avec l'œil). Arrêt soigné ou 1 min 30 après la recherche. Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_adrenaline'
author 'Lincolnnn'
description 'Blessé par balle : adrénaline haute ou basse selon les tirs autour, chutes et arme lâchée - standalone'
version '2.0.0'

dependency 'rp_weaponscontrol' -- tirs entendus et balles reçues (événements locaux)

shared_script 'config.lua'
client_script 'client.lua'
