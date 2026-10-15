--[[
    WEAPON_T7 - deuxième taser en ARME ADDON (ne remplace pas WEAPON_STUNGUN). Aucun framework requis.
    Même comportement que le taser du jeu : dégâts électriques, non mortel, munitions infinies, recharge.
    Modèle 3D : stream/w_pi_t7.ydr + stream/w_pi_t7.ytd (voir stream/LISEZMOI.txt).
    Fichiers meta adaptés de CENSOR37/FiveM-AddonWeaponTemplates (MIT, voir LICENSE-TEMPLATE.txt).
    Performance : aucune boucle (un seul AddTextEntry au démarrage) -> 0.00 ms.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'weapon_t7'
author 'Lincolnnn'
description 'Taser addon WEAPON_T7 (copie du stungun) - standalone'
version '1.0.0'

files {
    'meta/weaponarchetypes.meta',
    'meta/pedpersonality.meta',
    'meta/weaponanimations.meta',
    'meta/weapon.meta',
}

data_file 'WEAPON_METADATA_FILE' 'meta/weaponarchetypes.meta'
data_file 'PED_PERSONALITY_FILE' 'meta/pedpersonality.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'meta/weaponanimations.meta'
data_file 'WEAPONINFO_FILE' 'meta/weapon.meta'

client_script 'client.lua'
