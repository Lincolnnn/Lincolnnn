--[[
    RP PlateColors - Configuration (client)
    Les couleurs se règlent dans data/carcols.ymt (<FontColor>), pas ici.
]]
PlateColorsConfig = {
    -- Nombre de plaques dans data/carcols.ymt (les 6 du jeu de base, même ordre : 0 à 5)
    CustomPlates = 6,

    -- Si le jeu a AJOUTÉ les plaques du fichier à sa liste, les véhicules qui portent une plaque 0 à 5 prennent
    -- la copie colorée correspondante (même texture, autre couleur de texte). false : rien n'est changé.
    AutoRemap = true,

    -- Nombre de types de plaques du jeu sans aucun ajout (6 avant la build 3095, 13 à partir de la 3095)
    VanillaCounts = { 6, 13 },

    Interval = 1000,          -- ms entre deux passages sur les véhicules proches

    -- Commandes de test (false = aucune) : /plaques (diagnostic), /plaque <index> (plaque du véhicule actuel)
    InfoCommand = 'plaques',
    TestCommand = 'plaque',
}
