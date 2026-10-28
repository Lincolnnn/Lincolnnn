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
| le tireur | **recul** : la caméra remonte (et part un peu de côté) selon le type d'arme (pistolet léger, fusil à pompe et sniper forts, SMG faible) ; plus fort à la 1re personne et en véhicule ; petite **secousse** |
| tout le monde à moins de 90 m | **flash jaune** au bout du canon qui éclaire les alentours, à chaque tir |
| joueurs à moins de 15 m | **secousse** de la caméra (plus forte près du tireur et avec une arme bruyante) |
| joueurs à moins de 10 m | **acouphène** : un sifflement aigu monte d'un coup puis redescend tout seul (plus fort et plus long avec la proximité et le nombre de tirs) ; le tireur entend aussi un peu le sien |
| tout le monde à moins de 60 m | **fumée** : après **7 tirs rapides** (en 3 s), un filet de fumée sort du canon pendant 6 s |

Arme avec **silencieux** : ni flash, ni acouphène, secousse réduite. Le Taser, le pistolet de détresse, le pistolet radar,
l'extincteur et le jerrican ne sont jamais concernés (`Excluded`).

Synchronisation : le tireur envoie ses tirs par paquets (toutes les 100 ms) ; le serveur les vérifie, les limite
(25 paquets / s) et ne les relaie qu'aux joueurs à moins de 120 m. Chacun calcule le flash et la fumée sur l'arme du
tireur qu'il voit. Le sifflement est généré par le script (aucun fichier son).

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Profiles` | par type d'arme : recul (degrés), écart de côté, secousse du tireur, force du bruit |
| `Excluded` | armes jamais concernées |
| `Recoil` | activé ; multiplicateurs 1re personne, véhicule, général |
| `Flash` | activé, portée, couleur, rayon, intensité, durée (ms) |
| `Smoke` | activé, tirs et fenêtre (ms) pour la fumée, durée, délai entre deux, portée, effet de particules |
| `Tinnitus` | activé, portée, part de ses propres tirs, volume, durées min / max |
| `Shake` | secousse des voisins : activée, portée, force, type |
| `Sync` | portée du relais, paquets (ms), limite par seconde |

## Performance

Sans arme à feu en main : une vérification toutes les 250 ms (**0.00 ms**). Arme à feu en main : lecture du tir à
chaque image (comme le jeu) ; les effets ne tournent que quand quelqu'un tire.
