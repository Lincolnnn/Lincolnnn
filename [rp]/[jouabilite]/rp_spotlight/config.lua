--[[
    RP Spotlight - configuration
    ============================
    Projecteur de portière (« spotlight ») monté sur le montant de pare-brise des véhicules de la liste.

    UTILISATION (à bord, à la place qui tient le projecteur) :
      - Ctrl gauche (Key) : allumer / éteindre son projecteur ;
      - CLIC DROIT MAINTENU (AimButton) + souris : viser (le projecteur suit la caméra, un réticule s'affiche) ; relâché : il reste dans
        cette direction (par rapport au véhicule) ;
      - en visant, CLIC GAUCHE : verrouiller sur le point visé (il reste dessus quand le véhicule bouge) ; à nouveau :
        retour en manuel ;
    QUI TIENT QUEL PROJECTEUR : le CONDUCTEUR celui de gauche (driver) ; le PASSAGER AVANT celui de droite (passenger),
    s'il y en a un.
    Touches modifiables : Paramètres > Raccourcis clavier > FiveM.

    VÉHICULES : un modèle (nom de spawn) = ses projecteurs. driver = côté conducteur (gauche), passenger = côté
    passager avant (droit). offset = position sur le véhicule { x (gauche - / droite +), y (arrière - / avant +),
    z (bas - / haut +) } en mètres, depuis le centre du véhicule. Sans offset : DefaultDriver / DefaultPassenger.
    Réglage en jeu (à bord du véhicule) : /editspotlight (projecteur conducteur), /editspotlightside (projecteur
    passager) : un POINT ROUGE montre le départ de la lumière, curseurs X / Y / Z en haut au milieu de l'écran, la ligne
    à copier ici s'affiche.
]]

SpotlightConfig = {
    Key = 'LCONTROL',        -- allumer / éteindre
    AimButton = 'MOUSE_RIGHT', -- maintenu (projecteur allumé) : viser avec la souris
    AdjustCommand = 'editspotlight',         -- régler la position du projecteur CONDUCTEUR (ligne de config à copier)
    AdjustSideCommand = 'editspotlightside', -- régler la position du projecteur PASSAGER

    -- ---------------------------------------------------------------------
    -- VÉHICULES : à modifier librement (nom de spawn en minuscules)
    -- ---------------------------------------------------------------------
    Vehicles = {
        -- Deux projecteurs : conducteur (gauche) et passager avant (droit)
        kcso20fpiu = {
            driver    = { offset = { -0.89, 1.25, 0.81 } },
            passenger = { offset = {  0.79, 1.20, 0.80 } },
        },
        -- Un seul projecteur, côté conducteur
        wsp20fpiu   = { driver = { offset = { -0.89, 1.23, 0.81 } } },
        wsp25fpiu   = { driver = { offset = { -0.89, 1.20, 0.79 } } },
        wsp23tah    = { driver = { offset = { -0.85, 1.08, 0.61 } } },
        wsp20fpiuun = { driver = { offset = { -0.93, 0.62, 0.60 } } },
        wsp19fpiu   = { driver = { offset = { -0.85, 0.97, 0.54 } } },
        kcso19fpiu  = { driver = { offset = { -0.86, 1.04, 0.54 } } },
        kcso19tah   = { driver = { offset = { -0.99, 1.31, 0.97 } } },
    },
    DefaultDriver = { -0.95, 0.80, 0.55 },    -- position si une ligne n'a pas d'offset
    DefaultPassenger = { 0.95, 0.80, 0.55 },

    -- ---------------------------------------------------------------------
    -- LUMIÈRE
    -- ---------------------------------------------------------------------
    Light = {
        Color = { 235, 240, 255 }, -- blanc LED (R, G, B)
        Distance = 90.0,           -- portée (m)
        Brightness = 22.0,
        Roundness = 4.0,           -- netteté du bord du faisceau
        Radius = 9.0,              -- ouverture du faisceau (degrés)
        Falloff = 60.0,
        Lamp = true,               -- petite lumière sur la lampe elle-même
    },

    -- ---------------------------------------------------------------------
    -- FAISCEAU VISIBLE : rayon de lumière dans l'air (comme dans la brume) + halo quand on regarde la lampe de face.
    -- Bien visible la nuit, s'estompe au lever / coucher du soleil, invisible de jour (Day = 0.0) ; plus marqué sous
    -- la pluie (Rain). Il s'arrête là où la lumière touche un mur, le sol, un véhicule.
    -- ---------------------------------------------------------------------
    Beam = {
        Enabled = true,
        Alpha = 70,          -- opacité du rayon la nuit (0 - 255)
        Length = 45.0,       -- longueur maximale du rayon (m) ; il s'efface vers le bout
        Spread = 12.0,       -- ouverture du rayon (degrés) ; nil = celle de Light.Radius
        EndFlare = 0.9,      -- élargissement en plus vers la fin du rayon (0 = cône simple ; 0.9 : presque 2 x plus large au bout)
        Start = 0.1,         -- demi-largeur au départ (m), taille de la lampe
        Day = 0.0,           -- visibilité de jour (0 = invisible, 1 = comme la nuit)
        Rain = 0.6,          -- sous une forte pluie : x (1 + Rain)
        GlowAlpha = 220,     -- halo de la lampe vue de face (0 = aucun)
        GlowSize = 0.35,     -- taille du halo (m)
        Segments = 4,        -- découpage du rayon (plus = plus lisse, un peu plus coûteux)
        -- Color = { 255, 240, 210 }, -- couleur du rayon ; nil = celle de Light.Color
    },

    -- ---------------------------------------------------------------------
    -- ÉBLOUISSEMENT : un joueur DANS le faisceau (ou tout près, jusqu'à NearAngle degrés de son axe), la lampe en vue
    -- (rien entre les deux), voit un voile blanc et un gros halo sur la lampe. Plus fort en regardant la lampe en face,
    -- de près et la nuit ; s'efface en ~1 s après (persistance rétinienne). Pas pour les occupants du véhicule du
    -- projecteur.
    -- ---------------------------------------------------------------------
    Glare = {
        Enabled = true,
        NearAngle = 15.0,    -- au-delà de cet angle avec l'axe du faisceau (degrés) : plus d'éblouissement
        Range = 90.0,        -- distance maximale (m) ; diminue avec la distance
        Strength = 1.0,      -- force générale (x)
        Veil = 170,          -- voile blanc sur l'écran au plus fort (0 - 255)
        Size = 0.9,          -- taille du halo sur la lampe au plus fort (fraction de la hauteur de l'écran)
        Away = 0.12,         -- part restante en regardant ailleurs (0 = aucun effet sans regarder la lampe)
        Day = 0.35,          -- de jour (x) ; la nuit : 1
        Rise = 10.0,         -- vitesse d'apparition
        Fall = 2.5,          -- vitesse de disparition (plus petit = dure plus longtemps)
    },

    -- Débattement, en degrés, pour le projecteur CONDUCTEUR (le passager : l'inverse gauche / droite).
    -- Yaw : 0 = droit devant, négatif = vers la gauche, positif = vers la droite ; Pitch : négatif = vers le bas.
    Yaw = { Min = -110.0, Max = 50.0 },
    Pitch = { Min = -35.0, Max = 25.0 },

    RaycastDistance = 120.0,       -- portée de la visée / du verrouillage (m)
    RenderDistance = 160.0,        -- les projecteurs plus loin ne sont pas dessinés (m)
    SendMs = 100,                  -- en visant : envoi de la direction aux autres joueurs au plus toutes les 100 ms
}
