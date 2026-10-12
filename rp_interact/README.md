# RP Interact (FiveM)

Menu d'interactions, **fiches civiles** (profils et véhicules) et **Eye Target** (« l'œil »), **100% standalone**
(sans ESX / QBCore / vRP), NUI en HTML/CSS/Vanilla JS. Relié au MDC (`mdc_standalone`) et au chat écrit (`rp_chat`)
du même dépôt.

Le but : limiter les échanges écrits entre civils et policiers. Le civil prépare à l'avance ce que la police découvrira
(inspection, fouille, détail notoire) ; le policier l'obtient en visant la personne ou le véhicule avec l'œil.

## Installation

1. Copiez le dossier `rp_interact` dans `resources/` (à côté du MDC et du chat, pas à l'intérieur).
2. Dans `server.cfg` (après le MDC et le chat) : `ensure rp_interact`
3. **OneSync recommandé** : il permet au serveur de vérifier les distances et de supprimer le profil d'un véhicule
   dès que le véhicule disparaît.
4. **Emotes** : les emotes (`/e menotté2`, `/e tenirlebras`, `/e serendre17`…) viennent du mode
   d'emotes du serveur (dossier **RPEMOTES** / rpemotes / rpemotes-reborn), détecté automatiquement
   (`EmotesResource = 'auto'`). Au démarrage, le serveur lit l'**animation exacte** de chaque emote dans ses fichiers
   et l'écrit dans la console : `[RP Interact] Emotes lues dans "RPEMOTES" : menotté2 (…), tenirlebras (…)…`. Une emote
   introuvable est signalée en jaune : vérifiez son nom dans `config.lua` (`Emotes`, `Surrender`) ou ajoutez le
   fichier qui la définit à `EmoteFiles`. `rpi_emotes` (console) relit les fichiers.

## Menu d'interactions (touche F1)

Case **Police** : tout en bas, **Display MDC** : **Secteur** (zone de jeu, saisi à la main) et **Service principal**
(menu déroulant : APD, GSP ou APD & GSP), enregistrés aussitôt, gardés chez le joueur et affichés sur le display du
MDC (« aucun sélectionné » sinon). Au-dessus : si vous êtes en service (dans une unité du MDC), puis les actions **Menotter**,
**Prendre par le bras**, **Placer l'individu à l'arrière du véhicule** et **Faire s'asseoir l'individu** : toujours affichées, **grisées** tant que
personne (joueur ou PNJ) n'est assez près (2 m ; véhicule à 6 m pour placer), mises à jour en direct. Elles agissent
sur l'individu le plus proche.
Case **Civil** : rappel du **profil actif** en haut, la case **Mode civil**, puis **Créer un profil** et
**Créer un véhicule** (ouvrent la **fiche civile** et ferment le menu) et, en mode civil, **Tips arrestation**.
Case **Équipements** : **Tenues** (EUP) et **Armes** (loadouts) que vous enregistrez dans **`data/equipment.lua`**
(seules les tenues du personnage homme / femme sont proposées) ; **Remettre ma tenue** (celle d'avant la première tenue
enfilée) et **Retirer mes armes**. Réservé aux policiers en service (`EquipmentPoliceOnly`). D'autres options pourront
s'ajouter ici.
Case **Voiture** :
- **Spawn** : en haut, deux options gardées chez le joueur : **Supprimer l'ancien véhicule** (le dernier que vous avez
  fait apparaître, s'il n'y a pas d'autre joueur dedans) et **Apparaître dans le véhicule** (sinon devant vous). Puis
  **Police** (deux listes : **Atlanta Police Department** et **Georgia State Patrol**, réservées aux policiers en service,
  `SpawnPoliceOnly`) et **Autres**. Seuls les véhicules de **`data/vehicles.txt`** sont proposés, une ligne par
  véhicule : `spawn code ; service ; nom affiché ; livery ; extras` (ex. `apdfordexplorer2016 ; Atlanta Police
  Department ; Atlanta Police Dept / FPIU 2016 ; 1 ; 1,3`). La **livery** et les **extras** indiqués sont appliqués à
  l'apparition (extras listés activés, les autres désactivés). `rpi_vehicles` (console) relit le fichier. Le véhicule
  apparaît moteur coupé, plein fait (Vehicle Control).
- **Radio** : collez un **lien** (vidéo / musique YouTube, ou lien direct vers un fichier audio, un podcast, une radio
  en ligne) : le son est joué **dans le véhicule**. Tout le monde l'entend **au même moment et au même volume de base**
  (le volume est celui du véhicule : à 89 %, tout le monde l'a à 89 %). À bord : normalement ; dehors : de moins en
  moins fort avec la distance (`RadioRange`, 30 m) et **insonorisé** (son étouffé et plus faible) si aucune vitre n'est
  baissée et aucune portière n'est ouverte. Réglable seulement par les **places avant**, ou avec l'**œil** en visant
  l'intérieur avant du véhicule, **portière avant ouverte** (option « Radio du véhicule »). L'effet étouffé est un vrai
  filtre pour les liens directs qui l'autorisent ; pour YouTube, c'est une baisse du volume.

Échap : retour / fermeture.

**En service** = dans une unité du MDC : dès que vous rejoignez une unité, les fouilles et détails notoires
apparaissent dans l'œil (notification) ; dès que vous la quittez, ils sont retirés (et refusés par le serveur).

## Mode civil (case à cocher, gardée chez chaque joueur)

Ajoute des options visuelles propres au rôle de civil. La première : les **tips d'arrestation**, un mini menu
**non interactif** en haut au milieu de l'écran :

| Touche (par défaut) | Action | Commande lancée |
|---|---|---|
| **H** | Mains en l'air | `/e serendre17` |
| **J** | À genoux | `/e serendre3` |
| **L** | S'allonger | `/e serendre6` |
| **X** (fixe) | Arrêter l'emote en cours | arrêt par RPEMOTES (export `EmoteCancel`) |

- Il apparaît quand un **policier** (joueur dans une unité du MDC) vous **met en joue avec une arme** : visée directe
  ou à moins de **5 m** autour de vous (titre « Un policier vous tient en joue »).
- Sans mise en joue : Menu > Civil > **Tips arrestation** l'affiche.
- Il ne se ferme **qu'avec la touche Échap** (rappel « Échap : fermer » écrit en tout petit, en gris foncé, en bas du
  mini menu) : il **reste affiché quand le policier arrête de viser** (le titre redevient « Tips arrestation »).
  Pendant qu'il est affiché, Échap ferme les tips **sans ouvrir le menu pause ni la carte** (la pause reste bloquée
  jusqu'au relâchement de la touche).
- Les touches ne font l'emote **que pendant que le mini menu est affiché** (et jamais quand une fenêtre est ouverte).
  Chaque touche est un **raccourci de la commande `/e …`** de RPEMOTES (exactement comme si le joueur la tapait).
- **X** : l'emote est arrêtée par RPEMOTES lui-même (export `EmoteCancel`), ce script prend le dessus sur le X de
  RPEMOTES : plus de message « ^1Help^0 : No emote to cancel ». (Ancienne version de rpemotes sans cet export :
  `/e c` n'est envoyé que si une emote est réellement jouée.)
- Touches modifiables par chaque joueur : Échap > Paramètres > Raccourcis clavier > FiveM > « Civil : … ».
  Commandes et touches par défaut dans `config.lua` (`Surrender`).
- **Détection fiable** côté policier : tant qu'il est en service (unité du MDC), sa visée est surveillée en continu
  (aucune touche à maintenir : clic droit, manette ou raccourci modifié fonctionnent), les joueurs visés sont
  envoyés au serveur toutes les 150 ms pendant la visée et confirmés chaque seconde ; le serveur vérifie l'unité et la
  distance, et la mise en joue expire seule si le policier se déconnecte. Le civil doit avoir coché **Mode civil**.

Thème : celui du HUD (contour gris fin, angles légèrement arrondis), fond noir foncé transparent à 20 %.

## Fiche civile (style MDC, en dehors du MDC)

### Profils (permanents : `data/profiles.json`)

Liste de **vos** profils uniquement (20 max). Cliquer sur un profil affiche son détail avec **Définir comme profil
actif**, **Modifier** (puis Enregistrer) et **Supprimer**. Le premier profil créé devient actif automatiquement.

| Partie | Cases | Non coché / vide |
|---|---|---|
| Nom du profil | obligatoire | — |
| **Inspection** — *Observations visuelles et olfactives* | ☐ Visuel, ☐ Olfactif | « Rien à signaler » / « Rien d'anormal » / « Tout est correct » |
| **Fouille** — *Contenu de ce que détient votre personnage* | ☐ Partie supérieure du corps, ☐ Partie inférieure du corps | « Rien à signaler » / « Aucun élément » / « Rien d'illégal » |
| **Détail notoire** | texte facultatif | « Aucun détail notoire » |

Pour une même personne, la réponse par défaut choisie dans la liste est toujours la même.

### Véhicule (temporaire)

Le véhicule dans lequel vous êtes, sinon le plus proche (6 m). Le profil est **lié au véhicule physique** : il disparaît
quand le véhicule est supprimé ou au redémarrage du serveur, et n'est pas enregistré dans vos profils. Seul son créateur
peut le modifier ou le supprimer.

| Partie | Non rempli |
|---|---|
| ☐ **Inspection visuelle** → Intérieur, Extérieur | « Rien d'anormal » / « Tout semble normal » / « Rien de suspect » / « Rien à signaler » |
| **Inspection olfactive** (texte) | « Rien d'anormal » / « Rien de suspect » |
| **Détail notoire** | « Aucun détail notoire » |
| **Fouille** : Habitacle, Banquette arrière, Coffre | « Rien à signaler » / « Aucun élément » / « Rien d'illégal » |

## Eye Target (maintenir Alt)

Un œil apparaît au centre de l'écran ; il s'allume (bleu) quand la cible propose des options, avec son nom.
**Clic gauche** : liste des options, clic sur une option pour l'exécuter. **Échap**, clic droit ou clic à côté : fermer.

Fonctionne partout : **tous les joueurs**, **les PNJ**, **vous-même** (test : visez votre personnage en vue à la
3e personne, `AllowSelfTarget`), **tous les véhicules** (avec ou sans profil, enregistrés ou non) et les objets configurés.

| Cible | Tout le monde | Policier (dans une unité du MDC) en plus |
|---|---|---|
| Personne | Inspection visuelle, Inspection olfactive (10 m) | Détail notoire (10 m) ; Fouiller la partie supérieure / inférieure du corps (3 m, **15 s**) ; Menotter / Retirer les menottes, Prendre / Lâcher le bras, Faire s'asseoir / se relever (2 m) |
| Véhicule | Inspection visuelle intérieure / extérieure, Inspection olfactive (10 m) | Détail notoire (10 m) ; Fouille de l'habitacle, de la banquette arrière, du coffre (3 m, **35 s**) ; Placer l'individu à l'arrière (6 m, en le tenant par le bras) ; Faire sortir l'individu (arrière) |

- **Distances** : les observations se font jusqu'à **10 m**, les fouilles à **3 m**, menottes et bras à **2 m**. Les options
  apparaissent au fur et à mesure qu'on s'approche (elles ne sont jamais grisées pour une question de distance).
  Seule exception : **Supprimer**, proposée jusqu'à **50 m** (`DeleteDistance`) aux joueurs autorisés ; c'est la seule
  option visible au-delà de 10 m.
- **Fouilles** : barre de chargement (thème du HUD, barre bleue) — **15 s** pour une personne, **35 s** pour un véhicule.
  Pendant la fouille on ne se déplace pas ; **X** l'annule (elle s'interrompt aussi si la cible s'éloigne). Le serveur ne
  donne le résultat qu'une fois le temps écoulé.
- Une personne est toujours présentée comme « **Individu** » : ni identité, ni nom du profil actif, ni mention PNJ.
- Les résultats d'une personne sont **ceux de son profil actif** ; sans profil (ou PNJ) : réponses par défaut.
- Les inspections sont listées en premier, puis les actions sur l'environnement :
  - véhicule : **ouvrir / fermer la portière visée** (avant gauche, avant droite, arrière…), le capot ou le coffre,
    **monter** à la place correspondante (si libre ; impossible si le véhicule est verrouillé). Une portière ouverte
    ainsi est **refermée par le joueur** dès qu'il est à bord et que le véhicule commence à avancer. Après `/policeon`,
    ces options n'apparaissent plus sur un véhicule d'urgence pour un joueur qui n'est pas policier ;
  - personne : saluer ;
  - **Supprimer** (jusqu'à **50 m**) : PNJ, véhicule sans joueur à bord, objet — **y compris les véhicules et objets
    créés par des joueurs ou des scripts**. Réservé aux policiers en service (`DeleteAccess`) ou à la permission ACE
    `rpinteract.delete`. Jamais un joueur, ni un véhicule où se trouve un joueur. Avec OneSync, le serveur supprime
    l'élément pour tout le monde ; s'il est encore là, le client en prend le contrôle et le supprime. Une notification
    confirme « Élément supprimé. » (ou explique l'échec). Les objets de la carte sont masqués chez tous les joueurs
    (`rpi_showprops` en console pour tout réafficher) ;
  - bancs, chaises, abribus : **s'asseoir** (à la place la plus proche sur un banc ; X ou se déplacer pour se lever) ;
  - poubelles, bennes : fouiller la poubelle.
- Le résultat est **privé** : la fiche « Résultat » (à droite de l'écran) et sa copie dans le chat écrit (étiquette
  `PRIVÉ`) ne s'affichent que chez le joueur qui inspecte.
- L'annonce RP, elle, est publique : un `/me` automatique (mêmes règles qu'un `/me` : joueurs dans un rayon de 50 m)
  « observe attentivement l'individu », « fouille le coffre du véhicule »…
- Véhicule observé : seul le **modèle** est affiché (jamais la plaque d'immatriculation).
- Le serveur revérifie tout : police (unité du MDC), distances (10 m / 3 m / 2 m), durée des fouilles, délais.

### Police : menottes, prendre par le bras, véhicule (joueurs ET PNJ, pour tester seul)

- **Menotter** (2 m, **7 s** de barre) : **comportement de base de GTA 5**, sans emote : menottes du jeu
  (`SetEnableHandcuffs`) et animation « mains dans le dos » du jeu (`CuffAnim` : `mp_arresting idle`), avec les
  menottes aux poignets (`p_cs_cuffs_02_s`, dans leur toute première position). Si l'animation s'arrête (bousculé,
  monté dans un véhicule…), elle est **relancée automatiquement** ; menotté, il ne peut plus courir, sauter, frapper,
  viser ni monter seul dans un véhicule (les menottes du jeu sont levées le temps d'être placé / sorti par un
  policier). **Retirer les menottes** : 3 s.
- **Prendre par le bras** (individu le plus proche, 2 m) : le policier fait **`/e tenirlebras`**, l'individu est placé à
  sa droite, un peu devant (`DragOffset`). Il n'est **pas accroché** au policier : il suit sa position et **tourne sur
  son propre axe** pour s'orienter comme lui (`DragTurnSpeed`), sans pivoter avec le tronc du policier ; ses
  collisions restent supprimées. Il **marche quand le policier marche**. **Lâcher le bras** (œil, menu) ou touche
  **X** (`DragReleaseKey`, modifiable : Raccourcis clavier > FiveM > « Police : lâcher le bras »).
- **Faire s'asseoir l'individu** (2 m, à pied, **menotté uniquement**, pas tenu par le bras) : il fait l'emote
  **`/e menotté2`** (RPEMOTES) et **reste assis** (déplacements bloqués). Si l'emote s'arrête, c'est **la même**
  (`/e menotté2`, puis son animation exacte lue dans RPEMOTES) qui est relancée : plus de changement d'emote.
  La pose assise est celle de l'emote, telle quelle (plus d'inclinaison).
  **Faire se relever l'individu** : l'emote assise est arrêtée, il reprend la posture menotté du jeu. Le prendre par le
  bras ou le placer dans un véhicule le relève aussi.
- **Menottes** : position réglable (`CuffPropPlacement`, par défaut leur toute première position : rotation
  265 / 155 / 80, prévue pour l'animation du jeu).
- **Placer l'individu à l'arrière** (en le tenant, véhicule à 6 m) : **le policier va ouvrir lui-même** la portière
  arrière la plus proche (animation du jeu), puis lâche le bras ; l'individu **monte lui-même** à l'arrière (sans
  téléportation, places arrière uniquement), même dans un véhicule d'urgence, **sans refermer la portière** : le
  policier la referme avec l'œil. **Faire sortir l'individu (arrière)** : le policier ouvre la portière, l'individu
  descend et la laisse ouverte ; le policier la referme avec l'œil.
- Sur un PNJ, le client du policier fait tout lui-même (animation de l'emote lue dans RPEMOTES ; à défaut, les
  animations de secours `CuffAnim` / `SeatedAnim`).

### Menottes : modèle `p_cs_cuffs_02_s`

Le modèle existe déjà dans le jeu. Pour utiliser votre propre fichier, créez le dossier **`rp_interact/stream/`** et
placez-y **`rp_interact/stream/p_cs_cuffs_02_s.ydr`** (FiveM le charge automatiquement, aucune ligne à ajouter dans
`fxmanifest.lua`), puis redémarrez la ressource. Autre nom de modèle : `CuffProp` dans `config.lua`.

### Véhicules de police : `/policeon` et `/policeoff`

**Policier** = joueur dans une unité de police du MDC (vérifié aussi par le serveur).

- **`/policeoff`** (par défaut, **à chaque redémarrage du serveur**) : aucune règle, tout le monde monte dans tous les
  véhicules. Le script ne fait alors strictement rien (aucune boucle, aucune action sur les véhicules).
- **`/policeon`** : **seuls les policiers** montent dans un véhicule de police. Tous les autres joueurs (mode civil
  coché ou non) :
  - **essaient d'ouvrir la portière, elle reste verrouillée** : la tentative du jeu est arrêtée **avant que la
    portière bouge**, le joueur marche lui-même jusqu'à la portière visée, **bien en face**, à quelques centimètres
    de la poignée (`LockedDoorStand`), puis tire sur la poignée (`LockedDoorAnim`) ; la portière ne bouge pas,
    **la vitre n'est jamais cassée**, impossible de voler le véhicule à son conducteur ;
  - **peuvent faire apparaître un véhicule de police** : le véhicule apparaît et **reste** (jamais supprimé), mais le
    joueur en **descend aussitôt** et ne peut plus y remonter ;
  - ne voient plus, avec l'œil, les options d'ouverture des portières ni « Monter ».
- Exceptions : l'individu **placé à l'arrière par un policier** y monte et y reste ; une portière **ouverte par un
  policier** (œil « Ouvrir la portière », placer / faire sortir un individu) : un civil peut monter par celle-là
  (et seulement celle-là, tant qu'elle reste ouverte). Le policier qui la referme avec l'œil la reverrouille
  (nécessite OneSync : la portière est notée dans l'état du véhicule par le serveur).
- Un policier qui quitte son unité en étant à bord n'est pas éjecté : la règle ne concerne que la montée.
- Aucun verrou n'est posé sur le véhicule (un verrou est partagé par le réseau et bloquait aussi les policiers) :
  seul le jeu de chaque non-policier agit, sur son propre personnage.
- Véhicule de police : catégorie du jeu « véhicule d'urgence » (`PoliceVehicleClasses = { 18 }`) ou modèle listé
  dans `PoliceVehicleModels` (véhicules ajoutés rangés dans une autre catégorie).

Effet immédiat, sans redémarrage ni annonce aux autres joueurs : **seul l'auteur de la commande reçoit une
notification** confirmant le changement (et une ligne dans la console serveur). Commande autorisée : console,
policiers en service, ou permission ACE `rpinteract.admin` (`add_ace group.admin rpinteract.admin allow`).

Les modèles de bancs, chaises et poubelles se règlent dans `config.lua` (`Seats`, `TrashBins`).

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `MenuKey`, `TargetKey` | touches par défaut (F1, Alt gauche) ; chaque joueur les change dans Échap > Paramètres > Raccourcis clavier > FiveM |
| `MdcResource`, `ChatResource` | noms des dossiers du MDC et du chat |
| `SpawnPoliceOnly`, `EquipmentPoliceOnly` | véhicules de police (Voiture > Spawn) et équipements réservés aux policiers en service |
| `RadioRange`, `RadioInsulation`, `RadioMaxVolume` | radio du véhicule : portée dehors, volume quand tout est fermé (insonorisé), volume maximal |
| `ObserveDistance`, `SearchDistance`, `ActionDistance`, `DoorDistance`, `ObjectDistance`, `DeleteDistance` | distances : observations (10 m), fouilles (3 m), menottes / bras / assis (2 m), portières (3 m), bancs et poubelles (2,5 m), supprimer (50 m) |
| `AllowSelfTarget` | viser son propre personnage (test) ; `false` en production si vous préférez |
| `InspectCooldown`, `SearchDurations` | délai entre deux observations ; durée des fouilles (15 s personne, 35 s véhicule) |
| `EmotesResource`, `EmoteFiles` | mode d'emotes (RPEMOTES, `'auto'` = détecté) et fichiers supplémentaires où lire les emotes |
| `CuffPropPlacement`, `LockedDoorStand` | position / orientation des menottes ; où se tient le civil devant une portière verrouillée |
| `CuffDuration`, `UncuffDuration`, `Emotes`, `CuffAnim`, `SeatedAnim`, `CuffProp`, `DragOffset`, `DragTurnSpeed`, `DragReleaseKey`, `PlaceVehicleDistance` | police : durées, emotes (`/e menotté2`, `/e tenirlebras`, `/e c`), animation menotté debout du jeu (`CuffAnim`) et animation assise de secours (si l'emote est introuvable dans RPEMOTES), menottes, position / rotation de l'individu tenu, touche pour lâcher le bras, distance du véhicule |
| `DeleteAccess`, `DeleteAce` | qui peut supprimer (PNJ, véhicules sans joueur, objets) |
| `PoliceVehiclesAce`, `PoliceVehicleClasses`, `PoliceVehicleModels`, `LockedDoorAnim` | permission ACE pour `/policeon` / `/policeoff` ; ce qui compte comme véhicule de police ; animation « poignée verrouillée » |
| `MaxProfiles`, `TextMax` | profils par joueur, longueur des textes |
| `AnnounceWithMe`, `ResultsInChat`, `ResultDuration` | `/me` automatiques, copie dans le chat, durée d'affichage |
| `Defaults` | réponses par défaut |
| `Seats`, `TrashBins` | objets de l'environnement |
| `Surrender` | tips d'arrestation : commande, touche par défaut, libellé et emote de chaque action |
| `AimRadius`, `AimRange`, `AimRefresh` | mise en joue : rayon autour du civil, portée, confirmation |

## Liens avec le MDC et le chat

- **Policier** = joueur dans une unité du MDC : export serveur `getPlayerUnit(source)` du MDC (vérification fiable,
  lue à chaque fouille) et état `Player(source).state.mdcUnit` (affichage des options côté joueur, mis à jour à
  chaque entrée / sortie d'unité).
- **Noms des ressources** : le MDC et le chat publient eux-mêmes leur nom (`GlobalState.mdcResource`,
  `GlobalState.rpChatResource`) : peu importe le nom de leurs dossiers. Si le MDC est introuvable ou trop ancien
  (avant v1.18), la console serveur l'indique au démarrage.
- **Annonces RP** : export serveur `sendMe(source, texte)` du chat ; résultats privés : export client `addPrivate`.
- Sans le MDC, personne n'est policier (inspections visuelles et olfactives seulement) ; sans le chat, pas d'annonce ni
  de copie dans le chat. Le reste fonctionne.

## Données

`data/profiles.json` (voir `data/LISEZMOI.txt`). **À remplir vous-même** : `data/vehicles.txt` (véhicules du menu
Voiture > Spawn) et `data/equipment.lua` (tenues EUP et armes du menu Équipements). Pour une base de données : remplacez `loadProfiles()` / `saveProfiles()`
dans `server/server.lua`. Console serveur : `rpi_reload` recharge le fichier.

## Performance

- Aucune boucle quand rien n'est utilisé (0.00 ms dans le resmon). Radio : une vérification toutes les 250 ms
  seulement tant qu'une radio est allumée dans un véhicule à portée réseau.
- L'œil tourne uniquement pendant que la touche est maintenue (visée toutes les 50 ms, tir bloqué) et s'arrête ensuite.
- Assis sur un banc : une petite boucle attend la touche pour se lever, puis s'arrête.
- Portière ouverte avec l'œil : surveillance légère (250 ms) jusqu'à ce qu'elle soit refermée.
- Policier en service : une lecture de la visée toutes les 250 ms (~0.00 ms) ; pendant qu'il vise, détection des
  joueurs visés toutes les 150 ms. Hors service : aucune boucle.
- Barre de chargement : boucle uniquement pendant la fouille / le menottage.
- Menotté : boucle pendant qu'on est menotté (contrôles bloqués, emote vérifiée chaque seconde) ; tenu par le bras :
  suivi à chaque image (position fluide) UNIQUEMENT tant qu'on est tenu ; PNJ menottés : 1 s tant qu'il y en a.
- Lâcher le bras avec X : raccourci FiveM (aucune boucle).
- Tips d'arrestation : les touches fixes X et Échap sont lues uniquement pendant que les tips sont affichés.
- L'œil d'un joueur autorisé à supprimer vise jusqu'à 60 m (50 m + caméra) au lieu de 25 m : même coût (un rayon).
- `/policeoff` : aucune boucle. `/policeon` : une vérification toutes les 200 ms chez les non-policiers (à chaque
  image seulement pendant une tentative de montée dans un véhicule de police), 1 s chez les policiers.
