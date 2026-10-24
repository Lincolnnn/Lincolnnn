# Vehicle Control (`rp_vehiclecontrol`)

Gestion des véhicules **100% standalone** (sans ESX / QBCore / vRP) : essence, dégâts réalistes, ceinture de
sécurité, moteur toujours allumé, portières depuis l'intérieur, clignotants et poussée. Lié aux HUD du MDC
(`rp_mdc`) : le **car HUD** (au-dessus de la minimap, à côté du PLD) est dessiné et réglé dans le MDC
(*Paramètres > HUD & Display* : position, taille, éléments affichés, volume de la ceinture).

## Installation

1. Copiez le dossier `rp_vehiclecontrol` dans `resources/` (à côté du MDC, pas à l'intérieur).
2. Dans `server.cfg`, après le MDC et le chat : `ensure rp_vehiclecontrol`
3. **OneSync** recommandé (l'état des véhicules est partagé entre les joueurs).

Sans le MDC, tout fonctionne mais le car HUD n'est pas affiché. Sans `rp_chat`, les messages « Portière ouverte. »
passent par le chat d'origine.

**Mode nuit** (réglé dans le MDC : *Paramètres > MDC > Apparence*, appliqué à toutes les interfaces ou aux menus extérieurs) : **vert sur fond noir** pour le message « pousser le véhicule » (le car HUD suit le réglage du MDC) (`client/theme.lua` ; sans le MDC : thème jour).

## Touches (par défaut, modifiables : Paramètres > Raccourcis clavier > FiveM)

| Touche | Qui | Action |
|---|---|---|
| **O** | conducteur | Allumer le moteur et le laisser **toujours allumé** / le couper |
| **G** | tous | Attacher / détacher la ceinture (K ouvre le MDC) |
| **U** | conducteur, passager avant | Ouvrir / refermer **sa** portière (avant gauche / avant droite) |
| **I** | conducteur | Ouvrir / refermer les **deux portières avant** ensemble |
| **←** / **→** | conducteur | **Clignotant** gauche / droit (même touche pour l'arrêter) |
| **↓** | conducteur | **Warnings** (feux de détresse) |
| **↑** | conducteur | **Marche avant (D) / marche arrière (R)** |
| **K** | à pied | Devant le capot / derrière le coffre : **pousser** le véhicule / arrêter de pousser |

En voiture, aucun rappel des touches à l'écran (seule la notification du moteur, en montant côté conducteur).

## Car HUD (dessiné par le MDC)

- **Toujours affiché pour le conducteur** : moteur coupé, tout est **grisé** ; au démarrage, tout s'illumine.
- **Conducteur** : car HUD complet (vitesse, accélération, essence, ceinture, moteur très abîmé / détruit).
  **Passagers** : uniquement le **logo de la ceinture**.
- **Logo de la ceinture** : contour noir ; **transparent, sans couleur** quand elle n'est pas mise, **rempli de
  blanc** quand elle est mise, **clignote en rouge pâle** quand le véhicule roule sans ceinture.

## Clignotants et warnings

- **Flèche gauche / droite** : clignotant ; **flèche bas** : warnings. Les feux sont visibles par tous les joueurs.
- **Son du relais** (un seul fichier, `indicators_sound.ogg`, pour les clignotants et les warnings) joué **en boucle
  tant que le clignotant n'est pas coupé** (`SignalSoundMode`), volume `SignalVolume` (1,6), **même si tout le monde
  est descendu** : entendu à 100 % à bord et **autour du véhicule** (voir *Sons entendus autour du véhicule*).
  Comme dans une vraie voiture, le clignotant **s'arrête tout seul après le virage** (volant revenu droit après avoir tourné de 60°, `SignalCancelAngle`). Les warnings restent
  jusqu'à la touche, même véhicule laissé.

## Sons

Les sons du véhicule sont des **fichiers audio que vous déposez vous-même** dans `html/sounds/` (aucun n'est fourni,
voir `html/sounds/LISEZMOI.txt`), au format .ogg : `belt_on` (ceinture attachée), `belt_off` (détachée), `belt_chime`
(carillon de ceinture : un occupant détaché), `fast_belt_chime` (carillon rapide : plusieurs occupants détachés),
`indicators_sound` (clignotants / warnings). Les sons d'attache et de retrait de la ceinture sont joués
au volume `Seatbelt.BeltSoundVolume` (1,0) et les carillons à `Seatbelt.ChimeVolume` (1,0), multipliés par le réglage du joueur dans le MDC. Un fichier absent : ce son n'est pas joué. Clignotants : le fichier
est joué en boucle (`SignalSoundMode = 'loop'`,
le fichier contient le « tic-tac ») ou, si c'est un seul clic, rejoué toutes les `SignalInterval` ms (`'repeat'`).
Sans ce fichier, les clignotants marchent mais sans son. Volume réglé par chaque joueur dans le MDC
(*Paramètres > HUD & Display > Volume des sons du véhicule*, bouton « Tester »).

**Boucles sans limite** : chaque fichier est chargé une fois en mémoire au démarrage. Les carillons et les
clignotants en mode `'loop'` tournent alors en boucle **sans fin et sans coupure** tant qu'ils sont demandés,
quelle que soit la durée du fichier. Ils ne s'arrêtent que sur l'arrêt voulu : attaché, moteur coupé, sorti,
portière refermée… Si un son en boucle s'arrête quand même, il est relancé aussitôt.

**Ils se rétablissent seuls** :
- si le lecteur audio du navigateur du jeu se met en pause, il est relancé aussitôt (vérifié chaque seconde) ;
- s'il refuse de repartir, les sons passent par un autre lecteur, sans étouffement, pour ne jamais rester muets.

**Carillons = même fonctionnement que les clignotants** (`client/chimes.lua`, sur le modèle de `client/signals.lua`) :
- un son **par véhicule**, jamais partagé ni disputé entre plusieurs véhicules ;
- le véhicule est **suivi** tant que son carillon a lieu d'être ; toutes les 200 ms, seul le volume est recalculé selon
  la position du joueur, et seul ce qui change est envoyé : rien n'est relancé tant que rien ne change ;
- `Seatbelt.ChimeSoundMode` : `'loop'` (le fichier en boucle) ou `'repeat'` (rejoué toutes les `ChimeInterval` ms, pour un
  fichier qui ne contient qu'un seul « ding »), comme `SignalSoundMode` pour les clignotants.

**Boucle recollée, sans pause** (`Seatbelt.ChimeSeamless`) : un fichier de carillon qui finit (ou commence) par un
silence ferait une pause à chaque passage de la boucle. Le fichier est analysé au chargement :
- **plusieurs « ding »** : la boucle commence au premier et finit un écart habituel après le dernier (la médiane des
  écarts du fichier). Le passage de la fin au début garde exactement le rythme du carillon, sans pause ;
- **son continu** (sans silence au milieu) : son silence de début et de fin est retiré ;
- **un seul « ding » court** : le silence de début et de fin est ramené à 1 s au plus (`Seatbelt.ChimeMaxGap`, `0` =
  fichier joué tel quel), ou utilisez `ChimeSoundMode = 'repeat'`.

Le silence au milieu du fichier n'est jamais touché : le diagnostic l'indique.

**Jamais relancés du début pour une micro-coupure** : un carillon coupé devient muet tout de suite. S'il est redemandé
dans les 1,5 s, il reprend **là où il en était**, sans repartir du début. Cela couvre une portière qui bouge un instant,
un pas hors de portée ou une lecture de vitesse isolée. Au-delà de 1,5 s, il est arrêté pour de bon et repartira du
début la fois suivante.

**Diagnostic** : `setr vc_debug_sound 1` dans la console F8 affiche :
- chaque carillon démarré ou coupé, avec la raison ;
- l'analyse de son fichier : durée, silence au début, à la fin et plus long silence au milieu ;
- ce que fait le lecteur audio : démarrage, arrêt, relance, lecteur suspendu ou relancé.

`setr vc_debug_sound 0` pour arrêter.

### Sons entendus autour du véhicule

Clignotants / warnings, ceinture (attache, retrait) et carillon : **100 % pour les occupants** ; dehors, la distance est
mesurée **depuis la carrosserie** (`VehicleSounds`) :
- une portière (ou le coffre / le capot) **ouverte** : entendus jusqu'à **3 m**, son clair ;
- tout **fermé** : jusqu'à **1 m** seulement, **étouffés** (filtre passe-bas) et moins forts (réduction du bruit).
Un son coupé (clignotant désactivé, ceinture attachée…) s'arrête net, même au milieu.

## Moteur

- **Seule la touche** (O par défaut, configurable : Raccourcis clavier > FiveM) **allume et éteint le moteur**. Il ne
  démarre **jamais tout seul** (ni en montant, ni en accélérant) et ne s'éteint **jamais tout seul** (ni en descendant :
  allumé, il le reste pour le prochain conducteur ; coupé, il le reste). Exceptions : panne sèche, moteur détruit et
  calage d'un moteur très abîmé (il repart tout seul après quelques secondes, ou tout de suite avec **O**).
- Un véhicule que le joueur **vient de faire apparaître** est **remis à zéro** : moteur coupé, rien de l'ancien.
- **Véhicule ambiant** (circulation, PNJ) ou **laissé moteur allumé par un autre joueur** : il reste allumé pour le
  joueur qui monte (pas de remise à zéro).
- **Nouveau véhicule alors qu'il est déjà dans un véhicule** (apparition depuis un menu) : tout ce qui concernait
  l'ancien s'arrête (ceinture retirée sans bruit, carillon coupé, moteur et clignotants / warnings de l'ancien coupés,
  radio de l'ancien véhicule coupée avec `rp_interact`) et le nouveau part de zéro (moteur coupé, ceinture détachée,
  aucun réglage repris). C'est vrai :
  - que l'ancien véhicule soit **supprimé d'abord** (menu Spawn « Supprimer l'ancien véhicule », vMenu…) : le joueur
    se retrouve un instant debout sans être descendu ; pendant **1 seconde** le script attend de voir s'il est mis dans
    un nouveau véhicule (une vraie descente avec **F**, une éjection, une chute de moto, la mort : sortie immédiate) ;
  - ou **gardé** (le joueur est mis directement dans le nouveau) ;
  - même quand le jeu redonne au nouveau véhicule le numéro de l'ancien supprimé : un modèle ou un identifiant réseau
    différent suffit à le reconnaître.
- En montant **côté conducteur**, une notification **glisse depuis la gauche, juste au-dessus du car HUD** :
  « **O** » **Pour allumer le moteur** (« Seule cette touche l'allume et l'éteint »), ou « Pour couper le moteur » s'il
  tourne. Elle **disparaît 8 secondes** après la montée, même sans appuyer (`EngineNoticeDuration`), ou dès que **O**
  est utilisée.
- **Vrai démarrage** : démarreur du jeu, durée complète conservée (pot d'échappement, etc.) ; on ne peut pas
  accélérer pendant le démarrage (`EngineStartTime`, 1,2 s).
- Panne sèche ou moteur détruit : impossible à démarrer.

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
- **Faire le plein** (`client/refuel.lua`), aux pompes de toutes les stations de la carte (icônes) :
  1. **moteur coupé** et **descendu du véhicule** ;
  2. à la pompe : **E « Prendre le pistolet »** : un **vrai pistolet de pompe** dans la main, relié à la pompe par un
     **tuyau** (vu par les joueurs proches). Pistolet en main : impossible de monter dans un véhicule, de frapper ou
     de viser ;
  3. aller à la **trappe à essence**, toujours à l'**ARRIÈRE GAUCHE** du véhicule (petit repère vert au-dessus) :
     **E « Mettre le pistolet dans la trappe »** (refusé moteur allumé) ; le pistolet reste dans la trappe, **posé sur
     la carrosserie** (la vraie tôle est trouvée par un rayon, pas le cadre du modèle qui déborde), bec vers
     l'intérieur, et le plein se fait tout seul : **de vide à plein en 1 minute au maximum** (`RefuelPerSecond`),
     progression affichée ;
  4. réservoir plein : arrêt tout seul, et un **seul message** en haut à gauche : **« E pour ranger le pistolet »** (il
     retourne à la pompe, inutile d'y retourner). Pendant le plein, **E** l'arrête et range le pistolet ; pistolet en
     main loin d'une trappe : **E** le range aussi. Moteur allumé pendant le plein : interrompu.
  - Position du pistolet dans la trappe : `Nozzle.InFlap` / `RotationOrder` ; réglage en jeu, pistolet dans une trappe :
    commande **`vc_nozzle x y z rx ry rz [ordre]`** (valeurs affichées dans la console F8, à recopier dans `config.lua`).
  - Tuyau trop court (7 m, `Nozzle.HoseLength`) ou véhicule qui part avec le pistolet : il retourne à la pompe.
- **Jerrican** : rempli à la pompe (**G**, 3 s) ou **pris dans le coffre d'un véhicule de police** (`rp_equipment` : un
  jerrican plein d'origine dans chaque véhicule de police, à prendre et ranger). Plein, il remplit **2/5 d'un réservoir** (40 %, `JerrycanFuel`) ; en main
  près de la trappe (arrière gauche) : **E « Verser le jerrican »** (4 % par seconde, **E** pour arrêter).
- Véhicule jamais vu : créé par un script (**n'importe lequel** : garage, menu de spawn, /car…) = **au hasard entre 35 et
  87 %** du plein (`SpawnedFuel`) ; véhicule de la circulation = 25 à 85 % (`AmbientFuel`).
- L'essence est dans l'état du véhicule `fuel` (0 à 100, même format qu'**ox_fuel**) : lisible par d'autres scripts.

## Dégâts réalistes

- Le véhicule **encaisse comme un vrai** : au moment du choc, ce qui a été percuté est reconnu.
  - **Dégâts légers** : piéton, moto, vélo, barrière de chantier, plot, compteur / boîtier électrique, poubelle,
    panneau et autres petits objets (`LightModels`, objet inconnu : `UnknownObject`) : le moteur ne reçoit que 23 %
    des dégâts du jeu, rien de plus.
  - **Dégâts forts** : mur, bâtiment, rocher (décor fixe), voiture, camion, lampadaire, poteau, feu tricolore, bouche
    d'incendie, borne, glissière béton (`HeavyModels`) : 83 % des dégâts du jeu, une petite part des dégâts de
    carrosserie et, si le choc est **violent** (perte de vitesse brutale de plus de 20 MPH), des dégâts selon sa
    violence : mur à 40 MPH ≈ −205, à 60 MPH ≈ −580, à 70 MPH et plus : moteur détruit.
  - Sans choc (balles, explosion, chute) : 74 % des dégâts du jeu.
  - Les véhicules sont **~8 % plus résistants** qu'auparavant (tous ces coefficients baissés d'autant).
- Moteur **abîmé** (< 500) : puissance un peu réduite (80 %).
- **Palier 1 — moteur TRÈS ABÎMÉ** (< 300, `Critical`) :
  - il **roule très lentement** : 35 % de puissance (`CriticalPower`) et **25 MPH maximum** (`CriticalMaxSpeed`) ;
  - il **cale** au hasard en roulant (`StallChance`) : moteur coupé quelques secondes (`StallTime`, 2 à 4,5 s), puis
    il **repart tout seul** avec le démarreur (ou tout de suite avec **O**) ;
  - de la **fumée sort du capot**, vue par **tous les joueurs** (`Smoke` ; le jeu ajoute aussi sa propre fumée) ;
  - les **warnings s'allument tout seuls** (moteur allumé) ; ils **s'éteignent tout seuls** quand le moteur est
    **coupé avec O**, quand il **passe au palier 2** ou quand il est **réparé**. Éteints à la main par le conducteur :
    ils ne sont pas rallumés de force (seulement au prochain démarrage). Un calage ne les éteint pas ;
  - **logo du moteur orange** sur le car HUD (`CriticalHazards = false` : pas de warnings automatiques).
- **Accident important** (pas un simple accrochage) : choc **fort** (mur, voiture, poteau… pas un piéton, un plot ou
  une barrière) avec une **perte de vitesse d'au moins 25 MPH**, ou au moins **150 de dégâts** (moteur + carrosserie)
  pendant le choc (`AccidentHazards`) : **les warnings s'allument tout seuls**. Ils restent allumés (même moteur coupé
  ou détruit) jusqu'à ce que le conducteur les éteigne (flèche bas).
- **Palier 2 — moteur DÉTRUIT** (< 100, `Broken`) : véhicule **éteint, moteur coupé, impossible à rallumer** ; le
  **car HUD reste allumé**, tout en **rouge vif clignotant**, avec le **logo du moteur** en rouge plus foncé, fixe ; le
  logo de la ceinture ne clignote plus : attachée, rempli de **rouge fixe** ; détachée, seulement son **contour en
  rouge**, centre transparent, fixe. La fumée continue.
- Réparé (script de mécanicien ou `/repair`) : tout redevient normal (vitesse, fumée, warnings automatiques, logo).
- **`/repair`** : répare **uniquement le moteur** du véhicule où l'on est (sinon du plus proche, 5 m) : santé du
  moteur remise à neuf, véhicule de nouveau utilisable. La carrosserie, les vitres et les **dégâts visibles restent**.
  `Repair.Restricted = true` la réserve à la permission ACE `command.repair`.
- Ce script ne fait jamais prendre feu un véhicule (il ne descend pas le moteur sous 10).

### Dégâts visuels : le véhicule perd des morceaux (`Bodywork`)

Les morceaux ne tombent que sur de **vraiment gros accidents**, ou quand **plusieurs accidents** se sont additionnés
(mur, voiture, poteau… pas un piéton ni un plot ; perte de vitesse brutale d'au moins **22 MPH**, `MinDrop`) :

- Chaque choc ajoute de l'**usure** au côté touché (avant, arrière, gauche, droite) selon la perte de vitesse. Un
  choc sur le côté use aussi un peu l'avant et l'arrière (`SideToBumpers`, 40 %). Carrosserie déjà très abîmée (sous 400, `WornBody`) : les seuils baissent de 25 % (`WornFactor`).
- Un morceau ne peut tomber que quand l'usure de son côté atteint son seuil (`Wear`), puis selon sa chance (`Chance`).
  **Ordre de priorité** :

| Morceau | Usure du côté | Chance |
|---|---|---|
| **vitres** du côté touché | 35 | 40 % |
| **pare-choc** avant / arrière (aussi sur un choc latéral) | 60 | 85 % |
| **capot** (avant) / **coffre** (arrière) | 75 | 75 % |
| **pare-brise** (avant) | 90 | 50 % |
| **roue** du côté touché (ou un seul choc d'au moins 60 MPH) ; parfois une deuxième (25 %) | 140 | 50 % |

**Portières : elles ne tombent jamais** (dès que le conducteur monte, le jeu ne peut plus les arracher, même sur un
très gros choc ; `DoorsAjar.NeverFall`). Sur un **gros choc** (perte de vitesse d'au moins **40 MPH**,
`DoorsAjar.Drop`) ou quand le côté est très usé (110), la sécurité saute : le véhicule se **déverrouille** et des
portières **s'entrouvrent** un peu (8 à 20 % de leur ouverture, `Angle`) : celles du côté touché (50 % chacune), ou, sur
un choc avant / arrière, n'importe laquelle (30 %) ; deux au plus par choc. On peut les refermer normalement.

**Tonneaux accentués** (`Rollover`) : un véhicule qui part **déjà** en tonneau (penché de plus de 55°, plus sur ses
roues, à au moins 30 MPH) en fait **davantage** : sa rotation est relancée dans le même sens (au moins 4,5 rad/s ou
1,35 x celle du moment) avec un petit élan vers le haut, deux fois au plus par accident (une toutes les 0,65 s) ; une
vitre peut éclater à chaque relance. Rien dans les virages ordinaires. `Rollover.Enabled = false` : tonneaux du jeu.

**Verre brisé au sol** (gros accident : perte de vitesse d'au moins **35 MPH**, `Glass`) : sous chaque vitre qui vient
de casser (par le choc ou par ce script), une gerbe d'éclats (effet du jeu `glass_shards`), du **verre brisé à plat sur
la route** (3 plaques par vitre, décalques « verre » du jeu `5031` / `5032`, de 0,7 à 1,3 m, qui épousent le sol : plus
d'objets ni de bouteilles cassées) qui reste **5 minutes**, et
le **bruit du verre** (`Glass_Smash`, en plus de celui du jeu). Vu et entendu par tous les joueurs à moins de 120 m
(relayé par le serveur, chacun pose ses propres éclats : rien de synchronisé à gérer). Les vitres déjà cassées avant
l'accident (balles…) ne laissent pas de nouveau verre.

Chaque morceau ne tombe qu'une fois ; tout revient (usure comprise) à la réparation complète. Rien sur les motos,
vélos, bateaux, hélicoptères, avions et trains. Calculé par le conducteur (propriétaire du véhicule) : les morceaux
tombés, les portières entrouvertes et les tonneaux se voient chez tous les joueurs. `Glass.Models` (vide par défaut) :
objets posés en plus, si vous trouvez un modèle qui vous convient.

### Tirs sur un véhicule (`Gunshots`)

Une balle **bien placée** abîme vraiment le véhicule :
- dans le **moteur** (à moins de 0,85 m de l'os `engine` du véhicule ; sans cet os : le tiers avant, le capot) :
  santé du moteur - **dégâts de l'arme x 2,2** (pistolet ~55, fusil ~70, sniper ~220 par balle), sans la réduction
  appliquée aux dégâts du jeu : quelques balles bien placées le rendent très abîmé (il cale, fume), puis détruit ;
- dans le **réservoir** (os `petroltank…`) : réservoir percé, **l'essence fuit** (jamais d'explosion causée par ce script).
Ailleurs (portières, vitres, pneus) : le jeu, comme avant. C'est le **tireur** qui voit où sa balle a touché : il
l'envoie au serveur (20 balles / s au plus, à moins de 300 m), qui la transmet au joueur qui **contrôle le véhicule**
(lui seul peut changer sa santé). Aucune boucle : événement de dégâts du jeu.

## Ceinture de sécurité

- En s'attachant, le personnage fait le **geste du changement de station de radio** (`veh@std@ds@base` /
  `change_station`, côté passager `veh@std@ps@base`, haut du corps ; `Seatbelt.BuckleAnim`).
- Vrai son à l'attache et au retrait. **Attachée, impossible de descendre** (touche F bloquée) : il faut d'abord la
  détacher.
- **Carillon de ceinture**, par véhicule, moteur allumé, **dès que le véhicule roule à plus de 1 MPH** (`AlarmSpeed`) :
  il sonne **en boucle sans s'arrêter** jusqu'à ce que le véhicule soit **immobile** (0 MPH), que la personne
  **s'attache**, que le **moteur soit coupé** ou qu'elle **descende**. Il repart dès que le véhicule roule à nouveau :
  - **un** occupant détaché : `belt_chime.ogg` ;
  - **plusieurs** détachés en même temps : `belt_chime` **coupé net**, `fast_belt_chime.ogg` à la place ; dès qu'il
    n'en reste qu'un (l'un s'attache), `fast_belt_chime` s'arrête et `belt_chime` repart **du début** ;
  - véhicule immobile : moins de 0,3 MPH pendant 0,25 s (`StopSpeed` / `StopDelay` : une lecture isolée ne le coupe
    pas). `StopWhenStopped = false` pour qu'il continue à l'arrêt.
- **Descendre portière ouverte** : elle **reste ouverte**. Le jeu referme la portière à la fin de la descente ; une
  portière déjà ouverte avant de descendre (touche U / I…) est rouverte aussitôt, une seule fois (`KeepDoorOpenOnExit`).
- **Aucun son ne se multiplie** : chaque carillon (et le clignotant) est **un seul** fichier qui repart du début quand
  il arrive à sa fin (boucle), jamais relancé par-dessus lui-même, même si on met du temps à s'attacher ; `belt_on` /
  `belt_off` coupent le précédent avant de rejouer. Entendus par les occupants et autour du véhicule (règles ci-dessus).
- **Sons synchronisés** : les autres occupants les entendent à 100 %, les joueurs autour selon les règles ci-dessus
  (3 m portière ouverte, 1 m tout fermé et étouffés).
- **Éjection** (ceinture **détachée** uniquement ; l'éjection automatique du jeu reste désactivée) lors d'un vrai
  accident (choc qui fait perdre au moins 10 MPH, jamais un simple accrochage) :
  - **jamais en dessous de 60 MPH** (vitesse juste avant le choc) ;
  - **arrêt brutal** (de 60 MPH ou plus à **20 MPH ou moins**) : **70 %** de chances d'être éjecté ;
  - accident à 60 MPH ou plus **sans** chute aussi brutale : **45 %** de chances.
  Le joueur est d'abord **sorti du siège** (instantanément), puis **projeté en ragdoll** : corps inerte en chute libre,
  bras et jambes ballants (jamais assis ni debout en l'air), redonné l'image suivante une fois vraiment hors du
  véhicule, et maintenu pendant tout le vol. Même chose pour les **motos**. Il part par le pare-brise, par-dessus le toit,
  **dans le sens de la course**. C'est la **vitesse du véhicule** qui donne l'élan : une **impulsion de départ**
  calculée pour une distance **idéale** de **20 m à 60 MPH** à **60 m vers 120 MPH** (jamais plus rapide que le
  véhicule). Ce n'est **pas une limite** : ensuite la physique du jeu décide (il peut rouler un peu plus loin, ou
  s'arrêter plus tôt contre un obstacle), sans arrêt net. Il perd des points de vie. Attaché : jamais éjecté.
  Réglages : `Seatbelt` (`MinSpeed`, `SuddenStopSpeed`, `SuddenChance`, `AccidentDrop`, `CrashChance`,
  `IdealMinDistance`, `IdealMaxDistance`, `AirShare`, `ThrowLift`…).

## Motos : projection lors des accidents

Les motos n'ont pas de ceinture : ces règles s'appliquent au **pilote comme au passager**. Chaque joueur les applique
pour lui-même. Réglages : `Bike` dans `config.lua`.

- **Projection** pour **tout accident à partir de 35 MPH** (vitesse juste avant le choc) : **85 %** de chances.
  Un accident, c'est un choc qui fait perdre au moins 8 MPH, ou un choc contre un véhicule (perte d'au moins 3 MPH).
  - C'est le **même système** que l'éjection des voitures : ragdoll dès le départ, une impulsion de départ, puis la
    physique du jeu, sans arrêt net.
  - La **distance idéale grandit avec la vitesse** : **12 m à 35 MPH**, environ 26 m à 60 MPH, **60 m vers 120 MPH**.
    La projection n'est jamais plus rapide que la moto.
  - **Sens** : dans le sens de la course, avec un petit écart d'environ 10°.
  - **25 %** des projections partent ailleurs :
    - **sur le côté**, à gauche ou à droite (45 à 80° de la course, 75 % de la distance) ;
    - **vers l'arrière** (40 % de la distance), seulement quand c'est probable : choc contre une voiture ou un camion.
      Contre un mur, un poteau ou une autre moto, il part sur le côté.
  - Si le jeu désarçonne lui-même le motard pendant le choc, la même règle de projection s'applique, depuis l'endroit
    où il se trouve.
- **Rien d'autre** : aucune chute n'est ajoutée pour les petits incidents (trottoir, piéton, poteau, accident sous
  35 MPH ou sans projection). Le jeu garde son comportement normal.
- **Une seule décision par choc** : le même accident n'est jamais tiré deux fois.
- Une descente normale (touche F) ne déclenche rien.
- Vélos : ajoutez `[13] = true` dans `Bike.Classes`.

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
  Le jeu freinait tout seul un véhicule arrêté avec un joueur au volant (on ne pouvait plus le pousser) : pendant la
  poussée, le script appuie à sa place, très légèrement, sur la pédale dans le sens de la poussée (`Push.Pedal`), sans
  frein à main ; la vitesse reste celle de la poussée.
- Pendant la poussée, une notification rappelle « **K** Arrêter de pousser » ; **K** de nouveau pour arrêter. Arrêt
  automatique si le personnage tombe.
- **K ouvre aussi le MDC** : tant que le message est affiché (ou pendant la poussée), K n'ouvre pas le MDC (état du
  joueur `vcPushPrompt`, lu par le MDC). Ailleurs, K ouvre le MDC normalement. Les deux touches restent modifiables.

## Marche avant / marche arrière (touche ↑)

- **↑** (`Keys.gear`, modifiable : Raccourcis clavier > FiveM) passe de **D** (marche avant) à **R** (marche arrière)
  et inversement, avec un petit clic. Chaque véhicule part en **D**.
- **D** : on ne peut qu'**avancer et freiner**. Le frein (S) freine ; véhicule arrêté, il le **retient** au lieu de
  reculer.
- **R** : on ne peut que **freiner et reculer**. La marche arrière (S) recule ; l'accélérateur (Z / W) ne fait que
  freiner la marche arrière, puis retient le véhicule arrêté au lieu d'avancer.
- Affiché sur le **car HUD du MDC**, à droite : **R au-dessus de D**, une pastille glisse en douceur de l'un à l'autre
  (jaune en R). Pas de rapport sur les vélos, bateaux, hélicoptères, avions et trains (`Gear.SkipClasses`), ni pendant
  que le véhicule est poussé.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Keys` | touches par défaut (dont clignotants ← / →, warnings ↓, marche avant / arrière ↑) |
| `SoundVolume`, `SignalCancelAngle`, `SignalSoundMode`, `SignalInterval`, `SignalVolume` | volume sans le MDC, arrêt automatique du clignotant après un virage, son des clignotants (en boucle ou clic répété, rythme, volume) |
| `Fuel` | durée d'un plein (3 h 30), consommation au ralenti / plein gaz, classes, essence de départ, fuite, plein à la pompe (vitesse : 1 min max, distances, trappe arrière gauche `Flap`, pistolet et tuyau `Nozzle`), pompes, jerrican (2/5 d'un plein, vitesse, remplissage), stations (icônes) |
| `Damage` | dégâts légers / forts / sans choc, chocs violents, warnings automatiques d'accident important (`AccidentHazards`), paliers (abîmé ; 1 très abîmé : puissance, vitesse maxi, calages, warnings automatiques ; 2 détruit), fumée (`Smoke`), classes de véhicules légères, listes d'objets légers / forts |
| `Bodywork` | dégâts visuels : choc minimum (22 MPH), usure et chance de chaque morceau (vitres, pare-chocs, capot / coffre, pare-brise, roues), portières entrouvertes et déverrouillées sur un gros choc, jamais arrachées (`DoorsAjar`), verre brisé au sol (`Glass` : seuil, décalques, durée, effet, bruit, portée, objets facultatifs), part des chocs latéraux sur les pare-chocs, carrosserie usée, force pour arracher un pare-choc, classes sans dégâts visuels |
| `Gear` | marche avant / arrière : activée, vitesse considérée comme « arrêté », son du changement, classes sans rapport |
| `Rollover` | tonneaux accentués : vitesse minimale, inclinaison de départ, vitesse de rotation, élan, nombre de relances |
| `KeepDoorOpenOnExit` | portière ouverte gardée ouverte en descendant |
| `Seatbelt` | sons et carillons de la ceinture (un / plusieurs détachés ; dès 1 MPH moteur allumé, en boucle jusqu'à l'arrêt complet, l'attache, le moteur coupé ou la descente ; lecture des carillons `ChimeSoundMode` / `ChimeInterval`, boucle recollée `ChimeSeamless`, silence max `ChimeMaxGap`), éjection (dès 60 MPH : 70 % arrêt brutal / 45 % accident ; projeté en ragdoll, distance idéale 20-60 m selon la vitesse), classes sans ceinture |
| `Bike` | motos (pilote et passager) : projection dès 35 MPH (85 %, distance idéale 12-60 m selon la vitesse, 25 % sur le côté ou vers l'arrière si probable), aucune chute ajoutée pour les petits incidents (comportement du jeu), seuils, dégâts |
| `Repair` | commande `/repair` (moteur seulement), permission, distance |
| `VehicleSounds` | sons entendus autour du véhicule : 3 m portière ouverte, 1 m tout fermé (étouffé), volumes |
| `EngineNoticeDuration`, `EngineStartTime` | durée de la notification du moteur (8 s), durée du démarrage (1,2 s) |
| `StopLights`, `KeepWheelAngle` | feux stop à l'arrêt moteur tournant, angle des roues gardé à la descente |
| `Push` | vitesse de poussée, pression simulée sur la pédale avec quelqu'un au volant (`Pedal`), zone devant / derrière, position du personnage, animation, classes poussables |

## États des véhicules (pour d'autres scripts)

`Entity(vehicle).state` : `fuel` (0–100), `vcEngine` (toujours allumé), `vcBroken`
(moteur détruit), `vcDamaged` (moteur très abîmé ou détruit : fumée), `vcDoors` (qui a ouvert les portières avant), `vcSignal` (clignotants / warnings), `vcPushed` (poussé : par
qui, sens, poussée en cours). État du joueur : `seatbelt`, `seatbeltAlarm` (carillon de ceinture). Le serveur vérifie
chaque changement (conducteur, distance, essence qui ne monte qu'à la pompe, au rythme d'une pompe).
Événement local (client) `rp_vehiclecontrol:swapped` (`netId` de l'ancien véhicule, place) : le joueur est passé
directement dans un autre véhicule, l'ancien existe toujours (ex. `rp_interact` y coupe la radio).

## Performance

- À pied : une vérification toutes les 500 ms (~0.00 ms). Près d'un véhicule poussable (6 m) : toutes les 100 ms.
  Boucle à chaque image seulement près d'une pompe, pistolet de pompe sorti, jerrican en main, ou pendant la poussée.
  Tuyaux des autres joueurs : aucune boucle (état du joueur `vcHose`).
- À bord : ~0.02 ms (chocs, puissance ; à moto, en plus, une lecture de vitesse verticale pour les trottoirs) ; essence, dégâts, alarme et car HUD toutes les 100 ms ; ce qui a été
  percuté n'est cherché qu'au moment d'un choc ;
  car HUD envoyé seulement quand il change.
- Feux stop des véhicules des autres joueurs : boucle à chaque image seulement tant qu'un véhicule proche est arrêté
  moteur tournant ; roues : 2 s après une descente.
- Fumée des moteurs très abîmés : boucle d'1 s seulement tant qu'un véhicule fumant est connu (aucune sinon).
- Sorti d'un véhicule sans en descendre (véhicule supprimé, téléporté) : vérification à chaque image pendant 1 s au
  plus (nouveau véhicule ?), puis retour à la boucle à pied.
- Serveur : aucune boucle.
