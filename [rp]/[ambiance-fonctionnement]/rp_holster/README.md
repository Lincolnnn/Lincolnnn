# RP Holster

**Holsters EUP pleins / vides** : l'arme configurée est **dans le holster** quand elle est rangée, et le holster est
**vide** quand elle est sortie, avec un **geste** et un **son** à chaque sortie et à chaque rangement. 100 % standalone,
Lua 5.4. Version 2 : gestes et sons repris en partie de « EUP Gun Holster Animation Script with Sounds » de
**ChapterDonut** (voir *Crédits*).

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

En **sortant** et en **rangeant** une arme de la liste :

| | Sortie | Rangement |
|---|---|---|
| **Geste** (holster de la liste porté, à pied) | main au holster : `reaction@intimidation@cop@unarmed` **intro**, 600 ms | retour : même dictionnaire, **outro**, 600 ms |
| **Holster** | passe **vide** à 120 ms (`swapAt`) | passe **plein** à 450 ms (`swapAt`), à la fin du geste |
| **Son** (soi + joueurs proches) | `unholster.ogg` (`Sound.DrawFile`) | `holster.ogg` (`Sound.File`) |

- **Pendant le geste** (~0,6 s) : **ni tir, ni visée, ni roue des armes** (`Animation.BlockControls`), comme un vrai
  dégainage. Le geste ne prend que le **haut du corps** : on continue de marcher.
- **Sons** : à **chaque** sortie et rangement, holster porté ou non (`Sound.RequireHolster = true` : seulement avec un
  holster de la liste) ; entendus par les **joueurs proches** (`Sound.Range` = 8 m, plus faibles avec la distance,
  relayés par le serveur). Un `.mp3` / `.wav` marche aussi (changer `File` / `DrawFile`).
- **Pas de geste** en véhicule, à terre, en chute ou en nageant (le son reste, le holster change tout de suite), ni sans
  holster de la liste (`Animation.RequireHolster = false` : geste quand même).
- Arme de la liste **perdue** (lâchée, retirée) : ni son ni geste ; le holster suit l'inventaire.
- Avec une arme de la liste sur soi, la vérification passe à **100 ms** (`ArmedCheckMs`) : geste et son tombent au bon
  moment ; sans, 250 ms (`CheckMs`). Boucle par image seulement pendant un geste.

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
`EmptyWhenNoWeapon`, `CheckMs`, `ArmedCheckMs`, `Animation` (`Enabled`, `RequireHolster`, `BlockControls`, `Draw`,
`Holster` : dictionnaire, animation, durée en ms, `swapAt`),
`Sound` (`Enabled`, `File`, `DrawFile`, `Volume`, `Range`, `RequireHolster`).

## Installation

```cfg
ensure rp_holster
```

## Performance

Une lecture de la tenue toutes les 250 ms (**0.00 ms**) ; l'inventaire n'est lu que si un holster de la liste est porté.

## Crédits

Gestes (`reaction@intimidation@cop@unarmed` intro / outro et leurs temps) et sons `html/sounds/holster.ogg` /
`unholster.ogg` : **ChapterDonut**, « FiveM EUP Gun Holster Animation Script with Sounds » (https://chapterdonut.com).
L'archive ne précise pas de licence : les sons restent la propriété de leur auteur. Le code de rp_holster est réécrit
(un seul script au lieu de deux, sons entendus par les joueurs proches, armes et holsters de `config.lua`).
