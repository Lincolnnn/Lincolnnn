# RP Adrénaline

**Blessé par balle** : le personnage **chute** (ragdoll) au hasard pendant un moment, et **lâche son arme à feu** une
fois sur trois à chaque chute. La durée dépend de l'**adrénaline**, d'après le nombre de **coups de feu entendus à
moins de 30 m** (soi, autres joueurs, PNJ) pendant les 30 dernières secondes :

| Situation | Adrénaline | Chutes |
|---|---|---|
| **au moins 2 balles** reçues et **plus de 10 tirs** autour | **haute** | pendant **50 s**, une toutes les **3 à 10 s** (au hasard) |
| **au moins 1 balle** et **moins de 5 tirs** autour | **basse** | pendant **15 s**, une toutes les 3 à 10 s |
| entre les deux (5 à 10 tirs, ou 1 seule balle dans une grosse fusillade) | moyenne | pendant 30 s |

- À chaque chute : **1 chance sur 3** que l'**arme à feu tenue tombe au sol** (pas un Taser ni une lampe). Elle se
  **reprend avec l'œil** (Alt : « Ramasser »), avec ses accessoires et son chargeur (`rp_vehicleprops`).
- Une nouvelle blessure plus grave **relève** le niveau ou **prolonge** la période (jamais abaissée).
- À pied seulement (en véhicule, la chute prévue est sautée) ; arrêt à la mort / réapparition.
- Tout se règle dans `config.lua` (portée, fenêtres, seuils, durées, intervalles, temps au sol, `DropChance`).

## Installation

```cfg
ensure rp_weaponscontrol   # tirs entendus et balles reçues (obligatoire)
ensure rp_vehicleprops     # arme lâchée au sol, reprise avec l'œil
ensure rp_adrenaline
```

## Performance

Aucune boucle hors période : il écoute deux événements locaux de `rp_weaponscontrol`
(`rp_weaponscontrol:shotNear`, `rp_weaponscontrol:bulletHit`) ; pendant une période, une attente au hasard entre deux
chutes.
