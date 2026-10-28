# RP Weapons Control

Gestion des armes à feu : **recul**, **effets au tir**, **acouphènes**, **flash de bouche** et **fumée du canon**,
synchronisés avec les joueurs autour. 100 % standalone, Lua 5.4.

## Installation

Dans `[rp]/` (déjà en place), puis dans `server.cfg` :

```cfg
ensure rp_weaponscontrol
```

## Ce qui se passe à chaque tir

| Pour qui | Effet |
|---|---|
| le tireur | **recul** (comme le script de Lyrad / Blumlaut) : la caméra remonte de 0,1° par image jusqu'à la valeur de l'arme (`Weapons` : pistolet 0,3°, pompe 0,4°, sniper 0,5 à 0,7°…), à la 3e personne, pas en drive-by ; **secousse** propre à l'arme (`shake`) |
| tout le monde à moins de 90 m | **flash jaune** au bout du canon qui éclaire les alentours, à chaque tir |
| joueurs à moins de 15 m | petite **secousse** de la caméra (plus forte près du tireur) |
| tout le monde à moins de 60 m | **fumée** : après **7 tirs rapides** (en 3 s), un filet de fumée sort du canon pendant 6 s |

**Acouphène** (léger) : seulement quand ça tire beaucoup tout près : **au moins 10 tirs en 10 s** par des tireurs à
**moins de 10 m** du joueur, que ce soit lui-même, un autre joueur ou un **PNJ**. Un sifflement discret monte puis
redescend (plus long s'il y a encore plus de tirs), puis plus rien pendant 12 s.

**Pas de rechargement automatique** : chargeur vide, il faut recharger soi-même (touche **R**).

Avec **`rp_camshake`** : avant chaque secousse de tir, il est mis en pause (`TriggerEvent('rp_camshake:pause', 800)`)
pour que son tremblement de marche ne modifie plus l'amplitude de la secousse du tir (premiers tirs 20 fois trop brusques).

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

## Performance

Sans arme à feu en main : une vérification toutes les 250 ms (**0.00 ms**). Arme à feu en main : lecture du tir à
chaque image (comme le jeu) ; PNJ armés à moins de 10 m : leurs tirs lus à chaque image tant qu'il y en a (liste
refaite toutes les 250 ms) ; les effets ne tournent que quand quelqu'un tire.
