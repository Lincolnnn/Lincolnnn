# RP RoleplayZone (FiveM, standalone)

**Scènes de roleplay à fouiller**, préparées par les civils pour les policiers, sans framework (ni ESX, ni QBCore, ni
vRP). Menu NUI au style du MDC (mêmes couleurs que `rp_TrafficControl`), sons générés par l'interface (aucun fichier).

| Type | Ce que c'est | Ce que voit le policier |
|---|---|---|
| **Zone de recherche** | grand cercle de **15 à 60 m** | en y entrant : la **description du civil en haut au milieu de l'écran** (elle reste jusqu'à la sortie ou la suppression de la zone), un **court son d'intrigue**, le **cercle de la zone sur sa carte** (seulement pendant qu'il est dedans) ; en sortant : un son proche qui « lève » l'intrigue |
| **Périmètre à fouiller** | petit lieu (sol, recoin, dessous d'un escalier…), **0,5 à 5 m**, non lié à un objet | sur place : **E Fouiller les lieux** → barre de 6 s (X annule) → le contenu écrit par le civil |
| **Objet à fouiller** | un **props du décor** (poubelle, carton, benne, voiture épave…) | à côté : **E Fouiller l'objet** → barre de 6 s → le contenu |

Un périmètre ou un objet n'a pas besoin d'être dans une zone de recherche. Le contenu d'un périmètre / d'un objet
n'est jamais envoyé à l'avance aux joueurs : le serveur le donne au policier qui fouille, sur place.

## Installation

1. Copier le dossier `rp_RoleplayZone` dans `resources/`.
2. Dans `server.cfg` : `ensure rp_RoleplayZone` (après le MDC et `rp_interact`).
3. (Facultatif) administrateurs (créer en service, voir / supprimer toutes les scènes) :
   `add_ace group.admin rpscene.admin allow`.

## Civils : préparer une scène (`/scene`)

Réservé aux joueurs en **mode civil** (`rp_interact`, Menu F1 > Civil) qui ne sont pas dans une unité du MDC
(`Creators = 'everyone'` pour tout le monde).

1. **Le type** : Zone de recherche, Périmètre à fouiller ou Objet à fouiller.
2. **La sélection**, autour de soi (le menu se ferme) :
   - zone / périmètre : un **cercle blanc lumineux qui épouse le terrain** (sols, trottoirs, murs, toits, objets),
     comme l'indicateur de lancer de grenade de PUBG, suit le point visé ; **molette** : rayon ;
   - objet : l'objet du décor visé ressort en **contour blanc**, avec un cercle blanc à son pied ;
   - **E** pour choisir ; **Retour arrière**, clic droit ou **Échap** pour annuler (Échap n'ouvre pas le menu pause).
     Les scènes déjà posées autour sont dessinées en plus pâle.
3. **La description** : titre (facultatif), texte (message de la zone, ou ce que le policier trouvera), durée
   (30 min, 1 h, 2 h, 4 h ou illimitée) → **Créer**. « Replacer » refait la sélection.

**Mes scènes** : lieu, rayon, temps restant, nombre de fouilles et dernière unité qui a fouillé ; **Repérer** (point
GPS), **Modifier** (titre, texte, durée), **Supprimer**. Le civil est prévenu (message privé) quand sa scène est fouillée.

### Lâcher son arme (mode civil, touche G)

Réservé aux joueurs en **mode civil** (hors unité du MDC ; `Weapons.CivilOnly = false` : tout le monde).

1. Le joueur **sort une arme** : pendant **10 s**, un rappel en haut à gauche propose **« G Lâcher son arme »**. La
   touche reste utilisable **tout le temps** : le rappel n'apparaît qu'au début.
2. **G** : le texte change et propose la même touche pour **« Jeter son arme »**. La **molette** (haut ou bas)
   bascule sur **« Poser son arme au sol »** (et inversement). Pendant ce choix, les actions du jeu de base liées à la
   molette (changer d'arme, roue des armes, zoom de la lunette) sont **bloquées** : aucune double action.
   Retour arrière annule ; ranger ou changer d'arme annule aussi (et 10 s sans réponse).
3. **G** à nouveau : l'action choisie.
   - **Jeter** : geste de lancer, l'arme part de la main vers l'avant (là où regarde la caméra) et retombe au sol
     avec la physique du jeu, visible par tous ; elle est figée là où elle s'arrête.
   - **Poser** : l'arme est posée **couchée au sol**, devant le joueur.

L'arme au sol se récupère **uniquement avec l'œil de `rp_interact`** (Alt : « Arme au sol » → **Ramasser l'arme**, avec
ses munitions). Elle disparaît au bout de 60 min (`Weapons.Expire`). Les fusées, le jerrican et l'extincteur ne se
lâchent pas (`Weapons.Blacklist`). La touche se change dans Échap > Paramètres > Raccourcis clavier > FiveM.

## Policiers : l'œil d'aigle (Verr. Maj)

Policiers en service (unité du MDC). Touche **Verr. Maj** par défaut, comme la capacité spéciale du mode histoire
(H et J sont déjà pris par les emotes ; chaque joueur peut la changer dans Échap > Paramètres > Raccourcis clavier >
FiveM, ou utiliser `/oeildaigle`). Une utilisation toutes les 6 s.

- Un court son de « sonar » et un effet d'écran (teinte froide, `FocusIn` / `FocusOut`).
- Une **onde radar** part du joueur et s'éloigne jusqu'à **15 m** en 1,4 s : un cercle blanc lumineux qui épouse le
  terrain. Chaque **objet** et chaque **véhicule** qu'elle atteint ressort en **contour blanc** un court instant.
- Ce qui est **à fouiller** dans ces 15 m (objet à fouiller, arme lâchée : contour ; périmètre : cercle lumineux et
  une lueur) reste en surbrillance **4 s au maximum**.
- **Hors d'une zone de recherche** : la zone la plus proche (à moins de **100 m** de son bord) est **pointée** : la
  caméra se tourne et zoome vers elle (comme le mode histoire) et une **flèche directionnelle** s'affiche au milieu
  de l'écran avec la distance.
- **Dans une zone** : la flèche pointe la fouille la plus proche située au-delà de 15 m (`Eagle.InZoneArrow`).

## Rien ne disparaît autour des scènes

Tant qu'une scène existe, autour d'elle (zone : tout son cercle ; périmètre / objet : 10 m), les **objets du décor**,
les **PNJ** et les **véhicules stationnés** sont marqués comme **entités de mission** : un « ClearArea » lancé par un
autre script ne les retire plus. L'**objet à fouiller** est en plus **remis à sa place** (copie fixe) s'il disparaît
quand même. PNJ sortis de la scène, scène supprimée : tout est rendu au jeu.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Command`, `Key` | `/scene` (aucune touche par défaut) |
| `Creators`, `Searchers`, `AdminAce` | qui crée (`'civil'` / `'everyone'`), qui fouille (`'police'` / `'everyone'`), permission admin |
| `MaxScenes`, `MaxPerPlayer`, `Durations`, `DefaultDuration`, `RemoveOnDisconnect` | limites et durées |
| `TitleLength`, `TextLength` | longueur du titre (40) et du texte (500) |
| `Zone`, `Perimeter`, `Object` | rayons min / max / par défaut / pas de la molette ; distance de fouille d'un objet |
| `Search` | durée de la fouille, scénarios joués, durée de la fiche, `/me` automatique, civil prévenu |
| `ZoneBlip`, `Sounds` | couleur / transparence du cercle sur la carte, volume des sons |
| `Selector` | portée de la visée, épaisseur du cercle blanc |
| `Eagle` | touche, rayon (15 m), durées (onde, contours, 4 s pour les fouilles), caméra (100 m, zoom), flèche, effets d'écran |
| `Protect` | protection contre les « ClearArea » : rayon, objets / PNJ / véhicules stationnés, objet remis |
| `Weapons` | lâcher son arme : mode civil, touche (G), rappel (10 s), choix, force du lancer, geste, durée au sol, nombre par joueur, armes exclues |

Console : **`sceneclear`** supprime toutes les scènes.

## Liens avec les autres ressources

- **MDC** : policier = joueur dans une unité (`getPlayerUnit`) ; lieux avec les rues d'Atlanta (`GetLocationText`).
- **rp_interact** : mode civil (état `rpiCivilMode`) ; arme au sol ramassée à l'œil, seule façon de la récupérer (`ExternalObjects.rpDroppedWeapon`).
- **rp_chat** : messages privés (contenu trouvé, scène fouillée) et `/me` automatique (« fouille les lieux »).

## Fonctionnement et limites (à vérifier en jeu)

- **Contours** : `SetEntityDrawOutline` ne s'applique qu'aux **entités** (objets, véhicules). Les **murs et sols de la
  carte** ne sont pas des entités : l'onde radar (le cercle qui épouse le terrain) est dessinée sur eux à la place.
- **Protection** : une entité de mission résiste aux `ClearArea*` des autres scripts, mais pas à un `DeleteEntity`
  direct ; un PNJ / véhicule n'est marqué que par le joueur qui le contrôle (les objets du décor, par chaque joueur).
- Les effets d'écran (`hud_def_desat_cold`, `FocusIn`, `FocusOut`) et la caméra du mode histoire
  (`SetGameplayCoordHint`) sont réglables (`Eagle`) : à ajuster selon le rendu en jeu.
- Arme posée : couchée selon les dimensions de son modèle (côté le plus fin à la verticale). Arme jetée : l'élan est
  donné par le jeu du joueur qui la jette (s'il n'a pas la main sur l'objet, elle est posée devant lui) ; le geste
  (`anim@heists@narcotics@trash`, `throw_b`) et le moment où l'arme quitte la main (`ThrowRelease`) sont à ajuster.
- Scènes gardées en mémoire du serveur : elles disparaissent au redémarrage.

## Performance

- Aucune scène : **aucune boucle** (0.00 ms).
- Scènes : une vérification toutes les 500 ms (distances) ; protection toutes les 2 s, seulement à moins de 150 m.
- Boucle à chaque image seulement : à côté d'une fouille (aide « E »), pendant une fouille, pendant la sélection,
  pendant l'œil d'aigle (quelques secondes), pendant le rappel / le choix de l'arme.
- Arme en main vérifiée toutes les 250 ms en mode civil (toutes les 2 s sinon).
- Menu : aucune boucle Lua. Serveur : aucune boucle (une minuterie par scène / par arme).
