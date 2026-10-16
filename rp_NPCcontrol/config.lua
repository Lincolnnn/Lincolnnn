--[[
    RP NPC Control - configuration (partagée client / serveur)
    Toutes ces règles ne concernent QUE les PNJ créés par le jeu : un joueur (ou un script, menu de spawn…) peut
    toujours faire apparaître un véhicule de police, une ambulance, un policier…
]]
NPCConfig = {
    -- ---------------------------------------------------------------------
    -- SERVICES D'URGENCE DU JEU : police, shérifs, highway, SWAT, rangers, FIB, pompiers, ambulanciers
    -- (et leurs véhicules, hélicoptères, bateaux) n'apparaissent plus NULLE PART : commissariats, casernes,
    -- hôpitaux, trafic, à pied, courses-poursuites aléatoires, renforts envoyés sur les crimes / incendies /
    -- blessés. Les PNJ déjà présents au démarrage de la ressource sont retirés.
    -- ---------------------------------------------------------------------
    DisableEmergencyServices = true,

    -- Indice de recherche (étoiles) : jamais, pour personne
    DisableWantedLevel = true,

    -- ---------------------------------------------------------------------
    -- « EVERYONE IGNORE PLAYER » : les PNJ ne réagissent plus aux joueurs (ni insultes, ni agressions, ni fuite),
    -- plus aux fusillades ni aux explosions, et n'ont plus peur : piétons, passagers ET conducteurs.
    -- ---------------------------------------------------------------------
    EveryoneIgnorePlayer = true,
    NoFear = true,
    -- Réactions « choquées » des passants (coups de feu, explosions, accidents) supprimées à chaque image :
    -- ~0.01 ms ; false : seulement les réglages des PNJ (NoFear), aucune boucle à chaque image pour ça.
    SuppressShockingEvents = true,
    -- CONDUCTEURS (PNJ au volant) : quand le joueur vise, tire ou qu'une explosion a lieu, ceux du jeu à moins de
    -- DriverRange m reprennent aussitôt une conduite normale (vitesse DriverSpeed m/s, style de conduite du jeu), et
    -- encore pendant AlertTime ms dès qu'ils se remettent à fuir.
    DriverRange = 80.0,
    DriverSpeed = 15.0,
    DrivingStyle = 786603,
    AlertTime = 4000,

    -- ---------------------------------------------------------------------
    -- DENSITÉ DES PNJ : 1.0 = jeu de base ; 0.0 = aucun ; jusqu'à 3.0 (le triple).
    --   Traffic : véhicules qui circulent ; Parked : véhicules garés ; Peds : piétons (et PNJ des scénarios).
    -- Au-dessus de 1.0, le jeu en ajoute autant que sa mémoire et sa population maximale le permettent (au-delà
    -- d'environ 2.0, la différence se voit moins). Commande (console ou permission ACE "command.npcdensity") pour
    -- essayer sans redémarrer : npcdensity traffic 2.0 | npcdensity peds 0.5 | npcdensity all 1.0 (jusqu'au
    -- prochain redémarrage : la valeur gardée est celle de ce fichier).
    -- ---------------------------------------------------------------------
    Density = {
        Traffic = 1.0,
        Parked = 1.0,
        Peds = 1.0,
    },
    DensityCommand = 'npcdensity',

    -- PNJ des services d'urgence (modèles)
    EmergencyPeds = {
        's_m_y_cop_01', 's_f_y_cop_01', 's_m_y_sheriff_01', 's_f_y_sheriff_01', 's_m_y_hwaycop_01',
        's_m_y_swat_01', 's_m_m_snowcop_01', 's_m_y_ranger_01', 's_f_y_ranger_01',
        's_m_m_paramedic_01', 's_m_y_fireman_01', 'csb_cop',
    },
    -- Véhicules des services d'urgence (modèles)
    EmergencyVehicles = {
        'police', 'police2', 'police3', 'police4', 'policeb', 'policet', 'policeold1', 'policeold2',
        'sheriff', 'sheriff2', 'fbi', 'fbi2', 'pranger', 'riot', 'riot2',
        'polmav', 'predator', 'firetruk', 'ambulance',
    },
    -- Scénarios (PNJ posés dans le décor) des services d'urgence
    EmergencyScenarios = {
        'WORLD_HUMAN_COP_IDLES', 'WORLD_VEHICLE_POLICE_BIKE', 'WORLD_VEHICLE_POLICE_CAR',
        'WORLD_VEHICLE_POLICE_NEXT_TO_CAR', 'CODE_HUMAN_POLICE_CROWD_CONTROL', 'CODE_HUMAN_POLICE_INVESTIGATE',
    },
}
