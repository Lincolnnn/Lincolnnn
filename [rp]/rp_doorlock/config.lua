--[[
    RP Doorlock - configuration
    Portes du jeu (et des maps ajoutées) que les joueurs en mode civil ou sans rôle verrouillent / déverrouillent avec
    l'œil (jamais un policier en service, unité du MDC) ; porte verrouillée : les civils la déverrouillent ou y
    frappent, les POLICIERS EN SERVICE y frappent ou l'enfoncent (barre de réussite) : elle reste alors cassée (ne se
    verrouille plus) avec la description « Elle a été forcée. ».
]]

DoorlockConfig = {
    MdcResource = 'rp_mdc',          -- MDC : un joueur dans une unité est un policier en service
    Distance = 2.0,                  -- m : distance maximale entre le joueur et la porte (œil et serveur)
    MaxPerPlayer = 10,               -- portes verrouillées au plus par joueur (0 : sans limite)
    AdminAce = 'rp_doorlock.admin',  -- permission ACE : déverrouiller n'importe quelle porte (add_ace group.admin rp_doorlock.admin allow)
    PairDistance = 2.6,              -- m : porte double (deux battants) verrouillée / déverrouillée / enfoncée ensemble
    HoldDistance = 40.0,             -- m : porte verrouillée à moins de cette distance : verrou ré-appliqué quand elle se
                                     -- charge, porte figée une fois fermée (elle ne bat plus)

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

    -- Enfoncer (policiers en service seulement) : barre de réussite en bas de l'écran ; un curseur va et vient, ESPACE quand il
    -- est dans la zone verte (un coup de pied à chaque essai). Steps essais réussis : la porte cède. Zone : largeur
    -- de la zone verte à chaque étape (part de la barre) ; Speed : allers par seconde du curseur. MaxMisses essais
    -- ratés : le policier s'arrête (il peut recommencer). Cooldown ms au moins entre deux coups (serveur). La porte
    -- s'ouvre violemment et reste cassée (le verrou de son propriétaire saute, voir Broken). Un coup de pied (animation)
    -- à chaque essai, réussi ou raté.
    Kick = {
        Enabled = true, Steps = 3, Zone = { 0.2, 0.15, 0.11 }, Speed = { 0.9, 1.15, 1.4 }, MaxMisses = 3, Cooldown = 700,
        Anims = { { 'missprologuemcs_1', 'kick_down_player_zero', 1600, 650 }, -- dict, clip, durée, moment de l'impact
            { 'anim@scripted@player@freemode@ig6_stash_entry@door_trans@hinge_l@', 'kick_player1', 1600, 650 } },
        Force = 22.0,                -- poussée donnée au battant (il s'ouvre en grand)
        Shake = 0.25,                -- secousse de la caméra du policier à l'impact
    },

    -- Porte enfoncée : cassée, elle ne se verrouille plus. Description affichée au-dessus d'elle (comme la description
    -- visuelle d'une scène /scene) à moins de Distance m, si on la voit. Duration : minutes avant qu'elle soit réparée
    -- toute seule (0 : jusqu'au redémarrage du serveur) ; un admin (AdminAce) la répare avec l'œil.
    Broken = { Text = 'Elle a été forcée.', Distance = 10.0, Duration = 0, Scale = 0.34, Color = { 245, 238, 215 } },

    Save = true,                     -- verrous gardés après un redémarrage (data/locks.json)
}
