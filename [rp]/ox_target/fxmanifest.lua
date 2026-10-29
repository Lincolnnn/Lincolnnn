--[[
    ox_target (pont) - remplace ox_target par l'œil de rp_interact
    ---------------------------------------------------------------
    Les scripts qui exigent ox_target (ex. riven_spikes : herses, coffre des véhicules de police) fonctionnent avec
    notre œil (Alt) : leurs options (exports.ox_target:addGlobalVehicle, addSphereZone…) s'affichent dans sa liste.
    Ce n'est PAS le vrai ox_target : ne pas installer les deux (même nom de dossier). Standalone, aucun framework.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ox_target'
author 'Lincolnnn'
description 'Pont ox_target -> œil de rp_interact (options des scripts qui exigent ox_target) - standalone'
version '1.2.2-rp'

shared_script 'config.lua'
client_script 'client/client.lua'
