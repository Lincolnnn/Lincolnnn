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

## Menu d'interactions (touche F1)

Case **Police** : indique si vous êtes en service (dans une unité du MDC), puis les actions **Menotter**,
**Prendre par le bras**, **Placer l'individu à l'arrière du véhicule** et **Faire s'asseoir l'individu** : toujours affichées, **grisées** tant que
personne (joueur ou PNJ) n'est assez près (2 m ; véhicule à 6 m pour placer), mises à jour en direct. Elles agissent
sur l'individu le plus proche.
Case **Civil** : rappel du **profil actif** en haut, la case **Mode civil**, puis **Créer un profil** et
**Créer un véhicule** (ouvrent la **fiche civile** et ferment le menu) et, en mode civil, **Tips arrestation**.
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
| **X** (fixe) | Arrêter l'emote en cours | `/e c` |

- Il apparaît quand un **policier** (joueur dans une unité du MDC) vous **met en joue avec une arme** : visée directe
  ou à moins de **5 m** autour de vous (titre « Un policier vous tient en joue »), et disparaît peu après la fin de la visée.
- Sans mise en joue : Menu > Civil > **Tips arrestation** l'affiche (60 s, ou jusqu'à un nouveau clic).
- Les touches ne font l'emote **que pendant que le mini menu est affiché** (et jamais quand une fenêtre est ouverte).
- Touches modifiables par chaque joueur : Échap > Paramètres > Raccourcis clavier > FiveM > « Civil : … ».
  Les emotes (`/e …`) viennent de votre script d'emotes ; commandes et touches par défaut dans `config.lua` (`Surrender`).
- Côté policier, la détection ne tourne que pendant qu'il maintient le **clic droit** (visée) et qu'il est en service ;
  le serveur vérifie l'unité et la distance, et la mise en joue expire seule si le policier se déconnecte.

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

- **Menotter** (2 m, **7 s** de barre) : le civil fait l'emote **`/e menotté1`** et porte des menottes aux poignets
  (`p_cs_cuffs_02_s`). Si l'emote s'arrête (bousculé, monté dans un véhicule, touche…), elle est **relancée
  automatiquement** ; menotté, il ne peut plus courir, sauter, frapper, viser ni monter seul dans un véhicule.
  **Retirer les menottes** : 3 s.
- **Prendre par le bras** (individu le plus proche, 2 m) : le policier fait **`/e tenirlebras`**, l'individu est placé un
  peu devant à droite, **bien droit** (accroché à l'os racine du policier, `DragBone = 0`) ; il **marche quand le
  policier marche** et s'arrête avec lui. **Lâcher le bras** pour le relâcher.
- **Faire s'asseoir l'individu** (2 m, à pied, pas tenu par le bras) : il fait l'emote **`/e menotté2`** (assis au sol).
  Menotté, il **reste assis** (déplacements bloqués, emote relancée si elle s'arrête). **Faire se relever l'individu**
  pour le remettre debout (`/e menotté1` s'il est menotté). Le prendre par le bras ou le placer dans un véhicule le
  relève aussi. Sur un PNJ : animation `SeatedAnim` (à adapter si votre emote en utilise une autre).
- **Placer l'individu à l'arrière** (en le tenant, véhicule à 6 m) : le policier lâche le bras et ouvre la portière arrière
  la plus proche ; l'individu **monte lui-même** à l'arrière (sans téléportation, places arrière uniquement), même dans
  un véhicule d'urgence. **Faire sortir l'individu (arrière)** pour le ressortir.
- Sur un PNJ, le client du policier fait tout lui-même (animation de secours `mp_arresting` au lieu de l'emote).

### Menottes : modèle `p_cs_cuffs_02_s`

Le modèle existe déjà dans le jeu. Pour utiliser votre propre fichier, créez le dossier **`rp_interact/stream/`** et
placez-y **`rp_interact/stream/p_cs_cuffs_02_s.ydr`** (FiveM le charge automatiquement, aucune ligne à ajouter dans
`fxmanifest.lua`), puis redémarrez la ressource. Autre nom de modèle : `CuffProp` dans `config.lua`.

### Véhicules d'urgence : `/policeon` et `/policeoff`

`/policeon` : les véhicules de la catégorie du jeu « véhicule d'urgence » (classe 18) sont **verrouillés** pour les
joueurs qui ne sont pas policiers en service (unité du MDC) : ils essaient d'ouvrir la portière (animation du jeu) mais
n'y arrivent pas, **sans aucun message**. Exceptions : portière déjà ouverte, individu placé à l'arrière par un
policier, joueur déjà à bord (il peut descendre). L'œil ne leur propose plus d'ouvrir les portières ni de monter.
Les policiers ne sont jamais bloqués. `/policeoff` : tout est déverrouillé. Effet immédiat, sans redémarrage ni annonce
aux autres joueurs : **seul l'auteur de la commande reçoit une notification** confirmant le changement (et une ligne
dans la console serveur). Commande autorisée : console, policiers en service, ou permission ACE
`rpinteract.admin` (`add_ace group.admin rpinteract.admin allow`).

Les modèles de bancs, chaises et poubelles se règlent dans `config.lua` (`Seats`, `TrashBins`).

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `MenuKey`, `TargetKey` | touches par défaut (F1, Alt gauche) ; chaque joueur les change dans Échap > Paramètres > Raccourcis clavier > FiveM |
| `MdcResource`, `ChatResource` | noms des dossiers du MDC et du chat |
| `ObserveDistance`, `SearchDistance`, `ActionDistance`, `DoorDistance`, `ObjectDistance`, `DeleteDistance` | distances : observations (10 m), fouilles (3 m), menottes / bras / assis (2 m), portières (3 m), bancs et poubelles (2,5 m), supprimer (50 m) |
| `AllowSelfTarget` | viser son propre personnage (test) ; `false` en production si vous préférez |
| `InspectCooldown`, `SearchDurations` | délai entre deux observations ; durée des fouilles (15 s personne, 35 s véhicule) |
| `CuffDuration`, `UncuffDuration`, `Emotes`, `CuffAnim`, `SeatedAnim`, `CuffProp`, `DragOffset`, `DragBone`, `PlaceVehicleDistance` | police : durées, emotes (`/e menotté1`, `/e menotté2`, `/e tenirlebras`, `/e c`), animations de contrôle / secours (debout, assis), menottes, position et os d'attache de l'individu tenu, distance du véhicule |
| `DeleteAccess`, `DeleteAce` | qui peut supprimer (PNJ, véhicules sans joueur, objets) |
| `PoliceVehiclesAce` | permission ACE pour `/policeon` / `/policeoff` |
| `MaxProfiles`, `TextMax` | profils par joueur, longueur des textes |
| `AnnounceWithMe`, `ResultsInChat`, `ResultDuration` | `/me` automatiques, copie dans le chat, durée d'affichage |
| `Defaults` | réponses par défaut |
| `Seats`, `TrashBins` | objets de l'environnement |
| `Surrender` | tips d'arrestation : commande, touche par défaut, libellé et emote de chaque action |
| `AimRadius`, `AimRange`, `AimRefresh`, `AimWatchKey` | mise en joue : rayon autour du civil, portée, confirmation, touche de visée surveillée |
| `TipsAimDelay`, `TipsManualDuration` | durée des tips après la mise en joue / ouverts depuis le menu |

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

`data/profiles.json` (voir `data/LISEZMOI.txt`). Pour une base de données : remplacez `loadProfiles()` / `saveProfiles()`
dans `server/server.lua`. Console serveur : `rpi_reload` recharge le fichier.

## Performance

- Aucune boucle quand rien n'est utilisé (0.00 ms dans le resmon).
- L'œil tourne uniquement pendant que la touche est maintenue (visée toutes les 50 ms, tir bloqué) et s'arrête ensuite.
- Assis sur un banc : une petite boucle attend la touche pour se lever, puis s'arrête.
- Portière ouverte avec l'œil : surveillance légère (250 ms) jusqu'à ce qu'elle soit refermée.
- Policier qui vise (clic droit maintenu, en service) : détection toutes les 200 ms, uniquement pendant la visée.
- Barre de chargement : boucle uniquement pendant la fouille / le menottage.
- Menotté : boucle pendant qu'on est menotté (contrôles bloqués, emote vérifiée chaque seconde) ; tenu par le bras :
  100 ms tant qu'on est tenu ; PNJ menottés : 1 s tant qu'il y en a.
- Tips d'arrestation : la touche fixe X est lue uniquement pendant que les tips sont affichés.
- L'œil d'un joueur autorisé à supprimer vise jusqu'à 60 m (50 m + caméra) au lieu de 25 m : même coût (un rayon).
- `/policeon` : chez les non-policiers, une vérification des véhicules d'urgence proches toutes les 500 ms (100 ms
  pendant une tentative de montée), uniquement tant que la règle est active ; policier : 1 s, sans rien faire.
