# RP Adrénaline

**Blessé par balle** : selon l'**adrénaline** (fusillade ou non autour de lui), le personnage **chute** (ragdoll)
tout de suite ou bien plus tard, peut **lâcher son arme à feu** à chaque chute et prend une **démarche blessée**.
100 % standalone, Lua 5.4.

## Déroulement

1. **Balle reçue** : pendant **8 s**, le script compte les **coups de feu à moins de 50 m** autour du joueur (les
   siens, ceux des autres joueurs et des PNJ) et les balles reçues. **Aucune chute pendant ces 8 s.**
2. **À la fin des 8 s** :

| Scénario | Condition | Chutes |
|---|---|---|
| **Adrénaline haute** : « fusillade », résiste un peu mieux à la douleur | **10 tirs et plus** pendant les 8 s | les tirages ne commencent qu'**entre 50 et 70 s** après la fin des 8 s (au hasard), puis **un toutes les 8 s** |
| **Adrénaline basse** : « hors fusillade », effet de surprise | **moins de 5 tirs** | tirages **dès la fin des 8 s**, puis **un toutes les 8 s** |

À chaque tirage : **% de chances de chuter**, et à chaque chute **% de chances de lâcher l'arme** (seulement s'il en
tient une), selon les **balles reçues** (comptées jusqu'au tirage) :

| Balles reçues | Haute : chute / arme lâchée | Basse : chute / arme lâchée |
|---|---|---|
| 1 | 45 % / 45 % | 50 % / 55 % |
| 2 | 55 % / 65 % | 65 % / 70 % |
| 3 et plus (3 à 4) | 75 % / 80 % | 80 % / 75 % |

**Entre les deux** (5 à 9 tirs) : adrénaline basse (`Fallback = 'low'` ; `'high'` pour l'autre).

3. **Arme lâchée** (arme à feu tenue ; pas un Taser ni une lampe) : elle tombe au sol et se **reprend avec l'œil**
   (Alt : « Ramasser »), avec ses accessoires et son chargeur (`rp_vehicleprops`).
4. **Démarche blessée dès la 2e chute** : **`/walk injured`** (RPEMOTES) ; à la fin : **`/walk reset`**.
5. **Fin des chutes** :
   - **1 min 30 après la fin des 8 s** de recherche ;
   - ou dès que le joueur est **soigné** : **vie remise au maximum**, par n'importe quel menu (vMenu…) ; une balle
     arrêtée par le gilet (vie restée au maximum) ne compte pas comme une blessure ;
   - ou s'il **meurt** / **réapparaît** (rp_revive).
   La démarche normale revient à chaque fois. Une nouvelle balle après la fin : nouvel épisode (nouvelles 8 s).

À pied seulement : en véhicule, le tirage est sauté.

Tout se règle dans `config.lua` : recherche (`Analysis`), seuils (`High.MinShots`, `Low.MaxShots`), début des
chutes en adrénaline haute (`High.Start`), intervalle (`Every`), tableaux `Stages` (chute / arme lâchée par nombre de
balles), `Duration`, démarche (`Walk` : `Mode = 'command'` avec RPEMOTES, `'native'` sans, `false` : jamais), temps
au sol, `Debug` (détails dans F8).

**Démarche** : par défaut (`Walk.Mode = 'native'`), la démarche de `/walk injured` est posée directement par ce
script, sans passer par RPEMOTES : elle n'est jamais sauvegardée et ne revient pas à la connexion suivante. **Correctif** :
à chaque connexion / réapparition, une démarche blessée restée d'une ancienne sauvegarde de RPEMOTES (`PersistentWalk`)
est retirée (1, 3 et 6 s après l'apparition) s'il n'y a pas d'épisode en cours (`Walk.ClearOnSpawn`). `Walk.Mode =
'command'` : les commandes de RPEMOTES (`/walk injured`, `/walk reset`).

## Installation

```cfg
ensure rp_weaponscontrol   # tirs entendus et balles reçues (obligatoire) ; ShotEventRange = 50 m pour les PNJ
ensure rp_vehicleprops     # arme lâchée au sol, reprise avec l'œil
ensure rp_adrenaline
```

Export client : `exports.rp_adrenaline:level()` -> `'high'`, `'low'` ou `nil` (rien, ou recherche en cours).

## Performance

Aucune boucle sans blessure : il écoute deux événements locaux de `rp_weaponscontrol`
(`rp_weaponscontrol:shotNear`, `rp_weaponscontrol:bulletHit`). Pendant un épisode (1 min 38 au plus) : une
vérification toutes les 250 ms.
