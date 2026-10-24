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
| **Voie** (ex. voie de gauche d'une interstate) | les PNJ de cette voie se **rabattent avant le tronçon sur la voie la plus proche du même sens**, la longent, puis reprennent leur route. **Aucune voie du même sens** : **demi-tour** | seuls les PNJ de cette voie ralentissent / s'arrêtent, les autres voies circulent |
| **Sens** | chaussée séparée (autoroute) : **ses nœuds sont fermés** (l'autre sens n'est pas touché) ; route à double sens (nœuds partagés) : les PNJ de ce sens **recalculent leur route**, puis **font demi-tour** | zones de vitesse du jeu sur les nœuds de la chaussée + PNJ de ce sens |
| **Route entière** | **tous les nœuds du tronçon fermés** (déviation par le jeu) + PNJ qui arrivent : route recalculée, puis demi-tour | zones de vitesse sur les nœuds + PNJ des deux sens |

Les nœuds fermés ne sont plus empruntés par les PNJ (ni par le trafic qui apparaît). Les PNJ qui avaient déjà choisi
leur route sont dirigés à l'approche. Tout est **temporaire** (15 min, 30 min, 1 h, 2 h ou illimité) ; mesure levée :
réseau routier rendu **à l'original**, PNJ relâchés (route et vitesse normales).

**Mode nuit** (réglé dans le MDC : *Paramètres > MDC > Apparence*, appliqué à toutes les interfaces ou aux menus extérieurs) : **vert sur fond noir** pour le menu de gestion du trafic (`client/theme.lua` ; sans le MDC : thème jour).

## Installation

1. Copier le dossier `rp_TrafficControl` dans `resources/`.
2. Dans `server.cfg` : `ensure rp_TrafficControl` (après le MDC).
3. (Facultatif) pour un groupe sans unité MDC : `add_ace group.admin rptraffic.admin allow`.

## Utilisation

- **`/trafic`** (policier en service, unité du MDC) : menu **Gestion du trafic**.
  - **Portée** : Voie / Sens / Route entière ; **mesure** : Fermeture / Ralentissement / Arrêt du trafic ; vitesse
    (MPH) et **durée**.
  - **Mesures actives** : lieu (rues d'Atlanta du MDC), voie / sens, longueur, auteur, temps restant ; **Repérer**
    (point GPS), **Lever** ; « Lever mes mesures » / « Tout lever ».
- **Outil de pose** (aide en haut à gauche) : on **vise la route** (jusqu'à 150 m) ; le script lit la route du jeu à
  cet endroit (voies par sens, terre-plein) :
  - **le côté visé choisit le sens**, **le point visé choisit la voie** (« voie de gauche (1/3), sens nord-est ») ;
  - **↑ ↓** : portée (voie / sens / route entière) ; **molette** : changer de voie (voie) ou élargir (route
    entière) ; **← →** : vitesse (ralentissement) ; **R** : inverser le sens (route à double sens) ;
  - **E** au début du tronçon, **E** à la fin (dans n'importe quel ordre : le début est toujours placé du côté d'où
    arrive le trafic) ; **Retour arrière**, clic droit ou **Échap** : annuler (Échap n'ouvre pas le menu pause).
- **Aperçu** : la **bande concernée** (rouge : fermeture, orange : ralentissement, rouge foncé : arrêt) avec une
  **flèche du sens**, et les **nœuds du jeu** : **vert** ouvert, **orange** concerné (sera fermé / ralenti),
  **jaune** partagé avec l'autre sens (non fermé : les PNJ sont dirigés à la place), **rouge** déjà fermé.
- **Carte** : bande de chaque mesure le long de la route, avec son nom (« Fermeture : voie de gauche »…).

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Command`, `Key` | commande (`trafic`), touche (aucune par défaut) |
| `PoliceOnly`, `AdminAce`, `MdcResource` | droits : policiers en service (unité du MDC) ou permission ACE |
| `MaxMeasures`, `MaxPerPlayer`, `Durations`, `DefaultDuration`, `RemoveOnDisconnect` | limites et durées |
| `Segment` | longueur min / max, **`LaneWidth`** (largeur d'une voie du jeu, à ajuster avec l'aperçu), hauteur, marge et nombre max de nœuds, largeur ajoutable (route entière) |
| `Closure` | zone fermée autour de chaque nœud, distances d'approche / de recalcul, vitesse et style de conduite pendant le changement de voie / le demi-tour, vitesse rendue |
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
- **Voie** : il n'y a pas de nœud par voie dans le jeu ; la fermeture d'une voie se fait donc en **rabattant les PNJ**.
  La position des voies vient du nombre de voies du jeu et de `LaneWidth` : vérifiez avec l'aperçu que la bande tombe
  bien sur la voie, et ajustez `LaneWidth` si besoin.
- Sur une route **en courbe**, faites plusieurs tronçons courts (la bande suit la ligne droite début → fin).
- Un demi-tour sur autoroute dépend du jeu (un PNJ ne traverse pas le terre-plein) : il repart vers l'arrière par le
  réseau routier.

## Performance

- Aucune mesure : **aucune boucle** (0.00 ms).
- Mesure à moins de 400 m du joueur : une vérification toutes les 300 ms des PNJ qu'il contrôle près des tronçons ;
  plus loin, une simple distance toutes les 2 s.
- Outil de pose : boucle à chaque image **seulement pendant la pose** (nœuds relus toutes les 400 ms).
- Menu : aucune boucle Lua. Serveur : aucune boucle (une minuterie par mesure).
