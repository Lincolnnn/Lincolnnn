--[[
    RP Flares - configuration (partagée client / serveur)
]]
FlareConfig = {
    -- Fusée tenue en main (arme du jeu) et touche pour la poser au sol. Chaque joueur peut changer la touche :
    -- Échap > Paramètres > Raccourcis clavier > FiveM > « Fusée de détresse : poser au sol ».
    Weapon = 'WEAPON_FLARE',
    Key = 'G',
    -- Aide en haut à gauche de l'écran tant que la fusée est en main (false : aucune)
    Help = true,
    HelpPlace = 'Poser la fusée au sol',
    HelpTake = 'Utiliser le target pour la reprendre',

    -- Objet posé (debout : le script le redresse tout seul selon sa forme). Modèle de secours si le premier n'existe pas.
    Model = 'prop_flare_01',
    FallbackModel = 'w_am_flare',
    PlaceDistance = 0.7,          -- m devant le joueur
    PlaceTime = 900,              -- ms : le joueur se baisse pour la poser
    MaxPerPlayer = 0,             -- fusées posées en même temps par joueur (0 : illimité)
    BurnMinutes = 0,              -- durée de combustion (0 : jusqu'à ce qu'on la retire)
    RemoveDistance = 3.0,         -- m : retirer une fusée (œil de rp_interact)

    -- Flamme / fumée rouge (particules du jeu), au sommet de la fusée, pour tous les joueurs proches
    Effect = { Enabled = true, Asset = 'core', Name = 'proj_flare_fuse', Scale = 1.0, Distance = 120.0 },

    -- LUMIÈRE rouge vive autour de la fusée (vacille comme une vraie flamme). La nuit (de NightFrom h à NightTo h),
    -- elle est bien plus forte et porte plus loin.
    Light = {
        Color = { 255, 45, 25 },
        Distance = 150.0,         -- m : lumière dessinée jusqu'à cette distance du joueur
        Height = 0.15,            -- m au-dessus du sommet de la fusée
        Flicker = 0.30,           -- 0 : fixe ; 0.3 : vacille de ±30 %
        Day = { Range = 6.0, Intensity = 2.0 },
        Night = { Range = 16.0, Intensity = 9.0, GlowRange = 30.0, GlowIntensity = 2.5 }, -- lueur large en plus
        NightFrom = 19, NightTo = 7,
        Shadows = 20.0,           -- ombres projetées par la lumière (0 : aucune)
    },
}
