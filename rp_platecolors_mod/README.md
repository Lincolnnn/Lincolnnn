# Couleurs des plaques : mod client FiveM (dossier `mods`)

Ce n'est **pas une ressource serveur** : chaque joueur installe un fichier `.rpf` dans le dossier `mods` de FiveM. Le
jeu lit alors les nouvelles couleurs directement dans son `carcols.ymt` principal (`<FontColor>`). Le rendu est celui
du jeu, à n'importe quelle distance.

## Comment FiveM lit le dossier `mods`

FiveM ne prend pas un `.rpf` quelconque : il attend un **paquet** (même principe qu'un `.oiv` d'OpenIV) rangé dans un
`.rpf` :

```
plaques.rpf
├── assembly.xml          ← fourni ici (dit à FiveM quel fichier du jeu remplacer)
└── content/
    └── carcols.ymt       ← votre carcols.ymt modifié
```

`assembly.xml` déclare : `update\update.rpf` → `x64\data\carcols.ymt` remplacé par `content/carcols.ymt`. FiveM
monte ce fichier par-dessus celui du jeu (sans toucher à vos fichiers GTA V).

## 1. Préparer `carcols.ymt`

1. Avec **OpenIV** ou **CodeWalker**, ouvrez `GTAV/update/update.rpf/x64/data/carcols.ymt` (ne modifiez pas
   l'original : travaillez sur une copie / exportez-le).
2. Ouvrez-le en **XML** (OpenIV : éditeur intégré ; CodeWalker : clic droit → *Export XML*).
3. Section `<VehiclePlates>` → `<Textures>` : chaque `<Item>` est une plaque, reconnaissable à son
   `<DiffuseMapName>`. Remplacez **uniquement** la ligne `<FontColor>` de chacune, avec les valeurs de
   [`FontColor.xml`](FontColor.xml) :

   | Plaque | Couleur | `<FontColor>` |
   |---|---|---|
   | plate01 | bleu foncé | `0xFF0A2A8C` |
   | plate02 | blanc | `0xFFFFFFFF` |
   | plate03 | noir | `0xFF000000` |
   | plate04 | blanc | `0xFFFFFFFF` |
   | plate05 | bleu foncé | `0xFF0A2A8C` |
   | yankton_plate | bleu foncé | `0xFF0A2A8C` |

4. Réenregistrez-le en **`.ymt` binaire** (OpenIV : enregistrer dans l'éditeur ; CodeWalker : *Import XML*), sous le
   nom exact **`carcols.ymt`**, et placez-le dans `content/`.

## 2. Créer le `.rpf`

Avec **OpenIV** (mode édition) : dans un dossier de GTA V (par exemple `GTAV/mods/`), clic droit → *Nouveau* →
*Archive RPF*, nommée par exemple `plaques.rpf`. Ouvrez-la, puis :

- glissez-y `assembly.xml` (à la racine de l'archive) ;
- créez un dossier `content` dans l'archive et glissez-y votre `carcols.ymt`.

Le `LISEZMOI.txt` et ce README ne vont pas dans l'archive. Le chiffrement par défaut d'OpenIV (« OPEN ») est celui
que FiveM accepte.

## 3. Installer (chaque joueur)

Copiez `plaques.rpf` dans :

```
%localappdata%\FiveM\FiveM.app\mods\
```

(créez le dossier `mods` s'il n'existe pas), puis relancez FiveM.

## À savoir

- **Serveur** : `sv_pureLevel` doit être **absent ou à 0**. À `1`, FiveM refuse les `.rpf` non signés ; à `2`, il
  ignore tout le dossier `mods`.
- **N'utilisez pas en même temps la ressource `rp_platecolors`** : elle masque le texte du jeu pour le redessiner.
  Avec ce mod, retirez `ensure rp_platecolors` du `server.cfg`.
- Seuls les joueurs qui ont installé le fichier voient ces couleurs (purement visuel).
- Partez du `carcols.ymt` de **votre** `update.rpf`, à jour avec la build du serveur (`sv_enforceGameBuild`). Si le
  serveur change de build, refaites le fichier.
- Si votre `carcols.ymt` est ailleurs dans `update.rpf` que `x64/data/`, adaptez la ligne
  `<add source="carcols.ymt">x64\data\carcols.ymt</add>` d'`assembly.xml` (chemin à l'intérieur d'`update.rpf`).
