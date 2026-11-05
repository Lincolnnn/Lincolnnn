--[[
    RP Stamina - endurance de sprint selon les armes portées (dans l'inventaire, pas seulement en main) :
    policiers (unité du MDC) : armes longues (fusils à pompe, fusils d'assaut) ; civils : chaque type d'arme pèse.
    Sprint épuisé : course normale (illimitée). Barre en haut au milieu de l'écran. Aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_stamina'
author 'Lincolnnn'
description 'Endurance de sprint selon les armes portées (police : armes longues ; civils : par type d\'arme) - standalone'
version '1.1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
}

shared_script 'config.lua'
client_scripts {
    'client/theme.lua',   -- mode nuit (réglé dans le MDC)
    'client/client.lua',
}
