--[[
    RP Scene - configuration
    Options de Riven Scene Dynamics (script payant, jamais dans ce dépôt) dans l'œil (Alt) par le pont ox_target.
    Réservées aux policiers en service : ox_target/config.lua, PoliceOnly = { rp_scene = true } (déjà fait).
]]

RPSceneConfig = {
    -- Nom du dossier de Riven Scene Dynamics sur le serveur : sans lui (ou licence refusée), aucune option
    Resource = 'Riven_Scene_Dynamics',

    -- Commandes de Riven (shared/config.lua de Riven : Config.Command, Trunk.command, Evidence.command,
    -- SceneVehicles.command, UI.command) : à changer seulement si vous les avez renommées chez Riven
    Commands = {
        scene = 'rivenscene',
        trunk = 'riventrunk',
        evidence = 'rivenevidence',
        vehicle = 'rivenvehicle',
        ui = 'rivenui',
    },

    -- COFFRE : véhicules qui ont le kit de scène. Mêmes réglages que Config.Trunk de Riven (vehicleClasses, models),
    -- sinon Riven refuse d'ouvrir le coffre
    TrunkClasses = { [18] = true }, -- 18 = véhicules d'urgence
    TrunkModels = {},               -- spawn codes en plus (banalisées…), ex. { 'fbi', 'police4' }
    -- Riven n'ouvre son coffre qu'à moins de Config.Trunk.promptDistance (1,3 m) du pare-chocs arrière : choisi de
    -- plus loin dans l'œil, le joueur y marche d'abord (au plus WalkTimeout ms)
    TrunkStand = 0.6,    -- m derrière le pare-chocs où le joueur se place
    WalkTimeout = 4000,

    -- Options proposées (false pour en retirer une)
    Options = {
        trunk = true,      -- coffre d'un véhicule d'urgence : kit de scène (banderoles, poteaux, cônes, preuves…)
        perimeter = true,  -- véhicule d'urgence : périmètre automatique petit / moyen / grand
        ui = true,         -- véhicule d'urgence : gestion de la scène (interface F6 de Riven)
        register = true,   -- tout véhicule : l'enregistrer à la scène (V-001…)
        evidence = true,   -- plot de preuve : collecter
        post = true,       -- poteau de banderole : le retirer
    },

    -- Modèles des objets de Riven (chez Riven : Config.Evidence.markerProp.model, Config.Posts.model)
    EvidenceModels = { 'riven_evidence_marker_01' },
    PostModels = { 'prop_roadpole_01b' },

    -- Distances (m) entre le joueur et le point visé
    Distance = { trunk = 3.0, vehicle = 4.0, object = 2.5 },
}
