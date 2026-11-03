--[[
    RP Adrénaline - configuration
    ==============================
    1) BALLE REÇUE : le script compte pendant Analysis.Seconds s (8 s) les coups de feu entendus à moins de
       Analysis.Range m (50 m) autour du joueur (soi, autres joueurs, PNJ : rp_weaponscontrol) et les balles reçues.
       Aucune chute pendant ces 8 s.
    2) À LA FIN DES 8 s :
       - FUSILLADE (au moins High.MinShots tirs : 10) -> ADRÉNALINE HAUTE, résiste un peu mieux à la douleur : les
         chutes ne commencent qu'entre High.Start[1] et High.Start[2] s (50 à 70 s) après la fin des 8 s ; ensuite un
         tirage toutes les High.Every s (8 s) ;
       - HORS FUSILLADE (moins de Low.MaxShots tirs : 5) -> ADRÉNALINE BASSE, effet de surprise : tirages dès la fin
         des 8 s, toutes les Low.Every s ;
       - entre les deux (5 à 9 tirs) : scénario Fallback.
       À chaque tirage : Chance % de chuter (ragdoll) ; à chaque chute, Drop % de lâcher l'arme à feu tenue (seulement
       s'il en tient une ; reprise avec l'œil, « Ramasser », rp_vehicleprops). Chance et Drop selon les balles reçues
       (tableaux Stages : la ligne la plus haute atteinte ; la dernière = « et plus »), recalculés à chaque tirage.
    3) FIN : Duration s (1 min 30) après la fin des 8 s ; ou plus tôt si le joueur est SOIGNÉ (vie remise au maximum,
       par n'importe quel menu : vMenu…), meurt ou réapparaît.
    4) DÉMARCHE BLESSÉE dès la Walk.From-ième chute (2e) : « /walk injured » ; à la fin (ou soigné, mort) : « /walk reset ».
    Chutes à pied seulement : en véhicule, le tirage est sauté.
]]

AdrenalineConfig = {
    -- Recherche des tirs, dès la balle reçue
    Analysis = {
        Range = 50.0,   -- m autour du joueur
        Seconds = 8,    -- s de recherche ; les chutes ne commencent qu'après
        Lead = 1,       -- s : les tirs juste avant la balle comptent aussi (celui qui l'a touché)
    },

    Duration = 90,      -- s : les chutes s'arrêtent 1 min 30 après la fin de la recherche

    -- ADRÉNALINE HAUTE (fusillade) : 10 tirs et plus pendant les 8 s
    High = {
        MinShots = 10,
        Start = { 50, 70 }, -- s après la fin des 8 s : début des chutes (au hasard)
        Every = 8,          -- s entre deux tirages
        Stages = {
            { Bullets = 1, Chance = 45, Drop = 45 },
            { Bullets = 2, Chance = 55, Drop = 65 },
            { Bullets = 3, Chance = 75, Drop = 80 },  -- 3 à 4 balles (et plus)
        },
    },

    -- ADRÉNALINE BASSE (hors fusillade) : moins de 5 tirs pendant les 8 s
    Low = {
        MaxShots = 5,
        Every = 8,          -- s entre deux tirages (le premier dès la fin des 8 s)
        Stages = {
            { Bullets = 1, Chance = 50, Drop = 55 },
            { Bullets = 2, Chance = 65, Drop = 70 },
            { Bullets = 3, Chance = 80, Drop = 75 },  -- 3 balles et plus
        },
    },

    Fallback = 'low',   -- 5 à 9 tirs (ni fusillade ni hors fusillade) : 'low' ou 'high'

    -- Démarche blessée dès la 2e chute, jusqu'à la fin. Mode 'command' : commandes de RPEMOTES (« /walk injured »,
    -- « /walk reset ») ; 'native' : même démarche (Clipset) posée directement (sans RPEMOTES). false : jamais.
    Walk = { From = 2, Mode = 'command', Injured = 'walk injured', Reset = 'walk reset', Clipset = 'move_m@injured' },

    RagdollTime = { 1200, 2600 }, -- ms au sol à chaque chute (au hasard entre les deux)
    Debug = false,                -- détails dans la console F8
}
