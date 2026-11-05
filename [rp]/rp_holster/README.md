# RP Holster

**Holsters EUP pleins / vides** : l'arme configurée est **dans le holster** quand elle est rangée, et le holster est
**vide** quand elle est sortie, avec une animation et un son. 100 % standalone, Lua 5.4.

## Fonctionnement

Les holsters EUP (partie **« teef » / Accessories**, composant 7) existent en deux versions : **pleine** (arme dans le
holster) et **vide**. Quand le joueur porte l'une des deux versions d'un holster de la liste :

| Situation | Holster |
|---|---|
| arme **de la liste** (`Weapons`) **en main** | **vide** |
| arme de la liste dans l'inventaire, **rangée** | **plein** |
| aucune arme de la liste sur soi | **vide** (`EmptyWhenNoWeapon`) |

**Seules les armes de `Weapons`** (et des groupes de `Groups`, s'il y en a) comptent : sortir une autre arme (pistolet
qui n'est pas dans la liste, fusil…) **ne vide pas** le holster.

En **sortant** / **rangeant** une arme de la liste (holster de la liste porté) :
- **animation** : la main va au holster (`Animation.Draw` / `Animation.Holster`, haut du corps : on peut marcher) ;
  pas d'animation en véhicule, à terre ou en nageant ; en rangeant, le holster se remplit à la fin du geste ;
- **son `holster.ogg`** : à déposer dans `html/sounds/holster.ogg` (Ogg Vorbis) ; joué pour soi et **entendu par les
  joueurs proches** (`Sound.Range` = 8 m, plus faible avec la distance, relayé par le serveur). Sans fichier : aucun son.

La **texture** portée est gardée. Le changement se voit chez tous les joueurs (tenue synchronisée par le jeu). Un
holster qui n'est pas dans la liste n'est jamais touché.

## Configuration (`config.lua`)

Une ligne par holster, avec le **numéro du modèle plein** et celui du **modèle vide** (ceux de votre pack EUP, comptés
comme dans `outfits.json` de rp_interact : `"Accessories": "9:1"` -> `9`) :

```lua
Holsters = {
    { gender = 'male', full = 9, empty = 10, label = 'Holster de ceinture' },
    { gender = 'female', full = 9, empty = 10 },
},
```

Les numéros fournis sont des **exemples à remplacer**. Aussi : `Component` (partie du holster, 7 par défaut ; une
ligne peut avoir son propre `component`), `OneBased` (numéros à partir de 1, comme EUP), `Groups` / `Weapons` /
`Excluded` (armes qui vont dans le holster : celles de `Weapons` ; `Groups = { 'GROUP_PISTOL' }` pour toutes les armes
de poing ; sans `Weapons` ni `Groups` : toutes les armes de poing), `Inventory`
(armes de poing vérifiées dans l'inventaire, **ajoutez-y vos armes addon** ; celles de `Weapons` le sont toujours),
`EmptyWhenNoWeapon`, `CheckMs`, `Animation` (`Enabled`, `Draw`, `Holster` : dictionnaire, animation, durée en ms),
`Sound` (`Enabled`, `File`, `Volume`, `Range`).

## Installation

```cfg
ensure rp_holster
```

## Performance

Une lecture de la tenue toutes les 250 ms (**0.00 ms**) ; l'inventaire n'est lu que si un holster de la liste est porté.
