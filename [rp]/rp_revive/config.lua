--[[
    RP Revive - configuration
    À la mort : un écran s'affiche avec deux choix principaux, RÉANIMER SUR PLACE ou À L'HÔPITAL (un des hôpitaux
    ci-dessous, au hasard : le joueur ne choisit pas), et une case secondaire LAISSER MON CORPS SUR PLACE (une copie du
    personnage reste allongée là où il est mort ; elle garde la description de son profil civil actif, sauf l'odeur
    détectée automatiquement).
]]

ReviveConfig = {
    -- Secondes avant de pouvoir choisir (0 : tout de suite)
    Delay = 0,

    -- Hôpitaux (x, y, z, cap) : un au hasard
    Hospitals = {
        { label = 'Sandy Shores Medical Center', coords = vector4(1839.45, 3672.85, 34.28, 210.0) },
        { label = 'Paleto Bay Medical Center', coords = vector4(-247.36, 6331.20, 32.43, 225.0) },
    },

    -- Corps laissé sur place : retiré au bout de Minutes (0 : jamais), ou quand le même joueur en laisse un autre
    Corpse = { Enabled = true, Minutes = 30, MaxPerPlayer = 1 },

    -- Réapparition automatique de spawnmanager (ressource de base de FiveM) coupée : c'est ce menu qui réanime
    DisableAutoSpawn = true,

    -- Touches (au clavier, menu affiché) : réanimer sur place / à l'hôpital / laisser son corps
    Keys = { here = 'E', hospital = 'H', corpse = 'C' },

    InteractResource = 'rp_interact', -- description du profil gardée sur le corps (fiche civile)
}
