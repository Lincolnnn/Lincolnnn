# RP DLS (`rp_dls`)

Adaptation **FiveM** de **DLS** (*Dynamic Lighting System*, GTA V solo), **DLS v1 et DLS v2** : les véhicules DLS
retrouvent **tous leurs modes** (stages, **Cruise**, **Traffic Advisor**, **Takedown**, **Alley lights**, **Park**,
Phaser, Horn, clignotants…), **synchronisés entre tous les joueurs**, avec les **mêmes fichiers de véhicules XML que
DLS**, sans les modifier.
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

### Véhicules DLS v2 (`<Model vehicles="…">`)

Un fichier DLS v2 sert à **plusieurs modèles** (liste dans `<Model vehicles="…">`) et ses modes modifient les
gyrophares du **carcols du véhicule** : `rp_dls` a donc aussi besoin du `carcols.meta` et du `carvariations.meta`
du pack.

1. Copiez les fichiers DLS v2 tels quels dans `rp_dls/dls/` (ex. `dls/nlspdumk.xml`).
2. Copiez le `carcols.meta` et le `carvariations.meta` de la ressource du véhicule dans
   `rp_dls/dls/packs/<nom du pack>/` (ex. `dls/packs/nlspd/carcols.meta`).
3. Dans `config.lua`, mettez le **nom des fichiers** DLS v2 (pas les modèles : ils sont lus dans le fichier) et le
   pack :

```lua
Vehicles = { 'nlspdumk', 'nlspdscouts', 'nlspdmpower' },
Packs = { 'nlspd' },
```

Au démarrage, la console serveur liste chaque modèle trouvé (stages, TA, cruise, takedown, alley, nombre de modes,
réglage du carcols) et signale ce qui manque (fichier absent, modèle absent du carvariations…).

Repris de DLS v2 :
- **Modes** : chaque mode actif part des gyrophares du carcols (`apply_default_siren_settings`) ou de gyrophares
  éteints, puis applique ses `<Sequences>` et `<SirenSettings>` (`sequencerBpm`, `intensity`, `syncToBpm`,
  `multiples`, `delta`, `color`), dans l'ordre du fichier (le dernier l'emporte).
- **Groupes de commandes** : `Stages` (touche du jeu, J, pavé 1 à 3), `TA` (L : directions d'après le nom des modes),
  `Cruise` ([ : modes à la suite puis éteint), `Takedown` (pavé 9), `Left Alley` / `Right Alley` (pavé 6, panneau).
- **Déclencheurs** (`<Triggers>` / `<Requirements>`, `<All>` / `<Any>`, `delay_time`, `stay_on_time`) :
  `AudioMode` (sirène), `LightMode` (autre mode), `Speed`, `Time` (heure du jeu), `Weather`, `Doors`,
  `LightEmissive` (clignotants, feux stop), `Braking`, `Driver`, `VehicleOwner`. Les modes Park, Park night, Phaser,
  Horn, alley à l'ouverture des portières la nuit, clignotants, Door Kill, Braking… s'allument donc tout seuls.
- **Sons** : groupe `Siren` (un ton par entrée, plusieurs sirènes à la fois : ex. Siren2 + Siren1d), groupe `Horn`
  (air horn maintenu sur E, qui coupe la sirène s'il est exclusif), `soundset` / `soundbank` des packs de sons.
- **Gyrophares d'origine** gardés par le jeu tant que les modes actifs ne font qu'**ajouter** des gyrophares éteints
  dans le carcols (ex. stage 3 + clignotant sur un gyrophare orange) : rendu du jeu et PNJ qui se rangent ; sinon
  tout est dessiné à partir du carcols.
- Takedown et alley (`intensity` forte) : **vrais projecteurs** dans la direction de l'ampoule (`delta` du carcols).

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
| **[** | Cruise / Steady Burn (feux fixes ; DLS v2 : Cruise 1 → Cruise 2 → éteint) |
| **]** | Plafonnier |
| **Pavé 0** | Blackout : tous les feux éteints, phares compris (seule cette touche répond ensuite) |
| **R** | Sirène marche / arrêt (gyrophares allumés) |
| **1 / 2 / 3 / 4** | Ton 1 / 2 / 3 / 4 (même touche : couper) |
| **6** | Deuxième sirène (ton 1) par-dessus la première |
| **B** (maintenir) | Sirène manuelle ; **B + E** : ton 2 |
| **E** (klaxon) | Air horn (sirène coupée : air horn seul ; `AirHornInterruptsSiren` : remplace la sirène) |
| **Pavé 7** | Scan : tons changés au hasard toutes les 2 à 8 s |
| **Pavé 8** | Verrouiller / déverrouiller toutes les touches DLS |
| **Pavé 9** | Takedown : projecteurs avant (DLS v2 : modes du groupe Takedown à la suite, puis éteint) |
| **Pavé 6** | Alley : projecteur gauche → droite → les deux → éteint |
| **Pavé 5** | Afficher / masquer le panneau |
| **/dls** | Panneau cliquable à la souris (boutons, glisser le titre pour le déplacer, double-clic : position par défaut, Échap pour fermer) |

En conduisant un véhicule DLS, le klaxon du jeu, la caméra cinéma (R), la sélection d'arme sur 1 à 6 et la radio
(`DisableRadio`, et la roue des radios qui partage la touche des gyrophares) sont bloqués, comme dans DLS. Les clignotants restent ceux de `rp_vehiclecontrol`.

## Panneau

Petit panneau sombre en bas à droite (position gardée) : gyrophares allumés / éteints avec la touche du jeu à
utiliser, stages disponibles du véhicule (point vert : gyrophares d'origine), Cruise, plafonnier, blackout, scène
(Takedown, Alley gauche / droite, voyant PARK), Traffic Advisor (direction, motif, chenillard animé), tons, deuxième
sirène, scan, voyants HORN et MANUEL, verrou ; en DLS v2, la liste des modes actifs. Les touches réellement attribuées par le joueur sont affichées sur les
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
- DLS v2 : `<Extras>` (extras du véhicule allumés par un mode) pas encore pris en charge ; une condition inconnue
  est considérée fausse (message dans la console F8). `syncToBpm = false` avec un `speed` : rythme du bpm gardé.
- Les modes déclenchés (clignotants, park…) ne s'appliquent qu'aux véhicules déjà utilisés par un joueur ; un
  véhicule de PNJ jamais touché garde ses gyrophares du jeu.
- DLS v1 : **stationnement** (`Park`) : arrêté 2 s, gyrophares allumés, sans sirène, motif côté gauche / côté droit
  dessiné à partir du stage (ou du carcols du pack) ; takedown / alley : projecteurs dessinés par le script.

## Réglages utiles (`config.lua`)

- `Render` : distance d'affichage, nombre d'éclairages par image (`MaxLights`), portée et intensité de
  l'éclairage, taille des halos, halos masqués derrière les murs / en vue intérieure.
- `Stage3FromCarcols`, `SirenControlNonDLS`, `SirenKill`, `DisableRadio`, `DefaultTones`, `DefaultHorn`.
- **Diagnostic** : `setr dls_debug 1` (console F8) affiche le **numéro de chaque gyrophare** (os `sirenN`) sur le
  véhicule le plus proche, pour remplir les segments du Traffic Advisor ou les `Sirens` du Steady Burn.

*DLS (Dynamic Lighting System) est un plugin RagePluginHook open source de TheMaybeast (GPL-3.0). `rp_dls` en lit
le format de fichiers ; son code est écrit pour FiveM.*
