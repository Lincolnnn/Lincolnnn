--[[
    RP STAGES - configuration
    =========================
    Stages d'éclairage des véhicules de police, par EXTRAS du véhicule (SetVehicleExtra) :
      - 3 stages principaux : stage 1, stage 2, stage 3 (le stage 3 = stage de réponse : le stage de la sirène),
        changés avec UNE touche (stage suivant à chaque appui) ;
      - stages secondaires : Traffic Advisor Left (taLeft), Traffic Advisor Right (taRight), Steady Burn (steadyBurn),
        chacun avec sa propre touche.
    Aucun élément visuel (pas d'indicateur à l'écran).
    Rien n'est obligatoire : un véhicule n'a que les stages et les stages secondaires écrits pour lui.

    Pour chaque véhicule (clé = spawn code du véhicule, ex. 'police', 'sheriff2') :
      label       = nom (facultatif, messages de la console)
      stages      = { [1] = {...}, [2] = {...}, [3] = {...} }   -- seulement ceux qui existent sur ce véhicule
      secondary   = { taLeft = {...}, taRight = {...}, steadyBurn = {...} } -- facultatif
      off         = { [extra] = true/false }  -- facultatif : état des extras quand aucun stage n'est actif
                                              --   (sans « off » : tous les extras cités sont éteints)
      taExclusive = true   -- (défaut true) TA gauche et TA droite ne sont jamais allumés ensemble

    Un stage / stage secondaire :
      extras  = { [numéro de l'extra] = true (allumé) / false (éteint), ... }   -- seulement les extras ciblés
      overlay = true/false -- STAGES SECONDAIRES seulement (défaut true) : true = se superpose aux stages 1, 2, 3 ;
                           --   false = l'activer éteint le stage principal, choisir un stage l'éteint.
      label   = nom affiché (facultatif)

    Un extra cité dans un stage secondaire actif l'emporte sur le même extra du stage principal.
    SIRÈNE : gérée par Bozlights (main), JAMAIS par rp_stages (ni allumée, ni coupée, ni gyrophares du jeu). rp_stages la
    surveille seulement : allumée au stage 1 / 2 (ou sans stage) -> passage AUTOMATIQUE au stage 3 ; coupée -> retour au
    stage d'avant (s'il était déjà au stage 3, il y reste). Tant qu'elle sonne, le véhicule reste au stage 3.
    Un véhicule sans stage 3 : la sirène ne change rien.

    LES NUMÉROS D'EXTRAS CI-DESSOUS SONT DES EXEMPLES : remplacez-les par ceux de vos véhicules (menu des extras d'un
    trainer, ou fichier .yft / carcols du véhicule). Un extra qui n'existe pas sur le modèle est ignoré (avertissement
    une fois dans la console F8).
]]

RPStagesConfig = {
    -- Touches d'origine (modifiables par chaque joueur avec /modiftouche STAGES ... ; ou Paramètres > Raccourcis > FiveM)
    --   stages : UNE touche pour les stages principaux (aucun -> 1 -> 2 -> 3 -> aucun, seulement ceux du véhicule)
    --   taLeft / taRight / steadyBurn : une touche par stage secondaire (la sirène reste aux touches de Bozlights)
    Keys = {
        stages = 'Q',
        taLeft = '4', taRight = '5', steadyBurn = '6',
    },
    -- Touche des stages : après le dernier stage, true = retour à « aucun stage » ; false = retour au premier stage
    CycleOff = true,
    -- Roue de la radio du jeu (Q) bloquée au volant d'un véhicule configuré (Q = touche des stages par défaut)
    DisableRadioWheel = true,

    -- SIRÈNE (Bozlights) : surveillée au volant d'un véhicule configuré, toutes les SirenInterval ms.
    -- SirenCheck(véhicule) -> true quand la sirène sonne. Par défaut : la sirène du jeu (IsVehicleSirenAudioOn).
    -- Si Bozlights coupe la sirène du jeu et joue ses propres sons, la détection par défaut ne la voit pas : lisez alors
    -- l'information de Bozlights, par exemple son state bag (nom à vérifier dans Bozlights) :
    --     SirenCheck = function(veh) return Entity(veh).state.sirenOn == true end,
    -- ou bien, dans Bozlights (client), à chaque changement : TriggerEvent('rp_stages:siren', true) / (…, false)
    --   (l'événement l'emporte sur SirenCheck pour le véhicule conduit).
    SirenInterval = 150,
    SirenCheck = function(veh) return IsVehicleSirenAudioOn(veh) end,

    -- Délai (ms) de détection du véhicule du joueur (hors véhicule configuré : aucune autre boucle)
    CheckInterval = 400,
    -- Délai (ms) d'application aux véhicules qui arrivent à portée (déjà réglés par un autre joueur), et distance (m)
    StreamInterval = 2000, StreamDistance = 150.0,

    -- Permission (ACE) pour utiliser les stages ; false = tout conducteur d'un véhicule configuré
    Ace = false,

    Vehicles = {
        -- Exemple : voiture de patrouille (3 stages, TA gauche / droite qui se superposent, Steady Burn seul)
        ['police'] = {
            label = 'Police Cruiser',
            stages = {
                [1] = { extras = { [1] = true, [2] = false, [3] = false } },              -- feux arrière
                [2] = { extras = { [1] = true, [2] = true, [3] = false } },               -- + rampe avant
                [3] = { extras = { [1] = true, [2] = true, [3] = true } },                -- tout (réponse)
            },
            secondary = {
                taLeft = { extras = { [5] = true }, overlay = true },
                taRight = { extras = { [6] = true }, overlay = true },
                steadyBurn = { extras = { [7] = true }, overlay = false },
            },
        },
        -- Exemple : véhicule à 2 stages seulement, sans stage secondaire (pas de stage 3 : la sirène ne change rien)
        ['police2'] = {
            label = 'Police Buffalo',
            stages = {
                [1] = { extras = { [1] = true, [2] = false } },
                [2] = { extras = { [1] = true, [2] = true } },
            },
        },
        -- Exemple : stages 1 et 3, Traffic Advisor à gauche seulement
        ['sheriff'] = {
            label = 'Sheriff Cruiser',
            stages = {
                [1] = { extras = { [1] = true, [2] = false } },
                [3] = { extras = { [1] = true, [2] = true } },
            },
            secondary = {
                taLeft = { extras = { [4] = true }, overlay = true },
            },
        },
    },
}
