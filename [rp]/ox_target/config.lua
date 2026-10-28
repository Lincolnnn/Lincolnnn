--[[
    ox_target (pont) - configuration
    Les options ajoutées par les autres scripts s'affichent dans l'œil de rp_interact (ajouter 'ox_target' à
    rp_interact/config.lua : TargetProviders, déjà fait).
]]

BridgeConfig = {
    DefaultDistance = 7.0, -- m : distance d'une option qui n'en précise pas (comme ox_target)
    BoneDistance = 1.25,   -- m : options sur une partie du véhicule (bones = { 'boot' }…) : point visé à moins de 1,25 m
    -- Scripts dont les options ne sont proposées qu'aux policiers en service (dans une unité du MDC) : herses de
    -- riven_spikes (coffre des véhicules de police, ramasser / tirer le cordon d'une herse posée)
    PoliceOnly = { riven_spikes = true },
    -- Options cachées dans l'œil (nom de l'option qui commence par…) : elles restent utilisables par nos menus
    -- (export runOption) ; ici, prendre / ranger une herse se fait dans le menu Équipement du coffre (rp_equipment)
    HiddenPrefixes = { 'riven_spikes_trunk_' },
    -- Libellés des options traduits dans l'œil, par script (que sa langue soit réglée ou non) :
    -- Labels : texte exact -> texte ; Patterns : { motif Lua, texte avec %s } ; le texte capturé (nom de l'objet)
    -- passe par Nouns (avec son article)
    Translations = {
        riven_spikes = {
            Labels = {
                ['Grab cord'] = 'Saisir le cordon',
                ['Put strip back in trunk'] = 'Ranger la herse dans le coffre',
                ['Saisir le cordon'] = 'Saisir le cordon',
                ['Ranger la herse dans le coffre'] = 'Ranger la herse dans le coffre',
            },
            Patterns = {
                { '^Take (.+)$', 'Prendre %s dans le coffre' },
                { '^Prendre : (.+)$', 'Prendre %s dans le coffre' },
                { '^Pick up (.+)$', 'Ramasser %s' },
                { '^Ramasser : (.+)$', 'Ramasser %s' },
            },
            Nouns = {
                ['Spike Strip'] = 'la herse', ['Herse'] = 'la herse',
                ['Stop Stick'] = 'le Stop Stick', ['Stop Stick (Red)'] = 'le Stop Stick rouge', ['Stop Stick (rouge)'] = 'le Stop Stick rouge',
                ['Terminator'] = 'le Terminator', ['Terminator XS'] = 'le Terminator XS',
            },
        },
    },
    -- Titre de l'œil sur le sol (zones) selon le script qui a ajouté l'option ; sinon « Lieu »
    Labels = { riven_spikes = 'Herse' },
    -- Icônes Font Awesome d'ox_target -> icônes de l'œil (eye, search, door, car, hand, trash, lock, unlock, cuffs,
    -- barrier, box, move, note, seat, wave, music, nose) ; inconnue : hand
    Icons = {
        ['fa-hand'] = 'hand', ['fa-hand-fist'] = 'hand', ['fa-hand-holding'] = 'hand', ['fa-hands'] = 'hand',
        ['fa-road-barrier'] = 'barrier', ['fa-box-archive'] = 'box', ['fa-box'] = 'box', ['fa-box-open'] = 'box',
        ['fa-car'] = 'car', ['fa-car-side'] = 'car', ['fa-door-open'] = 'door', ['fa-door-closed'] = 'door',
        ['fa-trash'] = 'trash', ['fa-trash-can'] = 'trash', ['fa-lock'] = 'lock', ['fa-unlock'] = 'unlock',
        ['fa-eye'] = 'eye', ['fa-magnifying-glass'] = 'search', ['fa-search'] = 'search', ['fa-handcuffs'] = 'cuffs',
        ['fa-up-down-left-right'] = 'move', ['fa-arrows-up-down-left-right'] = 'move', ['fa-note-sticky'] = 'note',
        ['fa-chair'] = 'seat', ['fa-music'] = 'music',
    },
}
