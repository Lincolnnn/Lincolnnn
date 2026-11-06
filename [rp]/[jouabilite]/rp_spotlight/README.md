# rp_spotlight

**Projecteurs de portière** (« spotlight ») des véhicules de police, **configurés véhicule par véhicule** : côté
**conducteur** (gauche) et, sur certains modèles, côté **passager avant** (droit). Vus par **tous les joueurs**.
100 % standalone, Lua 5.4, cerulean.

> Écrit pour ce serveur. Le script `px_spotlight` fourni est **chiffré** (protection Cfx « escrow », fichier `.fxap`) :
> son code ne peut être ni lu ni modifié, et il n'a pas été contourné. `rp_spotlight` le **remplace** (ne lancez pas
> les deux) avec les mêmes idées : faisceau visible, visée, verrouillage sur un point, réglage de la position. Aucun
> fichier de `px_spotlight` n'est utilisé (le faisceau visible est dessiné par ce script, avec ses propres textures).

## Utilisation (à bord, à la place qui tient le projecteur)

| Touche | Effet |
|---|---|
| **Ctrl gauche** (appui court) | allumer / éteindre son projecteur |
| **Ctrl gauche** (maintenu) | **viser** : le projecteur suit la caméra (réticule) ; relâché, il garde cette direction par rapport au véhicule |
| en visant : **clic gauche** | **verrouiller** sur le point visé (il y reste quand le véhicule bouge) ; à nouveau : manuel |
| `/editspotlight` | régler la position du projecteur **conducteur** (point rouge, curseurs X / Y / Z, ligne à copier) |
| `/editspotlightside` | régler la position du projecteur **passager** (véhicules à deux projecteurs) |

- **Qui tient quoi** : le **conducteur** tient le projecteur de gauche ; le **passager avant** celui de droite (s'il
  y en a un). Le serveur vérifie la place à chaque changement.
- Un petit panneau (en bas à droite) montre le mode (Manuel / Verrouillé).
- Pas de stroboscope ni de suivi automatique d'une personne / d'un véhicule : on garde le projecteur dessus à la main
  (ou on verrouille sur un point).
- Débattement limité (pas de faisceau à travers l'habitacle) : `Yaw` / `Pitch` (inversés pour le passager).
- Le projecteur reste allumé si l'on descend du véhicule ; en reprenant la place, on retrouve son état.
- Touches modifiables : *Paramètres > Raccourcis clavier > FiveM* (« Projecteur : … »).

## Véhicules (`config.lua`, `Vehicles`) — à modifier librement

```lua
Vehicles = {
    kcso20fpiu = {                                   -- deux projecteurs
        driver    = { offset = { -0.89, 1.25, 0.81 } },
        passenger = { offset = {  0.79, 1.20, 0.80 } },
    },
    wsp20fpiu = { driver = { offset = { -0.89, 1.23, 0.81 } } }, -- un seul, côté conducteur
    -- wsp25fpiu, wsp23tah, wsp20fpiuun, wsp19fpiu, kcso19fpiu, kcso19tah : côté conducteur
},
```

`offset` = position de la lampe sur le véhicule `{ x (gauche - / droite +), y (arrière - / avant +), z (haut) }` en
mètres. Les valeurs fournies sont des **points de départ** (Ford PIU / Tahoe) : réglez-les en jeu avec
**`/editspotlight`** (projecteur conducteur) ou **`/editspotlightside`** (projecteur passager), à bord du véhicule
(n'importe quelle place) : un **point rouge** montre le **départ de la lumière** (avec un faisceau d'essai si le
projecteur est éteint), le panneau de réglage est **en haut au milieu de l'écran** ; copiez la ligne affichée (aussi
dans la console F8) dans `config.lua`. Le réglage en jeu ne vaut que pour vous jusqu'à la déconnexion.

## Lumière

`Light` : couleur (blanc LED), portée, intensité, netteté du bord, ouverture, atténuation ; `Lamp` : petite lumière
sur la lampe. `RaycastDistance` : portée de la visée et du verrouillage.

### Faisceau visible (`Beam`)
Le **rayon de lumière dans l'air** (comme dans la brume) est dessiné par ce script : une bande lumineuse tournée vers
la caméra, douce sur les bords et qui s'efface vers le bout (`textures/beam.png`), plus un **halo** quand on regarde
la lampe de face (`textures/glow.png`). Les deux textures ont été faites pour ce script.
- **Bien visible la nuit** (21 h - 5 h), s'estompe au lever et au coucher du soleil, **invisible de jour**
  (`Day = 0.0` ; mettre par ex. `0.15` pour un léger rayon de jour). Plus marqué sous la pluie (`Rain`).
- **S'arrête sur l'obstacle** : mur, sol, véhicule (relu toutes les 100 ms).
- **S'élargit vers la fin** (`EndFlare` : presque 2 x plus large au bout) pour rejoindre la tache éclairée.
- Réglages : `Alpha` (opacité), `Length` (longueur max, 45 m), `Spread` (ouverture, 12°), `EndFlare`, `Start` (largeur à la lampe),
  `GlowAlpha` / `GlowSize` (halo), `Color` (couleur, sinon celle de `Light`), `Enabled = false` pour le couper.

### Éblouissement (`Glare`)
Un joueur **dans le faisceau** d'un projecteur (ou **tout près** : jusqu'à 15° de son axe, `NearAngle`), **la lampe en
vue** (rien entre les deux : mur, véhicule, objet ; son propre pare-brise ne protège pas), est **ébloui** :
- **voile blanc** sur tout l'écran et **gros halo** sur la lampe, à l'endroit où elle est à l'écran ;
- **plus fort** en regardant la lampe **en face**, **de près** (jusqu'à 90 m, `Range`) et **la nuit** (de jour :
  x 0.35, `Day`) ; en regardant ailleurs, il en reste un peu (`Away`) ;
- apparaît vite, **s'efface en ~1 s** une fois sorti du faisceau (persistance rétinienne, `Fall`) ;
- jamais pour les occupants du véhicule qui porte le projecteur ; rien pendant le menu pause.
Réglages : `Strength` (force générale), `Veil` (voile), `Size` (halo), `Rise` / `Fall`, `Enabled = false` pour le
couper.

## Performance

0.00 ms hors d'un véhicule équipé et sans projecteur allumé à proximité. À bord : une vérification de la place toutes
les 500 ms. Boucle par image seulement pour **dessiner** un projecteur allumé à moins de `RenderDistance` (160 m) ou
**pendant la visée** ; le faisceau visible ajoute une dizaine de triangles par projecteur et un rayon de test toutes
les 100 ms ; l'éblouissement, un calcul d'angle par projecteur et un rayon de test toutes les 150 ms seulement si
l'on est dans (ou près) d'un faisceau. La direction est envoyée aux autres au plus toutes les 100 ms en visant ; chez eux, elle est
lissée.

## Installation

`ensure rp_spotlight` (et retirer `px_spotlight` du `server.cfg`).
