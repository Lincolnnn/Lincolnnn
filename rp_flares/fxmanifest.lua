--[[
    RP Flares - fusées de détresse posées au sol (WEAPON_FLARE) : une touche pose une fusée allumée, debout, sans la
    retirer des armes du joueur ; on la retire avec l'œil (rp_interact). Lumière renforcée la nuit. Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_flares'
author 'Lincolnnn'
description 'Fusées de détresse posées au sol, retirées avec l\'œil, lumière renforcée la nuit - standalone'
version '1.0.0'

shared_scripts {
    'config.lua',
}

client_scripts {
    'client/client.lua',
}

server_scripts {
    'server/server.lua',
}
