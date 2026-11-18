# RP Stages — stages des véhicules de police (extras)

Gère l'éclairage des véhicules de police **par leurs extras**, véhicule par véhicule (spawn code) :

- **3 stages principaux** : stage 1, stage 2, stage 3 — le **stage 3 est le stage de réponse** : **seul** à permettre
  la sirène ;
- **stages secondaires** : **Traffic Advisor Left**, **Traffic Advisor Right**, **Steady Burn**.

Aucun framework. Synchronisé entre les joueurs. Rien n'est obligatoire : chaque véhicule n'a que les stages qu'on lui
écrit dans `config.lua` (un véhicule sans stage 3, sans TA, avec seulement deux stages… tout est possible).

## Installation

1. Dossier `rp_stages` dans `resources/[rp]/[jouabilite]/`.
2. `server.cfg` : `ensure rp_stages` (après `rp_chat` pour que `/modiftouche STAGES` connaisse ses touches).
3. Écrire vos véhicules dans `config.lua` (voir ci-dessous) : **les numéros d'extras fournis sont des exemples**.

## Configuration (`config.lua`)

```lua
Vehicles = {
    ['police'] = {                                  -- spawn code du véhicule
        label = 'Police Cruiser',                   -- facultatif (indicateur à l'écran)
        stages = {                                  -- seulement ceux qui existent sur ce véhicule
            [1] = { extras = { [1] = true, [2] = false, [3] = false } },
            [2] = { extras = { [1] = true, [2] = true,  [3] = false } },
            [3] = { extras = { [1] = true, [2] = true,  [3] = true } },
        },
        secondary = {                               -- facultatif
            taLeft     = { extras = { [5] = true }, overlay = true },
            taRight    = { extras = { [6] = true }, overlay = true },
            steadyBurn = { extras = { [7] = true }, overlay = false, lights = false },
        },
        -- off = { [1] = true },                    -- facultatif : extras quand aucun stage n'est actif
        -- taExclusive = true,                      -- (défaut) TA gauche et TA droite jamais ensemble
    },
}
```

- `extras` : **seulement les extras ciblés**, chacun `true` (allumé) ou `false` (éteint) dans ce stage. Les extras
  non cités ne sont **jamais** touchés. Sans stage actif, tous les extras cités sont éteints (sauf `off`).
- `overlay` (stages secondaires, défaut `true`) : `true` = **se superpose** aux stages 1, 2, 3 ; `false` = l'activer
  éteint le stage principal (et la sirène), et choisir un stage l'éteint.
- `lights` (défaut `true`) : gyrophares du jeu allumés dans ce stage (les extras clignotants en ont besoin).
- Un extra cité dans un stage secondaire actif l'emporte sur le même extra du stage principal.
- Un extra absent du modèle est ignoré (avertissement unique dans la console F8). Les erreurs de configuration
  (stage 4, nom de stage secondaire inconnu…) sont signalées au démarrage.

## Sirène et stage 3

- La sirène n'est **audible qu'au stage 3**.
- Au **stage 1 ou 2** (ou sans stage), activer la sirène **passe automatiquement au stage 3** (« 3 AUTO » sur
  l'indicateur) ; quand la sirène est **coupée**, le véhicule **revient au stage d'avant** (stage 2 → sirène → stage 3 →
  sirène coupée → stage 2).
- S'il était **déjà au stage 3**, il **y reste** quand la sirène est coupée. Appuyer sur « stage 3 » pendant un stage 3
  automatique le garde aussi au stage 3 ensuite.
- Choisir le stage 1 ou 2 pendant la sirène **coupe la sirène**.
- Un véhicule **sans stage 3** a la sirène sans condition.
- Au volant d'un véhicule configuré, la touche de sirène du jeu (E) ne change plus les gyrophares : ils suivent le
  stage ; E reste le klaxon. La sirène se commande avec sa touche (R par défaut).

## Touches (modifiables : `/modiftouche STAGES …`, ou Paramètres > Raccourcis > FiveM)

| Action | Touche | Commande |
|---|---|---|
| Stage 1 / 2 / 3 (le stage actif appuyé de nouveau s'éteint) | `1` / `2` / `3` | `rps_stage1` / `rps_stage2` / `rps_stage3` |
| Traffic Advisor gauche / droite | `4` / `5` | `rps_ta_left` / `rps_ta_right` |
| Steady Burn | `6` | `rps_steady` |
| Sirène (stage 3) | `R` | `rps_siren` |

Seul le **conducteur** d'un véhicule configuré s'en sert (ailleurs les touches ne font rien). `Ace` dans `config.lua`
pour les réserver à une permission.

## Indicateur à l'écran

Petit cadre en bas à droite (conducteur seulement) : les stages du véhicule (actif en couleur, stage 3 en rouge,
« AUTO » s'il vient de la sirène), la sirène, puis TA ◀ / TA ▶ / SB si le véhicule en a. Position et affichage :
`Hud` dans `config.lua`. Masqué par le mode photo (`rp_freecam`).

## Fonctionnement

- L'état (stage, TA, Steady Burn, sirène) est calculé chez le conducteur (`shared/logic.lua`), appliqué tout de suite,
  puis **vérifié par le serveur** (bon conducteur, bon modèle, sirène seulement au stage 3…) qui le partage par le
  state bag `rpStages` du véhicule : chaque joueur proche applique les mêmes extras et entend (ou non) la sirène.
- `SetVehicleAutoRepairDisabled` : changer un extra **ne répare pas** le véhicule (dégâts de `rp_vehiclecontrol` gardés).
- Performance : hors véhicule configuré, une vérification toutes les 400 ms et une toutes les 2 s (véhicules réglés qui
  arrivent à portée) ; au volant d'un véhicule configuré, une boucle légère (gyrophares et sirène gardés dans l'état).
