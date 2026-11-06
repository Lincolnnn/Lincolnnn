# rp_policecards

Cartes aide-mémoire à l'écran : **carte Miranda** et **alphabet phonétique de la police** (américain, APCO :
Adam, Boy, Charles, David… et non l'alphabet OTAN). 100 % standalone, Lua 5.4, cerulean.

## Utilisation

| Commande | Effet |
|---|---|
| `/miranda` | afficher / masquer la carte Miranda |
| `/alphabet` (ou `/phonetique`) | afficher / masquer l'alphabet phonétique |
| `/cartes` | ajuster les cartes affichées : **glisser** pour déplacer, **molette** pour la taille, **clic droit** pour masquer une carte ; **Échap** ou **Entrée** pour finir |

Aussi dans **Menu Interaction > Police > Aide-mémoire** (`rp_interact`, le menu reste ouvert).

Les cartes s'affichent **sans curseur** (comme le bloc-notes en mode visuel) : le joueur **marche, conduit et ouvre ses
autres menus** (MDC, bloc-notes, Menu Interaction…). Les deux cartes peuvent être affichées en même temps. Place et
taille sont **gardées chez le joueur** (KVP) après `/cartes`. Cartes masquées pendant le menu pause et en mode photo
(`rp_freecam`, « Masquer les interfaces »).

**Carte Miranda : animation.** À l'affichage, le joueur lit la carte (emote `/e id3` du mode d'emotes) ; quand la
carte est masquée, l'animation s'arrête (seulement si elle est toujours jouée : une autre emote lancée entre-temps
n'est jamais coupée). Réglage : `emote` de la carte dans `config.lua` (`nil` = aucune).

Aucune touche par défaut : chaque joueur peut en choisir une (*Paramètres > Raccourcis clavier > FiveM* > « Carte : … »).

## Configuration (`config.lua`)

- `Cards` : `id`, `command`, `aliases`, `label`, `image` (dans `html/`), place par défaut `x`, `y` et largeur `width`
  (fractions de l'écran). Ajouter une carte = une ligne + une image `.webp` dans `html/img/`.
- `emote` (par carte) : commande d'emote jouée à l'affichage (`'e id3'` pour la carte Miranda), arrêtée au masquage
  (export `EmoteCancel` du mode d'emotes, sinon `EmoteCancel` de la config : `'e c'`).
- `AdjustCommand` (`cartes`), `MinWidth` / `MaxWidth`, `HideInPauseMenu`.

## Images

- `html/img/miranda.webp` : la carte Miranda fournie (convertie en WebP, 2112 × 1152, ~370 Ko au lieu de 5,8 Mo).
- `html/img/alphabet.webp` : alphabet phonétique de la police, fait pour ce serveur dans le même style.

## Performance

Aucune boucle quand aucune carte n'est affichée. Carte affichée : une vérification du menu pause toutes les 250 ms.

## Exports (client)

`toggle(id)`, `show(id)`, `hide(id)`, `isShown(id)`, `cards()` → `{ id, label, command, shown }`.

## Installation

`ensure rp_policecards` (après `rp_interact` ou avant : le menu la trouve à l'ouverture).
