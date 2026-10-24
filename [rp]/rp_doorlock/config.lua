--[[
    RP Doorlock - configuration
    Portes du jeu (et des maps ajoutées) que les joueurs EN MODE CIVIL (rp_interact : Menu F1 > Civil) verrouillent /
    déverrouillent avec l'œil ; les policiers en service (unité du MDC) enfoncent une porte verrouillée (barre de
    réussite). Un policier, ou un joueur ni civil ni policier, ne peut ni verrouiller ni déverrouiller.
]]

DoorlockConfig = {
    MdcResource = 'rp_mdc',          -- MDC : un joueur dans une unité est un policier en service
    InteractResource = 'rp_interact', -- mode civil (sans cette ressource : tout le monde est civil)
    Distance = 2.0,                  -- m : distance maximale entre le joueur et la porte (œil et serveur)
    MaxPerPlayer = 10,               -- portes verrouillées au plus par joueur (0 : sans limite)
    AdminAce = 'rp_doorlock.admin',  -- permission ACE : déverrouiller n'importe quelle porte (add_ace group.admin rp_doorlock.admin allow)
    PairDistance = 2.6,              -- m : porte double (deux battants) verrouillée / déverrouillée / enfoncée ensemble

    -- Reconnaître une porte : son modèle est dans models.lua (portes du jeu) ou ExtraModels (portes de vos maps), pas
    -- dans IgnoredModels, et elle a la taille d'une porte (hauteur, largeur en m). DetectBySize = true : tout objet
    -- fin ayant la taille d'une porte compte (maps ajoutées sans liste de modèles ; peut reconnaître à tort un
    -- panneau ou une vitre).
    ExtraModels = {},                -- ex. { 'mon_mlo_door_01', `autre_porte` }
    IgnoredModels = {},
    MinHeight = 1.6, MaxHeight = 7.0, MinWidth = 0.5,
    DetectBySize = false, MaxThickness = 0.4,

    -- Animations (dictionnaire, clip, durée en ms) : verrouiller / déverrouiller (la clé), frapper, enfoncer
    LockAnim = { 'anim@heists@keycard@', 'exit', 1200 },
    KnockAnim = { 'timetable@jimmy@doorknock@', 'knockdoor_idle', 2500 },
    Knock = { Enabled = true, Sound = { 'Door_Knock_Normal', 'dlc_btl_deliver_goods_sounds' }, Range = 15.0 },

    -- Enfoncer (policiers en service) : barre de réussite en bas de l'écran ; un curseur va et vient, ESPACE quand il
    -- est dans la zone verte (un coup de pied à chaque essai). Steps essais réussis : la porte cède. Zone : largeur
    -- de la zone verte à chaque étape (part de la barre) ; Speed : allers par seconde du curseur. MaxMisses essais
    -- ratés : le policier s'arrête (il peut recommencer). Cooldown ms au moins entre deux coups (serveur). La porte
    -- s'ouvre violemment et reste déverrouillée (le verrou de son propriétaire saute).
    Kick = {
        Enabled = true, Steps = 3, Zone = { 0.2, 0.15, 0.11 }, Speed = { 0.9, 1.15, 1.4 }, MaxMisses = 3, Cooldown = 700,
        Anims = { { 'missprologuemcs_1', 'kick_down_player_zero', 1600, 650 }, -- dict, clip, durée, moment de l'impact
            { 'anim@scripted@player@freemode@ig6_stash_entry@door_trans@hinge_l@', 'kick_player1', 1600, 650 } },
        Force = 22.0,                -- poussée donnée au battant (il s'ouvre en grand)
        Shake = 0.25,                -- secousse de la caméra du policier à l'impact
    },

    Save = true,                     -- verrous gardés après un redémarrage (data/locks.json)
}
