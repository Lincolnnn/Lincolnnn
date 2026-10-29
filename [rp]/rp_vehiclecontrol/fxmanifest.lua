--[[
    Vehicle Control - essence, dégâts réalistes, ceinture, moteur, portières, clignotants, poussée
    Aucun framework requis (ni ESX, ni QBCore, ni vRP).
    Lié au MDC (rp_mdc : car HUD et PLD) et au chat écrit (rp_chat : messages privés).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_vehiclecontrol'
author 'Lincolnnn'
description 'Vehicle Control : essence, dégâts, accidents réalistes, terrain, ceinture, motos (projection), moteur, portières, clignotants et poussée - standalone'
version '1.44.0'

ui_page 'html/index.html' -- message "pousser le véhicule", sons du véhicule, fiche /inspectvehicle, réparation de fortune (le car HUD est dessiné par le MDC)

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/sounds/*.ogg', -- sons du véhicule (ceinture, carillons de ceinture et de portière, clignotants) : à déposer vous-même (voir LISEZMOI.txt)
    'riven/bridge.lua',  -- chargé par Riven Impact Dynamics (client_script '@rp_vehiclecontrol/riven/bridge.lua', voir README)
}

shared_script 'config.lua'

client_scripts {
    'client/theme.lua',     -- mode nuit des menus (réglé dans le MDC)
    'client/main.lua',      -- boucle du véhicule, chocs, liaison avec le car HUD du MDC
    'client/seatbelt.lua',  -- ceinture, alarme, éjection, sons synchronisés
    'client/chimes.lua',    -- carillon de ceinture (comme le son des clignotants)
    'client/bike.lua',      -- motos : projection lors des accidents
    'client/fuel.lua',      -- essence : consommation, réservoir percé, stations sur la carte
    'client/refuel.lua',    -- plein : pompe avec un vrai pistolet (trappe arrière gauche), jerrican
    'client/damage.lua',    -- dégâts réalistes, véhicule cassé
    'client/gunshots.lua',  -- tirs bien placés : moteur, réservoir
    'client/bodywork.lua',  -- accidents : coffre / capot / portières qui s'ouvrent, pare-chocs, pare-brise, roues, bosses, pneus
    'client/glass.lua',     -- verre brisé au sol après un gros accident (chez tous les joueurs proches)
    'client/debris.lua',    -- débris de carrosserie sur la route après un gros choc, /cleardebris
    'client/rollover.lua',  -- tonneaux : départ plus facile (dérapage, virage mal engagé, PIT) et accentués
    'client/wheels.lua',    -- roues qui se détachent : virage beaucoup trop violent, trottoir percuté très fort
    'client/terrain.lua',   -- sol : herbe, terre, gravier, sable, boue (puissance, vitesse, adhérence)
    'client/occupants.lua', -- occupants : blessures, vue troublée, sonnés, tête qui part (1re personne)
    'client/inspect.lua',   -- /inspectvehicle (état du véhicule), /fieldrepair (réparation de fortune)
    'client/riven.lua',     -- Riven Impact Dynamics : réglages et notifications du pont (riven/bridge.lua)
    'client/sweep.lua',     -- nettoyage des débris d'accident à l'œil (balai, par zones, à plusieurs plus vite)
    'client/airbags.lua',   -- airbags de Riven : /airbagtest, secours si rien ne s'accroche
    'client/controls.lua',  -- moteur (O), portières (U / I)
    'client/signals.lua',   -- clignotants et warnings (flèches gauche / droite / bas)
    'client/gear.lua',      -- marche avant / marche arrière (flèche haut)
    'client/parked.lua',    -- feux stop à l'arrêt, position des roues gardée à la descente
    'client/push.lua',      -- pousser un véhicule (K)
    'client/hud.lua',       -- car HUD (en dernier)
}

server_scripts {
    'server/server.lua',
    'server/sweep.lua',     -- nettoyage des débris à l'œil : zones, joueurs qui balaient ensemble
}
