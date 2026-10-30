# RP RoleplayZone (FiveM, standalone)

**Scènes de roleplay à fouiller**, préparées par les civils pour les policiers, sans framework (ni ESX, ni QBCore, ni
vRP). Menu NUI au style du MDC (mêmes couleurs que `rp_TrafficControl`), sons générés par l'interface (aucun fichier).

| Type | Ce que c'est | Ce que voit le policier |
|---|---|---|
| **Zone de recherche** | grand cercle de **15 à 60 m** | en y entrant : la **description du civil en haut au milieu de l'écran** (elle reste jusqu'à la sortie ou la suppression de la zone), un **court son d'intrigue**, le **cercle de la zone sur sa carte** (seulement pendant qu'il est dedans) ; en sortant : un son proche qui « lève » l'intrigue |
| **Périmètre à fouiller** | petit lieu (sol, recoin, dessous d'un escalier…), **0,5 à 5 m**, non lié à un objet | avec l'**œil** (Alt) sur le sol du périmètre : **Fouiller les lieux** → barre de **6 s** (le plus petit) à **30 s** (le plus grand), selon la taille → le contenu écrit par le civil |
| **Objet ou véhicule à fouiller** | un **props du décor** (poubelle, carton, benne…) ou un **véhicule** (suivi même s'il bouge) | avec l'**œil** sur l'objet / le véhicule : **Fouiller l'objet / le véhicule** → barre de **8 s** → le contenu |

Pendant la barre, **X** annule. Fouille terminée : l'animation **continue** jusqu'à ce que le policier appuie sur
**X**. Un périmètre / un objet peut aussi avoir une **description visuelle** (ce qu'on voit) : elle s'affiche
**au-dessus** du lieu / de l'objet aux policiers à **moins de 10 m** qui le **voient** (rien entre leur caméra et lui :
derrière un mur, même à 10 m, elle n'apparaît pas). Un périmètre ou un objet n'a pas besoin d'être dans une zone de
recherche. Le contenu d'une fouille n'est jamais envoyé à l'avance aux joueurs : le serveur le donne au policier qui
fouille, sur place. Sans `rp_interact` (pas d'œil) : « E Fouiller » sur place (`Search.PromptWithoutTarget`).

## Installation

1. Copier le dossier `rp_RoleplayZone` dans `resources/`.
2. Dans `server.cfg` : `ensure rp_RoleplayZone` (après le MDC et `rp_interact`).
3. (Facultatif) administrateurs (créer en service, voir / supprimer toutes les scènes) :
   `add_ace group.admin rpscene.admin allow`.

**Mode nuit** (réglé dans le MDC : *Paramètres > MDC > Apparence*, appliqué à toutes les interfaces ou aux menus extérieurs) : **fond noir et couleur du mode nuit** (vert, jaune, rouge ou bleu) pour le menu `/scene` et les affichages sur le jeu (zone de recherche, flèche, fouille, résultats) (`client/theme.lua` ; sans le MDC : thème jour).

## Civils : préparer une scène (`/scene`)

Réservé aux joueurs en **mode civil** (`rp_interact`, Menu F1 > Civil) qui ne sont pas dans une unité du MDC
(`Creators = 'everyone'` pour tout le monde).

1. **Le type** : Zone de recherche, Périmètre à fouiller ou Objet / véhicule à fouiller, et la **vue** pour choisir :
   **Personnage** (la vue du jeu) ou **Caméra libre** (on se balade dans les environs sans déplacer son personnage,
   jusqu'à 60 m de lui : souris pour regarder, Z/Q/S/D ou W/A/S/D, Espace / Ctrl pour monter / descendre, Maj plus
   vite). **V** change de vue pendant la sélection.
2. **La sélection**, autour de soi (le menu se ferme) :
   - zone / périmètre : un **cercle blanc lumineux qui épouse le terrain** (sols, trottoirs, murs, toits, objets),
     comme l'indicateur de lancer de grenade de PUBG, suit le point visé ; **molette** : rayon ;
   - objet : l'objet du décor ou le **véhicule** visé ressort en **contour blanc**, avec un cercle blanc à son pied ;
   - **E** pour choisir ; **Retour arrière**, clic droit ou **Échap** pour annuler (Échap n'ouvre pas le menu pause).
     Les scènes déjà posées autour sont dessinées en plus pâle.
3. **La description** : titre (facultatif), texte (message de la zone, ou **ce que le policier trouvera** en
   fouillant), **description visuelle** (périmètre / objet : ce qu'on voit, affichée au-dessus ; l'un des deux au
   moins), durée (30 min, 1 h, 2 h, 4 h ou illimitée) → **Créer**. « Replacer » refait la sélection.

**Mes scènes** : lieu, rayon, temps restant, nombre de fouilles et dernière unité qui a fouillé ; **Repérer** (point
GPS), **Modifier** (titre, textes, durée), **Supprimer**. Avec l'**œil**, **en mode civil** (hors unité du MDC) et
dans le **secteur** de sa scène (la zone ou le lieu / l'objet + **70 m** autour, `Protect.AreaMargin`) : **Modifier la
description** sur son propre périmètre / objet, **Modifier la zone de recherche** en visant le sol de sa zone ou de ses
alentours (ouvre directement la scène). Le civil est prévenu (message privé) quand sa scène est fouillée.

### Lâcher son arme (mode civil, touche G)

Réservé aux joueurs en **mode civil** (hors unité du MDC ; `Weapons.CivilOnly = false` : tout le monde).

L'arme **quitte les mains tout de suite** (au moment du geste), avec ses munitions ; si le serveur refuse (trop
d'armes au sol, endroit impossible…), elle est **rendue**. Un autre script qui rendrait l'arme entre-temps est
contré (elle est retirée encore une fois à la confirmation).

1. Le joueur **sort une arme** : pendant **10 s**, un rappel en haut à gauche (au thème du HUD, avec la vraie touche
   du joueur) propose **« G Lâcher son arme »**. La touche reste utilisable **tout le temps** : le rappel n'apparaît
   qu'au début. Les actions du jeu sur G (grenade, détonateur) sont bloquées pendant le rappel et le choix.
2. **G** : le texte change et propose la même touche pour **« Jeter son arme »**. La **molette** (haut ou bas)
   bascule sur **« Poser son arme au sol »** (et inversement). Pendant ce choix, les actions du jeu de base liées à la
   molette (changer d'arme, roue des armes, zoom de la lunette) sont **bloquées** : aucune double action.
   Retour arrière annule ; ranger ou changer d'arme annule aussi (et 10 s sans réponse).
3. **G** à nouveau : l'action choisie.
   - **Jeter** : geste de lancer, l'arme part de la main vers l'avant (là où regarde la caméra) et retombe au sol
     avec la physique du jeu, visible par tous ; elle est figée là où elle s'arrête.
   - **Poser** : l'arme est posée **couchée au sol**, devant le joueur.

L'arme au sol se récupère **uniquement avec l'œil de `rp_interact`**, par **tout le monde** (Alt : « Arme au sol » →
**Ramasser l'arme**, avec ses munitions) : il suffit de viser le sol juste à côté (une arme couchée est très fine). Elle disparaît au bout de 60 min (`Weapons.Expire`). Les fusées, le jerrican et l'extincteur ne se
lâchent pas (`Weapons.Blacklist`). La touche se change dans Échap > Paramètres > Raccourcis clavier > FiveM.

## Policiers : l'œil d'aigle (Verr. Maj)

Policiers en service (unité du MDC). Touche **Verr. Maj** par défaut, comme la capacité spéciale du mode histoire
(H et J sont déjà pris par les emotes ; chaque joueur peut la changer dans Échap > Paramètres > Raccourcis clavier >
FiveM, ou utiliser `/oeildaigle`). Une utilisation toutes les 6 s.

- Un court son de « sonar » et un effet d'écran (teinte froide, `FocusIn` / `FocusOut`).
- Une **onde radar** part du joueur et s'éloigne jusqu'à **15 m** en 1,4 s en **clignotant** : un cercle blanc
  lumineux qui épouse le terrain. Chaque **objet** et chaque **véhicule** qu'elle atteint ressort en **contour blanc**
  un court instant.
- Ce qui est **à fouiller** dans ces 15 m (objet / véhicule à fouiller, arme au sol : contour ; périmètre : cercle
  lumineux et une lueur) reste en surbrillance **plus longtemps (5,2 s)** et **bat comme un cœur** : la couleur passe
  **progressivement** du blanc au jaune pâle (`Eagle.SearchColor`) et revient, deux pulsations douces puis un repos
  (`Eagle.Heartbeat`, 1,3 s) ; rien n'apparaît ni ne disparaît d'un coup (le contour s'éteint doucement à la fin).
  La couleur des contours du jeu est la même pour tout l'écran : tant que des contours blancs ordinaires sont encore
  affichés, le jaune monte dans une **boîte** autour de l'objet ; ensuite, c'est son contour qui prend la couleur.
- **Hors d'une zone de recherche** : la zone la plus proche (à moins de **100 m** de son bord) est **pointée** : la
  caméra se tourne et zoome vers elle (comme le mode histoire) et une **flèche directionnelle** s'affiche au milieu
  de l'écran avec la distance.
- **Dans une zone** : la flèche pointe la fouille la plus proche située au-delà de 15 m (`Eagle.InZoneArrow`).

## Rien ne disparaît autour des scènes

Tant qu'une scène existe, autour d'elle (zone : tout son cercle ; périmètre / objet : 10 m), les **objets du décor**,
les **PNJ** et les **véhicules stationnés** sont marqués comme **entités de mission** : un « ClearArea » lancé par un
autre script ne les retire plus. L'**objet à fouiller** est en plus **remis à sa place** (copie fixe) s'il disparaît
quand même. PNJ sortis de la scène, scène supprimée : tout est rendu au jeu.
Dans le **secteur** d'une scène (zone / lieu / objet + **70 m**), l'œil de `rp_interact` ne propose plus
**« Supprimer »** (véhicules, objets) ni **« Supprimer le props »**, et son serveur les refuse (export
`isProtectedArea(coords)`, client et serveur).

## Sessions : `/sessionon`, `/sessionoff`

Un message pour **tous les joueurs**, en haut au milieu de l'écran (même style que l'entrée dans une zone de
recherche, en dessous si une zone est déjà affichée), avec un **son de message reçu**, pendant 12 s
(`Session.Duration`) :
- **`/sessionon`** : « Début de la session : départ des patrouilles et début des interventions. »
- **`/sessionoff`** : « Fin de session : terminez vos interactions dans le calme, les patrouilles rentrent aux
  stations. »

Réservé à la permission ACE **`rpsession`** (ex. `add_ace group.admin rpsession allow`) ou à `AdminAce` ; la console du
serveur peut aussi. Textes, titres et commandes : `Session` dans `config.lua`.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Command`, `Key` | `/scene` (aucune touche par défaut) |
| `Creators`, `Searchers`, `AdminAce` | qui crée (`'civil'` / `'everyone'`), qui fouille (`'police'` / `'everyone'`), permission admin |
| `MaxScenes`, `MaxPerPlayer`, `Durations`, `DefaultDuration`, `RemoveOnDisconnect` | limites et durées |
| `TitleLength`, `TextLength` | longueur du titre (40) et du texte (500) |
| `Zone`, `Perimeter`, `Object` | rayons min / max / par défaut / pas de la molette ; distance de fouille d'un objet |
| `Search` | durées (objet / véhicule 8 s ; périmètre 6 à 30 s), touche X, scénarios (lieu, objet, véhicule), « E » sans rp_interact, fiche, `/me`, civil prévenu |
| `Look`, `LookLength` | description visuelle : distance (10 m), vérification de la vue, taille, couleur, longueur |
| `ZoneBlip`, `Sounds` | couleur / transparence du cercle sur la carte, volume des sons |
| `Selector` | portée de la visée, épaisseur du cercle blanc, vue par défaut (`Camera`), caméra libre (portée, vitesse), touche V |
| `Eagle` | touche, rayon (15 m), durées (onde, contours, 5,2 s pour les fouilles), jaune pâle et battement (`Heartbeat`), caméra (100 m, zoom), flèche, effets d'écran |
| `Protect` | protection contre les « ClearArea » : rayon, objets / PNJ / véhicules stationnés, objet remis ; secteur (`AreaMargin`, 70 m) |
| `Weapons` | lâcher son arme : mode civil, touche (G), rappel (10 s), choix, force du lancer, geste, durée au sol, nombre par joueur, armes exclues |

Console : **`sceneclear`** supprime toutes les scènes.

## Liens avec les autres ressources

- **MDC** : policier = joueur dans une unité (`getPlayerUnit`) ; lieux avec les rues d'Atlanta (`GetLocationText`).
- **rp_interact** : mode civil (état `rpiCivilMode`) ; arme au sol ramassée à l'œil, seule façon de la récupérer
  (`ExternalObjects.rpDroppedWeapon`) ; fouilles et « Modifier la description » à l'œil (`TargetProviders` de
  rp_interact : exports `targetOptions` / `targetSelect` de ce script, y compris sur un point du sol).
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
- Scènes gardées en mémoire du serveur : elles disparaissent au redémarrage. Un véhicule à fouiller supprimé emporte
  sa scène avec lui.
- Description visuelle : texte du jeu dessiné au-dessus du point (vue vérifiée toutes les 250 ms par un rayon depuis
  la caméra) ; caméra libre : caméra de script (`CreateCam`), à vérifier en jeu (sensibilité de la souris).

## Performance

- Aucune scène : **aucune boucle** (0.00 ms).
- Scènes : une vérification toutes les 500 ms (distances) ; protection toutes les 2 s, seulement à moins de 150 m.
- Boucle à chaque image seulement : pendant une fouille, à moins de 10 m d'une description visuelle, pendant la sélection,
  pendant l'œil d'aigle (quelques secondes), pendant le rappel / le choix de l'arme.
- Arme en main vérifiée toutes les 250 ms en mode civil (toutes les 2 s sinon).
- Menu : aucune boucle Lua. Serveur : aucune boucle (une minuterie par scène / par arme).
