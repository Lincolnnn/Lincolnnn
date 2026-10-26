# RP VehicleProps (`rp_vehicleprops`)

Objets **collés sur les véhicules** (sac, arme, radio, paquet, carton, mallette…), posés et réglés avec **l'œil de
`rp_interact`**. 100 % standalone : ni `ox_lib`, ni `ox_target`, ni framework. Interface NUI en HTML/CSS/Vanilla JS au
thème clair du MDC (bannière de couleur, coins presque carrés), mode nuit compris.

D'après le script « CartoonPropTrunk » (ox_lib / ox_target), réécrit pour ce serveur.

## Installation

1. Le dossier est déjà dans `[rp]/`. Dans `server.cfg` : `ensure rp_vehicleprops` (après `rp_interact`).
2. `rp_interact` l'ajoute à son œil (`config.lua` : `TargetProviders`, déjà fait).

## Utilisation

**Œil (Alt) sur un véhicule**, à pied, à moins de 3 m :

- **Ajouter un objet** : choisissez l'objet dans la liste (par catégorie). Il apparaît **là où vous regardiez** avec
  l'œil (le coffre, le toit, le siège…), avec la rotation choisie la dernière fois pour cet objet.
- **Déplacer un objet (n)** : choisissez l'un des objets posés, puis réglez-le.
- **Retirer un objet** : choisissez l'objet à retirer.

**Éditeur** : position **gauche / droite**, **arrière / avant**, **bas / haut** (m, depuis le centre du véhicule) et
rotation **tangage**, **roulis**, **lacet** (degrés), au curseur, au clavier (valeur tapée) ou à la **molette** sur la
ligne ; **sensibilité** (pas plus fin ou plus grand). L'aperçu (légèrement transparent) n'est visible que par vous.
**Enregistrer** : l'objet est posé chez **tous les joueurs**. **Échap / Annuler** : rien ne change.

Les objets restent collés au véhicule (ils suivent ses mouvements, sans collision) et **disparaissent avec lui**. Un
joueur qui arrive près du véhicule les voit aussi.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Distance` | distance maximale au véhicule pour l'œil (3 m) |
| `ServerDistance` | distance maximale vérifiée par le serveur (8 m) |
| `MaxPerVehicle` | objets au plus par véhicule (12) |
| `Restricted` | `true` : réservé à la permission ACE `rp_vehicleprops.use` |
| `Editor` | portée de la position (±3 m), pas des curseurs, sensibilité |
| `Props` | objets proposés : `id` unique, `label`, `category`, `model` (modèle du jeu). **Le serveur n'accepte que ces modèles.** |

## Fonctionnement

- Les objets d'un véhicule sont dans son état `rpProps` (liste : objet, position, rotation), écrit **uniquement par le
  serveur** après vérification : véhicule réel, joueur à côté, objet de la liste, position et rotation bornées,
  nombre maximal, une action tous les 250 ms au plus.
- Chaque joueur pose ses propres objets (locaux, sans collision, indestructibles), collés au véhicule ; ils sont
  refaits quand l'état change.
- Performance : une vérification toutes les 2,5 s (véhicules proches qui portent des objets, véhicules disparus) ;
  rien d'autre. Éditeur : seulement pendant le réglage.
