# RP DLS (`rp_dls`)

Adaptation **FiveM** de **DLS** (*Dynamic Lighting System*, GTA V solo) : les véhicules DLS retrouvent **tous leurs
stages** (stage 1, 2, 3, custom 1 et 2, **Steady Burn / Cruise**, **Traffic Advisor**, Wail Setup…),
**synchronisés entre tous les joueurs**, avec les **mêmes fichiers de véhicules XML que DLS**, sans les modifier.
Sirènes (4 tons, deuxième sirène, manuelle, air horn sur le klaxon, scan) et panneau de commande NUI.
**100 % standalone** (sans ESX / QBCore / vRP).

## Pourquoi un seul stage sur FiveM, et ce que fait ce script

Dans le jeu, un véhicule n'a **qu'un seul réglage de gyrophares** : celui de son `carcols.meta` (`sirenSettings` de
`carvariations.meta`). DLS solo change ce réglage pendant la partie en **modifiant la mémoire du jeu** grâce à
RagePluginHook (`EmergencyLightingOverride`). **FiveM n'a aucun équivalent** : aucune fonction ne permet de changer
les gyrophares d'un véhicule en jeu. C'est pour ça que vos véhicules DLS n'affichent qu'un stage.

`rp_dls` contourne ce manque :

- le stage dont le véhicule dispose déjà (son carcols, le **stage 3** par défaut) reste **affiché par le jeu** :
  rendu parfait, ampoules allumées, phares wig-wag, et les **PNJ se rangent** ;
- les **autres stages sont dessinés par le script**, à partir des `<Sirens>` du XML de DLS, comme le ferait le jeu :
  chaque `<Item>` du stage correspond à l'os `sirenN` du modèle, allumé selon sa **séquence de 32 temps**
  (`flashiness` / `rotation`) au rythme du `sequencerBpm`, × `multiples`, avec sa **couleur** :
  **halo** sur l'ampoule (atténué quand elle regarde de l'autre côté, masqué derrière un mur ou un bâtiment) et
  **éclairage** de la route et des murs (`light = true`) ;
- **Traffic Advisor** et **Steady Burn** remplacent la séquence de leurs ampoules, comme dans DLS ;
- **horloge commune** (heure du réseau) : tous les joueurs voient les mêmes éclats au même moment.

## Installation

1. Copiez le dossier `rp_dls` dans `resources/`.
2. Dans `server.cfg` : `ensure rp_dls` (après vos véhicules). **OneSync** recommandé.
3. Vos véhicules DLS restent **streamés comme avant** (leur ressource avec `.yft`, `carcols.meta`,
   `carvariations.meta`…) : `rp_dls` ne les remplace pas.
4. Copiez leurs **fichiers DLS** (GTA V solo : `Plugins/DLS/<modèle>.xml`) **tels quels** dans `rp_dls/dls/`
   (nom du fichier = nom du modèle) et ajoutez le modèle à `Vehicles` dans `config.lua` :

```lua
Vehicles = {
    'police',                                -- dls/police.xml
    { model = 'police2', file = 'police' },  -- plusieurs modèles sur un même fichier
    { model = 'sheriff', native = { 1 } },   -- stage 1 affiché par le jeu (carcols) au lieu du stage 3
},
```

`dls/police.xml` est un exemple complet et commenté (stages 1 et 2 dessinés, stage 3 d'origine, Steady Burn,
Traffic Advisor à 3 segments, stage gardé en descendant).

## Allumer / éteindre les gyrophares : touche du jeu de base

Les gyrophares s'allument et s'éteignent **uniquement avec la touche du jeu de base** (la même pour les deux) :
**A** sur un clavier AZERTY (Q en QWERTY), croix gauche à la manette. C'est un contrôle de GTA (`LightsControl =
85`), réglé dans les paramètres du jeu, **pas** dans les raccourcis FiveM. L'allumage reprend le **dernier stage
utilisé** sur ce véhicule (sinon le premier du XML, voir `LightsOnStage`). Gyrophares éteints, les touches de stage
DLS ne font rien.

## Touches DLS (par défaut, modifiables : Échap > Paramètres > Raccourcis clavier > FiveM > « DLS : … »)

Celles de DLS solo, sauf **K** (MDC), **G** (ceinture) et **T** (chat), déjà prises sur ce serveur. Conducteur
d'un véhicule DLS ou d'urgence seulement.

| Touche | Action |
|---|---|
| **A** (jeu de base) | Allumer / éteindre les gyrophares |
| **J** | Stage suivant (1 → 2 → 3 → custom… → 1), gyrophares allumés |
| **Pavé 1 / 2 / 3** | Stage 1 / 2 / 3 direct, gyrophares allumés |
| **L** | Traffic Advisor : gauche → diverge → droite → warn → éteint |
| **Pavé 4** | Traffic Advisor : motif suivant |
| **[** | Steady Burn / Cruise (feux fixes) |
| **]** | Plafonnier |
| **Pavé 0** | Blackout : tous les feux éteints, phares compris (seule cette touche répond ensuite) |
| **R** | Sirène marche / arrêt (gyrophares allumés) |
| **1 / 2 / 3 / 4** | Ton 1 / 2 / 3 / 4 (même touche : couper) |
| **6** | Deuxième sirène (ton 1) par-dessus la première |
| **B** (maintenir) | Sirène manuelle ; **B + E** : ton 2 |
| **E** (klaxon) | Air horn (sirène coupée : air horn seul ; `AirHornInterruptsSiren` : remplace la sirène) |
| **Pavé 7** | Scan : tons changés au hasard toutes les 2 à 8 s |
| **Pavé 8** | Verrouiller / déverrouiller toutes les touches DLS |
| **Pavé 5** | Afficher / masquer le panneau |
| **/dls** | Panneau cliquable à la souris (boutons, glisser le titre pour le déplacer, double-clic : position par défaut, Échap pour fermer) |

En conduisant un véhicule DLS, le klaxon du jeu, la caméra cinéma (R), la sélection d'arme sur 1 à 6 et la radio
(`DisableRadio`, et la roue des radios qui partage la touche des gyrophares) sont bloqués, comme dans DLS. Les clignotants restent ceux de `rp_vehiclecontrol`.

## Panneau

Petit panneau sombre en bas à droite (position gardée) : gyrophares allumés / éteints avec la touche du jeu à
utiliser, stages disponibles du véhicule (point vert : gyrophares d'origine), Cruise, plafonnier, blackout, Traffic Advisor (direction, motif, chenillard animé), tons, deuxième
sirène, scan, voyants HORN et MANUEL, verrou. Les touches réellement attribuées par le joueur sont affichées sur les
boutons.

## Synchronisation

Un seul état par véhicule, `dls` (*state bag* du véhicule) : stage, Traffic Advisor et son motif, Steady Burn,
plafonnier, blackout, ton, deuxième sirène, air horn. Il est **écrit par le serveur seul**, après vérification :
l'auteur **conduit** le véhicule (ou vient d'en descendre : stage gardé, sirène coupée) et chaque valeur existe
pour ce modèle (stages de son XML, TA et Steady Burn seulement s'il en a…). Chaque client l'applique aux véhicules
proches : **tout le monde voit les mêmes gyrophares et entend les mêmes sirènes**, jouées depuis le véhicule (même
conducteur descendu). Le conducteur voit ses changements tout de suite. Un véhicule qu'aucun joueur n'a touché (PNJ)
est laissé au jeu.

## Ce qui est repris de DLS

| Fichier DLS | Repris |
|---|---|
| `<StageSettings>` | `Stage1Enabled`… `CustomStage2Enabled`, `GetStage3FromCarcols` |
| `<Sirens>` | `Stage1`, `Stage2`, `Stage3`, `CustomStage1`, `CustomStage2` (sequencerBpm, timeMultiplier, lightFalloffMax ; par ampoule : flashiness, rotation, multiples, color, intensity, corona, light, rotate) |
| `<SoundSettings>` | `Tone1`…`Tone4`, `Horn`, `AirHornInterruptsSiren`, `SirenKillOverride` |
| `<SpecialModes>` | `PresetSirenOnLeaveVehicle` (stage gardé en descendant, stage d'avant repris en remontant), `WailSetup`, `SteadyBurn` (`Pattern`, `Sirens`) |
| `<TrafficAdvisory>` | `Type` (three / four / five / six), `DivergeOnly`, `AutoEnableStages`, `AutoDisableStages`, `DefaultEnabledDirection`, `TAgroup`, `DefaultTApattern`, segments `L EL CL C CR ER R` |
| `Traffic Advisory/*.xml` | Groupes de motifs (format `TAgroup`) dans `dls/trafficadvisory/` ; `default.xml` contient les motifs documentés par DLS (+ Warn) et un motif « chase » |

**Sons d'un pack de sirènes** (autre ressource avec sa banque audio) : `NOM@BANQUE` dans `<Tone1>`… (ex.
`NOM_DU_SON@NOM_DE_LA_BANQUE`, voir la documentation du pack). Sans `@`, ce sont les sons du jeu.

**Véhicules d'urgence sans fichier DLS** (`SirenControlNonDLS`) : gyrophares d'origine (un stage), tons, air
horn, manuelle et scan pris en charge de la même façon.

## Limites (FiveM)

- Sur un **stage dessiné**, les **PNJ ne se rangent pas** (le jeu ne le fait que gyrophares d'origine allumés) :
  gardez le stage d'urgence sur le carcols (`Stage3FromCarcols = true`, par défaut).
- Sur un stage dessiné, les **ampoules du modèle** ne s'allument pas elles-mêmes : ce sont les halos et l'éclairage
  du script qui les remplacent. Les séquences des **phares / feux arrière** (`leftHeadLight`…) ne sont reproduites
  que sur le stage d'origine.
- Traffic Advisor ou Steady Burn sur le stage d'origine : ce stage est alors dessiné à partir du XML (s'il le
  décrit), sinon TA / Steady Burn sont dessinés par-dessus les gyrophares d'origine.
- Gyrophares tournants (`rotate`) : rotation approchée.

## Réglages utiles (`config.lua`)

- `Render` : distance d'affichage, nombre d'éclairages par image (`MaxLights`), portée et intensité de
  l'éclairage, taille des halos, halos masqués derrière les murs / en vue intérieure.
- `Stage3FromCarcols`, `SirenControlNonDLS`, `SirenKill`, `DisableRadio`, `DefaultTones`, `DefaultHorn`.
- **Diagnostic** : `setr dls_debug 1` (console F8) affiche le **numéro de chaque gyrophare** (os `sirenN`) sur le
  véhicule le plus proche, pour remplir les segments du Traffic Advisor ou les `Sirens` du Steady Burn.

*DLS (Dynamic Lighting System) est un plugin RagePluginHook open source de TheMaybeast (GPL-3.0). `rp_dls` en lit
le format de fichiers ; son code est écrit pour FiveM.*
