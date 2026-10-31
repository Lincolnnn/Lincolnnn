# RP Weapons Control

Gestion des armes à feu : **recul**, **effets au tir**, **acouphènes**, **flash de bouche** et **fumée du canon**,
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
| le tireur | **recul** (comme le script de Lyrad / Blumlaut) : la caméra remonte de 0,1° par image jusqu'à la valeur de l'arme (`Weapons` : pistolet 0,5°, fusil d'assaut 0,5°, pompe 0,4°, sniper 0,5 à 0,7°…), à la 3e personne, pas en drive-by ; **secousse** propre à l'arme (`shake`) |
| tout le monde à moins de 90 m | **flash jaune** au bout du canon qui éclaire les alentours, à chaque tir |
| joueurs à moins de 15 m | petite **secousse** de la caméra (plus forte près du tireur) |
| tout le monde à moins de 60 m | **fumée** : après **15 tirs rapides** (en 3 s), un filet de fumée sort du canon pendant 6 s |

**Acouphène** (léger) : seulement quand ça tire beaucoup tout près : **au moins 15 tirs en 10 s** par des tireurs à
**moins de 10 m** du joueur, que ce soit lui-même, un autre joueur ou un **PNJ**. Un sifflement discret monte puis
redescend (plus long s'il y a encore plus de tirs), puis plus rien pendant 12 s.

**Pas de rechargement automatique** : chargeur vide, il faut recharger soi-même (touche **R**).

Avec **`rp_camshake`** : avant chaque secousse de tir, il est mis en pause (`TriggerEvent('rp_camshake:pause', 800)`)
pour que son tremblement de marche ne modifie plus l'amplitude de la secousse du tir (premiers tirs 20 fois trop brusques).

### Effet de tir sur les bords de l'écran (`Suppression`)
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

**CartoonFlashlight** (ressource à part, lampe tenue en main avec ses animations, inchangée ; `Flashlight.Cartoon`) :
ses armes (`WEAPON_FLASHLIGHT`) sont gérées par elle ; ce script ne rallume plus la lampe du jeu sur ces armes (elle
doublait la lumière du modèle). États gardés : `exports.rp_weaponscontrol:flashlightWanted(arme)` /
`setFlashlight(arme, allumée)` / événement client `rp_weaponscontrol:flashlight` (utilisé par `rp_vehicleprops` quand
on reprend une arme posée avec sa lampe allumée).

**Aide au style du serveur** pour une autre ressource : `exports.rp_weaponscontrol:showHint(id, { title, lines })`
(lignes `{ touche, texte }` ou texte simple), à rappeler au moins toutes les 300 ms ; plus rappelée : retirée. Carte
noire, bandeau rouge, touches en gros, en haut à gauche. Utilisée par CartoonFlashlight (seule modification de ce
script : son aide, en français : « E Allumer / Éteindre la lampe », « O Changer de position »).

### Sélecteur de tir (`FireMode`)
Sur les armes **automatiques** (pistolets-mitrailleurs, mitrailleuses, fusils d'assaut, AP Pistol, Machine Pistol,
fusils à pompe automatiques ; `Groups` / `Weapons` / `Excluded`) : touche **B** (Raccourcis clavier > FiveM > « Arme :
coup par coup / automatique ») -> **petit clic** et **logo en bas au milieu de l'écran** : **AUTO** (orange, 3 balles)
ou **COUP PAR COUP** (blanc, 1 balle), affiché **3 s après l'appui** puis retiré (`BadgeSeconds` ; `Badge = true` :
affiché tant que l'arme est en main). Coup par coup : **un tir par pression de la détente**. Le mode est gardé pour
chaque arme. B sert aussi au Taser 10 (sécurité) : chacun ne réagit qu'à sa propre arme.

Arme avec **silencieux** : ni flash, ni acouphène, secousse réduite. Le Taser, le pistolet de détresse, le pistolet radar,
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
| `Flash` | activé, portée, couleur, rayon, intensité, durée (ms) |
| `Smoke` | activé, tirs et fenêtre (ms) pour la fumée, durée, délai entre deux, portée, effet de particules |
| `Tinnitus` | activé, portée (10 m), tirs (10) et fenêtre (10 s), PNJ compris, volume, durées, délai entre deux |
| `Shake` | secousse des voisins : activée, portée, force, type |
| `Sync` | portée du relais, paquets (ms), limite par seconde |
| `Suppression` | effet de tir sur les bords : montées (`Own`, `Near`, `Incoming`, `Hit`, `Curve`), portées, tailles (`MinCoverage`, `MaxCoverage`), voile (`Opacity`, `Blur`, `Streaks`, `Grain`, `Tint`), vrai flou du jeu (`GameBlur`), rouge si touché, durée (`FadeOut`), premier plan (`ZIndex`), secousses |

## Performance

Sans arme à feu en main : une vérification toutes les 250 ms (**0.00 ms**). Arme à feu en main : lecture du tir à
chaque image (comme le jeu) ; PNJ armés à moins de 10 m : leurs tirs lus à chaque image tant qu'il y en a (liste
refaite toutes les 250 ms ; jusqu'à 25 m pour l'effet de tir) ; les effets ne tournent que quand quelqu'un tire.
L'effet sur les bords : voile dessiné par l'interface (aucune boucle Lua) ; flou du jeu mis à jour ~30 fois par seconde
seulement pendant l'effet ; tout s'arrête quand il a disparu.
