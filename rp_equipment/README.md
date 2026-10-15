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
- Un véhicule de police qui n'est dans aucune catégorie n'a que le râtelier.

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
| `LongGuns` | râtelier : endroit (`Where`), types concernés, emplacements et groupes d'armes, munitions données (`GiveAmmo`), fichier de sauvegarde, accessoires et noms en plus |

## Performance

- Hors service ou en véhicule : rien.
- À pied et en service : une recherche toutes les 500 ms (~0.01 ms) ; à chaque image seulement près d'une portière
  avant / du coffre (proposition) ou menu ouvert.
- Serveur : aucune boucle.
