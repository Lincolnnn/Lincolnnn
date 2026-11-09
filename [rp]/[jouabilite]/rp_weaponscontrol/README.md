# RP Weapons Control

Gestion des armes à feu : **recul**, **effets au tir**, **flash de bouche** et **fumée du canon**,
synchronisés avec les joueurs autour, et **effet de tir sur les bords de l'écran** (voile style motion blur, secousse
quand on nous tire dessus, bords rouges si on est touché). 100 % standalone, Lua 5.4.

## Installation

Dans `[rp]/` (déjà en place), puis dans `server.cfg` :

```cfg
ensure rp_weaponscontrol
```

## Ce qui se passe à chaque tir

| Pour qui | Effet |
|---|---|
| le tireur | **recul** (comme le script de Lyrad / Blumlaut) : la caméra remonte de 0,1° par image jusqu'à la valeur de l'arme (`Weapons` : pistolet 0,5°, fusil d'assaut 0,65°, pompe 0,45°, sniper 0,5 à 0,7°…), à la 3e personne, pas en drive-by ; **secousse** propre à l'arme (`shake`) |
| tout le monde à moins de 90 m | **flash jaune** au bout du canon qui éclaire les alentours, à chaque tir |
| joueurs à moins de 15 m | petite **secousse** de la caméra (plus forte près du tireur) |
| tout le monde à moins de 60 m | **fumée** : après **15 tirs rapides** (en 3 s), un filet de fumée sort du canon pendant 6 s |

**Acouphène : retiré** (plus aucun sifflement).

**Pas de rechargement automatique** : chargeur vide, il faut recharger soi-même (touche **R**).

Avec **`rp_camshake`** : avant chaque secousse de tir, il est mis en pause (`TriggerEvent('rp_camshake:pause', 800)`)
pour que son tremblement de marche ne modifie plus l'amplitude de la secousse du tir (premiers tirs 20 fois trop brusques).

### Effet de tir sur les bords de l'écran (`Suppression`)

**Par défaut (`Suppression.Visual = 'light'`) : SECOUSSES seulement + bords de l'écran légèrement assombris** (rouges
si touché), un simple dégradé dont l'opacité s'efface (aucun flou, aucun masque, aucun calcul image par image : pas
de perte de FPS). `'none'` : aucun effet visuel (secousses gardées). `'full'` : l'ancien effet décrit ci-dessous
(voile flouté, traînées, grain, vrai flou du jeu), **lourd pour les FPS**.
Un **voile style « motion blur »** sur les **bords de l'écran seulement** (jamais au centre) : transparent mais dense
(on voit à travers, mal), avec des traînées rayonnantes floutées et un léger grain. Il apparaît quand :

| Situation | Montée de l'effet (par tir) | En plus |
|---|---|---|
| on tire soi-même | `Own` (0,09 ; silencieux : moitié) | |
| quelqu'un tire **près de nous** (joueur ou PNJ, moins de `Range` = 25 m) | `Near` (0,06 au plus près, moins en s'éloignant) | |
| quelqu'un tire **dans notre direction**, touché ou non (balle passée à moins de `IncomingRadius` = 2,5 m ; PNJ : en combat contre nous) | `Incoming` (0,18), quelle que soit la distance | **secousse** de la caméra (`IncomingShake`) |
| on est **touché** par une balle | `Hit` | le **voile vire à la couleur `HitColor`** (dosée par `HitOpacity`) et les bords se teintent, puis il redevient gris (`HitFade`) + secousse (`HitShake`) |

L'effet est **bien visible dès les premiers tirs** (`Curve` = 0,5 : densité et flou montent vite), et **plus ça tire,
plus il prend de place**, petit à petit : de `MinCoverage` (10 % de l'écran depuis chaque bord) jusqu'à `MaxCoverage`
(32 %) au plus, après une longue rafale ; le centre reste toujours net. Sans nouveau tir, il **disparaît en `FadeOut` ms** (5,5 s ; le rouge : `HitFade`).
Il passe **au-dessus de tout** : HUD, PLD, car HUD, minimap, menus, MDC (pendant l'effet, l'interface de ce script
passe au premier plan, `SetNuiZindex(ZIndex)`, puis revient à 0). Tout se règle à la main dans **`config.lua` >
`Suppression`** (tailles, densité `Opacity`, flou `Blur`, traînées `Streaks`, grain `Grain`, couleur `Tint`, montées,
durées, secousses), puis `restart rp_weaponscontrol`.

La direction de chaque tir (du canon vers le point visé) est envoyée avec le paquet de tirs ; le serveur la vérifie
(départ près du tireur, longueur raisonnable) avant de la relayer. « Touché » vient de l'événement de dégâts du jeu
(seulement une arme à feu : pas le Taser, ni un coup de poing).

**Deux couches** :
- **vrai flou de l'image du jeu** (`GameBlur`) : le script crée un modificateur « timecycle » du jeu et règle ses
  variables de **flou en vignette** (bords flous, centre net, comme une photo floutée) et de **flou de mouvement**
  (recul, secousses), dosées selon l'intensité de l'effet, puis le retire. Les variables sont cherchées par leur nom
  dans le jeu (`blur_vignetting_intensity`, `blur_vignetting_radius`, `motionblur…`) : introuvables, message dans la
  console F8 et seul le voile reste. Le modificateur est posé dans l'emplacement « extra » du jeu (aussi utilisé par
  Vehicle Control après un choc : chacun ne retire que le sien) ;
- **voile par-dessus** (NUI, au-dessus de tout) : léger voile laiteux, traînées rayonnantes fondues et grain ; c'est
  lui qui couvre les interfaces (HUD, PLD, minimap, menus), qu'aucun script ne peut flouter réellement.

Aucun effet de couleur du jeu : l'ancien effet « zoom » (`RaceTurbo`, teinte orange grisâtre) est retiré.

« Touché » : l'arme est cherchée dans l'événement de dégâts du jeu (son empreinte y arrive non signée, à côté de
nombres à virgule : convertie avant d'être reconnue ; avant, elle ne l'était pas et le voile restait gris), sinon le
jeu indique « blessé par une arme tenue par quelqu'un » (ni corps à corps, ni véhicule). **`wc_hittest`** (F8) joue
l'effet « touché » pour régler la couleur ; **`wc_hitdebug`** affiche dans F8 ce que le jeu envoie quand on est blessé.

Réglage en jeu : **`wc_blurtest`** (F8) joue l'effet au maximum (`wc_blurtest 0.4` : à 40 %) et affiche les variables
de flou trouvées ; ajustez `Suppression.GameBlur` (`Intensity`, `RadiusMin` / `RadiusMax`, `MotionBlur`) et le voile
(`Opacity`, `Blur`, `Streaks`, `Grain`, `Tint`), puis `restart rp_weaponscontrol`.

### Lampe toujours allumée (`Flashlight`)
Une lampe **allumée par le joueur** (lampe sur l'arme, ou lampe de poche simple `WEAPON_FLASHLIGHT` /
`WEAPON_POCKETLIGHT`) **reste allumée** : en courant, sans viser, et **quand l'arme est rangée puis ressortie** (ou
reprise dans l'équipement), elle se rallume toute seule. Éteinte par le joueur : elle reste éteinte. **Arme baissée**
(sans viser) : elle reste allumée ; ce réglage du jeu est global et d'autres scripts le remettent à « seulement en
visant » (CartoonFlashlight à chaque fois que sa lampe démarre ou s'arrête) : il est réappliqué en permanence tant
qu'une arme est en main.

**Le script prend le dessus sur la lampe du jeu** (`Flashlight.Override = true`, défaut) : la lampe d'origine du jeu
(accessoire « lampe » des armes, lampe torche / de poche) **n'est plus jamais affichée** ; seule la lampe du script
(ci-dessous) l'est. La touche de la lampe du jeu (**E**) allume / éteint la lampe du script ; elle est gardée pour
chaque arme (rangée puis ressortie : comme elle était) et vue par tous (état `rpLamp`). Armes avec lampe : les
accessoires `Flashlight.Components` et les lampes tenues ; une arme ajoutée dont le jeu allume la lampe est reconnue
toute seule (sa lampe du jeu est coupée aussitôt). `Override = false` : la lampe du jeu reste, celle du script s'ajoute.
Ressource arrêtée : la lampe du jeu reprend (rallumée si la nôtre l'était).
**Chaque arme a sa propre lampe** : allumée sur le pistolet, elle ne l'est pas sur l'AR-15. Elle **reste allumée tant
que l'arme est en main**, ou **posée** (au sol ou sur un véhicule, puis reprise : elle revient allumée) ; **arme rangée**
(ou changée) : sa lampe **s'éteint**, à rallumer à la main (E). Le jeu qui rallume sa propre lampe en changeant d'arme
n'est jamais pris pour un allumage.

La touche E est prise sur **toutes les armes à feu** : la lampe du jeu ne s'allume jamais, même à la première
utilisation (arme ajoutée : un essai invisible vérifie qu'elle a une lampe). **Son** en allumant / éteignant (clic du
bouton, plus grave à l'extinction ; entendu plus bas par les joueurs à moins de 10 m ; `Flashlight.Sound`).

**Tache de lumière** : **centre puissant** (`Light.Core` = 60 % du cône, à `Intensity`, bord net `CoreRoundness`) et
**bords moins éclairés** (cône entier à `Intensity` x `Edge` = 0,3, bord doux) ; aussi pour CartoonFlashlight (son
`Config.Light`). Lueur / orbe de la lampe plus fine (`GlowSize`, `GlowRange`, `GlowIntensity`, `Beam.GlowAlpha`).

**Emplacement de la lampe par arme** (armes ajoutées, ex. PM4 ; admins) : **`/editflashlight`**, l'arme en main (comme
`/editspotlight`) : un **point rouge** montre le départ de la lumière (un trait : sa direction ; lampe éteinte : lumière
d'essai), curseurs **X / Y / Z** (axes de l'arme, m) en haut au milieu, à la souris. **Enregistrer pour tous** : gardé
par le serveur pour tous les joueurs, même après un redémarrage ; **Par défaut** : retiré ; **Terminer** (ou Échap) :
gardé pour vous jusqu'à la déconnexion. La ligne pour `config.lua` (`Flashlight.Positions`) s'affiche (et dans F8).
Permission : `add_ace group.admin rp_weaponscontrol.admin allow` (`Flashlight.EditAce`), ou la permission `command`.
Réglées dans `config.lua` : **PM4**, **Glock 19**, **P226** (`WEAPON_FM1_P226`), **MP92**.

**Modes d'intensité** (Bas / De base / Fort) : **lampe torche de CartoonFlashlight seulement** (touche **B**, son
`Config.Modes`) ; pas les lampes des armes. L'éblouissement suit le mode choisi.

**Nouveau système de lampe** (`Flashlight.Light`, `Beam`, `Glare`, `Strobe` ; repris de la base de `rp_spotlight`) :
tant que la lampe est allumée (lampe sur une arme **ou** lampe tenue en main), le script ajoute :
- **la lumière** : faisceau projeté avec ombres (les `Shadows` = 2 lampes les plus proches, pour ne pas éclairer à
  travers les murs), réglable **par catégorie** : `Light.Object` (lampe torche / de poche) et `Light.Weapon` (lampe des
  armes à feu). Réglages principaux : **`Range` = distance** (m) et **`Intensity` = puissance** ; puis `Radius`
  (largeur du cône), `Falloff` (atténuation), `Roundness`, `Color` (commune) ;
- **le faisceau visible** (`Beam`) : le cône de lumière dessiné dans l'air (textures `textures/beam.png` / `glow.png`),
  plus visible la nuit et sous la pluie (`Day`, `Rain`), opacité `Alpha` ;
- **la lueur de la lampe** : petit halo à la sortie de la lampe (`GlowRange`, `GlowIntensity`, `GlowSize`) ;
- **l'éblouissement** (`Glare`) : visé par une lampe d'arme ou pointé par une lampe torche (à moins de `GlareRange` m,
  dans l'axe), la lampe en vue : voile blanc et halo sur la lampe, plus fort de près, en la regardant en face et la
  nuit. **Moins fort que celui des projecteurs** (`rp_spotlight`) : voile 110 au plus (`Veil`, projecteur : 170), halo
  plus petit (`Size`), force `Strength` = 0,75 ; par catégorie : `GlareStrength`, `GlareRange` ;
- **le stroboscope** (`Strobe`) : touche **F7** (Raccourcis clavier > FiveM > « Lampe : stroboscope » ; pas L, qui
  sert à s'allonger) avec une lampe en main ou sur l'arme : la lampe clignote (`Hz` = 10 éclats/s, `Duty`), plus fort
  (`Power`) et plus éblouissante (`GlareBoost`). Vu par tous les joueurs proches. S'arrête en changeant d'arme, en
  montant dans un véhicule ou à la mort.

Les lampes des autres joueurs (moins de `OthersRange` = 80 m) sont dessinées pareil : tout le monde voit la même chose.
Performance : liste des lampes relue toutes les `CheckMs` = 250 ms ; le dessin à chaque image ne tourne **que** tant
qu'une lampe est allumée près de vous (0,00 ms sinon).

**Texture plus réaliste** (Realistic_Flashlight, de RespawnDG) : son fichier `graphics.ytd` (10 Mo) **n'est pas dans
le dépôt** (aucune licence fournie). Pour l'utiliser : créez le dossier `rp_weaponscontrol/stream/` et posez-y
`graphics.ytd` (FiveM diffuse tout seul ce dossier, rien à ajouter au manifeste), puis **retirez la ressource
`Realistic_Flashlight`** de `server.cfg` (deux ressources qui remplacent `graphics.ytd` se gênent). Le dossier
`stream/` de ce script est ignoré par git : le fichier reste chez vous.

**CartoonFlashlight** (ressource à part, version modifiée pour le serveur, fournie à part ; `Flashlight.Cartoon`) :
**utilisée par défaut** (`Cartoon.Enabled = true`) quand elle est démarrée : la lampe tenue (`WEAPON_FLASHLIGHT`), ses
animations, **sa lumière** et **son stroboscope** (F7) sont à elle, réglés dans **son** `config.lua` :
`Config.Light` (**`Range` = distance**, **`Intensity` = puissance**, `Radius`, `Falloff`, `Roundness`, `Color`,
`Shadows`, `OthersRange` ; `Enabled = false` : lumière d'origine du modèle) et `Config.Strobe`. Ce script ajoute à ses
lampes (la vôtre et celles des joueurs autour, lues par son export `lamps`) le **faisceau visible**, la **lueur** et
l'**éblouissement** (réglages `Light.Object`, `Beam`, `Glare` d'ici), sans seconde lumière. CartoonFlashlight
arrêtée, ou `Cartoon.Enabled = false` : la lampe tenue est gérée entièrement ici (`Light.Object`, stroboscope F7).
États gardés : `exports.rp_weaponscontrol:flashlightWanted(arme)` / `setFlashlight(arme, allumée)` / événement client
`rp_weaponscontrol:flashlight` (utilisé par `rp_vehicleprops` quand on reprend une arme posée avec sa lampe allumée).

**Aide au style du serveur** pour une autre ressource : `exports.rp_weaponscontrol:showHint(id, { title, lines })`
(lignes `{ touche, texte }` ou texte simple), à rappeler au moins toutes les 300 ms ; plus rappelée : retirée. Carte
noire, bandeau rouge, touches en gros, en haut à gauche. Utilisée par CartoonFlashlight (seule modification de ce
script : son aide, en français : « E Allumer / Éteindre la lampe », « O Changer de position »).

**Lampe en main** (lampe torche / de poche, lampes de CartoonFlashlight ; `Flashlight.HandLights`) : état local
`LocalPlayer.state.flashlightHand`. Ses touches (**E** allumer / éteindre, **O** position) passent avant celles des
autres scripts : pas de menu Équipement du véhicule ni de proposition « E » (`rp_equipment`), pas de pistolet /
jerrican d'essence sur E (`rp_vehiclecontrol`) tant qu'elle est en main.

### Sélecteur de tir (`FireMode`)
Sur les armes **automatiques** (pistolets-mitrailleurs, mitrailleuses, fusils d'assaut, AP Pistol, Machine Pistol,
fusils à pompe automatiques ; `Groups` / `Weapons` / `Excluded`) : touche **B** (Raccourcis clavier > FiveM > « Arme :
coup par coup / automatique ») -> **petit clic** et **logo en bas au milieu de l'écran** : **AUTO** (orange, 3 balles)
ou **COUP PAR COUP** (blanc, 1 balle), affiché **3 s après l'appui** puis retiré (`BadgeSeconds` ; `Badge = true` :
affiché tant que l'arme est en main). Coup par coup : **un tir par pression de la détente**. Le mode est gardé pour
chaque arme. B sert aussi au Taser 10 (sécurité) : chacun ne réagit qu'à sa propre arme.

**Armes longues en coup par coup** (`FireMode.Long`) : chaque fois qu'un joueur **prend en main** une arme longue à
sélecteur (fusils d'assaut, carabines, mitrailleuses, pistolets-mitrailleurs non compacts, fusils à pompe
automatiques : sortie de l'arme, changement d'arme, reprise sur un véhicule ou au sol…), elle passe en **coup par
coup** et le **logo du mode de tir s'affiche** quelques secondes (`BadgeSeconds`, sans clic), comme après un appui
sur B ; B la remet en automatique. `Long.Mode = false` : garder le dernier mode choisi ; `Long.Badge = false` : pas
de logo ; `Long.Groups` / `Long.NotLong` : ce qui compte comme arme longue (Micro SMG, Mini SMG, AP Pistol et Machine
Pistol, tenus comme un pistolet, n'en sont pas). Une arme longue sans sélecteur (pompe, précision) tire déjà au coup
par coup : pas de logo.

Arme avec **silencieux** : pas de flash, secousse réduite. Le Taser, le pistolet de détresse, le pistolet radar,
l'extincteur et le jerrican ne sont jamais concernés (`Excluded`). Les armes sont reconnues quel que soit le signe de
leur empreinte (le problème des « negative hashes » du script d'origine est réglé).

Synchronisation : le tireur envoie ses tirs par paquets (toutes les 100 ms) ; le serveur les vérifie, les limite
(25 paquets / s) et ne les relaie qu'aux joueurs à moins de 120 m. Chacun calcule le flash et la fumée sur l'arme du
tireur qu'il voit. Le sifflement est généré par le script (aucun fichier son).

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Weapons` | par arme (`WEAPON_…`) : `recoil` (remontée totale par tir, degrés), `shake` (secousse du tireur) |
| `Profiles` | par type d'arme : valeurs d'une arme absente de `Weapons`, force du bruit (`loudness`) |
| `Excluded` | armes jamais concernées |
| `Recoil` | activé, degrés par image (`Step`), douceur (`Smooth`), 1re personne, drive-by, multiplicateur |
| `NoAutoReload` | pas de rechargement automatique |
| `FireMode` | sélecteur de tir : touche, mode par défaut, clic, logo, armes concernées ; `Long` : armes longues en coup par coup à la prise en main (mode, logo, groupes) |
| `Flash` | activé, portée, couleur, rayon, intensité, durée (ms) |
| `Smoke` | activé, tirs et fenêtre (ms) pour la fumée, durée, délai entre deux, portée, effet de particules |
| `Shake` | secousse des voisins : activée, portée, force, type |
| `Sync` | portée du relais, paquets (ms), limite par seconde |
| `Suppression` | effet de tir sur les bords : montées (`Own`, `Near`, `Incoming`, `Hit`, `Curve`), portées, tailles (`MinCoverage`, `MaxCoverage`), voile (`Opacity`, `Blur`, `Streaks`, `Grain`, `Tint`), vrai flou du jeu (`GameBlur`), rouge si touché, durée (`FadeOut`), premier plan (`ZIndex`), secousses |

## Performance

Sans arme à feu en main : une vérification toutes les 250 ms (**0.00 ms**). Arme à feu en main : lecture du tir à
chaque image (comme le jeu) ; PNJ armés à moins de 10 m : leurs tirs lus à chaque image tant qu'il y en a (liste
refaite toutes les 250 ms ; jusqu'à 25 m pour l'effet de tir) ; les effets ne tournent que quand quelqu'un tire.
L'effet sur les bords : voile dessiné par l'interface (aucune boucle Lua) ; flou du jeu mis à jour ~30 fois par seconde
seulement pendant l'effet ; tout s'arrête quand il a disparu.

## Événements pour les autres scripts (client)

Aucun coût sans écouteur : `rp_weaponscontrol:shotNear` (n tirs, distance du tireur en m ; soi, autres joueurs, PNJ
armés jusqu'à `ShotEventRange` = 50 m) et `rp_weaponscontrol:bulletHit` (le joueur vient d'être touché par une balle).
Utilisés par `rp_adrenaline`.
