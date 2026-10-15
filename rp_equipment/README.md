# RP Equipment — équipement des véhicules de police (FiveM)

Script **100 % standalone** (sans ESX / QBCore / vRP), interface NUI en HTML/CSS/Vanilla JS, au style du MDC.

À pied, près d'une **portière avant** ou du **coffre** d'un véhicule de police, une proposition s'affiche :
la touche **E** (modifiable) ouvre le menu **Équipement** du véhicule.

## Installation

1. Copiez le dossier `rp_equipment` dans `resources/`.
2. Dans `server.cfg`, après le MDC et `rp_interact` : `ensure rp_equipment`
3. Touche : *Paramètres > Raccourcis clavier > FiveM > « Véhicule de police : menu Équipement »*.

## Qui y a accès

Les **policiers en service** : les joueurs dans une unité du MDC (`mdc_standalone`). C'est vérifié par le serveur
à chaque action. `PoliceOnly = false` pour l'ouvrir à tout le monde.

## Le menu

- Il **s'ouvre** près d'une portière avant (« Équipement du véhicule (portière) ») ou derrière le véhicule
  (« … (coffre) »). Au coffre, le coffre s'ouvre, et se referme à la fermeture du menu (`OpenTrunk`).
- On peut **marcher** menu ouvert (souris pour cliquer ; caméra et armes bloquées). Le menu **se ferme tout seul** à
  plus de **4 m** du véhicule (`CloseDistance`), en montant dans un véhicule, en mourant ou en quittant le service.
  **Échap** ou ✕ le ferme aussi.
- **Matériel** : ce que **ce type de véhicule** contient **à cet endroit** (portières avant ou coffre), bouton
  « Prendre ». Exemples fournis :
  - portières avant : lampe torche, matraque, Taser, chargeurs de pistolet ;
  - coffre : gilet pare-balles, trousse de secours, extincteur, fusées de détresse, munitions de fusil et cartouches ;
  - **GSP uniquement** : pistolet lance-fusées et parachute.

## Types de véhicules

Chaque véhicule a un type, qui décide de son équipement :

| Type | Véhicules |
|---|---|
| `apd`, `gsp`, `fcso` | modèles listés dans `Types.<type>.Models`, **ou** rangés dans ce service dans `rp_interact/data/vehicles.json` (« Service ») |
| `police` | véhicules d'urgence (classe 18) qui ne sont dans aucun service : équipement commun |

Un objet sans `Vehicles` est dans tous les types. `Vehicles = { 'gsp' }` le réserve aux véhicules de la GSP.
Après avoir modifié `rp_interact/data/vehicles.json` : tapez `rpequip_reload` dans la console serveur.

## Armes longues (râtelier)

- Par défaut, un véhicule n'a **aucune** arme longue. Il peut en stocker **deux** : un **fusil à pompe** et un
  **fusil d'assaut** (groupes d'armes `GROUP_SHOTGUN` / `GROUP_RIFLE`).
- **« Ranger l'arme longue »** : le policier doit **tenir l'arme dans les mains**. Elle va dans l'emplacement qui
  lui correspond, s'il est libre. Le menu indique l'arme tenue et si son emplacement est déjà occupé.
- L'arme est **sauvegardée telle quelle** : modèle, **accessoires** (lampe, viseur, poignée, silencieux, chargeur,
  bouche, canon, camouflage…), **teinte** de l'arme et des accessoires, **munitions**.
- **« Sortir l'arme »** : lui **ou un collègue** la récupère **identique**, directement en main. L'emplacement se
  vide pour tout le monde (deux policiers ne peuvent pas sortir la même arme).
- Sauvegardé **par plaque** dans `data/racks.json` : gardé au redémarrage du serveur et quand le véhicule réapparaît
  avec la même plaque.
- Armes addon : leurs accessoires se déclarent dans `LongGuns.ExtraComponents`, leur nom dans `LongGuns.Names`.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Key` | touche par défaut (E) |
| `PoliceOnly`, `MdcResource` | accès réservé aux policiers en service (unité du MDC) |
| `InteractDistance` | distance d'une portière avant / du coffre pour la proposition (1,6 m) |
| `CloseDistance` | au-delà, le menu se ferme (4 m de la carrosserie) |
| `OpenTrunk` | ouvrir le coffre pendant le menu |
| `Types`, `InteractVehicles`, `ServiceTypes` | types de véhicules (modèles, services de rp_interact, classes) |
| `Equipment` | matériel : `Type` (`weapon`, `ammo`, `armor`, `health`, `event`), `Where` (`front`, `trunk`, `both`), `Vehicles` |
| `LongGuns` | râtelier : endroit (`Where`), types concernés, emplacements et groupes d'armes, fichier de sauvegarde, accessoires et noms en plus |

`Type = 'event'` déclenche un événement client (`Event`) : pour brancher un autre script (cônes, herse…).

## Performance

- Hors service ou en véhicule : rien.
- À pied et en service : une recherche toutes les 500 ms (~0.01 ms) ; à chaque image seulement près d'une portière
  avant / du coffre (proposition) ou menu ouvert.
- Serveur : aucune boucle.
