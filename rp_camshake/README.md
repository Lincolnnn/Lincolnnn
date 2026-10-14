# RP CamShake (FiveM)

Petit script **100% standalone** (sans ESX / QBCore / vRP), client uniquement, sans interface : la caméra tremble
selon ce que fait le personnage.

## Installation

1. Copiez le dossier `rp_camshake` dans `resources/`.
2. Dans `server.cfg` : `ensure rp_camshake`

## Fonctionnement

| Situation | Effet |
|---|---|
| À l'arrêt | aucun tremblement |
| **Marche** | léger tremblement |
| **Course** | plus fort |
| **Sprint** | encore plus fort |
| En visant avec une arme | réduit (`AimFactor`, `0` = aucun) |
| **En véhicule** | **aucun** tremblement… |
| …sauf **accident** | secousse selon la violence : accrochage (même minime : la carrosserie perd un peu de vie) → légère ; choc moyen → moyenne ; gros accident → forte. Aussi un arrêt brutal sans dégât visible |
| **Chute** (réception après une chute) | grosse secousse |
| Personnage **à terre** (ragdoll : trébuche, glisse, renversé…) | grosse secousse |
| **Percuté par un véhicule** | très grosse secousse |
| Coup ou balle reçus | secousse légère |

- Le tremblement de marche s'ajuste **en douceur** (pas d'à-coup en passant de la marche à la course).
- Une secousse plus faible ne coupe pas une plus forte en cours ; après un choc, le tremblement de marche reprend.
- Le tremblement d'un **autre script** (ivresse, drogue…) n'est ni coupé ni remplacé.
- **`/tremblement`** : chaque joueur active ou coupe l'effet (gardé chez lui, même après reconnexion).

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Walk`, `Run`, `Sprint` | secousse du jeu et amplitude pour chaque allure |
| `AimFactor`, `Smoothing` | réduction en visant ; douceur des changements d'amplitude |
| `Impacts` | secousse, amplitude, durée et force de chaque choc (accidents léger / moyen / gros, chute, à terre, percuté, coup) |
| `Crash` | seuils d'accident en véhicule (perte de vitesse, dégâts) |
| `FallTime` | durée de chute avant qu'une réception compte |
| `Command` | nom de la commande (`false` : aucune) |

## Performance

Une vérification toutes les **100 ms** quand le personnage se déplace (ou que le véhicule roule), toutes les
**250 ms** à l'arrêt, avec quelques natives seulement (≈ 0.00 ms dans le resmon). Les dégâts reçus sont détectés par
un **événement** du jeu (`CEventNetworkEntityDamage`), sans boucle.
