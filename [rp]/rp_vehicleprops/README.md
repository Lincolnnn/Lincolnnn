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

## Arme ou lampe tenue en main (`Held`)

Liée à `rp_interact` (œil, accessoires des armes), `rp_weaponscontrol` (lampe toujours allumée), CartoonFlashlight
(lampe tenue) et `rp_taser10` :

- **Sur un véhicule** (œil, à 3 m) : **« Poser l'arme ici »** (point visé), **« … sur le toit »** (4 endroits,
  au-dessus des portières : celui de la **portière la plus proche** du joueur, avant / arrière, gauche / droite ;
  véhicule sans ces portières : milieu du toit), **« … sur le coffre »** (seulement les véhicules à **coffre plat**, berlines… : surface nettement plus basse que le toit et
  presque horizontale, vérifiée sur le véhicule). L'arme est posée **directement** (sans physique : elle ne glisse
  plus) : des rayons vers le bas trouvent la carrosserie (la **collision** du véhicule, comme les impacts de balles)
  et son **inclinaison** (moyenne de 5 points : les courbes du capot, du toit) ; l'arme est **couchée, inclinée comme
  la surface, au ras** (son point le plus bas posé dessus, 4 mm, `Lift`). Elle reste **collée au véhicule** chez tous
  les joueurs, avec ses **accessoires** (lus par `rp_interact`), leurs teintes, sa **teinte**, ses **munitions** et sa
  **lampe allumée** (arme avec lampe : vraie lampe du jeu ; lampe torche : lumière du modèle). 4 au plus par véhicule.
- **« Reprendre : <arme> »** (œil sur le véhicule) : rendue **telle quelle**, lampe rallumée si elle l'était.
- **Ailleurs** (sol, mur, personne…), arme ou lampe en main : **« Poser l'arme au sol »** / **« … la lampe au sol »**,
  de la même façon (au point visé à moins de 3 m, sinon devant soi) ; **« Ramasser : <arme> »** avec l'œil (n'importe
  qui, à 2,5 m). 3 au plus par joueur (`GroundMax`). **La jeter** reste possible avec `rp_RoleplayZone` (touche G).
- **Taser** : au sol avec `rp_taser10` (sondes gardées) ; relié à un suspect, il ne va pas sur un véhicule.

Lampes torches posées allumées : **lumière du modèle** (celle de CartoonFlashlight), réappliquée régulièrement ;
`Beam.Drawn = true` : faisceau dessiné en plus (`TorchBeamAxis` pour son axe). Le serveur vérifie : arme en main (ou
mains déjà vides), distance, nombres, valeurs bornées ; refus : l'arme est rendue.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Distance` | distance maximale au véhicule pour l'œil (3 m) |
| `ServerDistance` | distance maximale vérifiée par le serveur (8 m) |
| `MaxPerVehicle` | objets au plus par véhicule (12) |
| `Restricted` | `true` : réservé à la permission ACE `rp_vehicleprops.use` |
| `Editor` | portée de la position (±3 m), pas des curseurs, sensibilité |
| `Held` | arme / lampe tenue : armes par véhicule, objets au sol (par joueur, en tout), distances, hauteur au-dessus de la surface, modèles des lampes, armes exclues, faisceau dessiné |
| `Props` | objets proposés : `id` unique, `label`, `category`, `model` (modèle du jeu). **Le serveur n'accepte que ces modèles.** |

## Fonctionnement

- Les objets d'un véhicule sont dans son état `rpProps` (liste : objet, position, rotation), écrit **uniquement par le
  serveur** après vérification : véhicule réel, joueur à côté, objet de la liste, position et rotation bornées,
  nombre maximal, une action tous les 250 ms au plus.
- Chaque joueur pose ses propres objets (locaux, sans collision, indestructibles), collés au véhicule ; ils sont
  refaits quand l'état change.
- Performance : une vérification toutes les 2,5 s (véhicules proches qui portent des objets, véhicules disparus) ;
  rien d'autre. Éditeur : seulement pendant le réglage.
