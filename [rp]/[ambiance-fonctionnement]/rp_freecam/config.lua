--[[
    RP Freecam - configuration
    /freecam ouvre le menu ; flèches haut / bas : choisir, gauche / droite : régler, Entrée : activer,
    Espace (caméra libre) ou H : masquer / afficher le menu (pour la photo), Retour arrière ou Échap : quitter (tout
    est remis comme avant).
    Caméra libre : ZQSD / WASD, souris pour regarder, E monter, A / Q descendre (touches « couverture »),
    Maj rapide, Ctrl lent, molette : zoom.
]]

FreecamConfig = {
    Command = 'freecam',
    -- Distance max entre la caméra et le personnage (m) ; 0 = sans limite. Évite de « voir » loin sans y être.
    MaxDistance = 60.0,
    -- Champ de vision (zoom) : degrés ; plus petit = zoom avant
    Fov = { Min = 5.0, Max = 100.0, Default = 50.0, Step = 2.5 },
    -- Vitesses de déplacement (m/s) : lente, normale, rapide (Maj : x3, Ctrl : x0,25)
    Speeds = { { label = 'Lente', value = 2.0 }, { label = 'Normale', value = 6.0 }, { label = 'Rapide', value = 15.0 } },
    Sensitivity = 6.0,      -- souris (degrés par unité de mouvement)
    MenuToggleControl = 22, -- caméra libre : touche qui masque / affiche le menu (22 = Espace ; H marche toujours)
    RollStep = 5.0,         -- inclinaison : degrés par cran (← →)
    RollMax = 90.0,         -- inclinaison max (90 = caméra couchée sur le côté : photo verticale ; Entrée : 90° / 0°)
    -- Interfaces des scripts du serveur masquées avec l'option « Masquer les interfaces » : événement client
    -- 'rp_freecam:hideUi' (true / false), écouté par le MDC (HUD, PLD, car HUD), le chat, l'œil, les barres…
    HideUiEvent = 'rp_freecam:hideUi',
    -- Composants du HUD du jeu masqués à chaque image (aide, textes de zone / rue / véhicule, armes, réticule…)
    HideHudComponents = { 1, 2, 3, 4, 6, 7, 8, 9, 13, 14, 15, 16, 17, 19, 20, 21, 22 },
}
