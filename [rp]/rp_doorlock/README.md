# RP Doorlock

Portes **à verrouiller / déverrouiller** par les **joueurs civils** (mode civil coché ou sans rôle), **à frapper**,
et **à enfoncer** par les **policiers en service** (barre de réussite) ; une porte enfoncée reste **cassée**.
100 % standalone (ni ESX, ni QBCore, ni vRP), Lua 5.4.

Fonctionne avec l'**œil** de [`rp_interact`](../rp_interact/README.md) (Alt) : `rp_doorlock` est dans
`TargetProviders` de sa config. Les policiers en service sont les joueurs dans une unité du MDC
([`rp_mdc`](../rp_mdc/README.md)).

## Installation

Dans `[rp]/` (déjà en place), puis dans `server.cfg`, **après** `rp_mdc` et `rp_interact` :

```cfg
ensure rp_doorlock
```

Optionnel : déverrouiller n'importe quelle porte et réparer une porte forcée (admins) : `add_ace group.admin rp_doorlock.admin allow`.

## Utilisation (œil, Alt, porte à moins de 2 m)

| Porte | Qui | Option |
|---|---|---|
| Porte | Joueur civil (mode civil coché ou sans rôle) | Policier en service (unité du MDC, quel que soit le service) |
|---|---|---|
| ouverte | **Verrouiller la porte**, **Frapper à la porte** | **Frapper à la porte** |
| verrouillée | **Déverrouiller la porte** (tout civil, pas seulement celui qui l'a verrouillée), **Frapper à la porte** | **Frapper à la porte**, **Enfoncer la porte** (barre de réussite) |
| forcée | **Frapper à la porte** | **Frapper à la porte** |

Un admin peut en plus déverrouiller toute porte et **réparer** une porte forcée. Le serveur vérifie les mêmes règles
(un civil ne peut pas enfoncer, un policier ne peut ni verrouiller ni déverrouiller).

- **Verrouiller / déverrouiller** : le personnage se tourne vers la porte et fait le geste de la clé
  (`anim@heists@keycard@`). La porte se ferme et reste **bloquée chez tout le monde**, même loin d'elle, **portes des
  bâtiments du jeu de base comprises** (maison de Franklin, postes de police…) :
  - chaque porte verrouillée est ajoutée au système de portes du jeu sous **son propre identifiant** (modèle converti
    en entier, état « verrouillée » posé en deux temps, comme ox_doorlock) ;
  - le jeu n'applique un verrou qu'une fois la porte **chargée** près du joueur : à moins de 40 m (`HoldDistance`),
    le verrou est donc **ré-appliqué dès que la porte se charge** (ou si le jeu l'a perdu) ;
  - la porte est **refermée d'un coup** (même grande ouverte) puis **figée avec ses collisions** : elle **ne bouge
    plus du tout** et **bloque les joueurs** comme un mur (ni en la poussant, ni en courant, ni en voiture) ; décalée
    par quelque chose, elle est remise en place ; libérée quand on la déverrouille.
  Une **porte double** (deux battants côte à côte) est verrouillée en entier.
- Les verrous sont gardés après un redémarrage (`data/locks.json`). **10 portes** au plus verrouillées par joueur
  (`MaxPerPlayer`) ; n'importe quel joueur civil peut les déverrouiller.
- **Enfoncer** (policiers en service) : une **barre** blanche apparaît en bas de l'écran (« Enfoncer la porte », réussites
  « 1 / 3 »), avec une **zone verte** et un **curseur** qui va et vient ; trois cases montrent les étapes. **ESPACE**
  quand le curseur est dans le vert. **À chaque essai, réussi ou raté, le personnage donne un coup de pied dans la
  porte** (animation `missprologuemcs_1` du prologue, une autre en secours) ; réussi : petite secousse, étape
  suivante (zone plus fine, curseur plus rapide) ; raté : « La porte tient bon. ». **3 réussites** (`Kick.Steps`) :
  le verrou saute et le battant s'ouvre violemment chez tout le monde. **3 ratés** (`Kick.MaxMisses`) ou **RETOUR**
  (Échap aussi) : le joueur s'arrête (il peut recommencer). Le serveur compte les réussites et impose un délai entre
  deux coups (`Kick.Cooldown`).
- **Porte forcée** : elle est **cassée** et **ne se verrouille plus** (« Porte forcée » à l'œil). Au-dessus d'elle,
  la description **« Elle a été forcée. »** s'affiche automatiquement, comme la description visuelle d'un props de
  `/scene` (même texte 3D, à moins de 10 m, seulement si on la voit). Elle est réparée par un admin (**Réparer la
  porte**), au bout de `Broken.Duration` minutes si vous en mettez, ou au redémarrage du serveur.
- **Frapper** : animation du jeu (`timetable@jimmy@doorknock@`), bruit des coups entendu par les joueurs proches.
- Les portes ne peuvent **pas être supprimées** avec l'œil de `rp_interact` (« Supprimer » n'est pas proposé sur une
  porte ; export client `isDoor(entity)`).

**Mode nuit** (réglé dans le MDC : *Paramètres > MDC > Apparence*, appliqué à toutes les interfaces ou aux menus extérieurs) : **fond noir et couleur du mode nuit** (vert, jaune, rouge ou bleu) pour la barre pour enfoncer une porte (`client/theme.lua` ; sans le MDC : thème jour).

## Quelles portes ?

Les portes et portails du jeu : `models.lua` (≈ 1 000 modèles, tirés de la liste des objets du jeu), à condition
d'avoir la taille d'une porte (`MinHeight`, `MaxHeight`, `MinWidth`). Portes de vos maps (MLO) : ajoutez leurs
modèles dans `ExtraModels` ; ou `DetectBySize = true` pour reconnaître tout objet fin ayant la taille d'une porte
(peut aussi reconnaître un panneau ou une vitre). Un modèle à ne jamais proposer : `IgnoredModels`.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `MdcResource` | nom du MDC (policiers en service) |
| `Distance`, `PairDistance`, `HoldDistance` | distance joueur / porte (2 m) ; second battant d'une porte double (2,6 m) ; portes verrouillées tenues fermées autour du joueur (40 m) |
| `MaxPerPlayer`, `AdminAce` | portes par joueur ; permission admin |
| `ExtraModels`, `IgnoredModels`, `MinHeight`, `MaxHeight`, `MinWidth`, `DetectBySize`, `MaxThickness` | reconnaître une porte |
| `LockAnim`, `KnockAnim`, `Knock` | animations, bruit des coups frappés et sa portée |
| `Kick` | enfoncer : `Steps` réussites nécessaires, `Zone` largeur de la zone verte et `Speed` vitesse du curseur à chaque étape, `MaxMisses` ratés avant l'arrêt, `Cooldown`, animations (et moment de l'impact), force donnée au battant, secousse |
| `Broken` | porte forcée : texte affiché au-dessus (« Elle a été forcée. »), distance (10 m), réparée toute seule au bout de `Duration` minutes (0 : au redémarrage), taille et couleur du texte |
| `Save` | verrous gardés après un redémarrage |

## Performance

Aucune boucle sans porte verrouillée ni porte forcée. Sinon, une vérification par seconde (toutes les 0,5 s près
d'une de ces portes) : distance, verrou ré-appliqué si besoin, porte figée. Le texte « Elle a été forcée. » n'est
dessiné que s'il est visible à moins de 10 m ; la barre pour enfoncer lit les touches seulement pendant qu'elle est
affichée. Au repos : **0.00 ms**.
