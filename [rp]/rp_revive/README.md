# RP Revive

Réanimer son personnage après la mort : **sur place** ou **dans un hôpital** (au hasard), en laissant si on le souhaite
**son corps sur place**. 100 % standalone (ni ESX, ni QBCore, ni vRP), Lua 5.4.

## Installation

Dans `[rp]/` (déjà en place), puis dans `server.cfg`, **après** `rp_interact` :

```cfg
ensure rp_revive
```

La réapparition automatique de `spawnmanager` (ressource de base de FiveM) est coupée par ce script
(`DisableAutoSpawn`) : c'est son écran qui réanime. Désactivez toute autre ressource de réanimation / respawn.

## En jeu

À la mort, un écran s'affiche en bas au milieu (les choix s'activent au bout de `Delay` secondes, 0 par défaut : tout de suite) :

| Choix | Touche | Effet |
|---|---|---|
| **Réanimer sur place** (principal) | **E** | là où se trouve le corps (à côté du véhicule si on est mort à bord) |
| **Réanimer à l'hôpital** (principal) | **H** | dans un hôpital **au hasard** : Sandy Shores Medical Center ou Paleto Bay Medical Center ; le joueur ne choisit pas |
| ☐ **Laisser mon corps sur place** (secondaire) | **C** | une **copie du personnage** (même apparence, tenue comprise) reste allongée là où il est mort, visible par tout le monde |

Souris ou clavier. Réanimé avec toute sa vie, sang et blessures effacés. Réanimé par un autre script (secours…) :
l'écran se ferme tout seul.

**Le corps laissé sur place** (copie réseau, marquée `rpCorpse`) :
- garde la **description du profil civil actif** du joueur (fiche civile de `rp_interact` : inspection visuelle et
  olfactive, fouilles, détail notoire), **sauf l'odeur détectée automatiquement** ; à l'œil il est présenté comme
  « **Corps** » ; les policiers peuvent l'inspecter et le fouiller (pas de menottes ni de « prendre par le bras ») ;
- retiré au bout de `Corpse.Minutes` (30) ou quand le même joueur en laisse un autre (`MaxPerPlayer`, 1), et à l'arrêt
  du script ; on peut aussi le supprimer avec l'œil (« Supprimer »).

**Mode nuit** (réglé dans le MDC) : l'écran prend la couleur du mode nuit ; de jour, les couleurs du logo du serveur.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Delay` | secondes avant de pouvoir choisir |
| `Hospitals` | hôpitaux (nom, `vector4` position + cap) : un au hasard |
| `Corpse` | corps laissé : activé, durée (minutes, 0 = jamais retiré), un par joueur |
| `DisableAutoSpawn` | couper la réapparition automatique de spawnmanager |
| `Keys` | touches de l'écran (E, H, C) |
| `InteractResource` | nom de `rp_interact` (description du profil sur le corps) |

## Performance

Une vérification « suis-je mort ? » toutes les 500 ms (une native) ; rien d'autre au repos : **0.00 ms**.
