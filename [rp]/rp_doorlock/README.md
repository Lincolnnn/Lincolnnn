# RP Doorlock

Portes **à verrouiller / déverrouiller** par les joueurs **en mode civil**, **à frapper**, et **enfoncées** par les
policiers en service (barre de réussite). 100 % standalone (ni ESX, ni QBCore, ni vRP), Lua 5.4.

Fonctionne avec l'**œil** de [`rp_interact`](../rp_interact/README.md) (Alt) : `rp_doorlock` est dans
`TargetProviders` de sa config. Les policiers en service sont les joueurs dans une unité du MDC
([`rp_mdc`](../rp_mdc/README.md)) ; le **mode civil** est la case du menu de `rp_interact` (page Civil).

## Installation

Dans `[rp]/` (déjà en place), puis dans `server.cfg`, **après** `rp_mdc` et `rp_interact` :

```cfg
ensure rp_doorlock
```

Optionnel : déverrouiller n'importe quelle porte (admins) : `add_ace group.admin rp_doorlock.admin allow`.

## Utilisation (œil, Alt, porte à moins de 2 m)

| Porte | Qui | Option |
|---|---|---|
| ouverte à tous | joueurs **en mode civil** (pas les policiers en service) | **Verrouiller la porte** |
| verrouillée | son propriétaire, s'il est en mode civil (et pas policier en service) ; un admin dans tous les cas | **Déverrouiller la porte** |
| verrouillée | policiers en service | **Enfoncer la porte** (barre de réussite) |
| toutes | tout le monde | **Frapper à la porte** (bruit entendu à 15 m) |

Un policier en service, ou un joueur sans rôle (ni mode civil, ni unité du MDC), n'a **ni Verrouiller ni
Déverrouiller**. Le serveur vérifie les mêmes règles (le mode civil est publié par `rp_interact` :
`Player(src).state.rpiCivilMode`). Sans `rp_interact` démarré (`InteractResource`), tout le monde est civil.

- **Verrouiller / déverrouiller** : le personnage se tourne vers la porte et fait le geste de la clé
  (`anim@heists@keycard@`). La porte se ferme et reste **bloquée chez tout le monde**, même loin d'elle : chaque porte
  verrouillée est ajoutée au système de portes du jeu sous **son propre identifiant** (modèle converti en entier, état
  « verrouillée » posé en deux temps, comme ox_doorlock), ce qui corrige la porte qui restait battante. Une **porte
  double** (deux battants côte à côte) est verrouillée en entier.
- La porte appartient au joueur qui l'a verrouillée (sa licence : il la retrouve après une reconnexion et après un
  redémarrage, `data/locks.json`). **10 portes** au plus par joueur (`MaxPerPlayer`).
- **Enfoncer** : une **barre** apparaît en bas de l'écran, avec une **zone verte** et un **curseur blanc** qui va et
  vient ; trois cases montrent les étapes. **ESPACE** quand le curseur est dans le vert : coup de pied réussi (le
  personnage frappe la porte, petite secousse), étape suivante, zone plus fine et curseur plus rapide. Raté : coup de
  pied, « La porte tient bon. ». **3 réussites** (`Kick.Steps`) : le verrou saute et le battant s'ouvre violemment chez
  tout le monde. **3 ratés** (`Kick.MaxMisses`) ou **RETOUR** (Échap aussi) : le policier s'arrête (il peut
  recommencer). Le serveur compte les réussites et impose un délai entre deux coups (`Kick.Cooldown`).
- **Frapper** : animation du jeu (`timetable@jimmy@doorknock@`), bruit des coups entendu par les joueurs proches.
- Les portes ne peuvent **pas être supprimées** avec l'œil de `rp_interact` (« Supprimer » n'est pas proposé sur une
  porte ; export client `isDoor(entity)`).

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
| `InteractResource` | ressource du mode civil (`rp_interact`) |
| `MaxPerPlayer`, `AdminAce` | portes par joueur ; permission admin |
| `ExtraModels`, `IgnoredModels`, `MinHeight`, `MaxHeight`, `MinWidth`, `DetectBySize`, `MaxThickness` | reconnaître une porte |
| `LockAnim`, `KnockAnim`, `Knock` | animations, bruit des coups frappés et sa portée |
| `Kick` | enfoncer : `Steps` réussites nécessaires, `Zone` largeur de la zone verte et `Speed` vitesse du curseur à chaque étape, `MaxMisses` ratés avant l'arrêt, `Cooldown`, animations (et moment de l'impact), force donnée au battant, secousse |
| `Save` | verrous gardés après un redémarrage |

## Performance

Aucune boucle : les verrous sont appliqués une fois (à la connexion, puis à chaque changement) par le système de
portes du jeu, qui les tient tout seul. Rien ne tourne en dehors de l'œil, des animations et de la barre pour enfoncer (boucle de touches uniquement
pendant qu'elle est affichée) : **0.00 ms**.
