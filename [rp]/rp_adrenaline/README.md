# RP Adrénaline

**Blessé par balle** : selon l'**adrénaline** (l'intensité de la fusillade autour de lui), le personnage **chute**
(ragdoll) tout de suite ou bien plus tard, et peut **lâcher son arme à feu** à chaque chute. 100 % standalone, Lua 5.4.

## Déroulement

1. **Première balle reçue** : pendant **15 s**, le script compte les **coups de feu autour du joueur, à moins de
   50 m** (les siens, ceux des autres joueurs et des PNJ), et les balles qu'il reçoit. **Aucune chute pendant ces
   15 s.**
2. **À la fin des 15 s**, un des deux scénarios est choisi :

| Scénario | Condition | Chutes |
|---|---|---|
| **Adrénaline haute** (résistance à la douleur forte) | **au moins 3 balles** reçues ET **au moins 15 tirs** autour | **première chute entre 50 et 70 s après la première blessure**, plus tôt s'il a pris plus de balles (tableau ci-dessous) ; ensuite **55 % de chances de chuter toutes les 7 s** |
| **Adrénaline basse** (résistance à la douleur basse) | **4 balles au plus** ET **moins de 8 tirs** autour | dès la fin des 15 s : **55 % de chances de chuter toutes les 7 s** ; **65 %** de lâcher l'arme à chaque chute |

Adrénaline haute, selon les balles reçues :

| Balles reçues | Première chute (après la première blessure) | Lâcher l'arme à chaque chute |
|---|---|---|
| 3 | vers la fin : 63 à 70 s | 65 % |
| 4 | 60 à 68 s | 70 % |
| 5 | 57 à 65 s | 75 % |
| 6 | vers le milieu : 55 à 64 s | 80 % |
| 7 et plus | dès 50 s (50 à 52 s) | 85 % |

Une balle de plus reçue avant cette première chute peut l'**avancer** (jamais la retarder) et relève le pourcentage.

**Cas entre les deux** (8 à 14 tirs autour ; moins de 3 balles dans une grosse fusillade ; 5 balles et plus avec peu
de tirs) : **adrénaline basse** (`Fallback = 'low'` ; `'high'` pour l'autre).

3. **Arme lâchée** (si le joueur tient une arme à feu ; pas un Taser ni une lampe) : elle tombe au sol et se
   **reprend avec l'œil** (Alt : « Ramasser »), avec ses accessoires et son chargeur (`rp_vehicleprops`).
4. **Fin des chutes** :
   - **1 min 30 après la fin des 15 s** de recherche (donc 1 min 45 après la première balle) ;
   - ou dès que le joueur est **soigné** : **vie remise au maximum**, par n'importe quel menu (vMenu, admin…) ; une
     balle arrêtée par le gilet (vie restée au maximum) ne compte pas comme une blessure ;
   - ou s'il **meurt** / **réapparaît** (rp_revive).
   Une nouvelle balle après la fin : nouvel épisode (nouvelles 15 s de recherche).

À pied seulement : en véhicule, une chute tirée au sort est sautée ; la première chute de l'adrénaline haute attend
qu'il descende (avant la fin de l'épisode).

Tout se règle dans `config.lua` : portée et durée de la recherche (`Analysis`), seuils des deux scénarios, tableau
`High.Stages`, chutes après la première (`High.AfterFirst`, `false` : une seule chute), tirages de l'adrénaline
basse (`Low.Every`, `Low.Jitter`, `Low.Chance`, `Low.Drop`), `Duration`, temps au sol, `Debug` (détails dans F8).

## Installation

```cfg
ensure rp_weaponscontrol   # tirs entendus et balles reçues (obligatoire) ; ShotEventRange = 50 m pour les PNJ
ensure rp_vehicleprops     # arme lâchée au sol, reprise avec l'œil
ensure rp_adrenaline
```

Export client : `exports.rp_adrenaline:level()` -> `'high'`, `'low'` ou `nil` (rien, ou recherche en cours).

## Performance

Aucune boucle sans blessure : il écoute deux événements locaux de `rp_weaponscontrol`
(`rp_weaponscontrol:shotNear`, `rp_weaponscontrol:bulletHit`). Pendant un épisode (1 min 45 au plus) : une
vérification toutes les 250 ms.
