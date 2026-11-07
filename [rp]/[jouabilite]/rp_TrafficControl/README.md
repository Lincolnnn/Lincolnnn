# RP TrafficControl (FiveM, standalone)

**Gestion du trafic voie par voie**, sans framework (ni ESX, ni QBCore, ni vRP), menu NUI au style du MDC.

La plupart des scripts de trafic **suppriment les véhicules** autour du joueur. Celui-ci ne supprime **rien** : il agit
sur le **réseau routier du jeu** (les nœuds de circulation que suivent les PNJ) et dirige les PNJ concernés, sur un
**tronçon précis** : **une voie**, **un sens** ou **la route entière**.

## Comment GTA V représente les routes (et pourquoi c'est important)

- Une route n'a **qu'une seule ligne de nœuds**, au centre de la chaussée. Chaque liaison entre deux nœuds porte un
  **nombre de voies dans chaque sens** (et la largeur du terre-plein). **Il n'existe pas de nœud par voie.**
- Sur les **autoroutes / interstates**, chaque sens est une **chaussée séparée**, avec **ses propres nœuds**.

Le script en tient compte :

| Portée | Fermeture | Ralentissement / arrêt |
|---|---|---|
| **Voie** (ex. voie de gauche d'une interstate) | **plots virtuels** (invisibles, sans collision) : un **biseau** en amont puis une ligne le long de la voie ouverte, que les PNJ **contournent** ; les PNJ de cette voie **conduits en ligne droite sur la voie la plus proche du même sens** avant la zone ; **les autres voies du même sens ralentissent à 20 MPH**, progressivement. **Aucune voie du même sens** : ligne de plots en travers (arrêt) et **demi-tour** | **tout le sens** (la voie choisie **et** les autres voies de ce sens) : **périmètre en amont**, freinage **progressif** jusqu'à la limite / l'arrêt |
| **Sens** | chaussée séparée (autoroute) : **ses nœuds sont fermés** (l'autre sens n'est pas touché) ; route à double sens (nœuds partagés) : les PNJ de ce sens **recalculent leur route**, puis **font demi-tour** ; ligne de plots virtuels en travers au début | tout le sens, progressif depuis l'amont |
| **Route entière** | **tous les nœuds du tronçon fermés** (déviation par le jeu) + PNJ qui arrivent : route recalculée, puis demi-tour ; lignes de plots virtuels aux deux bouts | les deux sens, progressif depuis l'amont |

Les nœuds fermés ne sont plus empruntés par les PNJ (ni par le trafic qui apparaît). Les PNJ qui avaient déjà choisi
leur route sont dirigés à l'approche. Tout est **temporaire** (15 min, 30 min, 1 h, 2 h ou illimité) ; mesure levée :
réseau routier rendu **à l'original**, PNJ relâchés (route et vitesse normales).

**Mode nuit** (réglé dans le MDC : *Paramètres > MDC > Apparence*, appliqué à toutes les interfaces ou aux menus extérieurs) : **fond noir et couleur du mode nuit** (vert, jaune, rouge ou bleu) pour le menu de gestion du trafic (`client/theme.lua` ; sans le MDC : thème jour).

## Installation

1. Copier le dossier `rp_TrafficControl` dans `resources/`.
2. Dans `server.cfg` : `ensure rp_TrafficControl` (après le MDC).
3. (Facultatif) pour un groupe sans unité MDC : `add_ace group.admin rptraffic.admin allow`.

## Utilisation

- **`/trafic`** (policier en service, unité du MDC) : menu **Gestion du trafic**. Une nouvelle mesure se fait **dans
  cet ordre : d'abord la ZONE du trafic, ensuite l'ACTION** :
  1. **« Choisir la zone du trafic »** (portée : Voie / Sens / Route entière, modifiable ensuite ; **vue**) : le menu se
     ferme et on **vise la route** (jusqu'à 150 m). L'**aide** s'affiche **en haut à gauche dans un petit panneau de
     l'interface** (sans curseur), plus avec l'aide du jeu : celle-ci, trop longue, sortait coupée et empêchait l'aide des
     autres scripts de s'afficher (proposition du menu Équipement du véhicule…). **Trois vues** (choisies dans le menu,
     **V** pour changer pendant le choix) :
     - **Joueur** : la vue du jeu ; le personnage se déplace normalement ;
     - **Dessus** : caméra **50 m au-dessus** du joueur, regard vers le sol ; **ZQSD / WASD** : glisser, **souris** :
       tourner, **Espace / Ctrl** : monter / descendre (15 à 120 m), **Maj** : plus vite ;
     - **Libre** : caméra libre comme `/scene` et `/freecam` (souris, ZQSD / WASD, Espace / Ctrl, Maj) ;
     dessus et libre restent à **moins de 100 m du joueur** (`Editor.CameraRange`), le personnage ne bouge pas, une
     petite croix au centre de l'écran vise. Le script lit la route du jeu à l'endroit visé (voies par sens,
     terre-plein) :
     - **le côté visé choisit le sens**, **le point visé choisit la voie** (« voie de gauche (1/3), sens nord-est ») ;
     - **↑ ↓** : portée (voie / sens / route entière) ; **molette** : changer de voie (voie) ou élargir (route
       entière) ; **R** : inverser le sens (route à double sens) ;
     - **← →** : **décaler la bande** (par 0,25 m) pour l'**aligner sur les voies peintes** ; **Maj + ← →** : **largeur
       des voies** (par 0,1 m, gardée d'une pose à l'autre). La position des voies est calculée depuis la ligne de nœuds
       du jeu et une largeur de voie théorique : sur certaines routes elle ne tombe pas pile sur les voies peintes,
       d'où ce réglage, visible en direct grâce aux voies remplies. Après le premier E, la voie choisie ne change plus ;
     - **E** au début de la zone, **E** à la fin (dans n'importe quel ordre : le début est toujours placé du côté d'où
       arrive le trafic) ; **Retour arrière**, clic droit ou **Échap** : annuler (Échap n'ouvre pas le menu pause).
     - **Aperçu** : les **voies remplies au sol** (cases transparentes, `Editor.FillLanes`) : **bleu** la zone,
       **vert** les autres voies du même sens, **gris** l'autre sens ; contour et **flèche du sens** ; et les **nœuds
       du trafic** du jeu : **vert** ouvert, **orange** concerné, **jaune** partagé avec l'autre sens (les PNJ sont
       dirigés à la place), **rouge** déjà fermé.
  2. **Zone choisie** : elle **reste affichée dans le monde** et le panneau **« Action sur ce trafic »** s'ouvre, avec
     le résumé de la zone (lieu, voie / sens, longueur, nœuds du trafic) :
     - **Fermeture de voie** : **le trafic se réoriente vers une autre voie** (le panneau dit laquelle : « vers la
       voie centrale » ; aucune autre voie dans ce sens : demi-tour) ; **les autres voies du même sens ralentissent
       à 20 MPH** (`Closure.SideSlow`), pour que les PNJ ne se rabattent pas à pleine vitesse (dans le monde, ces
       voies passent en **orange**). Pour un sens / la route : **Fermeture du
       sens** / **de la route** (le trafic est dévié) ;
     - **Ralentissement** : vitesse (**− / +**, MPH) ;
     - **Ralentissement** et **Arrêt** portent sur **tout le sens** (voie choisie et autres voies du même sens ; route
       entière : les deux sens), avec un **périmètre en amont** : le trafic **freine progressivement** en arrivant
       (de 70 MPH 150 m avant jusqu'à la limite au début de la zone), il ne pile pas ;
     - **Arrêt du trafic** : le trafic freine progressivement et **s'arrête à une ligne de plots virtuels** en travers du
       sens, au début de la zone ;
     - **Durée** (15 min, 30 min, 1 h, 2 h, illimitée) ; **« Appliquer »** pose la mesure.
     La zone prend dans le monde la couleur de l'action choisie (rouge : fermeture, orange : ralentissement, rouge
     foncé : arrêt). Clavier : **1 / 2 / 3** choisissent l'action, **Entrée** applique. **« Rechoisir »** : retour à
     la visée de la route ; **« Annuler »** / **Échap** : la zone est abandonnée, rien n'est posé.
  - **Mesures actives** : lieu (rues d'Atlanta du MDC), voie / sens, longueur, auteur, temps restant ; **Repérer**
    (point GPS), **Lever** ; « Lever mes mesures » / « Tout lever ».
- **Carte** : bande de chaque mesure le long de la route, avec son nom (« Fermeture : voie de gauche »…).

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Command`, `Key` | commande (`trafic`), touche (aucune par défaut) |
| `PoliceOnly`, `AdminAce`, `MdcResource` | droits : policiers en service (unité du MDC) ou permission ACE |
| `MaxMeasures`, `MaxPerPlayer`, `Durations`, `DefaultDuration`, `RemoveOnDisconnect` | limites et durées |
| `Segment` | longueur min / max, **`LaneWidth`** (largeur de voie au départ ; Maj + ← → pendant le choix), `MinLaneWidth` / `MaxLaneWidth`, décalage max (`MaxShift`, ← →), hauteur, marge et nombre max de nœuds, largeur ajoutable (route entière) |
| `Closure` | zone fermée autour de chaque nœud, distances d'approche / de recalcul, vitesse et style de conduite pendant le changement de voie / le demi-tour, vitesse rendue, ralentissement des autres voies du sens (`SideSlow` 20 MPH) |
| `Obstacles` | faux obstacles (fermetures et plots) : modèle, espacement, place laissée libre, nombre max (par mesure, en tout, par vérification), portée, collision (non), rangée en travers (sens / route), `Debug`, plots (`Cones` : regroupement, espacement, nombre max) |
| `Speed` | limites MPH, rayon des zones de vitesse sur les nœuds, périmètre en amont (`Upstream` 150 m, `UpstreamStart` 70 MPH), arrêt avant la zone (`StopBefore`), marge du sens (`BandMargin`) |
| `VirtualCones` | plots virtuels : biseau, espacements, détection (12 m), marge, décalage max du passage, vitesse et style du contournement |
| `Editor` | portée de la visée, distance à la route, aperçu des nœuds, voies remplies (`FillLanes`), vues : portée des caméras (`CameraRange`, 100 m), vue du dessus (hauteur 50 m, min / max, champ, vitesse), caméra libre (vitesse) |
| `Blips`, `BlipColors` | qui voit les mesures sur la carte, couleurs |
| `Range`, `Interval` | PNJ gérés près des tronçons à moins de 400 m du joueur, toutes les 300 ms |

Console : **`trafficclear`** lève toutes les mesures.

## Fonctionnement et limites (à vérifier en jeu)

- Les nœuds et les zones de vitesse sont **propres au jeu de chaque joueur** : le serveur publie les mesures
  (`GlobalState.rpTraffic`) et chaque joueur les applique ; un PNJ est dirigé par le joueur qui le contrôle.
- Natives : `SetRoadsInArea` / `SetRoadsBackToOriginal` (une petite zone par nœud retenu), `AddRoadNodeSpeedZone` /
  `RemoveRoadNodeSpeedZone`, et les tâches de conduite des PNJ (`TaskVehicleDriveToCoord`, `…Longrange`,
  `TaskVehicleTempAction`, `SetDriveTaskCruiseSpeed`, `TaskVehicleDriveWander`).
- **Plots virtuels** (`VirtualCones`) : **invisibles, sans collision** (rien dans le monde), traités **comme les plots de
  la police** (qui marchent bien) : **les PNJ doivent les contourner ou s'arrêter devant, selon l'action** :
  - **fermeture d'une voie** (avec une voie ouverte à côté) : **biseau** de 30 m en amont (du bord extérieur de la voie
    fermée vers le bord de la voie ouverte), puis **ligne** le long de ce bord jusqu'à la fin : les PNJ **contournent** ;
  - **arrêt du trafic**, **sens / route fermés**, voie sans autre voie : **ligne en travers** du sens au début de la
    zone (route entière : aussi à la fin) : les PNJ **s'arrêtent** devant.
  Chaque plot virtuel porte un **faux obstacle** (`Obstacles` : véhicule du jeu de base, invisible, figé, **sans
  collision** : ni joueur ni PNJ ne heurte quoi que ce soit, l'œil et les tirs passent au travers) que l'**IA du jeu**
  contourne, pour tous les PNJ. Les PNJ que ce joueur contrôle suivent en plus **la logique des plots de la police** :
  un plot dans leur trajectoire à moins de 12 m -> passage le plus proche **sur la route** (voie voisine) s'il y en a
  un, sinon **arrêt** devant. Locaux (chaque joueur pose les siens, à moins de 220 m) ; une place prise par un vrai
  véhicule (police garée dans la voie…) est laissée libre. `Obstacles.Debug = true` : visibles en transparence.
- **Fermeture d'une voie, PNJ dirigés** : ceux que ce joueur contrôle sont conduits **en ligne droite** (style du jeu
  « ForceStraightLine », `Closure.MergeStyle`) vers un point de la voie ouverte **qui avance avec eux** (`MergeLead`,
  `PassLead`), jamais plus vite que les voies ralenties ; après la zone, ils reprennent leur route. Bloqués plus de
  25 s : relâchés (`PhaseTimeout`).
- **Fermeture d'une voie, autres voies** : les nœuds de la chaussée de ce sens (autoroute), dans la zone et 150 m en
  amont, reçoivent des **zones de vitesse du jeu progressives** (de 70 MPH à 20 MPH), et les PNJ des autres voies du
  sens sont ralentis de la même façon (`Closure.SideSlow`, `Speed.Upstream`).
- **Ralentissement / arrêt** (`Speed`) : **tout le sens** (bande de toutes ses voies, +1,5 m de marge : `BandMargin`),
  **périmètre en amont** de 150 m (`Upstream`) : la vitesse visée baisse **progressivement** de 70 MPH
  (`UpstreamStart`) jusqu'à la limite au début de la zone. Pour **tous les PNJ** : zones de vitesse du jeu sur les
  nœuds de ce sens (zone et amont, chacune à sa vitesse) ; pour les PNJ que ce joueur contrôle : vitesse redonnée à
  chaque vérification, **jamais au-dessus de leur vitesse à l'entrée** du périmètre (ils freinent, n'accélèrent pas).
  Arrêt : freinage progressif, arrêt 8 m avant la zone (`StopBefore`) et ligne de plots virtuels. (Avant, seuls les
  PNJ de la bande exacte et des 25 derniers mètres étaient ralentis, d'où un effet aléatoire selon la voie et la
  vitesse.) Une route à double sens (nœuds communs aux deux sens) ne peut pas être ralentie dans un seul sens par les
  nœuds : seuls les PNJ dirigés y ralentissent.
- **Plots de la police** (rp_equipment, posés depuis le coffre) : chaque **dispositif** (plots à moins de 6 m les uns
  des autres) reçoit des **faux obstacles tout le long de sa ligne** (tous les 3,5 m, dans l'axe de la ligne ; un plot
  seul : un obstacle dans le sens de la route) : les PNJ le traitent comme **infranchissable**, comme les zones du
  `/trafic` (`Obstacles.Cones`). La déviation des PNJ autour des plots reste celle de rp_equipment.
- Sur une route **en courbe**, faites plusieurs tronçons courts (la bande suit la ligne droite début → fin).
- Un demi-tour sur autoroute dépend du jeu (un PNJ ne traverse pas le terre-plein) : il repart vers l'arrière par le
  réseau routier.

## Performance

- Aucune mesure : **aucune boucle** (0.00 ms).
- Mesure à moins de 400 m du joueur : une vérification toutes les 300 ms des PNJ qu'il contrôle près des tronçons ;
  plus loin, une simple distance toutes les 2 s. Obstacles invisibles : posés peu à peu (6 au plus par vérification),
  seulement près du joueur ; « pas de collision » réglé une seule fois par paire obstacle / joueur.
- Choix de la zone : boucle à chaque image **seulement pendant le choix** et tant que la zone choisie est affichée
  (nœuds relus toutes les 400 ms).
- Menu : aucune boucle Lua. Serveur : aucune boucle (une minuterie par mesure).
