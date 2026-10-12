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
- **Son du relais** (un seul fichier, `indicators_sound.ogg`, pour les clignotants et les warnings) entendu par les
  occupants, joué en boucle tant que le clignotant est allumé (`SignalSoundMode`), volume `SignalVolume` (+25 %).
  Comme dans une vraie voiture, le clignotant **s'arrête tout seul après le virage** (volant revenu droit après avoir tourné de 60°, `SignalCancelAngle`). Les warnings restent
  jusqu'à la touche, même véhicule laissé.

## Sons

Les sons du véhicule sont des **fichiers audio** (`html/sounds/*.ogg`) : verrou de ceinture (`belt_on`), déclic et
sangle qui se rembobine (`belt_off`), carillon du tableau de bord (`belt_chime`) : imitations fabriquées pour ce script,
**remplaçables par vos propres enregistrements** (mêmes noms de fichiers, format .ogg). Clignotants et warnings :
**`indicators_sound.ogg`, à ajouter vous-même** dans `html/sounds/` ; il est joué en boucle (`SignalSoundMode = 'loop'`,
le fichier contient le « tic-tac ») ou, si c'est un seul clic, rejoué toutes les `SignalInterval` ms (`'repeat'`).
Sans ce fichier, les clignotants marchent mais sans son. Volume réglé par chaque joueur dans le MDC
(*Paramètres > HUD & Display > Volume des sons du véhicule*, bouton « Tester »).

## Moteur

- Un véhicule **apparaît moteur coupé** : en montant, il reste coupé (le démarrage automatique du jeu est bloqué).
- En montant **côté conducteur**, une notification **glisse depuis la gauche, juste au-dessus du car HUD** : touche
  **O** « Allumer le moteur — il reste allumé, même en descendant » (ou « Couper le moteur » s'il tourne déjà).
  Elle **disparaît 8 secondes** après la montée, même sans appuyer (`EngineNoticeDuration`), ou dès que **O** est
  utilisée.
- **O** allume le moteur et le marque **toujours allumé** : il le reste, **même quand le joueur descend**, et pour
  le prochain conducteur. **O** de nouveau : coupé.
- **Accélérer** démarre toujours le moteur, comme dans le jeu de base (sans le marquer « toujours allumé »).
- Panne sèche ou véhicule cassé : impossible à démarrer.

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
    panneau et autres petits objets (`LightModels`, objet inconnu : `UnknownObject`) : le moteur ne reçoit que 25 %
    des dégâts du jeu, rien de plus.
  - **Dégâts forts** : mur, bâtiment, rocher (décor fixe), voiture, camion, lampadaire, poteau, feu tricolore, bouche
    d'incendie, borne, glissière béton (`HeavyModels`) : 90 % des dégâts du jeu, une petite part des dégâts de
    carrosserie et, si le choc est **violent** (perte de vitesse brutale de plus de 20 MPH), des dégâts selon sa
    violence : mur à 40 MPH ≈ −220, à 60 MPH ≈ −630, à 70 MPH et plus : véhicule cassé.
  - Sans choc (balles, explosion, chute) : 80 % des dégâts du jeu.
- Moteur **abîmé** (< 500) : puissance réduite (80 %) ; **critique** (< 300) : 60 % de puissance et **calages** au
  hasard en roulant ; **cassé** (< 100) : moteur coupé, impossible à redémarrer, et **logo rouge « véhicule cassé »**
  sur le car HUD (jamais visible autrement). Réparé par un script de mécanicien : tout redevient normal.
- Ce script ne fait jamais prendre feu un véhicule (il ne descend pas le moteur sous 10).

## Ceinture de sécurité

- Vrai son à l'attache et au retrait. **Attachée, impossible de descendre** (touche F bloquée) : il faut d'abord la
  détacher. Détachée : **carillon au-dessus de 5 MPH**, répété jusqu'à l'arrêt du véhicule ou jusqu'à l'attache.
- **Sons synchronisés** : les occupants entendent tout à 100 %, les joueurs autour (15 m) de moins en moins fort.
- **Éjection** (ceinture **détachée**), lors d'un **choc contre un objet fixe (mur…) ou un véhicule** (arrêté ou en
  mouvement) :
  - au-dessus de **55 MPH** : dès que le choc fait perdre au moins 15 MPH ;
  - entre **40 et 55 MPH** : si la vitesse chute brutalement (au moins 30 MPH, ex. **45 → 0**) ;
  - **jamais en dessous de 40 MPH**.
  Le joueur traverse le pare-brise avec l'élan du véhicule et perd des points de vie. Attaché : jamais éjecté
  (l'éjection automatique du jeu est désactivée, seule cette règle compte).

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
| `SoundVolume`, `SignalCancelAngle`, `SignalSoundMode`, `SignalInterval`, `SignalVolume` | volume sans le MDC, arrêt automatique du clignotant après un virage, son des clignotants (en boucle ou clic répété, rythme, volume +25 %) |
| `Fuel` | durée d'un plein (3 h 30), consommation au ralenti / plein gaz, classes, essence de départ, fuite, vitesse du plein, pompes, jerrican, stations (icônes) |
| `Damage` | dégâts légers / forts / sans choc, chocs violents, paliers (abîmé / critique / cassé), puissance, calages, classes de véhicules légères, listes d'objets légers / forts |
| `Seatbelt` | alarme (5 MPH), portée des sons, règles d'éjection (55 / 40 MPH, pertes de vitesse), classes sans ceinture |
| `EngineNoticeDuration` | durée de la notification du moteur (8 s) |
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
- Serveur : aucune boucle.
