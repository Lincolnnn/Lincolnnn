# RP Scene — Riven Scene Dynamics dans l'œil

Met les fonctions principales de **Riven Scene Dynamics** (banderoles de police, script payant de Riven Systems)
dans **notre œil** (Alt), par le pont `ox_target`, comme pour les herses de `riven_spikes`.

- **Aucun code de Riven** ici, et Riven n'est **pas modifié** : `rp_scene` lance ses commandes (`/riventrunk`,
  `/rivenscene auto …`, `/rivenevidence collect`…).
- Riven s'installe **à part, tel qu'acheté**, avec sa licence. Il n'est **jamais dans ce dépôt** (`.gitignore`).
- Sans Riven démarré (ou licence refusée : Riven s'arrête lui-même), **aucune option** n'apparaît.
- Options réservées aux **policiers en service** (dans une unité du MDC) : `ox_target/config.lua`,
  `PoliceOnly = { …, rp_scene = true }` (déjà fait).

## Installation

1. Copiez `Riven_Scene_Dynamics/` tel que vous l'avez acheté dans `resources/[rp]/`.
2. `server.cfg` :
   ```
   set riven_license_key "VOTRE-CLÉ"     # clé de Riven, jamais dans le dépôt
   ensure ox_target
   ensure Riven_Scene_Dynamics
   ensure rp_scene
   ```
3. Si le dossier de Riven porte un autre nom : `config.lua`, `Resource`.

## Dans l'œil (policier en service)

| On vise | Option | Riven |
|---|---|---|
| **Coffre** d'un véhicule d'urgence (classe 18, ou `TrunkModels`) | **Kit de scène (banderoles, poteaux, cônes, preuves)** : le joueur marche jusqu'au pare-chocs, puis le coffre de Riven s'ouvre | `/riventrunk` |
| Véhicule d'urgence | **Périmètre automatique : petit / moyen / grand** | `/rivenscene auto small` … |
| Véhicule d'urgence | **Gestion de la scène** (interface de Riven : scènes, preuves, véhicules, tableau tactique) | `/rivenui` |
| Autre véhicule | **Enregistrer le véhicule à la scène** (V-001…) | `/rivenvehicle register` |
| Plot de preuve | **Collecter la preuve** | `/rivenevidence collect` |
| Poteau de banderole | **Retirer le poteau** | `/rivenscene post remove` |

Une fois le rouleau en main, tout se passe chez Riven : **E** pose un point, flèches pour tourner, **Retour arrière**
termine. Passer une banderole à pied : **E** devant elle (se baisser / enjamber).

Chaque option se retire dans `config.lua` (`Options`).

## Réglages conseillés dans la config de Riven (`shared/config.lua`, chez vous)

Rien n'est obligatoire. Pour que tout soit cohérent :

- `Config.Trunk.vehicleClasses` / `models` : **les mêmes véhicules** que `TrunkClasses` / `TrunkModels` de
  `rp_scene` (sinon Riven refuse d'ouvrir le coffre).
- **Doublons** avec nos scripts : cônes, barrières, fusées et projecteurs existent déjà dans `rp_equipment` /
  `rp_flares`. Pour ne garder que les banderoles au coffre de Riven : `Config.Trunk.props = {}`.
- **Touche E au coffre** : Riven affiche toujours sa propre invite « E Open trunk » derrière un véhicule
  d'urgence ; `rp_equipment` utilise aussi E au coffre. Riven n'a pas de réglage pour couper seulement cette invite
  (`Config.Trunk.enabled = false` coupe aussi `/riventrunk`, donc l'option de l'œil). À vérifier en jeu.
- Accès : cette version de Riven est **ouverte à tous** (pas de métier). L'œil ne propose les options qu'aux
  policiers en service, mais les commandes de Riven restent tapables par tous.

## Performance

Rien ne tourne : les conditions des options ne sont lues que pendant que l'œil vise.
