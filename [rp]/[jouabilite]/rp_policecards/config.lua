--[[
    RP Police Cards - configuration
    /miranda, /alphabet : affiche / masque la carte (aussi dans Menu Interaction > Police). La carte reste à l'écran
    SANS curseur : on marche, on conduit, on ouvre ses autres menus (comme le bloc-notes en mode visuel).
    /cartes : ajuster les cartes affichées (curseur) : glisser pour déplacer, molette pour la taille, clic droit pour
    masquer une carte ; Échap ou Entrée pour finir. Place et taille gardées chez le joueur.
    Touches : aucune par défaut ; chaque joueur peut en choisir (Paramètres > Raccourcis clavier > FiveM).
]]

CardsConfig = {
    Cards = {
        -- x, y : position par défaut du coin haut-gauche (fraction de l'écran) ; width : largeur (fraction de l'écran)
        { id = 'miranda', command = 'miranda', label = 'Carte Miranda', image = 'img/miranda.webp',
          x = 0.70, y = 0.08, width = 0.28 },
        { id = 'alphabet', command = 'alphabet', aliases = { 'phonetique' }, label = 'Alphabet phonétique (police)',
          image = 'img/alphabet.webp', x = 0.70, y = 0.40, width = 0.28 },
    },
    AdjustCommand = 'cartes', -- ajuster les cartes affichées (déplacer, taille)
    MinWidth = 0.12,          -- taille réglable (fraction de la largeur de l'écran)
    MaxWidth = 0.60,
    HideInPauseMenu = true,   -- cartes masquées pendant le menu pause / la carte (vérifié seulement quand une carte est affichée)
}
