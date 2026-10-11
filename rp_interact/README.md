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
Case **Civil** : rappel du **profil actif** en haut, puis **Créer un profil** et **Créer un véhicule** : ouvrent la
**fiche civile** et ferment le menu. Échap : retour / fermeture.

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
    **monter** à la place correspondante (si libre ; impossible si le véhicule est verrouillé) ;
  - personne : saluer ;
  - bancs, chaises, abribus : **s'asseoir** (à la place la plus proche sur un banc ; X ou se déplacer pour se lever) ;
  - poubelles, bennes : fouiller la poubelle.
- Le résultat s'affiche à droite de l'écran (fiche « Résultat ») et une copie arrive dans votre chat écrit.
- Une annonce RP est envoyée automatiquement dans le chat (`/me`, rayon de 100 m) : « observe attentivement
  l'individu », « fouille le coffre du véhicule »…
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

## Liens avec le MDC et le chat

- **Policier** = joueur dans une unité du MDC : export serveur `exports.mdc_standalone:getPlayerUnit(source)`
  (vérification fiable) et état `Player(source).state.mdcUnit` (affichage des options côté joueur).
- **Annonces RP** : export serveur `exports.rp_chat:sendMe(source, texte)`.
- Sans le MDC, personne n'est policier (inspections visuelles et olfactives seulement) ; sans le chat, pas d'annonce ni
  de copie dans le chat. Le reste fonctionne.

## Données

`data/profiles.json` (voir `data/LISEZMOI.txt`). Pour une base de données : remplacez `loadProfiles()` / `saveProfiles()`
dans `server/server.lua`. Console serveur : `rpi_reload` recharge le fichier.

## Performance

- Aucune boucle quand rien n'est utilisé (0.00 ms dans le resmon).
- L'œil tourne uniquement pendant que la touche est maintenue (visée toutes les 50 ms, tir bloqué) et s'arrête ensuite.
- Assis sur un banc : une petite boucle attend la touche pour se lever, puis s'arrête.
