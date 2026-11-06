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
| **Voie** (ex. voie de gauche d'une interstate) | **obstacles invisibles** le long de la voie fermée (que les PNJ du jeu contournent et ne peuvent pas traverser) **et** les PNJ de cette voie **conduits en ligne droite sur la voie la plus proche du même sens** avant le tronçon, qu'ils longent, puis reprennent leur route. **Aucune voie du même sens** : **demi-tour** | seuls les PNJ de cette voie ralentissent / s'arrêtent, les autres voies circulent |
| **Sens** | chaussée séparée (autoroute) : **ses nœuds sont fermés** (l'autre sens n'est pas touché) ; route à double sens (nœuds partagés) : les PNJ de ce sens **recalculent leur route**, puis **font demi-tour** | zones de vitesse du jeu sur les nœuds de la chaussée + PNJ de ce sens |
| **Route entière** | **tous les nœuds du tronçon fermés** (déviation par le jeu) + PNJ qui arrivent : route recalculée, puis demi-tour | zones de vitesse sur les nœuds + PNJ des deux sens |

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
  1. **« Choisir la zone du trafic »** (portée : Voie / Sens / Route entière, modifiable ensuite) : le menu se ferme et
     on **vise la route** (jusqu'à 150 m, aide en haut à gauche). Le script lit la route du jeu à cet endroit (voies
     par sens, terre-plein) :
     - **le côté visé choisit le sens**, **le point visé choisit la voie** (« voie de gauche (1/3), sens nord-est ») ;
     - **↑ ↓** : portée (voie / sens / route entière) ; **molette** : changer de voie (voie) ou élargir (route
       entière) ; **R** : inverser le sens (route à double sens) ;
     - **E** au début de la zone, **E** à la fin (dans n'importe quel ordre : le début est toujours placé du côté d'où
       arrive le trafic) ; **Retour arrière**, clic droit ou **Échap** : annuler (Échap n'ouvre pas le menu pause).
     - **Aperçu** : la zone en **bleu** avec une **flèche du sens**, et les **nœuds du trafic** du jeu : **vert**
       ouvert, **orange** concerné, **jaune** partagé avec l'autre sens (les PNJ sont dirigés à la place), **rouge**
       déjà fermé.
  2. **Zone choisie** : elle **reste affichée dans le monde** et le panneau **« Action sur ce trafic »** s'ouvre, avec
     le résumé de la zone (lieu, voie / sens, longueur, nœuds du trafic) :
     - **Fermeture de voie** : **le trafic se réoriente vers une autre voie** (le panneau dit laquelle : « vers la
       voie centrale » ; aucune autre voie dans ce sens : demi-tour). Pour un sens / la route : **Fermeture du
       sens** / **de la route** (le trafic est dévié) ;
     - **Ralentissement** : vitesse (**− / +**, MPH) ;
     - **Arrêt du trafic** : le trafic s'arrête avant la zone ;
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
| `Segment` | longueur min / max, **`LaneWidth`** (largeur d'une voie du jeu, à ajuster avec l'aperçu), hauteur, marge et nombre max de nœuds, largeur ajoutable (route entière) |
| `Closure` | zone fermée autour de chaque nœud, distances d'approche / de recalcul, vitesse et style de conduite pendant le changement de voie / le demi-tour, vitesse rendue |
| `Obstacles` | obstacles invisibles des fermetures : modèle, espacement, place laissée libre, nombre max (par mesure, en tout, par vérification), portée, collision, rangée en travers (sens / route), `Debug` |
| `Speed` | limites MPH, rayon des zones de vitesse sur les nœuds, distances de ralentissement / d'arrêt avant le tronçon |
| `Editor` | portée de la visée, distance à la route, aperçu des nœuds |
| `Blips`, `BlipColors` | qui voit les mesures sur la carte, couleurs |
| `Range`, `Interval` | PNJ gérés près des tronçons à moins de 400 m du joueur, toutes les 300 ms |

Console : **`trafficclear`** lève toutes les mesures.

## Fonctionnement et limites (à vérifier en jeu)

- Les nœuds et les zones de vitesse sont **propres au jeu de chaque joueur** : le serveur publie les mesures
  (`GlobalState.rpTraffic`) et chaque joueur les applique ; un PNJ est dirigé par le joueur qui le contrôle.
- Natives : `SetRoadsInArea` / `SetRoadsBackToOriginal` (une petite zone par nœud retenu), `AddRoadNodeSpeedZone` /
  `RemoveRoadNodeSpeedZone`, et les tâches de conduite des PNJ (`TaskVehicleDriveToCoord`, `…Longrange`,
  `TaskVehicleTempAction`, `SetDriveTaskCruiseSpeed`, `TaskVehicleDriveWander`).
- **Voie** : il n'y a pas de nœud par voie dans le jeu. La fermeture d'une voie se fait donc par deux moyens, ensemble :
  - **Obstacles invisibles** (`Obstacles`) : des **véhicules du jeu de base** (`blista`), **invisibles, figés, sans
    conducteur, portes verrouillées**, posés **tous les 7 m le long de la voie fermée** (sens / route fermés : une rangée
    **en travers** au début du tronçon). C'est un comportement d'**origine** du jeu : un PNJ qui arrive sur un véhicule
    arrêté **change de voie pour le contourner** (style de conduite normal du trafic : « changer de voie autour d'un
    obstacle », « contourner les véhicules arrêtés ») ; et avec la **collision**, il **ne peut pas passer au travers**.
    Ça marche aussi pour les PNJ que ce script ne dirige pas (contrôlés par un autre joueur, apparus en route). Ils sont
    **locaux** (chaque joueur pose les siens, seulement à moins de 220 m du tronçon, quelques-uns par vérification) ; une
    place déjà prise (voiture de police garée dans la voie…) est laissée libre. **Les joueurs ne les touchent jamais**
    (ni à pied ni en véhicule : pas de collision avec eux), l'**œil** de rp_interact **passe au travers**, et `/dv`,
    l'inspection, la pompe à essence, « véhicule le plus proche » de rp_interact les ignorent (véhicules invisibles).
    `Obstacles.Debug = true` : visibles en transparence, pour régler `LaneWidth` / `Spacing`.
  - **PNJ dirigés** : ceux que ce joueur contrôle sont conduits **en ligne droite** (style du jeu « ForceStraightLine »,
    `Closure.MergeStyle`) vers un point de la voie ouverte **qui avance avec eux** (`MergeLead`, `PassLead`) : sinon le
    suivi de route du jeu les garde sur leur voie jusqu'au point visé (c'est pour ça que la fermeture de voie ne
    marchait pas). Ils s'arrêtent toujours pour un véhicule ou un piéton devant eux ; après le tronçon, ils reprennent
    leur route. Bloqués plus de 25 s : relâchés (`PhaseTimeout`).
- **Ralentissement** : la vitesse limite est redonnée au PNJ **à chaque vérification** (une autre tâche du jeu la
  remettait à la vitesse normale), en plus des zones de vitesse du jeu.
  La position des voies vient du nombre de voies du jeu et de `LaneWidth` : vérifiez avec l'aperçu que la bande tombe
  bien sur la voie, et ajustez `LaneWidth` si besoin.
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
