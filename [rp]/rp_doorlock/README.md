# RP Doorlock

Portes **à verrouiller / déverrouiller** par les joueurs, **à frapper**, et **enfoncées à coups de pied** par les
policiers en service. 100 % standalone (ni ESX, ni QBCore, ni vRP), Lua 5.4.

Fonctionne avec l'**œil** de [`rp_interact`](../rp_interact/README.md) (Alt) : `rp_doorlock` est dans
`TargetProviders` de sa config. Les policiers en service sont les joueurs dans une unité du MDC
([`rp_mdc`](../rp_mdc/README.md)).

## Installation

Dans `[rp]/` (déjà en place), puis dans `server.cfg`, **après** `rp_mdc` et `rp_interact` :

```cfg
ensure rp_doorlock
```

Optionnel : déverrouiller n'importe quelle porte (admins) : `add_ace group.admin rp_doorlock.admin allow`.

## Utilisation (œil, Alt, porte à moins de 2 m)

| Porte | Qui | Option |
|---|---|---|
| ouverte à tous | tout le monde (policiers en service compris, `PoliceCanLock`) | **Verrouiller la porte** |
| verrouillée | son propriétaire (celui qui l'a verrouillée) ou un admin | **Déverrouiller la porte** |
| verrouillée | policiers en service | **Enfoncer la porte** (un coup de pied) |
| toutes | tout le monde | **Frapper à la porte** (bruit entendu à 15 m) |

- **Verrouiller / déverrouiller** : le personnage se tourne vers la porte et fait le geste de la clé
  (`anim@heists@keycard@`). La porte se ferme et reste **bloquée chez tout le monde**, même loin d'elle (système de
  portes du jeu). Une **porte double** (deux battants côte à côte) est verrouillée en entier.
- La porte appartient au joueur qui l'a verrouillée (sa licence : il la retrouve après une reconnexion et après un
  redémarrage, `data/locks.json`). **10 portes** au plus par joueur (`MaxPerPlayer`).
- **Enfoncer** : coup de pied (`missprologuemcs_1`, celui du prologue ; une autre animation en secours), petite
  secousse de la caméra. Chaque coup a **35 %** de chances de faire céder la porte (`Kick.Chance`) ; elle cède
  forcément au **5e** (`Kick.Max`). Sinon : « La porte tient bon (2 / 5) ». Quand elle cède, le verrou saute et le
  battant s'ouvre violemment chez tout le monde. Un coup toutes les 1,5 s au plus.
- **Frapper** : animation du jeu (`timetable@jimmy@doorknock@`), bruit des coups entendu par les joueurs proches.

## Quelles portes ?

Les portes et portails du jeu : `models.lua` (≈ 1 000 modèles, tirés de la liste des objets du jeu), à condition
d'avoir la taille d'une porte (`MinHeight`, `MaxHeight`, `MinWidth`). Portes de vos maps (MLO) : ajoutez leurs
modèles dans `ExtraModels` ; ou `DetectBySize = true` pour reconnaître tout objet fin ayant la taille d'une porte
(peut aussi reconnaître un panneau ou une vitre). Un modèle à ne jamais proposer : `IgnoredModels`.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `MdcResource` | nom du MDC (policiers en service) |
| `Distance`, `PairDistance` | distance joueur / porte (2 m) ; second battant d'une porte double (2,6 m) |
| `MaxPerPlayer`, `PoliceCanLock`, `AdminAce` | portes par joueur ; les policiers peuvent verrouiller ; permission admin |
| `ExtraModels`, `IgnoredModels`, `MinHeight`, `MaxHeight`, `MinWidth`, `DetectBySize`, `MaxThickness` | reconnaître une porte |
| `LockAnim`, `KnockAnim`, `Knock` | animations, bruit des coups frappés et sa portée |
| `Kick` | enfoncer : chance par coup, nombre de coups maximum, délai, animations (et moment de l'impact), force donnée au battant, secousse |
| `Save` | verrous gardés après un redémarrage |

## Performance

Aucune boucle : les verrous sont appliqués une fois (à la connexion, puis à chaque changement) par le système de
portes du jeu, qui les tient tout seul. Rien ne tourne en dehors de l'œil et des animations : **0.00 ms**.
