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
| on tire soi-même | `Own` (0,05 ; silencieux : moitié) | |
| quelqu'un tire **près de nous** (joueur ou PNJ, moins de `Range` = 25 m) | `Near` (0,035 au plus près, moins en s'éloignant) | |
| quelqu'un tire **dans notre direction**, touché ou non (balle passée à moins de `IncomingRadius` = 2,5 m ; PNJ : en combat contre nous) | `Incoming` (0,12), quelle que soit la distance | **secousse** de la caméra (`IncomingShake`) |
| on est **touché** par une balle | `Hit` (0,22) | **bords légèrement rouges** (`HitColor`, `HitOpacity`) + secousse (`HitShake`) |

**Plus ça tire, plus l'effet s'étend** vers le centre : de `MinCoverage` (5 % de l'écran depuis chaque bord) jusqu'à
`MaxCoverage` (20 %) au plus. Sans nouveau tir, il **disparaît en `FadeOut` ms** (5,5 s ; le rouge : `HitFade`).
Il passe **au-dessus de tout** : HUD, PLD, car HUD, minimap, menus, MDC (pendant l'effet, l'interface de ce script
passe au premier plan, `SetNuiZindex(ZIndex)`, puis revient à 0). Tout se règle à la main dans **`config.lua` >
`Suppression`** (tailles, densité `Opacity`, flou `Blur`, traînées `Streaks`, grain `Grain`, couleur `Tint`, montées,
durées, secousses), puis `restart rp_weaponscontrol`.

La direction de chaque tir (du canon vers le point visé) est envoyée avec le paquet de tirs ; le serveur la vérifie
(départ près du tireur, longueur raisonnable) avant de la relayer. « Touché » vient de l'événement de dégâts du jeu
(seulement une arme à feu : pas le Taser, ni un coup de poing).

Note : une interface (NUI) ne peut pas flouter réellement l'image du jeu ni les autres interfaces ; le voile imite un
flou de mouvement (dense, traînées, grain), dessiné par-dessus.

### Lampe toujours allumée (`Flashlight`)
Une lampe **allumée par le joueur** (lampe sur l'arme, ou lampe de poche simple `WEAPON_FLASHLIGHT` /
`WEAPON_POCKETLIGHT`) **reste allumée** : en courant, sans viser, et **quand l'arme est rangée puis ressortie** (ou
reprise dans l'équipement), elle se rallume toute seule. Éteinte par le joueur : elle reste éteinte.

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
| `Suppression` | effet de tir sur les bords : montées (`Own`, `Near`, `Incoming`, `Hit`), portées, tailles (`MinCoverage`, `MaxCoverage`), aspect (`Opacity`, `Blur`, `Streaks`, `Grain`, `Tint`), rouge si touché, durée (`FadeOut`), premier plan (`ZIndex`), secousses |

## Performance

Sans arme à feu en main : une vérification toutes les 250 ms (**0.00 ms**). Arme à feu en main : lecture du tir à
chaque image (comme le jeu) ; PNJ armés à moins de 10 m : leurs tirs lus à chaque image tant qu'il y en a (liste
refaite toutes les 250 ms ; jusqu'à 25 m pour l'effet de tir) ; les effets ne tournent que quand quelqu'un tire.
L'effet sur les bords est dessiné par l'interface (aucune boucle Lua) et s'arrête complètement quand il a disparu.
