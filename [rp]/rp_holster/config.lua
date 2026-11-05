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
        { gender = 'male', full = 9, empty = 10, label = 'Holster de ceinture (EXEMPLE)' },
        { gender = 'male', full = 11, empty = 12, label = 'Holster de cuisse (EXEMPLE)' },
        { gender = 'female', full = 9, empty = 10, label = 'Holster de ceinture (EXEMPLE)' },
    },

    -- Armes qui vont dans le holster : groupes du jeu (armes de poing) + armes précises ; jamais : Excluded
    Groups = { 'GROUP_PISTOL' },
    Weapons = {},
    Excluded = { 'WEAPON_FLAREGUN' },

    -- Armes de poing vérifiées dans l'inventaire (le jeu ne sait pas les énumérer) : armes du jeu + armes ajoutées
    Inventory = {
        'WEAPON_PISTOL', 'WEAPON_PISTOL_MK2', 'WEAPON_COMBATPISTOL', 'WEAPON_APPISTOL', 'WEAPON_PISTOL50',
        'WEAPON_SNSPISTOL', 'WEAPON_SNSPISTOL_MK2', 'WEAPON_HEAVYPISTOL', 'WEAPON_VINTAGEPISTOL', 'WEAPON_MARKSMANPISTOL',
        'WEAPON_REVOLVER', 'WEAPON_REVOLVER_MK2', 'WEAPON_DOUBLEACTION', 'WEAPON_CERAMICPISTOL', 'WEAPON_NAVYREVOLVER',
        'WEAPON_GADGETPISTOL', 'WEAPON_PISTOLXM3',
        -- armes ajoutées du serveur
        'WEAPON_GLOCK19', 'WEAPON_FM1_P226', 'WEAPON_SWMP9', 'WEAPON_P320',
    },

    EmptyWhenNoWeapon = true, -- aucune arme de poing sur soi : holster vide
    CheckMs = 250,            -- vérification (ms) ; seulement quand un holster de la liste est porté
}
