# rp_spotlight

**Projecteurs de portière** (« spotlight ») des véhicules de police, **configurés véhicule par véhicule** : côté
**conducteur** (gauche) et, sur certains modèles, côté **passager avant** (droit). Vus par **tous les joueurs**.
100 % standalone, Lua 5.4, cerulean.

> Écrit pour ce serveur. Le script `px_spotlight` fourni est **chiffré** (protection Cfx « escrow », fichier `.fxap`) :
> son code ne peut être ni lu ni modifié, et il n'a pas été contourné. `rp_spotlight` le **remplace** (ne lancez pas
> les deux) avec les mêmes idées : visée, verrouillage sur un point, suivi d'une cible, stroboscope, réglage de la
> position. Aucun fichier de `px_spotlight` n'est utilisé.

## Utilisation (à bord, à la place qui tient le projecteur)

| Touche | Effet |
|---|---|
| **Ctrl gauche** (appui court) | allumer / éteindre son projecteur |
| **Ctrl gauche** (maintenu) | **viser** : le projecteur suit la caméra (réticule) ; relâché, il garde cette direction par rapport au véhicule |
| en visant : **clic gauche** | **verrouiller** sur le point visé (il y reste quand le véhicule bouge) ; à nouveau : manuel |
| en visant : **clic droit** | **suivre** le véhicule / la personne visé(e) (plaque affichée) ; à nouveau : manuel |
| **Maj droite** | stroboscope |
| `/editspotlight` | régler la position du projecteur **conducteur** (point rouge, curseurs X / Y / Z, ligne à copier) |
| `/editspotlightside` | régler la position du projecteur **passager** (véhicules à deux projecteurs) |

- **Qui tient quoi** : le **conducteur** tient le projecteur de gauche ; le **passager avant** celui de droite (s'il
  y en a un). Le serveur vérifie la place à chaque changement.
- Un petit panneau (en bas à droite) montre le mode (Manuel / Verrouillé / Suivi), la plaque suivie et le
  stroboscope. Cible perdue (trop loin, disparue) : retour en manuel.
- Débattement limité (pas de faisceau à travers l'habitacle) : `Yaw` / `Pitch` (inversés pour le passager).
- Le projecteur reste allumé si l'on descend du véhicule ; en reprenant la place, on retrouve son état.
- Touches modifiables : *Paramètres > Raccourcis clavier > FiveM* (« Projecteur : … »).

## Véhicules (`config.lua`, `Vehicles`) — à modifier librement

```lua
Vehicles = {
    kcso20fpiu = {                                   -- deux projecteurs
        driver    = { offset = { -0.93, 0.62, 0.60 } },
        passenger = { offset = {  0.93, 0.62, 0.60 } },
    },
    wsp20fpiu = { driver = { offset = { -0.93, 0.62, 0.60 } } }, -- un seul, côté conducteur
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

`Light` : couleur (blanc LED), portée, intensité, netteté du bord, ouverture, atténuation ; `Lamp` : petit halo sur
la lampe. `StrobeMs` : rythme du stroboscope. `RaycastDistance` : portée de la visée et du suivi.

## Performance

0.00 ms hors d'un véhicule équipé et sans projecteur allumé à proximité. À bord : une vérification de la place toutes
les 500 ms. Boucle par image seulement pour **dessiner** un projecteur allumé à moins de `RenderDistance` (160 m) ou
**pendant la visée**. La direction est envoyée aux autres au plus toutes les 100 ms en visant ; chez eux, elle est
lissée.

## Installation

`ensure rp_spotlight` (et retirer `px_spotlight` du `server.cfg`).
