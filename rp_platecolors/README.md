# RP PlateColors (FiveM)

Couleur du **texte des plaques d'immatriculation** (lettres et chiffres) via **`carcols.ymt`**, section
`<VehiclePlates>` → `<FontColor>`. **100% standalone** (sans ESX / QBCore / vRP).

```
rp_platecolors/
├── fxmanifest.lua        data_file 'CARCOLS_FILE' 'data/carcols.ymt'
├── config.lua
├── client.lua            détection, application des couleurs, commandes de test
├── data/carcols.ymt      ← les couleurs se règlent ici (<FontColor>)
└── outil/generateur.html ← page pour choisir les couleurs et générer le XML (s'ouvre dans un navigateur)
```

## ⚠️ À savoir avant tout

La couleur du texte d'une plaque ne vient **pas** d'une texture : elle est écrite dans la section
`<VehiclePlates>` du **`carcols.ymt` principal du jeu** (`update.rpf/x64/data/carcols.ymt`).

Un `carcols` chargé par une ressource (`data_file 'CARCOLS_FILE'`) est traité comme un **pack DLC** : le jeu y lit
les kits de tuning, les gyrophares, les couleurs de vitres… Mais d'après la documentation de GTA V (GTAMods) et les
retours de la communauté FiveM, **il ne prend pas les plaques d'un pack DLC** (la texture s'affiche, mais la couleur
du texte reste celle d'origine). FiveM ne propose pas de directive pour remplacer le `carcols.ymt` principal depuis le
serveur.

D'où **deux méthodes** :

| | Méthode 1 : ressource serveur | Méthode 2 : garantie (update.rpf) |
|---|---|---|
| Installation | `ensure rp_platecolors`, rien chez les joueurs | chaque joueur copie un `update.rpf` modifié dans le dossier `mods` de FiveM |
| Fonctionne | **seulement si le jeu ajoute les plaques** du fichier (testé automatiquement, voir ci-dessous) | **oui**, le jeu lit directement les nouvelles couleurs |
| Visible par | tous les joueurs | seulement les joueurs qui ont installé le fichier |

La ressource **teste elle-même** la méthode 1 au démarrage et vous dit dans la console (F8) si elle fonctionne.
Si ce n'est pas le cas, le fichier `data/carcols.ymt` et le générateur servent pour la méthode 2.

## Méthode 1 : ressource serveur

1. Copiez le dossier `rp_platecolors` dans `resources/`.
2. Dans `server.cfg` : `ensure rp_platecolors`
3. Réglez les couleurs dans `data/carcols.ymt` (ou générez le fichier avec `outil/generateur.html`).
4. Redémarrez le serveur (un fichier `CARCOLS_FILE` est lu au chargement : reconnectez-vous après chaque changement).

### Ce que fait la ressource

`data/carcols.ymt` contient une **copie des 6 plaques du jeu** (mêmes textures, même ordre), avec une autre couleur
de texte. Au démarrage, le script compte les types de plaques connus du jeu
(`GET_NUMBER_OF_VEHICLE_NUMBER_PLATES`) :

- **le nombre a augmenté de 6** (12 ou 19 selon la build) : les plaques ont été ajoutées. Chaque véhicule qui porte
  une plaque 0 à 5 reçoit sa **copie colorée** (même fond, nouvelle couleur de texte). Le changement est fait par le
  propriétaire réseau du véhicule, donc synchronisé pour tout le monde. À l'arrêt de la ressource, les plaques
  d'origine sont remises.
- **le nombre n'a pas changé** (6 ou 13) : le jeu n'a rien ajouté. La console F8 l'indique :
  `[rp_platecolors] 13 types de plaques : le jeu n'a ajouté aucune plaque de carcols.ymt.`
  → passez à la **méthode 2**.

### Commandes de test

| Commande | Effet |
|---|---|
| `/plaques` | diagnostic dans la console F8 : nombre de types de plaques, plaques colorées chargées ou non, plaque du véhicule actuel |
| `/plaque <index>` | met la plaque `<index>` sur votre véhicule (pour voir chaque couleur) |

## Méthode 2 : garantie (update.rpf)

Le jeu lit les couleurs directement dans son `carcols.ymt` principal. On modifie seulement les lignes `<FontColor>`.

1. Ouvrez **OpenIV** (mode édition) ou **CodeWalker** (RPF Explorer, mode édition), sur une **copie** de
   `GTAV/update/update.rpf`.
2. Allez dans `update.rpf/x64/data/carcols.ymt` et exportez-le en **XML**.
3. Dans la section `<VehiclePlates>` → `<Textures>`, chaque `<Item>` est une plaque, reconnaissable à son
   `<DiffuseMapName>` (`plate01`, `plate02`, `plate03`, `plate04`, `plate05`, `yankton_plate`, puis les plaques
   ajoutées par le jeu). Remplacez **uniquement** `<FontColor>` (et si vous voulez `<FontOutlineColor>`,
   `<IsFontOutlineEnabled>`). Le générateur, onglet **« Lignes FontColor (update.rpf) »**, donne ces lignes.
4. Réimportez le XML à la place de `carcols.ymt` et enregistrez l'`update.rpf`.
5. Chaque joueur copie cet `update.rpf` dans le dossier **`mods`** de FiveM
   (`%localappdata%\FiveM\FiveM.app\mods\`), puis relance FiveM.

À savoir :

- Seuls les joueurs qui ont le fichier voient les nouvelles couleurs (c'est purement visuel, sans effet sur le jeu).
- Un serveur en **`sv_pureLevel 1` ou `2`** refuse les fichiers du dossier `mods` : laissez `sv_pureLevel` à 0 (ou absent).
- Si vous changez de build (`sv_enforceGameBuild`), refaites le fichier à partir du nouvel `update.rpf`.
- Ne modifiez pas `<FontExtents>` ni `<MaxLettersOnPlate>` (position et nombre de caractères).

## Couleurs

Format **`0xAARRGGBB`** : `AA` = opacité (`FF` = opaque), puis rouge, vert, bleu en hexadécimal.

| Couleur | Valeur | | Couleur | Valeur |
|---|---|---|---|---|
| Noir | `0xFF000000` | | Rouge | `0xFFC8102E` |
| Blanc | `0xFFFFFFFF` | | Vert | `0xFF007A33` |
| Bleu foncé | `0xFF0A2A8C` | | Orange | `0xFFFF6A00` |
| Jaune | `0xFFFFC800` | | Violet | `0xFF6B2FA3` |

Couleurs par défaut du fichier fourni :

| Index | Plaque | Texte |
|---|---|---|
| 0 | blanche cursive « San Andreas » | noir |
| 1 | fond noir | blanc |
| 2 | fond bleu | blanc |
| 3 | blanche sobre (la plus courante) | noir |
| 4 | blanche « Exempt » (service) | rouge |
| 5 | North Yankton | bleu foncé |

### Générateur

Ouvrez `outil/generateur.html` dans un navigateur (double-clic, pas besoin du serveur) : sélecteur de couleur par
plaque, contour optionnel, aperçu, puis **Copier** :

- **Fichier complet** : à coller à la place de tout le contenu de `data/carcols.ymt` (méthode 1) ;
- **Lignes FontColor** : à reporter dans le `carcols.ymt` de `update.rpf` (méthode 2).

Le dossier `outil/` n'est pas chargé par FiveM (absent du `fxmanifest.lua`).

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `CustomPlates` | nombre de plaques dans `data/carcols.ymt` (6) |
| `AutoRemap` | met la copie colorée sur les véhicules quand les plaques sont ajoutées (`false` : rien n'est changé) |
| `VanillaCounts` | nombre de types de plaques du jeu sans ajout (6 avant la build 3095, 13 ensuite) |
| `Interval` | ms entre deux passages sur les véhicules proches (1000) |
| `InfoCommand`, `TestCommand` | noms des commandes `/plaques` et `/plaque` (`false` : aucune) |

## Performance

Si les plaques ne sont pas ajoutées, le script s'arrête après le diagnostic (0 boucle). Sinon, un passage par
seconde sur les véhicules proches, deux natives par véhicule (≈ 0.00 ms dans le resmon).
