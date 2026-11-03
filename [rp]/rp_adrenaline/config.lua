--[[
    RP Adrénaline - configuration
    ==============================
    1) PREMIÈRE BALLE REÇUE : le script compte pendant Analysis.Seconds s (15 s) les coups de feu entendus à moins
       de Analysis.Range m (50 m) autour du joueur (soi, autres joueurs, PNJ : rp_weaponscontrol) et les balles reçues.
       Aucune chute pendant ces 15 s.
    2) À LA FIN DES 15 s, un des deux scénarios est choisi :
       - ADRÉNALINE HAUTE (résistance à la douleur forte) : au moins High.MinBullets balles (3) ET au moins
         High.MinShots tirs autour (15) -> PREMIÈRE CHUTE retardée, entre 50 et 70 s après la première blessure :
         plus il a pris de balles, plus elle arrive tôt et plus il risque de lâcher son arme (High.Stages) ;
         ensuite (High.AfterFirst) : la douleur prend le dessus, Chance % de chuter toutes les Every s ;
       - ADRÉNALINE BASSE (résistance à la douleur basse) : au plus Low.MaxBullets balles (4) ET moins de Low.MaxShots
         tirs autour (8) -> dès la fin des 15 s, Low.Chance % (55 %) de chuter toutes les Low.Every s (7 s) ;
       - entre les deux (8 à 14 tirs ; moins de 3 balles dans une grosse fusillade ; 5 balles et plus avec peu de
         tirs) : scénario Fallback ('low' ou 'high').
    3) À CHAQUE CHUTE, l'arme à feu tenue est lâchée au sol avec le pourcentage du scénario (reprise avec l'œil,
       « Ramasser », rp_vehicleprops).
    4) FIN : Duration s (1 min 30) après la fin des 15 s ; ou plus tôt si le joueur est SOIGNÉ (vie remise au maximum,
       par n'importe quel menu), meurt ou réapparaît.
    Chutes à pied seulement : en véhicule, une chute tirée au sort est sautée (la première chute de l'adrénaline haute
    attend qu'il descende).
]]

AdrenalineConfig = {
    -- Recherche des tirs, dès la première balle reçue
    Analysis = {
        Range = 50.0,   -- m autour du joueur
        Seconds = 15,   -- s de recherche ; les chutes ne commencent qu'après
        Lead = 1,       -- s : les tirs juste avant la première balle comptent aussi (celui qui l'a touché)
    },

    Duration = 90,      -- s : les chutes s'arrêtent 1 min 30 après la fin de la recherche

    -- ADRÉNALINE HAUTE : 3 balles au moins ET 15 tirs au moins autour
    High = {
        MinBullets = 3, MinShots = 15,
        -- Première chute : From à To s après la PREMIÈRE BLESSURE (au hasard dans l'intervalle) ; Drop : % de lâcher
        -- l'arme. Choisi par le nombre de balles reçues (la ligne la plus haute atteinte ; la dernière = « et plus »).
        -- Une balle de plus avant la chute peut l'avancer (jamais la retarder).
        Stages = {
            { Bullets = 3, From = 63, To = 70, Drop = 65 },  -- 3 balles : plutôt vers la fin des 50 / 70 s
            { Bullets = 4, From = 60, To = 68, Drop = 70 },
            { Bullets = 5, From = 57, To = 65, Drop = 75 },
            { Bullets = 6, From = 55, To = 64, Drop = 80 },  -- 6 balles : plutôt vers le milieu
            { Bullets = 7, From = 50, To = 52, Drop = 85 },  -- 7 balles et plus : dès 50 s
        },
        -- Après la première chute : Chance % de chuter toutes les Every s (même % de lâcher l'arme), jusqu'à la fin.
        -- false : une seule chute.
        AfterFirst = { Every = 7, Chance = 55 },
    },

    -- ADRÉNALINE BASSE : 4 balles au plus ET moins de 8 tirs autour
    Low = {
        MaxBullets = 4, MaxShots = 8,
        Every = 7,      -- s entre deux tirages au sort (le premier dès la fin des 15 s)
        Jitter = 0,     -- s : écart au hasard (+/-) autour de Every (0 : toutes les 7 s pile)
        Chance = 55,    -- % de chuter à chaque tirage
        Drop = 65,      -- % de lâcher l'arme à chaque chute
    },

    Fallback = 'low',   -- cas entre les deux scénarios : 'low' ou 'high'

    RagdollTime = { 1200, 2600 }, -- ms au sol à chaque chute (au hasard entre les deux)
    Debug = false,                -- détails dans la console F8
}
