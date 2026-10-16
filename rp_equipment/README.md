# RP Equipment — équipement des véhicules de police (FiveM)

Script **100 % standalone** (sans ESX / QBCore / vRP), interface NUI en HTML/CSS/Vanilla JS, au style du MDC.

À pied, près d'une **portière avant** ou du **coffre** d'un véhicule de police, une proposition s'affiche :
la touche **E** (modifiable) ouvre le menu **Équipement** du véhicule.

## Installation

1. Copiez le dossier `rp_equipment` dans `resources/`.
2. Dans `server.cfg`, après le MDC et `rp_interact` : `ensure rp_equipment`
3. Touche : *Paramètres > Raccourcis clavier > FiveM > « Véhicule de police : menu Équipement »*.

## Qui y a accès

Les **policiers en service** : les joueurs dans une unité du MDC. Le MDC est trouvé **quel que soit le nom de son
dossier** (il publie lui-même son nom) ; en secours, l'unité que le MDC donne au joueur suffit. C'est vérifié par le
serveur à chaque action. `PoliceOnly = false` pour l'ouvrir à tout le monde.

## Le menu

- Il **s'ouvre** près d'une portière avant (« Équipement du véhicule (portière) ») ou derrière le véhicule
  (« … (coffre) »). Au coffre, le coffre s'ouvre, et se referme à la fermeture du menu (`OpenTrunk`).
- On peut **marcher** menu ouvert (souris pour cliquer ; caméra et armes bloquées). Le menu **se ferme tout seul** à
  plus de **4 m** du véhicule (`CloseDistance`), en montant dans un véhicule, en mourant ou en quittant le service.
  **Échap** ou ✕ le ferme aussi.
- **Équipement** : les pièces EUP de la **catégorie du véhicule** (voir ci-dessous), à **mettre** et **retirer** de sa
  tenue. Une pièce portée est cochée (bouton « Retirer »). En la retirant, ce que le policier portait avant revient.
  Seules les pièces de son personnage (homme / femme) sont proposées.
  **Objets** (bouton « Prendre » / « Ranger ») : par défaut, un **jerrican d'essence** dans **tous les véhicules de
  police** (APD, GSP, FCSO et véhicules de police sans service) : plein, il remplit **2/5 d'un réservoir** (en main près
  de la trappe à essence, arrière gauche : **E**, voir `rp_vehiclecontrol`).

## Équipement EUP par catégorie : `equipment.json`

Le fichier `equipment.json` (dans le dossier `rp_equipment`) a **une liste par catégorie** de véhicule :
`"Atlanta Police Department"`, `"Georgia State Patrol"`, `"Fayette County Sheriff Office"`. Ce sont les catégories
des véhicules dans `rp_interact/data/vehicles.json` (champ `Service`).

Chaque pièce s'écrit **comme une tenue du `/eup`** (`data/outfits.json` de rp_interact), avec **seulement les parties
qu'elle change** :

```json
{
    "Atlanta Police Department": [
        { "Name": "Gilet pare-balles APD", "Gender": "Male", "Armor": "13:1" },
        { "Name": "Casquette APD", "Gender": "Male", "Hat": "47:1" }
    ]
}
```

- Parties possibles : `Hat`, `Glasses`, `Ear`, `Watch`, `Bracelet` (accessoires), `Mask`, `UpperSkin`, `Pants`,
  `Parachute`, `Shoes`, `Accessories`, `UnderCoat`, `Armor`, `Decal`, `Top`.
- Numéros `"modèle:texture"` comptés **à partir de 1**, comme le `/eup` (`Eup.OneBased`).
- `Gender` : `Male` / `Female` (absent : les deux).
- **Objet** (arme du jeu que le policier prend et range) : `"Weapon"` et `"Ammo"` au lieu des parties, ex.
  `{ "Name": "Jerrican d'essence (2/5 d'un plein)", "Weapon": "WEAPON_PETROLCAN", "Ammo": 4500 }` (fourni dans chaque
  catégorie).
- Catégorie `"Police"` : véhicules de police qui ne sont dans aucune autre catégorie (râtelier + ses objets : le
  jerrican par défaut).

Après une modification : tapez `rpequip_reload` dans la console serveur.

## Types de véhicules

Chaque véhicule a un type, qui décide de son équipement :

| Type | Véhicules |
|---|---|
| `apd`, `gsp`, `fcso` | véhicules de cette catégorie dans `rp_interact/data/vehicles.json` (« Service »), **ou** modèles listés dans `Types.<type>.Models` |
| `police` | véhicules d'urgence (classe 18) qui ne sont dans aucune catégorie : râtelier seulement |

Après avoir modifié `rp_interact/data/vehicles.json` : tapez `rpequip_reload` dans la console serveur.

## Armes longues (râtelier)

- Par défaut, un véhicule n'a **aucune** arme longue. Il peut en stocker **deux** : un **fusil à pompe** et un
  **fusil d'assaut** (groupes d'armes `GROUP_SHOTGUN` / `GROUP_RIFLE`).
- **« Ranger l'arme longue »** : le policier doit **tenir l'arme dans les mains**. Elle va dans l'emplacement qui
  lui correspond, s'il est libre. Le menu indique l'arme tenue et si son emplacement est déjà occupé.
- L'arme est **sauvegardée telle quelle** : modèle, **accessoires** (lampe, viseur, poignée, silencieux, chargeur,
  bouche, canon, camouflage…), **teinte** de l'arme et des accessoires. Pas de gestion des munitions.
- **« Sortir l'arme »** : lui **ou un collègue** la récupère **identique**, directement en main, avec 250 munitions
  (`LongGuns.GiveAmmo`). L'emplacement se
  vide pour tout le monde (deux policiers ne peuvent pas sortir la même arme).
- Sauvegardé **par plaque** dans `data/racks.json` : gardé au redémarrage du serveur et quand le véhicule réapparaît
  avec la même plaque.
- Armes addon : leurs accessoires se déclarent dans `LongGuns.ExtraComponents`, leur nom dans `LongGuns.Names`.

## Coffre : plots de circulation et fusées (inventaire)

Au **coffre** d'un véhicule de police, la partie **« Coffre »** du menu se gère **comme un inventaire**, sauvegardé
**par plaque** dans `data/stock.json` (gardé au redémarrage du serveur et quand le véhicule réapparaît avec la même
plaque). C'est le **même coffre pour tous** les policiers.

**Plots de circulation** (cône orange à bandes blanches, `prop_roadcone02a`)
- **6 plots d'origine** dans chaque coffre (`Stock.Cones.Default`), **10 au maximum** (`Stock.Cones.Max`).
- **« Prendre un plot »** : le policier le **porte dans les mains** (un seul à la fois). Plot en main : pas d'arme, pas
  de coup, pas de visée, pas de montée en véhicule ; une aide en haut à gauche rappelle les touches.
- **G** (modifiable : *Raccourcis clavier > FiveM > « Plot de circulation : poser au sol »*) : il le **pose debout au
  sol**, devant lui, dans son axe. Le plot est créé **par le serveur** : visible par tous, figé, il reste même si le
  policier se déconnecte. Mort avec un plot en main : il tombe à ses pieds.
- **Reprendre** : avec l'**œil** de `rp_interact` (**Alt**), « Plot de circulation » : **Ramasser le plot** (policiers
  en service, à 2,5 m) : il le porte de nouveau.
- **« Ranger le plot »** : dans le coffre de **n'importe quel** véhicule de police (s'il n'est pas plein : 10 max).
- **Un plot pris et pas remis n'est plus dans le coffre** : le coffre garde son compte (5 si on en a laissé un au sol).
- Un plot porté au moment d'une déconnexion est perdu ; les plots au sol sont retirés si `rp_equipment` redémarre.

**Fusées de détresse** (`WEAPON_FLARE`, posées au sol avec `rp_flares`)
- Rangeables **comme les armes longues** : **« Ranger 1 »** / **« Tout ranger »** (celles que le policier a sur lui) et
  **« Prendre 1 »** / **« Prendre tout »**. **20 au maximum** par coffre (`Stock.Flares.Max`), aucune d'origine (les
  10 de départ viennent de l'équipement de service de `rp_interact`), 25 au maximum sur soi.
- Le menu affiche le nombre dans le coffre et sur le policier, mis à jour pour tous ceux qui ont ce coffre ouvert.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Key` | touche par défaut (E) |
| `PoliceOnly`, `MdcResource` | accès réservé aux policiers en service (unité du MDC ; `MdcResource` seulement si le MDC ne publie pas son nom) |
| `InteractDistance` | distance d'une portière avant / du coffre pour la proposition (1,6 m) |
| `CloseDistance` | au-delà, le menu se ferme (4 m de la carrosserie) |
| `OpenTrunk` | ouvrir le coffre pendant le menu |
| `Types`, `InteractVehicles`, `ServiceTypes` | types de véhicules (catégories de rp_interact, modèles, classes) |
| `EquipmentFile`, `Eup` | fichier de l'équipement EUP (`equipment.json`), numéros comptés à partir de 1 |
| `Stock` | coffre-inventaire : où (`Where`), fichier (`SaveFile`), plots (`Cones` : 6 d'origine, 10 max, modèle, distance de pose, port : os, décalage, animation), fusées (`Flares` : 20 max), touche de pose (`PlaceKey`, G) |
| `LongGuns` | râtelier : endroit (`Where`), types concernés, emplacements et groupes d'armes, munitions données (`GiveAmmo`), fichier de sauvegarde, accessoires et noms en plus |

## Performance

- Hors service ou en véhicule : rien.
- À pied et en service : une recherche toutes les 500 ms (~0.01 ms) ; à chaque image seulement près d'une portière
  avant / du coffre (proposition) ou menu ouvert.
- Plot porté : une boucle à chaque image **seulement tant qu'il est dans les mains** (aide, touches bloquées).
- Serveur : aucune boucle.
