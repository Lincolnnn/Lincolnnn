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

Case **Police** : indique si vous êtes en service (dans une unité du MDC) et ce que l'œil vous permet.
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
| Personne | Inspection visuelle, Inspection olfactive | Fouiller la partie supérieure du corps, Fouiller la partie inférieure du corps, Détail notoire |
| Véhicule | Inspection visuelle intérieure, Inspection visuelle extérieure, Inspection olfactive | Détail notoire, Fouille de l'habitacle, Fouille de la banquette arrière, Fouille du coffre |

- Les résultats d'une personne sont **ceux de son profil actif** ; sans profil (ou PNJ) : réponses par défaut.
- Les inspections sont listées en premier, puis les actions sur l'environnement :
  - véhicule : **ouvrir / fermer la portière visée** (avant gauche, avant droite, arrière…), le capot ou le coffre,
    **monter** à la place correspondante (si libre ; impossible si le véhicule est verrouillé). Une portière ouverte
    ainsi est **refermée par le joueur** dès qu'il est à bord et que le véhicule commence à avancer ;
  - personne : saluer ;
  - bancs, chaises, abribus : **s'asseoir** (à la place la plus proche sur un banc ; X ou se déplacer pour se lever) ;
  - poubelles, bennes : fouiller la poubelle.
- Le résultat est **privé** : la fiche « Résultat » (à droite de l'écran) et sa copie dans le chat écrit (étiquette
  `PRIVÉ`) ne s'affichent que chez le joueur qui inspecte.
- L'annonce RP, elle, est publique : un `/me` automatique (mêmes règles qu'un `/me` : joueurs dans un rayon de 100 m)
  « observe attentivement l'individu », « fouille le coffre du véhicule »…
- Véhicule observé : seul le **modèle** est affiché (jamais la plaque d'immatriculation).
- Le serveur revérifie tout : police (unité du MDC), distance (8 m), délai entre deux inspections.

Les modèles de bancs, chaises et poubelles se règlent dans `config.lua` (`Seats`, `TrashBins`).

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `MenuKey`, `TargetKey` | touches par défaut (F1, Alt gauche) ; chaque joueur les change dans Échap > Paramètres > Raccourcis clavier > FiveM |
| `MdcResource`, `ChatResource` | noms des dossiers du MDC et du chat |
| `ObjectDistance`, `EntityDistance` | portée de l'œil (objets / personnes et véhicules) |
| `AllowSelfTarget` | viser son propre personnage (test) ; `false` en production si vous préférez |
| `InspectDistance`, `InspectCooldown` | contrôles serveur |
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
