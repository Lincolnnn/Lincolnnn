# RP Equipment — équipement des véhicules de police (FiveM)

Script **100 % standalone** (sans ESX / QBCore / vRP), interface NUI en HTML/CSS/Vanilla JS, au style du MDC.

À pied, près d'une **portière avant** ou du **coffre** d'un véhicule de police, une proposition s'affiche :
la touche **E** (modifiable) ouvre le menu **Équipement** du véhicule.

## Installation

1. Copiez le dossier `rp_equipment` dans `resources/`.
2. Dans `server.cfg`, après le MDC et `rp_interact` : `ensure rp_equipment`
3. Touche : *Paramètres > Raccourcis clavier > FiveM > « Véhicule de police : menu Équipement »*.

**Mode nuit** (réglé dans le MDC : *Paramètres > MDC > Apparence*, appliqué à toutes les interfaces ou aux menus extérieurs) : **fond noir et couleur du mode nuit** (vert, jaune, rouge ou bleu) pour le menu Équipement (`client/theme.lua` ; sans le MDC : thème jour).

## Qui y a accès

Les **policiers en service** : les joueurs dans une unité du MDC. Le MDC est trouvé **quel que soit le nom de son
dossier** (il publie lui-même son nom) ; en secours, l'unité que le MDC donne au joueur suffit. C'est vérifié par le
serveur à chaque action. `PoliceOnly = false` pour l'ouvrir à tout le monde.

## Le menu

- Il **s'ouvre** près d'une portière avant (« Équipement du véhicule (portière) ») ou derrière le véhicule
  (« … (coffre) »). La **portière avant la plus proche** s'ouvre (côté gauche : **conducteur** ; côté droit :
  **passager avant**, `OpenFrontDoor`), ou le **coffre** (`OpenTrunk`). Déjà ouverte : elle n'est pas rouverte. Dans
  tous les cas elle **se referme à la fermeture du menu**.
- On peut **marcher** menu ouvert (souris pour cliquer ; caméra et armes bloquées). Le menu **se ferme tout seul** à
  plus de **4 m** du véhicule (`CloseDistance`), en montant dans un véhicule, en mourant ou en quittant le service.
  **Échap** ou ✕ le ferme aussi ; **Échap n'ouvre pas le menu pause du jeu** (bloqué jusqu'au relâchement de la
  touche, comme pour les tips civils).
- **Équipement** : les pièces EUP de la **catégorie du véhicule** (voir ci-dessous), à **mettre** et **retirer** de sa
  tenue. Une pièce portée est cochée (bouton « Retirer »). En la retirant, ce que le policier portait avant revient.
  Seules les pièces de son personnage (homme / femme) sont proposées.
  **Objets** (bouton « Prendre » / « Ranger ») : armes du jeu ajoutées dans `equipment.json` (aucun par défaut ; le
  **jerrican d'essence** est désormais dans le **coffre**, voir plus bas).

## Équipement EUP par police : `equipment.json`

Le fichier `equipment.json` (dans le dossier `rp_equipment`) a **une liste par police** (celles du MDC) :
`"Washington State Patrol"` et `"King County Sheriff Office"` (ou `"WSP"` / `"KCSO"`). C'est la police des
véhicules dans `rp_interact/data/vehicle.json` (champ `subCategory`).

Chaque pièce s'écrit **comme une tenue du `/eup`** (`data/outfits.json` de rp_interact), avec **seulement les parties
qu'elle change** :

```json
{
    "Washington State Patrol": [
        { "Name": "Gilet pare-balles WSP", "Gender": "Male", "Armor": "14:1" },
        { "Name": "Chapeau de Trooper", "Gender": "Male", "Hat": "14:1" }
    ]
}
```

- Parties possibles : `Hat`, `Glasses`, `Ear`, `Watch`, `Bracelet` (accessoires), `Mask`, `UpperSkin`, `Pants`,
  `Parachute`, `Shoes`, `Accessories`, `UnderCoat`, `Armor`, `Decal`, `Top`.
- Numéros `"modèle:texture"` comptés **à partir de 1**, comme le `/eup` (`Eup.OneBased`).
- `Gender` : `Male` / `Female` (absent : les deux).
- **Objet** (arme du jeu que le policier prend et range) : `"Weapon"` et `"Ammo"` au lieu des parties, ex.
  `{ "Name": "Extincteur", "Weapon": "WEAPON_FIREEXTINGUISHER", "Ammo": 2000 }` (aucun par défaut : le jerrican est
  dans le coffre).
- Catégorie `"Police"` : véhicules de police qui ne sont d'aucune de ces polices (râtelier, coffre, et les objets
  que vous y ajoutez).

Après une modification : tapez `rpequip_reload` dans la console serveur.

## Types de véhicules

Chaque véhicule a un type, qui décide de son équipement :

| Type | Véhicules |
|---|---|
| `wsp`, `kcso` | véhicules de cette police dans `rp_interact/data/vehicle.json` (« subCategory » : `Washington State Patrol`, `King County Sheriff Office`), **ou** modèles listés dans `Types.<type>.Models` |
| `police` | véhicules d'urgence (classe 18) qui ne sont d'aucune de ces polices : râtelier seulement |

L'ancien `rp_interact/data/vehicles.json` (champ `Service`) est lu seulement en l'absence de `vehicle.json`. Après
avoir modifié le fichier de rp_interact : tapez `rpequip_reload` dans la console serveur.

## Armes longues (râtelier)

- Par défaut, un véhicule n'a **aucune** arme longue. Il a **deux emplacements séparés**, **une arme longue
  chacun** (fusil à pompe, fusil d'assaut, fusil de précision, mitrailleuse : `LongGuns.Groups`) :
  - **à l'avant** (habitacle) : menu ouvert à une **portière avant** ;
  - **dans le coffre** : menu ouvert au **coffre**.
  Une arme rangée à l'avant **ne se reprend qu'à l'avant**, une arme rangée dans le coffre **qu'au coffre** : le
  menu ne montre que l'emplacement de l'endroit où l'on est (le serveur vérifie aussi).
- **« Ranger l'arme longue »** : le policier doit **tenir l'arme dans les mains**. Elle va dans l'emplacement de
  l'endroit où il est (avant ou coffre), s'il est libre. Le menu indique l'arme tenue et si l'emplacement est déjà
  occupé.
- Ancien `data/racks.json` (un emplacement par sorte d'arme) : converti tout seul au démarrage (fusil à pompe ->
  avant, fusil d'assaut -> coffre ; aucune arme perdue).
- L'arme est **sauvegardée telle quelle** : modèle, **accessoires** (lampe, viseur, poignée, silencieux, chargeur,
  bouche, canon, camouflage…), **teinte** de l'arme et des accessoires. Pas de gestion des munitions.
- **« Sortir l'arme »** : lui **ou un collègue** la récupère **identique**, directement en main, avec 250 munitions
  (`LongGuns.GiveAmmo`). L'emplacement se
  vide pour tout le monde (deux policiers ne peuvent pas sortir la même arme).
- Sauvegardé **par plaque** dans `data/racks.json` : gardé au redémarrage du serveur et quand le véhicule réapparaît
  avec la même plaque.
- Armes addon : leurs accessoires se déclarent dans `LongGuns.ExtraComponents`, leur nom dans `LongGuns.Names`.

## Coffre : plots de circulation, jerrican, pistolet radar et fusées (inventaire)

Au **coffre** d'un véhicule de police, la partie **« Coffre »** du menu se gère **comme un inventaire**, sauvegardé
**par plaque** dans `data/stock.json` (gardé au redémarrage du serveur et quand le véhicule réapparaît avec la même
plaque). C'est le **même coffre pour tous** les policiers.

**Plots de circulation** (cône orange à bandes blanches, `prop_roadcone02a`)
- **7 plots d'origine** dans chaque véhicule de police (`Stock.Cones.Default`), **10 au maximum** (`Stock.Cones.Max`).
- **`/restock`** (policier en service, assis dans le véhicule de police ou à 6 m de lui) : coffre rempli à **100 %** :
  **10 / 10 plots**, **20 / 20 fusées**, un **jerrican plein** et le **pistolet radar**. Les **armes longues** ne sont pas touchées (à ranger soi-même).
- **Prendre** : le policier **choisit le nombre** avec **− / +** (de 1 à ce que le coffre contient et ce qu'il peut
  encore porter : **5 plots au plus** à la fois, `Stock.Cones.MaxCarry`), puis **« Prendre N plots »**. Il les **porte en pile dans les mains**.
  Plots en main : pas d'arme, pas de coup, pas de visée, pas de montée en véhicule.
- **Aide en haut à gauche** tant qu'il porte des plots : **« "G" pour poser un plot (N en mains), utiliser le target
  pour récupérer les plots posés. »** (la touche réellement choisie par le joueur). Le texte est envoyé au jeu en
  morceaux de moins de 99 caractères : au-delà, le jeu l'affichait mal. Après avoir posé le **dernier** plot, le rappel
  « Utiliser le target pour récupérer les plots posés. » reste affiché quelques secondes.
- **G** (modifiable : *Raccourcis clavier > FiveM > « Plot de circulation : poser au sol »*) : **un** plot posé **debout
  au sol**, devant lui ; on rappuie pour le suivant. Les plots sont créés **par le serveur** : visibles par tous, figés,
  ils restent même si le policier se déconnecte. Mort avec des plots en main : ils tombent autour de ses pieds.
- **Reprendre avec le target** (`rp_interact`, **Alt**), « Plot de circulation » (policiers en service, à 2,5 m) :
  - **« Ramasser le plot »** : celui visé ;
  - **« Ramasser les plots autour »** : celui visé **et tous ceux posés autour** (`Stock.Cones.PickupRadius`, 8 m),
    **d'un coup** (« 3 plots ramassés (5 en main) »).
  Ils s'ajoutent à ceux déjà portés (**5 au plus** : au-delà, le reste reste au sol).
- **Ranger** : le bouton range **tout d'un coup** : **« Ranger les N plots »** s'il en porte plusieurs, **« Ranger le
  plot »** s'il n'en a qu'un. Dans le coffre de **n'importe quel** véhicule de police ; si le coffre ne peut pas tout
  prendre (10 max), il range ce qui rentre et garde le reste en main.
- **Un plot pris et pas remis n'est plus dans le coffre** : le coffre garde son compte.
- Des plots portés au moment d'une déconnexion sont perdus ; les plots au sol sont retirés si `rp_equipment` redémarre.

**Trafic PNJ autour des plots** (`client/traffic.lua`, `Stock.Cones.Traffic`) : **seulement les plots posés avec ce
menu** (jamais ceux du décor).
- Plots à moins de 6 m les uns des autres = **un dispositif** (ligne, biseau en diagonale…). Autour, une zone de
  vitesse du jeu fait **ralentir** les véhicules qui approchent.
- Un véhicule PNJ qui a un plot du dispositif **dans sa trajectoire à moins de 10 m** (`Detect`) **anticipe** : il
  cherche le passage le plus proche de lui, à gauche ou à droite, assez large pour lui et **sur la route** (voie
  voisine ou **voie d'en face**), s'y engage à allure réduite, dépasse le dernier plot puis reprend sa route. Ex. :
  3 plots en diagonale qui ferment la voie de droite : les PNJ passent sur l'autre voie.
- **Aucune autre voie** (route à une voie, dispositif qui ferme toute la route) : le dispositif est
  **infranchissable**, les véhicules s'arrêtent devant ; ils repartent quand les plots sont retirés.
- Chaque joueur ne dirige que les PNJ que son jeu contrôle (réseau). Aucune boucle sans plot posé ; plot à plus de
  200 m (`Range`) : rien n'est fait.

**Jerrican d'essence** (`WEAPON_PETROLCAN`, `Stock.Jerrycans`)
- **Un jerrican plein** dans le coffre de **chaque véhicule de police** (1 / 1). **« Prendre »** : il est donné plein
  (2/5 d'un réservoir avec `rp_vehiclecontrol` : en main près de la trappe, **E « Verser le jerrican »**).
- **« Ranger »** : remis dans le coffre **avec l'essence qui lui reste** (le menu l'affiche : « 1 / 1 dans le coffre
  (40 %) »). Un seul par coffre ; on ne peut pas en prendre un deuxième si l'on en a déjà un sur soi.
- **`/restock`** remet un jerrican **plein** dans le coffre.

**Pistolet radar** (`WEAPON_RADARGUN`, `Stock.RadarGuns`)
- **Un pistolet radar** dans le coffre de **chaque véhicule de police** (1 / 1) : **« Prendre »** / **« Ranger »**. Un
  seul par coffre ; on ne peut pas en prendre un deuxième si l'on en a déjà un sur soi. **`/restock`** le remet.

**Herse** (script payant **riven_spikes**, facultatif ; `Stock.Spikes`)
- Prise et rangée avec **l'œil** (Alt) sur le coffre de tout véhicule d'urgence : **« Prendre la herse dans le
  coffre »** / **« Ranger la herse dans le coffre »** (options de Riven ; voir [`ox_target/`](../ox_target/README.md)).
  `Stock.Spikes.Menu = true` ajoute en plus une ligne « Herse » à ce menu (désactivée par défaut).
- Herse en main : la touche **X** de Riven (« ranger dans la poche ») ne la fait plus disparaître : elle revient
  aussitôt dans les mains. On doit la **lancer / poser au sol** ou la **ranger dans le coffre** (œil). Mort, à bord d'un
  véhicule, à terre ou menotté : Riven la range lui-même. `Stock.Spikes.KeepInHands = false` : comportement de Riven.

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
| `OpenFrontDoor` | ouvrir la portière avant la plus proche pendant le menu |
| `Stock` | coffre-inventaire : où (`Where`), fichier (`SaveFile`), plots (`Cones` : 7 d'origine, 10 max, `MaxCarry` = 5 portés, `PickupRadius` du ramassage groupé, modèle, distance de pose, port : os, décalage, animation, pile `MaxProps` / `StackStep`), fusées (`Flares` : 20 max), jerrican (`Jerrycans` : 1 plein d'origine, 1 max, `Ammo` = plein), pistolet radar (`RadarGuns` : 1 d'origine, 1 max), touche de pose (`PlaceKey`, G), commande `/restock` (`RestockCommand`, `RestockDistance`), trafic PNJ (`Cones.Traffic` : distance d'anticipation 10 m, regroupement, marge, décalage max, vitesses, zone de ralentissement, portée) |
| `LongGuns` | râtelier : types concernés, armes longues acceptées (`Groups`), emplacements (`Slots` : avant / coffre, `Where`), munitions données (`GiveAmmo`), fichier de sauvegarde, accessoires et noms en plus |

## Performance

- Hors service ou en véhicule : rien.
- À pied et en service : une recherche toutes les 500 ms (~0.01 ms) ; à chaque image seulement près d'une portière
  avant / du coffre (proposition) ou menu ouvert.
- Plots portés : une boucle à chaque image **seulement tant qu'ils sont dans les mains** (aide, touches bloquées) ;
  rappel du target quelques secondes après le dernier plot posé.
- Trafic PNJ : **aucune boucle sans plot posé** ; plots à plus de 200 m : réveil léger toutes les 250 ms (aucun calcul) ;
  dispositif à portée : vérification des véhicules proches toutes les 250 ms.
- Menu fermé avec Échap : quelques images de blocage du menu pause, puis plus rien.
- Serveur : aucune boucle.
