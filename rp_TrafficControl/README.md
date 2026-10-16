# RP TrafficControl (FiveM, standalone)

**Gestion du trafic par le réseau routier du jeu**, sans framework (ni ESX, ni QBCore, ni vRP), menu NUI au style
du MDC.

La plupart des scripts de trafic **suppriment les véhicules** dans un rayon autour du joueur. Celui-ci ne supprime
**rien** : il agit sur les **nœuds de circulation** du jeu (le réseau que suivent les PNJ et le GPS), comme le font
les missions de GTA :

| Mesure | Ce que fait le jeu |
|---|---|
| **Route barrée** (déviation) | les nœuds du tronçon sont **fermés** : les PNJ ne l'empruntent plus et **prennent une autre route** à l'intersection précédente ; aucun véhicule n'y apparaît. Ceux qui arrivent quand même (route déjà choisie) **recalculent leur route** à l'approche |
| **Limitation de vitesse** | zone de vitesse du jeu : les PNJ qui la traversent **ralentissent** (5 à 80 MPH) |
| **Arrêt du trafic** | zone de vitesse à 0 : les véhicules PNJ **s'arrêtent** dans la zone (accident, barrage filtrant) |

Tout est **temporaire** : levée automatique au bout de la durée choisie (15 min, 30 min, 1 h, 2 h) ou quand on la lève
(« Illimitée »). Le réseau routier revient alors **à l'original**.

## Installation

1. Copier le dossier `rp_TrafficControl` dans `resources/`.
2. Dans `server.cfg` : `ensure rp_TrafficControl` (après le MDC).
3. (Facultatif) pour un groupe sans unité MDC : `add_ace group.admin rptraffic.admin allow`.

## Utilisation

- **`/trafic`** (policier en service, unité du MDC) : menu **Gestion du trafic**.
  - **Nouvelle mesure** : Route barrée / Limitation de vitesse / Arrêt du trafic ; vitesse (MPH) et **durée**.
  - **Mesures actives** : lieu (noms des rues d'Atlanta du MDC), auteur, temps restant ; **Repérer** (point GPS) et
    **Lever** ; « Lever mes mesures » / « Tout lever ».
- Choisir une mesure ferme le menu et lance l'**outil de pose** (aide en haut à gauche) :
  - on **vise la route** (jusqu'à 150 m) : le point **s'accroche au milieu de la route** la plus proche
    (**Ctrl gauche** maintenu : pose libre) ;
  - **route barrée** : **E** au début du tronçon, **E** à la fin. Largeur de départ = **celle de la route visée**
    (nombre de voies du jeu), **molette** pour la régler ;
  - **limitation / arrêt** : **molette** pour le rayon, **← →** pour la vitesse, **E** pour poser ;
  - **Retour arrière**, clic droit ou **Échap** : annuler (Échap n'ouvre pas le menu pause).
- **Aperçu des nœuds** pendant la pose : les nœuds de circulation du jeu autour de la visée sont affichés —
  **vert** : ouvert, **orange** : sera fermé par ce tronçon, **rouge** : déjà fermé. Après la pose, ils passent au
  rouge : on voit tout de suite ce que les PNJ vont éviter.
- **Carte** (menu pause, mini-carte) : tronçons barrés (zone rouge le long de la route), limitations (cercle orange),
  arrêts (cercle rouge foncé), avec leur nom. `Blips` : `everyone`, `police` ou `none`.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Command`, `Key` | commande (`trafic`), touche (aucune par défaut) |
| `PoliceOnly`, `AdminAce`, `MdcResource` | droits : policiers en service (unité du MDC) ou permission ACE |
| `MaxMeasures`, `MaxPerPlayer` | mesures actives sur le serveur / par joueur |
| `Durations`, `DefaultDuration`, `RemoveOnDisconnect` | durées proposées (0 = illimitée), levée à la déconnexion |
| `Closure` | longueur min / max, largeur (auto selon les voies, min / max, pas), hauteur couverte (pentes, ponts), déviation intelligente (`SmartDetour`, `ApproachDistance`), `StopEntries` (arrêt du trafic aux deux bouts en plus) |
| `Speed` | limite par défaut / min / max / pas (MPH), rayon par défaut / min / max / pas |
| `Editor` | portée de la visée, accroche à la route, aperçu des nœuds |
| `Blips`, `BlipColors` | qui voit les mesures sur la carte, couleurs |
| `NodeNative`, `Range` | arguments avancés des natives des nœuds ; distance de la déviation intelligente |

Console : **`trafficclear`** lève toutes les mesures.

## Fonctionnement et limites (à vérifier en jeu)

- Les nœuds et les zones de vitesse sont **propres au jeu de chaque joueur** : le serveur publie les mesures
  (`GlobalState.rpTraffic`) et **chaque joueur les applique** chez lui ; les PNJ sont dirigés par le joueur dont le jeu
  les contrôle, donc tout le monde voit le même comportement.
- Natives utilisées : `SetRoadsInAngledArea` / `SetRoadsBackToOriginalInAngledArea` (nœuds), `AddRoadNodeSpeedZone` /
  `RemoveRoadNodeSpeedZone` (vitesse). Les arguments booléens de `SetRoadsInAngledArea` ne sont pas documentés
  officiellement : si les nœuds ne passent pas au rouge dans l'aperçu après la pose, essayez
  `NodeNative = { unknown1 = true }` (ou `network = true`).
- Un PNJ **déjà sur le tronçon** au moment de la fermeture le termine. Sur une route sans autre chemin (cul-de-sac
  créé par la fermeture), un PNJ peut s'arrêter devant : c'est une route barrée.
- Le **GPS** du jeu suit les mêmes nœuds : il devrait proposer un autre itinéraire (non vérifié).
- Si les PNJ ne réagissent pas comme prévu, une version plus simple (zones de vitesse seules, ou suppression
  ciblée) peut remplacer la fermeture des nœuds.

## Performance

- Aucune mesure : **aucune boucle** (0.00 ms).
- Route barrée à moins de 400 m du joueur : une vérification toutes les 500 ms des PNJ qu'il contrôle près du tronçon
  (déviation intelligente) ; plus loin, une simple distance toutes les 2 s.
- Outil de pose : boucle à chaque image **seulement pendant la pose** (nœuds relus toutes les 400 ms).
- Menu : aucune boucle Lua ; le temps restant est compté par l'interface.
- Serveur : aucune boucle (une minuterie par mesure).
