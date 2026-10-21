# RP PlateColors (FiveM)

Couleur du **texte des plaques d'immatriculation** (lettres et chiffres), **sans carcols.ymt**. Même idée qu'un
`<VehiclePlates>` / `<FontColor>` de carcols : **une couleur de texte (et un contour) par type de plaque**, réglée en
Lua ou dans un **éditeur en jeu**. **100% standalone** (sans ESX / QBCore / vRP), interface NUI en HTML/CSS/Vanilla JS.

```
rp_platecolors/
├── fxmanifest.lua
├── config.lua            couleurs par type de plaque, tailles, distances, permission
├── client/plates.lua     police du jeu masquée, texte redessiné en couleur, placement automatique
├── client/editor.lua     éditeur /plaqueedit
├── server/server.lua     enregistrement des réglages (data/plates.json), envoi à tous les joueurs
├── html/                 panneau de l'éditeur (NUI)
├── assets/               police des plaques (atlas), textures de remplacement
├── data/plates.json      réglages faits en jeu (positions par modèle, couleurs)
└── outil/police.py       régénère assets/ (autre police, voir plus bas)
```

## Pourquoi pas un carcols.ymt ?

La couleur du texte est un paramètre du shader des plaques, lu **uniquement** dans le `carcols.ymt` principal du jeu
(`update.rpf`). Un `carcols` chargé par une ressource est traité comme un pack DLC, et le jeu n'y lit pas les plaques :
c'est pour ça que la v1 ne changeait rien. Aucune native ne modifie cette couleur.

## Comment fait le script

1. La **police des plaques du jeu** (`vehshare` → `vehicle_generic_plate_font`, même méthode que les scripts de
   plaques personnalisées) est remplacée par une **texture vide** : le jeu n'écrit plus de caractères. Le fond de la
   plaque (texture, reflets, saleté) reste celui du jeu.
2. Le **texte réel de la plaque** (`GET_VEHICLE_NUMBER_PLATE_TEXT`, donc compatible avec les garages, le MDC, les
   fausses plaques…) est **redessiné en 3D** sur la plaque (`DRAW_TEXTURED_POLY`), dans les **8 cases** du jeu, avec
   la couleur de son **type de plaque**. Il suit le véhicule, son inclinaison et la caméra.
3. Le texte n'est dessiné que pour les plaques **proches** (22 m), **tournées vers la caméra** et **pas cachées** par
   un mur, un objet ou un autre véhicule. Il est un peu baissé la nuit (le jeu ne l'éclaire pas).

## Installation

1. Copiez le dossier `rp_platecolors` dans `resources/`.
2. Dans `server.cfg` :
   ```
   ensure rp_platecolors
   add_ace group.admin rp_platecolors.edit allow
   ```
3. Si vous aviez mis la v1 : supprimez l'ancien `data/carcols.ymt` (il ne servait à rien).
4. Reconnectez-vous : le texte des plaques prend les couleurs de `config.lua`.

## Position du texte sur la plaque

Le jeu ne donne pas la position des plaques d'un modèle. Le script la trouve de deux façons :

- **automatiquement**, la première fois qu'il croise un modèle : os `platelight` (la lumière au-dessus de la plaque
  arrière), sinon les dimensions du modèle, et un rayon contre la carrosserie pour l'avant. Correct sur beaucoup de
  véhicules, mais pas exact partout ;
- **par modèle, dans l'éditeur** : réglé une fois, enregistré dans `data/plates.json` et envoyé à **tous** les
  joueurs, pour tous les véhicules de ce modèle.

### Éditeur : `/plaqueedit`

Permission : ace `rp_platecolors.edit`. Prend le véhicule où vous êtes assis, sinon le plus proche (8 m).

**Onglet Position** (pour le modèle) : choisissez **Arrière** / **Avant**, cochez ou non *Plaque de ce côté*, puis
déplacez le texte : un **cadre bleu** montre la plaque, le texte bouge en direct.

| Réglage | Boutons | Clavier |
|---|---|---|
| Gauche / droite | − / + | `←` `→` |
| Hauteur | − / + | `↑` `↓` |
| Avant / arrière (enfoncer / sortir) | − / + | `PgUp` `PgDn` |
| Inclinaison (plaque penchée) | − / + | `R` `F` |
| Rotation | − / + | `Q` `E` |
| Taille | − / + | `+` `−` |

`Maj` = pas ×5. **Tab** libère la souris pour tourner la caméra autour du véhicule (le panneau reste affiché), **Tab**
à nouveau pour reprendre le panneau. **Enregistrer** applique le réglage pour tout le monde ; **Estimation auto**
remet l'estimation (sans enregistrer) ; **Supprimer** efface le réglage du modèle.

Astuce : descendez du véhicule et placez-vous derrière (ou devant), puis `/plaqueedit` : le véhicule le plus proche
est pris.

**Onglet Couleurs** : pour chaque type de plaque, couleur du texte, contour (case + couleur). Aperçu en direct sur
toutes les plaques. Cliquez sur l'aperçu `12AB` d'un type pour le **mettre sur le véhicule** et voir le résultat.
**Enregistrer les couleurs** les applique pour tout le monde (elles passent avant `config.lua`) ;
**Rétablir config.lua** efface les couleurs enregistrées.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Plates` | par type de plaque (index du jeu) : `text = { R, G, B }`, `outline = { R, G, B }` ou `false` (comme `FontColor` / `FontOutlineColor`) |
| `Default` | couleur d'un type absent de la liste |
| `Text` | largeur des 8 caractères, hauteur, décalage vertical, distance devant la plaque |
| `PlateSize` | taille du cadre de l'éditeur |
| `NightBrightness` | luminosité du texte la nuit (1.0 = pas de changement) |
| `MaxDistance`, `MaxPlates` | distance et nombre maximum de plaques dessinées |
| `ScanInterval`, `OcclusionInterval` | fréquence de recherche des véhicules et des tests de visibilité |
| `Auto` | placement automatique : écart sous `platelight`, hauteur sans `platelight`, retrait |
| `EditCommand`, `EditAce`, `EditRange` | éditeur : commande, permission, distance du véhicule |

Types de plaques du jeu : 0 blanche cursive, 1 fond noir, 2 fond bleu, 3 blanche sobre (la plus courante),
4 « Exempt », 5 North Yankton ; à partir de la build 3095 : 6 eCola, 7 Las Venturas, 8 Liberty City, 9 LS Car Meet,
10 LS Panic, 11 LS Pounders, 12 Sprunk.

## Couleur propre à un véhicule (autres scripts)

Prioritaire sur le type de plaque, synchronisée pour tous (state bag `plateColor`) :

```lua
-- client (propriétaire du véhicule)
exports.rp_platecolors:SetVehiclePlateColor(vehicle, { 255, 200, 0 }, { 0, 0, 0 })  -- texte, contour (ou nil)
exports.rp_platecolors:SetVehiclePlateColor(vehicle, nil)                          -- retour à la couleur du type

-- serveur
Entity(vehicle).state.plateColor = { text = { 255, 200, 0 }, outline = false }
```

## Autre police

`assets/plate_font.png` (et son contour) est un atlas de 8 × 5 cases (64 × 96 px) : `0-9`, `A-Z`, `-`, `.`,
caractères **blancs** sur fond transparent (la couleur est appliquée en jeu). Pour une autre police :

```
pip install pillow
python outil/police.py chemin/vers/police.ttf
```

Police fournie : DejaVu Sans Bold (licence libre Bitstream Vera / DejaVu), compressée en largeur comme une police de
plaque.

## Limites

- Les plaques **au-delà de 22 m** (`MaxDistance`) n'ont pas de texte : le jeu n'en écrit plus et le script ne les
  dessine pas (à cette distance, les caractères ne sont de toute façon pas lisibles).
- Le texte n'est pas éclairé par le jeu (phares, ombres) : `NightBrightness` le baisse la nuit.
- Sur un modèle mal estimé, le texte peut être décalé tant qu'il n'a pas été réglé dans l'éditeur.
- Pour revenir au texte du jeu : `stop rp_platecolors` (la police d'origine est remise).

## Performance

Recherche des véhicules toutes les 400 ms, test de visibilité asynchrone toutes les 250 ms. Par image, 4 triangles
par caractère, seulement pour les plaques proches, tournées vers la caméra et visibles (en pratique quelques
plaques). Ressource arrêtée ou aucune plaque proche : aucune boucle active (attente de 200 ms).
