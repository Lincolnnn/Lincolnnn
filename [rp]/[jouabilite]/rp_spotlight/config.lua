--[[
    RP Spotlight - configuration
    ============================
    Projecteur de portière (« spotlight ») monté sur le montant de pare-brise des véhicules de la liste.

    UTILISATION (à bord, à la place qui tient le projecteur) :
      - Ctrl gauche (Key), APPUI COURT : allumer / éteindre son projecteur ;
      - Ctrl gauche MAINTENU : viser (le projecteur suit la caméra, un réticule s'affiche) ; relâché : il reste dans
        cette direction (par rapport au véhicule) ;
      - en visant, CLIC GAUCHE : verrouiller sur le point visé (il reste dessus quand le véhicule bouge) ; à nouveau :
        retour en manuel ;
      - en visant, CLIC DROIT : suivre le véhicule / la personne visé(e) (plaque affichée) ; à nouveau : manuel ;
      - Maj droite (StrobeKey) : stroboscope.
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
    Key = 'LCONTROL',        -- appui court : allumer / éteindre ; maintenu : viser
    HoldMs = 220,            -- au-delà (ms), l'appui est une visée (pas un allumage)
    StrobeKey = 'RSHIFT',    -- stroboscope (projecteur allumé)
    AdjustCommand = 'editspotlight',         -- régler la position du projecteur CONDUCTEUR (ligne de config à copier)
    AdjustSideCommand = 'editspotlightside', -- régler la position du projecteur PASSAGER

    -- ---------------------------------------------------------------------
    -- VÉHICULES : à modifier librement (nom de spawn en minuscules)
    -- ---------------------------------------------------------------------
    Vehicles = {
        -- Deux projecteurs : conducteur (gauche) et passager avant (droit)
        kcso20fpiu = {
            driver    = { offset = { -0.93, 0.62, 0.60 } },
            passenger = { offset = {  0.93, 0.62, 0.60 } },
        },
        -- Un seul projecteur, côté conducteur
        wsp20fpiu   = { driver = { offset = { -0.93, 0.62, 0.60 } } },
        wsp25fpiu   = { driver = { offset = { -0.93, 0.62, 0.60 } } },
        wsp23tah    = { driver = { offset = { -1.00, 0.85, 0.75 } } },
        wsp20fpiuun = { driver = { offset = { -0.93, 0.62, 0.60 } } },
        wsp19fpiu   = { driver = { offset = { -0.93, 0.62, 0.60 } } },
        kcso19fpiu  = { driver = { offset = { -0.93, 0.62, 0.60 } } },
        kcso19tah   = { driver = { offset = { -1.00, 0.85, 0.75 } } },
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
        Lamp = true,               -- petit halo sur la lampe elle-même
    },
    StrobeMs = 75,                 -- rythme du stroboscope (ms)

    -- Débattement, en degrés, pour le projecteur CONDUCTEUR (le passager : l'inverse gauche / droite).
    -- Yaw : 0 = droit devant, négatif = vers la gauche, positif = vers la droite ; Pitch : négatif = vers le bas.
    Yaw = { Min = -110.0, Max = 50.0 },
    Pitch = { Min = -35.0, Max = 25.0 },

    RaycastDistance = 120.0,       -- portée de la visée / du verrouillage / du suivi (m)
    RenderDistance = 160.0,        -- les projecteurs plus loin ne sont pas dessinés (m)
    SendMs = 100,                  -- en visant : envoi de la direction aux autres joueurs au plus toutes les 100 ms
}
