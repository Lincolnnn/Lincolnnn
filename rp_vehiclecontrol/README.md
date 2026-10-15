# Vehicle Control (`rp_vehiclecontrol`)

Gestion des véhicules **100% standalone** (sans ESX / QBCore / vRP) : essence, dégâts réalistes, ceinture de
sécurité, moteur toujours allumé, portières depuis l'intérieur, clignotants et poussée. Lié aux HUD du MDC
(`mdc_standalone`) : le **car HUD** (au-dessus de la minimap, à côté du PLD) est dessiné et réglé dans le MDC
(*Paramètres > HUD & Display* : position, taille, éléments affichés, volume de la ceinture).

## Installation

1. Copiez le dossier `rp_vehiclecontrol` dans `resources/` (à côté du MDC, pas à l'intérieur).
2. Dans `server.cfg`, après le MDC et le chat : `ensure rp_vehiclecontrol`
3. **OneSync** recommandé (l'état des véhicules est partagé entre les joueurs).

Sans le MDC, tout fonctionne mais le car HUD n'est pas affiché. Sans `rp_chat`, les messages « Portière ouverte. »
passent par le chat d'origine.

## Touches (par défaut, modifiables : Paramètres > Raccourcis clavier > FiveM)

| Touche | Qui | Action |
|---|---|---|
| **O** | conducteur | Allumer le moteur et le laisser **toujours allumé** / le couper |
| **G** | tous | Attacher / détacher la ceinture (K ouvre le MDC) |
| **U** | conducteur, passager avant | Ouvrir / refermer **sa** portière (avant gauche / avant droite) |
| **I** | conducteur | Ouvrir / refermer les **deux portières avant** ensemble |
| **←** / **→** | conducteur | **Clignotant** gauche / droit (même touche pour l'arrêter) |
| **↓** | conducteur | **Warnings** (feux de détresse) |
| **K** | à pied | Devant le capot / derrière le coffre : **pousser** le véhicule / arrêter de pousser |

En voiture, aucun rappel des touches à l'écran (seule la notification du moteur, en montant côté conducteur).

## Car HUD (dessiné par le MDC)

- **Toujours affiché pour le conducteur** : moteur coupé, tout est **grisé** ; au démarrage, tout s'illumine.
- **Conducteur** : car HUD complet (vitesse, accélération, essence, ceinture, véhicule cassé).
  **Passagers** : uniquement le **logo de la ceinture**.
- **Logo de la ceinture** : contour noir ; **transparent, sans couleur** quand elle n'est pas mise, **rempli de
  blanc** quand elle est mise, **clignote en rouge pâle** quand le véhicule roule sans ceinture.

## Clignotants et warnings

- **Flèche gauche / droite** : clignotant ; **flèche bas** : warnings. Les feux sont visibles par tous les joueurs.
- **Son du relais** (un seul fichier, `indicators_sound.ogg`, pour les clignotants et les warnings) joué **en boucle
  tant que le clignotant n'est pas coupé** (`SignalSoundMode`), volume `SignalVolume` (renforcé : 4,782, soit +200 %), **même si tout le monde
  est descendu** : entendu à 100 % à bord et **autour du véhicule** (voir *Sons entendus autour du véhicule*).
  Comme dans une vraie voiture, le clignotant **s'arrête tout seul après le virage** (volant revenu droit après avoir tourné de 60°, `SignalCancelAngle`). Les warnings restent
  jusqu'à la touche, même véhicule laissé.

## Sons

Les sons du véhicule sont des **fichiers audio que vous déposez vous-même** dans `html/sounds/` (aucun n'est fourni,
voir `html/sounds/LISEZMOI.txt`), au format .ogg : `belt_on` (ceinture attachée), `belt_off` (détachée), `belt_chime`
(carillon), `indicators_sound` (clignotants / warnings). Les sons d'attache et de retrait de la ceinture sont joués
**plus fort** (×1,725, `Seatbelt.BeltSoundVolume`) et le carillon renforcé (1,56, `Seatbelt.ChimeVolume`). Un fichier absent : ce son n'est pas joué. Clignotants : le fichier
est joué en boucle (`SignalSoundMode = 'loop'`,
le fichier contient le « tic-tac ») ou, si c'est un seul clic, rejoué toutes les `SignalInterval` ms (`'repeat'`).
Sans ce fichier, les clignotants marchent mais sans son. Volume réglé par chaque joueur dans le MDC
(*Paramètres > HUD & Display > Volume des sons du véhicule*, bouton « Tester »).

### Sons entendus autour du véhicule

Clignotants / warnings, ceinture (attache, retrait) et carillon : **100 % pour les occupants** ; dehors, la distance est
mesurée **depuis la carrosserie** (`VehicleSounds`) :
- une portière (ou le coffre / le capot) **ouverte** : entendus jusqu'à **3 m**, son clair ;
- tout **fermé** : jusqu'à **1 m** seulement, **étouffés** (filtre passe-bas) et moins forts (réduction du bruit).
Un son coupé (clignotant désactivé, ceinture attachée…) s'arrête net, même au milieu.

## Moteur

- **Seule la touche** (O par défaut, configurable : Raccourcis clavier > FiveM) **allume et éteint le moteur**. Il ne
  démarre **jamais tout seul** (ni en montant, ni en accélérant) et ne s'éteint **jamais tout seul** (ni en descendant :
  allumé, il le reste pour le prochain conducteur ; coupé, il le reste). Exceptions : panne sèche et véhicule cassé.
- Un véhicule **apparaît moteur coupé**.
- En montant **côté conducteur**, une notification **glisse depuis la gauche, juste au-dessus du car HUD** :
  « **O** » **Pour allumer le moteur** (« Seule cette touche l'allume et l'éteint »), ou « Pour couper le moteur » s'il
  tourne. Elle **disparaît 8 secondes** après la montée, même sans appuyer (`EngineNoticeDuration`), ou dès que **O**
  est utilisée.
- **Vrai démarrage** : démarreur du jeu, durée complète conservée (pot d'échappement, etc.) ; on ne peut pas
  accélérer pendant le démarrage (`EngineStartTime`, 1,2 s).
- Panne sèche ou véhicule cassé : impossible à démarrer.

## Feux stop et roues

- **Feux stop** allumés quand le véhicule est **à l'arrêt, moteur tournant**, conducteur au volant (comme un pied sur
  le frein), **vus par tous les joueurs** (`StopLights`).
- **Position des roues** : en descendant, les roues gardent **exactement** l'angle du volant juste avant la descente
  (le jeu les redresse d'habitude), pour tous les joueurs, même quand le véhicule revient à portée (`KeepWheelAngle`).

## Essence

- Un **plein dure 3 h 30 en temps réel** (pas l'heure du jeu) en conduite normale (`Fuel.FullTankMinutes`).
  Consommation réaliste selon la charge du moteur : **40 %** de cette consommation au ralenti, **~100 %** en conduite
  normale, **160 %** pied au plancher ; moteur coupé : rien. Multiplicateur par classe possible (`ClassFactor`).
- Moteur laissé allumé sans conducteur : il continue de consommer (ralenti).
- **Réservoir percé** (accident) : fuite d'essence, jusqu'à 4 % par minute.
- **Panne sèche** : le moteur s'arrête et ne redémarre plus.
- **Faire le plein** : à pied près d'une pompe (toutes les stations de la carte, repérées par une icône), le véhicule
  à moins de 6 m, **moteur coupé** : **E** (2,5 % par seconde, **E** pour arrêter). **G** à la pompe : prendre un
  **jerrican** ; jerrican en main près d'un véhicule : **E** pour le vider dans le réservoir (25 % d'un plein).
- Véhicule jamais vu : créé par un script (garage, menu) = plein ; véhicule de la circulation = 25 à 85 %.
- L'essence est dans l'état du véhicule `fuel` (0 à 100, même format qu'**ox_fuel**) : lisible par d'autres scripts.

## Dégâts réalistes

- Le véhicule **encaisse comme un vrai** : au moment du choc, ce qui a été percuté est reconnu.
  - **Dégâts légers** : piéton, moto, vélo, barrière de chantier, plot, compteur / boîtier électrique, poubelle,
    panneau et autres petits objets (`LightModels`, objet inconnu : `UnknownObject`) : le moteur ne reçoit que 23 %
    des dégâts du jeu, rien de plus.
  - **Dégâts forts** : mur, bâtiment, rocher (décor fixe), voiture, camion, lampadaire, poteau, feu tricolore, bouche
    d'incendie, borne, glissière béton (`HeavyModels`) : 83 % des dégâts du jeu, une petite part des dégâts de
    carrosserie et, si le choc est **violent** (perte de vitesse brutale de plus de 20 MPH), des dégâts selon sa
    violence : mur à 40 MPH ≈ −205, à 60 MPH ≈ −580, à 70 MPH et plus : véhicule cassé.
  - Sans choc (balles, explosion, chute) : 74 % des dégâts du jeu.
  - Les véhicules sont **~8 % plus résistants** qu'auparavant (tous ces coefficients baissés d'autant).
- Moteur **abîmé** (< 500) : puissance réduite (80 %) ; **critique** (< 300) : 60 % de puissance et **calages** au
  hasard en roulant ; **cassé** (< 100) : moteur coupé, impossible à redémarrer ; le **car HUD reste allumé**, tout
  en **rouge vif clignotant**, avec le **logo du moteur** en rouge plus foncé, fixe. Réparé (script de mécanicien ou
  `/repair`) : tout redevient normal.
- **`/repair`** : répare **uniquement le moteur** du véhicule où l'on est (sinon du plus proche, 5 m) : santé du
  moteur remise à neuf, véhicule de nouveau utilisable. La carrosserie, les vitres et les **dégâts visibles restent**.
  `Repair.Restricted = true` la réserve à la permission ACE `command.repair`.
- Ce script ne fait jamais prendre feu un véhicule (il ne descend pas le moteur sous 10).

## Ceinture de sécurité

- Vrai son à l'attache et au retrait. **Attachée, impossible de descendre** (touche F bloquée) : il faut d'abord la
  détacher. Détachée : **carillon au-dessus de 5 MPH**, **coupé net** dès que la ceinture est attachée, que le joueur
  descend du véhicule, ou que le véhicule est **arrêté** (moins de 2 MPH, `StopSpeed`).
- **Sons synchronisés** : les autres occupants les entendent à 100 %, les joueurs autour selon les règles ci-dessus
  (3 m portière ouverte, 1 m tout fermé et étouffés).
- **Éjection** (ceinture **détachée** uniquement ; l'éjection automatique du jeu reste désactivée) lors d'un vrai
  accident (choc qui fait perdre au moins 10 MPH, jamais un simple accrochage) :
  - **jamais en dessous de 60 MPH** (vitesse juste avant le choc) ;
  - **arrêt brutal** (de 60 MPH ou plus à **20 MPH ou moins**) : **70 %** de chances d'être éjecté ;
  - accident à 60 MPH ou plus **sans** chute aussi brutale : **45 %** de chances.
  Le joueur est **projeté entre 20 et 60 m** du véhicule (plus il roulait vite, plus loin : 60 m vers 120 MPH), par
  le pare-brise et par-dessus le toit, dans le sens de la course ; si l'obstacle percuté bloque ce chemin, il part de
  côté. Il ne reste jamais sur le lieu de l'accident : arrêté trop tôt par un obstacle, il est posé au sol à 20 m. Il
  perd des points de vie. Attaché : jamais éjecté. Réglages : `Seatbelt` (`MinSpeed`, `SuddenStopSpeed`,
  `SuddenChance`, `AccidentDrop`, `CrashChance`, `MinDistance`, `MaxDistance`…).

## Portières (depuis l'intérieur)

- **U** : conducteur → portière avant gauche ; passager avant → portière avant droite. **I** (conducteur) : les deux
  portières avant. Même touche pour refermer.
- **Priorité à celui qui a ouvert** : si le passager a ouvert sa portière et que le conducteur ouvre les deux portières
  avant, seule celle du conducteur s'ouvre ; en refermant, le conducteur ne referme pas celle du passager (et
  inversement). Une portière ouverte par un joueur descendu, ou à la main, se referme normalement.
- Un simple message **privé** dans le chat : « Portière ouverte. », « Portières fermées. »…

## Pousser un véhicule

- À pied, **devant le capot ou derrière le coffre** d'un véhicule (avec ou sans quelqu'un au volant), un petit message apparaît en bas de l'écran, sur un **fond noir légèrement transparent** :
  « **K** Pousser le véhicule ».
- **K** : le personnage se met en position contre le pare-chocs (animation de poussée). Il pousse en **avançant avec
  sa touche habituelle** (Z / W), **tout droit uniquement**. Derrière le coffre, le véhicule avance ; devant le capot,
  il recule.
- **Quelqu'un au volant** : il ne peut plus accélérer ni reculer, **seulement tourner le volant** pendant qu'on le pousse.
- Pendant la poussée, une notification rappelle « **K** Arrêter de pousser » ; **K** de nouveau pour arrêter. Arrêt
  automatique si le personnage tombe.
- **K ouvre aussi le MDC** : tant que le message est affiché (ou pendant la poussée), K n'ouvre pas le MDC (état du
  joueur `vcPushPrompt`, lu par le MDC). Ailleurs, K ouvre le MDC normalement. Les deux touches restent modifiables.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Keys` | touches par défaut (dont clignotants ← / →, warnings ↓) |
| `SoundVolume`, `SignalCancelAngle`, `SignalSoundMode`, `SignalInterval`, `SignalVolume` | volume sans le MDC, arrêt automatique du clignotant après un virage, son des clignotants (en boucle ou clic répété, rythme, volume renforcé) |
| `Fuel` | durée d'un plein (3 h 30), consommation au ralenti / plein gaz, classes, essence de départ, fuite, vitesse du plein, pompes, jerrican, stations (icônes) |
| `Damage` | dégâts légers / forts / sans choc, chocs violents, paliers (abîmé / critique / cassé), puissance, calages, classes de véhicules légères, listes d'objets légers / forts |
| `Seatbelt` | carillon (au-dessus de 5 MPH, coupé sous 2 MPH), éjection (dès 60 MPH : 70 % arrêt brutal / 45 % accident ; projeté à 20-60 m), classes sans ceinture |
| `Repair` | commande `/repair` (moteur seulement), permission, distance |
| `VehicleSounds` | sons entendus autour du véhicule : 3 m portière ouverte, 1 m tout fermé (étouffé), volumes |
| `EngineNoticeDuration`, `EngineStartTime` | durée de la notification du moteur (8 s), durée du démarrage (1,2 s) |
| `StopLights`, `KeepWheelAngle` | feux stop à l'arrêt moteur tournant, angle des roues gardé à la descente |
| `Push` | vitesse de poussée, zone devant / derrière, position du personnage, animation, classes poussables |

## États des véhicules (pour d'autres scripts)

`Entity(vehicle).state` : `fuel` (0–100), `vcEngine` (toujours allumé), `vcBroken`
(cassé), `vcDoors` (qui a ouvert les portières avant), `vcSignal` (clignotants / warnings), `vcPushed` (poussé : par
qui, sens, poussée en cours). État du joueur : `seatbelt`, `seatbeltAlarm`. Le serveur vérifie
chaque changement (conducteur, distance, essence qui ne monte qu'à la pompe, au rythme d'une pompe).

## Performance

- À pied : une vérification toutes les 500 ms (~0.00 ms). Près d'un véhicule poussable (6 m) : toutes les 100 ms.
  Boucle à chaque image seulement près d'une pompe, jerrican en main, ou pendant la poussée.
- À bord : ~0.02 ms (chocs, puissance) ; essence, dégâts, alarme et car HUD toutes les 100 ms ; ce qui a été
  percuté n'est cherché qu'au moment d'un choc ;
  car HUD envoyé seulement quand il change.
- Feux stop des véhicules des autres joueurs : boucle à chaque image seulement tant qu'un véhicule proche est arrêté
  moteur tournant ; roues : 2 s après une descente.
- Serveur : aucune boucle.
