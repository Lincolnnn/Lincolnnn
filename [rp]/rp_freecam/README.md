# rp_freecam — /freecam (mode photo)

**Standalone**, Lua 5.4, `cerulean`. Pour **tous les joueurs** (aucune permission). **0,00 ms** tant que `/freecam`
n'est pas ouvert.

`/freecam` ouvre un petit menu en haut à gauche (au style des menus du serveur, mode nuit du MDC compris), **au
clavier, sans curseur** (la souris reste à la caméra) :

| Option | Effet |
|---|---|
| **Caméra libre** | caméra détachée du personnage (qui ne bouge plus) : **ZQSD / WASD** bouger, **souris** regarder, **E** monter, **A** (AZERTY) / **Q** (QWERTY) descendre, **Maj** rapide, **Ctrl** lent, **molette** zoom. Jamais à plus de `MaxDistance` m (60) du personnage ; le monde se charge autour de la caméra. |
| **Masquer la minimap** | minimap masquée |
| **Masquer le HUD du jeu** | textes de zone / rue / véhicule, aide, armes, réticule… masqués à chaque image |
| **Masquer les interfaces** | interfaces des scripts du serveur masquées (HUD et PLD du MDC, car HUD, chat, œil, barres, notifications, mode de tir…) : événement client `rp_freecam:hideUi` (true / false), écouté par chaque ressource du serveur (`[rp]`) |
| **Masquer mon personnage** | invisible pour soi seulement (photo du décor) |
| **Zoom** | champ de vision 5° à 100° (← → ou molette) |
| **Vitesse** | lente / normale / rapide |
| **Inclinaison** | -45° à 45° (photo penchée) |
| **Réinitialiser** | zoom, vitesse, inclinaison par défaut |

**Espace** (caméra libre ; le personnage ne saute pas) ou **H** (toujours) : masquer / remettre le menu (pour prendre
la photo, ex. touche F12 de Steam ou capture Windows ; `MenuToggleControl`).
**Retour arrière** ou **Échap** (ou « Quitter ») : sortie, tout est remis comme avant (caméra, minimap, interfaces).

Une autre ressource peut savoir si le mode photo est ouvert : `exports.rp_freecam:active()`.

## Installation

```
ensure rp_freecam
```

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Command` | nom de la commande (`freecam`) |
| `MaxDistance` | distance max caméra ↔ personnage (m), 0 = sans limite |
| `Fov` | zoom : `Min`, `Max`, `Default`, `Step` (cran de molette) |
| `Speeds` | vitesses de déplacement (m/s) |
| `Sensitivity`, `RollStep` | souris, cran d'inclinaison |
| `HideUiEvent` | événement envoyé aux autres scripts pour masquer leurs interfaces |
| `HideHudComponents` | composants du HUD du jeu masqués |
