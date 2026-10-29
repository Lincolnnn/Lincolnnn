VMKConfig = {
    -- Dossier de vMenu sur le serveur (majuscules / minuscules indifférentes)
    VMenuResource = 'vMenu',

    -- Touche par défaut pour ouvrir vMenu et pour le noclip : NOMS DE TOUCHES du clavier (M, F2, F5, HOME…), comme
    -- dans Paramètres > Raccourcis clavier > FiveM ; jamais un numéro de contrôle (244, 289 : ancien format, qui
    -- donnait V).
    MenuKey = 'M',
    NoClipKey = 'F2',

    -- Nom des raccourcis de vMenu (vMenu:<MappingId>:MenuToggle). Un nom jamais utilisé : la touche ci-dessus
    -- s'applique à TOUS les joueurs, même ceux qui avaient V enregistré sous l'ancien nom (qui ne fait plus rien).
    -- Changez-le (rp_m2, rp_m3…) chaque fois que vous changez MenuKey / NoClipKey, pour l'imposer à nouveau à tous.
    MappingId = 'rp_m',

    -- /vmenutouches (F8 ou chat) : affiche, chez le joueur, les réglages que vMenu a reçus
    CheckCommand = 'vmenutouches',
}
