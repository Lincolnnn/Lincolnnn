--[[
    TASER 10 (Axon) - script de Cartoon (1.7.0), adapté pour ce serveur : plus de dépendance à ox_target, l'option
    « Retirer les sondes du Taser » passe par l'œil de rp_interact (exports targetOptions / targetSelect).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rp_taser10'
author 'Cartoon (adapté : Lincolnnn)'
description 'TASER 10 : cartouches, sondes, fils, laser, lampe, CID - standalone, œil de rp_interact'
version '1.7.0-rp.4'
-- 1.0.0 Pacific Valley Version
-- 1.5.0 Pre Release + Patches
-- 1.6.0 Pre Lighting & Client Sync Patch
-- 1.6.1 Changed 'Reactivate' functionality & ragdoll behavior
-- 1.7.0-rp.1 Sans ox_target : œil de rp_interact (retirer les sondes, recharger), textes des touches en français

ui_page 'html/index.html'

shared_script 'config.lua'

client_script 'client.lua'
server_script 'server.lua'

data_file 'DLC_ITYP_REQUEST' 'stream/prong.ytyp'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/imgs/*',
    'html/imgs/charge/*',
    'html/imgs/battery/*',
    'html/imgs/function/*',
    'html/sound/*',
    'stream/prong.ytyp'
}
