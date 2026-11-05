# RP Holster

**Holsters EUP pleins / vides** : l'arme de poing est **dans le holster** quand elle est rangée, et le holster est
**vide** quand elle est sortie. 100 % standalone, Lua 5.4.

## Fonctionnement

Les holsters EUP (partie **« teef » / Accessories**, composant 7) existent en deux versions : **pleine** (arme dans le
holster) et **vide**. Quand le joueur porte l'une des deux versions d'un holster de la liste :

| Situation | Holster |
|---|---|
| arme de poing **en main** | **vide** |
| arme de poing dans l'inventaire, **rangée** | **plein** |
| aucune arme de poing sur soi | **vide** (`EmptyWhenNoWeapon`) |

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
`Excluded` (armes qui vont dans le holster : armes de poing par défaut, sans le pistolet de détresse), `Inventory`
(armes de poing vérifiées dans l'inventaire, **ajoutez-y vos armes addon**), `EmptyWhenNoWeapon`, `CheckMs`.

## Installation

```cfg
ensure rp_holster
```

## Performance

Une lecture de la tenue toutes les 250 ms (**0.00 ms**) ; l'inventaire n'est lu que si un holster de la liste est porté.
