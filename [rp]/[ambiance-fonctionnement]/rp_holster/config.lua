--[[
    RP Holster - configuration
    ==========================
    Les holsters EUP (partie « teef » / Accessories, composant 7) existent en deux versions : PLEINE (arme dans le
    holster) et VIDE. Le script porte la version pleine quand l'arme de poing est RANGÉE (dans l'inventaire, pas en
    main) et la version vide quand elle est SORTIE (ou quand le joueur n'en a pas). La texture portée est gardée.

    À REMPLIR : une ligne par holster, avec le numéro du modèle plein et celui du modèle vide (les numéros de votre pack
    EUP, comptés comme dans outfits.json de rp_interact : "Accessories": "9:1" -> 9). Les numéros ci-dessous sont des
    EXEMPLES à remplacer.
    Le holster n'est géré que si le joueur porte l'un des deux modèles de la ligne (tenue mise avec /eup, vMenu…).
]]

HolsterConfig = {
    Enabled = true,

    Component = 7,      -- partie du holster : 7 = « teef » / Accessories (EUP)
    OneBased = true,    -- numéros comptés à partir de 1, comme outfits.json (false : numéros du jeu, à partir de 0)

    -- { gender = 'male' | 'female' (facultatif : les deux), full = modèle plein, empty = modèle vide,
    --   component = autre partie (facultatif), label = nom (aide) }
    Holsters = {
        { gender = 'male', full = 209, empty = 210, label = 'Holster de ceinture (EXEMPLE)' },
        { gender = 'male', full = 211, empty = 212, label = 'Holster de cuisse (EXEMPLE)' },
        { gender = 'male', full = 207, empty = 208, label = 'Holster de ceinture (EXEMPLE)' },
        { gender = 'male', full = 205, empty = 206, label = 'Holster de cuisse (EXEMPLE)' },
        { gender = 'male', full = 200, empty = 202, label = 'Holster de ceinture (EXEMPLE)' },
        { gender = 'male', full = 201, empty = 203, label = 'Holster de cuisse (EXEMPLE)' },
    },

    -- Armes qui vont dans le holster : SEULES ces armes le vident quand on les sort (et le remplissent quand on les
    -- range) ; une autre arme (pas dans la liste) ne touche pas au holster. Groups = { 'GROUP_PISTOL' } (facultatif) :
    -- toutes les armes de poing en plus. Jamais : Excluded
    Weapons = { 'WEAPON_MP92', 'WEAPON_P320', 'WEAPON_GLOCK19', 'WEAPON_FM1_P226' },
    Excluded = { 'WEAPON_FLAREGUN' },

    -- Armes de poing vérifiées dans l'inventaire (le jeu ne sait pas les énumérer) : armes du jeu + armes ajoutées
    Inventory = {
        -- armes ajoutées du serveur
        'WEAPON_GLOCK19', 'WEAPON_FM1_P226', 'WEAPON_SWMP9', 'WEAPON_P320',
    },

    EmptyWhenNoWeapon = true, -- aucune arme de poing sur soi : holster vide
    CheckMs = 250,            -- vérification (ms)
    ArmedCheckMs = 100,       -- vérification (ms) avec une arme de la liste en main (son du rangement au bon moment)

    -- ANIMATION : la main va au holster quand on sort / range une arme de la liste (holster porté, à pied)
    Animation = {
        Enabled = true,
        Draw = { dict = 'rcmjosh4', clip = 'josh_leadout_cop2', ms = 600 },                 -- sortir l'arme
        Holster = { dict = 'reaction@intimidation@cop@unarmed', clip = 'intro', ms = 500 },  -- la ranger
    },

    -- SON : html/sounds/holster.ogg (fichier à déposer ; .mp3 / .wav acceptés aussi : changez File), joué en sortant
    -- ET en rangeant une arme de la liste, entendu par les joueurs proches (plus faible avec la distance).
    -- RequireHolster = false : son même sans holster de la liste porté ; true : seulement avec un holster de la liste.
    Sound = { Enabled = true, File = 'holster.ogg', Volume = 0.5, Range = 8.0, RequireHolster = false },
}
