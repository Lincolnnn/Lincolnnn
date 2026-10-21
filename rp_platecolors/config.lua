--[[
    RP PlateColors - Configuration (partagée client / serveur)
    Même idée que <VehiclePlates> d'un carcols.ymt, mais en Lua : une couleur de texte (et un contour) par type de
    plaque. Le texte d'origine du jeu est masqué et redessiné par le script, dans ces couleurs.
    Les couleurs choisies dans l'éditeur en jeu (/plaqueedit) sont enregistrées dans data/plates.json et passent
    avant celles-ci.
]]
PlateConfig = {
    -- Couleur du texte par type de plaque (index du jeu, GET_VEHICLE_NUMBER_PLATE_TEXT_INDEX).
    -- text = { R, G, B } (0-255) ; outline = { R, G, B } pour un contour, ou false.
    Plates = {
        [0]  = { label = 'Blanche cursive (plate01)',     text = { 10, 42, 140 },   outline = false }, -- bleu foncé
        [1]  = { label = 'Fond noir (plate02)',           text = { 255, 255, 255 }, outline = false }, -- blanc
        [2]  = { label = 'Fond bleu (plate03)',           text = { 0, 0, 0 },       outline = false }, -- noir
        [3]  = { label = 'Blanche sobre (plate04)',       text = { 255, 255, 255 }, outline = false }, -- blanc
        [4]  = { label = 'Blanche « Exempt » (plate05)',  text = { 10, 42, 140 },   outline = false }, -- bleu foncé
        [5]  = { label = 'North Yankton (yankton_plate)', text = { 10, 42, 140 },   outline = false }, -- bleu foncé
        -- Plaques ajoutées par la build 3095 (sur une build plus ancienne, elles n'existent pas)
        [6]  = { label = 'eCola',                         text = { 255, 255, 255 }, outline = false },
        [7]  = { label = 'Las Venturas',                  text = { 0, 0, 0 },       outline = false },
        [8]  = { label = 'Liberty City',                  text = { 0, 0, 0 },       outline = false },
        [9]  = { label = 'LS Car Meet',                   text = { 255, 255, 255 }, outline = false },
        [10] = { label = 'LS Panic',                      text = { 255, 255, 255 }, outline = false },
        [11] = { label = 'LS Pounders',                   text = { 255, 255, 255 }, outline = false },
        [12] = { label = 'Sprunk',                        text = { 255, 255, 255 }, outline = false },
    },
    Default = { text = { 0, 0, 0 }, outline = false },   -- type de plaque absent de la liste

    -- Taille du texte (mètres, plaque du jeu ≈ 0.31 x 0.155 m). 8 cases de caractères, comme le jeu.
    Text = {
        Width = 0.265,      -- largeur des 8 caractères
        Height = 0.072,     -- hauteur des caractères
        OffsetUp = -0.006,  -- décalage vertical du texte par rapport au centre de la plaque
        Lift = 0.004,       -- distance devant la surface de la plaque (évite que le texte soit caché)
    },
    PlateSize = { 0.31, 0.155 },   -- cadre affiché dans l'éditeur

    -- Lumière : le texte dessiné n'est pas éclairé par le jeu, on le baisse la nuit (1.0 = pas de changement)
    NightBrightness = 0.55,

    -- Affichage
    MaxDistance = 22.0,     -- m entre la caméra et la plaque (au-delà, rien n'est lisible de toute façon)
    MaxPlates = 16,         -- plaques dessinées au maximum (les plus proches)
    ScanInterval = 400,     -- ms entre deux recherches des véhicules proches
    OcclusionInterval = 250,-- ms entre deux tests « la plaque est-elle cachée par un mur / un véhicule »

    -- Placement automatique (modèle jamais réglé dans l'éditeur)
    Auto = {
        BelowLight = 0.075,     -- arrière : centre de la plaque sous l'os « platelight » (lumière de plaque)
        HeightRatio = 0.28,     -- sans « platelight » : hauteur de la plaque (part de la hauteur du véhicule)
        Inset = 0.01,           -- plaque un peu en retrait de la carrosserie trouvée par le rayon
    },

    -- Éditeur en jeu : position par modèle et couleurs (ace : add_ace group.admin rp_platecolors.edit allow)
    EditCommand = 'plaqueedit',
    EditAce = 'rp_platecolors.edit',
    EditRange = 8.0,            -- m : véhicule le plus proche si le joueur n'est pas dedans
}
