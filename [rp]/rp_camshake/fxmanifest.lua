--[[
    RP CamShake - tremblement de la caméra selon le déplacement (marche, course, sprint) et secousses lors
    des chocs (accident en véhicule, chute, ragdoll, percuté). Aucun framework requis.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_camshake'
author 'Lincolnnn'
description 'Tremblement de caméra réaliste (marche, course, sprint, chocs) - standalone'
version '1.1.1'

client_scripts {
    'config.lua',
    'client.lua',
}
