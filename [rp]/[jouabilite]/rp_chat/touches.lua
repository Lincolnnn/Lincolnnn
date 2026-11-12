--[[
    RP Chat - TOUCHES MODIFIABLES avec /modiftouche (catalogue)
    ===========================================================
    /modiftouche                              -> liste des scripts
    /modiftouche [script]                     -> spécificités du script et leurs touches actuelles
    /modiftouche [script] [spécificité] [touche] -> nouvelle touche (pour vous seulement, gardée)
    /modiftouche [script] [spécificité] defaut   -> touche d'origine

    Un script = un nom court (MDC, CHAT, VEHICULE…) et ses spécificités (ouvrir, moteur, ceinture…), chacune liée à la
    commande que le script relie à une touche (RegisterKeyMapping). Majuscules et accents sans importance.
      cmd     : commande de la touche ; hold = true : touche « maintenue » (+commande / -commande)
      key     : touche d'origine (affichée) ; device : 'keyboard' (défaut) ou 'mouse_button'
      res     : ressource qui la gère (la spécificité n'est proposée que si elle est démarrée)
    Ajouter une touche : une ligne ici ; la ressource doit charger keyguard.lua (voir README).
]]

RPChatKeyScripts = {
    { name = 'MDC', label = 'MDC (Mobile Data Computer)', res = 'rp_mdc', actions = {
        { id = 'ouvrir', label = 'Ouvrir le MDC', cmd = 'mdc', key = 'K' },
        { id = 'accepter', label = 'Accepter l\'appel proposé', cmd = 'mdc_offer_yes', key = 'Y' },
        { id = 'refuser', label = 'Refuser l\'appel proposé', cmd = 'mdc_offer_no', key = 'N' },
    } },
    { name = 'CHAT', label = 'Chat écrit', res = 'rp_chat', actions = {
        { id = 'ouvrir', label = 'Ouvrir / fermer le chat', cmd = 'rpchat', key = 'T' },
        { id = 'monter', label = 'Remonter dans la conversation', cmd = 'rpchat_up', key = 'PAGEUP' },
        { id = 'descendre', label = 'Descendre dans la conversation', cmd = 'rpchat_down', key = 'PAGEDOWN' },
    } },
    { name = 'VEHICULE', label = 'Véhicule (Vehicle Control)', res = 'rp_vehiclecontrol', actions = {
        { id = 'moteur', label = 'Allumer / couper le moteur', cmd = 'vc_engine', key = 'O' },
        { id = 'ceinture', label = 'Attacher / détacher la ceinture', cmd = 'vc_seatbelt', key = 'G' },
        { id = 'portiere', label = 'Ouvrir / fermer sa portière', cmd = 'vc_door', key = 'U' },
        { id = 'portieres', label = 'Les deux portières avant (conducteur)', cmd = 'vc_frontdoors', key = 'I' },
        { id = 'clignogauche', label = 'Clignotant gauche', cmd = 'vc_signal_left', key = 'LEFT' },
        { id = 'clignodroit', label = 'Clignotant droit', cmd = 'vc_signal_right', key = 'RIGHT' },
        { id = 'warnings', label = 'Warnings (feux de détresse)', cmd = 'vc_hazards', key = 'DOWN' },
        { id = 'rapport', label = 'Marche avant (D) / arrière (R)', cmd = 'vc_gear', key = 'UP' },
    } },
    { name = 'INTERACTION', label = 'Menu Interaction et œil', res = 'rp_interact', actions = {
        { id = 'menu', label = 'Menu Interaction', cmd = 'interactions', key = 'F1' },
        { id = 'oeil', label = 'Œil (maintenir)', cmd = 'rpi_target', key = 'LMENU', hold = true },
        { id = 'lacherbras', label = 'Police : lâcher le bras', cmd = 'rpi_release', key = 'X' },
        { id = 'debattre', label = 'Civil : se débattre (tenu par le bras)', cmd = 'rpi_struggle', key = 'SPACE' },
        { id = 'mainsenlair', label = 'Tips d\'arrestation : mains en l\'air', cmd = 'rpi_hands', key = 'H' },
        { id = 'genoux', label = 'Tips d\'arrestation : à genoux', cmd = 'rpi_knees', key = 'J' },
        { id = 'allonger', label = 'Tips d\'arrestation : s\'allonger', cmd = 'rpi_prone', key = 'L' },
    } },
    { name = 'EQUIPEMENT', label = 'Équipement des véhicules de police', res = 'rp_equipment', actions = {
        { id = 'menu', label = 'Menu Équipement du véhicule', cmd = 'rp_equipment', key = 'E' },
        { id = 'poser', label = 'Poser au sol (plot, sac médical porté)', cmd = 'rp_cone_place', key = 'G' },
        { id = 'radar', label = 'Prendre / ranger le pistolet radar (à l\'avant)', cmd = 'radargun', key = '' },
    } },
    { name = 'FUSEE', label = 'Fusées de détresse', res = 'rp_flares', actions = {
        { id = 'poser', label = 'Poser la fusée au sol', cmd = 'rp_flare_place', key = 'G' },
    } },
    { name = 'PROJECTEUR', label = 'Projecteur de portière (spotlight)', res = 'rp_spotlight', actions = {
        { id = 'allumer', label = 'Allumer / éteindre', cmd = 'rp_spotlight', key = 'LCONTROL', hold = true },
        { id = 'viser', label = 'Viser (maintenir)', cmd = 'rp_spotlight_aim', key = 'MOUSE_RIGHT', hold = true, device = 'mouse_button' },
    } },
    { name = 'ARMES', label = 'Armes et lampes', res = 'rp_weaponscontrol', actions = {
        { id = 'tir', label = 'Coup par coup / automatique', cmd = 'rp_firemode', key = 'B' },
        { id = 'stroboscope', label = 'Stroboscope de la lampe', cmd = 'rp_flashlight_strobe', key = 'F7' },
    } },
    { name = 'TASER', label = 'TASER 10', res = 'rp_taser10', actions = {
        { id = 'securite', label = 'Sélecteur ARMÉ / SÉCURITÉ', cmd = 'axonSafety', key = 'B', hold = true },
        { id = 'alerte', label = 'Alerte sonore et lampe stroboscopique', cmd = 'axonSelectorUp', key = 'R', hold = true },
        { id = 'test', label = 'Sélecteur vers le bas (discret, test)', cmd = 'axonSelectorDown', key = 'G', hold = true },
    } },
    { name = 'BLOCNOTES', label = 'Bloc-notes', res = 'rp_notepad', actions = {
        { id = 'ouvrir', label = 'Ouvrir / fermer', cmd = 'notepad', key = 'F2' },
    } },
    { name = 'TRAFIC', label = 'Gestion du trafic', res = 'rp_TrafficControl', actions = {
        { id = 'ouvrir', label = 'Ouvrir la gestion du trafic', cmd = 'trafic', key = '' },
    } },
    { name = 'SCENE', label = 'Scènes de roleplay', res = 'rp_RoleplayZone', actions = {
        { id = 'ouvrir', label = 'Ouvrir /scene', cmd = 'scene', key = '' },
        { id = 'oeildaigle', label = 'Œil d\'aigle (policiers)', cmd = 'oeildaigle', key = 'CAPITAL' },
        { id = 'lacherarme', label = 'Mode civil : lâcher son arme', cmd = 'lacherarme', key = 'G' },
    } },
    { name = 'NUMEROS', label = 'Noms RP au-dessus des têtes', res = 'rp_overheadids', actions = {
        { id = 'afficher', label = 'Afficher (maintenir)', cmd = 'numeros', key = 'HOME', hold = true },
    } },
    { name = 'CARTES', label = 'Cartes de police', res = 'rp_policecards', actions = {
        { id = 'miranda', label = 'Carte Miranda', cmd = 'miranda', key = '' },
        { id = 'alphabet', label = 'Alphabet phonétique', cmd = 'alphabet', key = '' },
    } },
}

-- Noms de touches acceptés (ceux de FiveM), avec des équivalents en français
RPChatKeyAliases = {
    ESPACE = 'SPACE', ENTREE = 'RETURN', ENTER = 'RETURN', MAJ = 'LSHIFT', SHIFT = 'LSHIFT', CTRL = 'LCONTROL',
    CONTROL = 'LCONTROL', ALT = 'LMENU', VERRMAJ = 'CAPITAL', CAPSLOCK = 'CAPITAL', TAB = 'TAB', HAUT = 'UP', BAS = 'DOWN',
    GAUCHE = 'LEFT', DROITE = 'RIGHT', SUPPR = 'DELETE', INSER = 'INSERT', DEBUT = 'HOME', ORIGINE = 'HOME', FIN = 'END',
    PAGEHAUT = 'PAGEUP', PAGEBAS = 'PAGEDOWN', RETOUR = 'BACK', CLICGAUCHE = 'MOUSE_LEFT', CLICDROIT = 'MOUSE_RIGHT',
    CLICMOLETTE = 'MOUSE_MIDDLE', SOURIS4 = 'MOUSE_EXTRABTN1', SOURIS5 = 'MOUSE_EXTRABTN2',
}
