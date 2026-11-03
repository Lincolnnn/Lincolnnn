# RP Viser

Chaque joueur choisit son **mode de visée** avec **`/viser`** (choix gardé chez lui) :

| Mode | Comment on vise |
|---|---|
| **Maintenir pour viser** (par défaut) | maintenir le **clic droit**, comme de base dans le jeu |
| **Appuyer pour viser** | **un appui** sur le clic droit : la visée reste active ; **un autre appui** : elle s'arrête (comme un jeu de tir) |

- `/viser` : passe d'un mode à l'autre ; `/viser maintenir` / `/viser appuyer` : choisir directement. Message privé
  dans le chat (rp_chat), et la commande est proposée en tapant « / » (utilisable sans nom RP).
- Mode « appuyer » : seulement avec une **arme à feu** en main, **à pied**. La visée s'arrête toute seule si l'arme est
  rangée / changée, en véhicule, à terre, mort, menotté, ou quand une interface prend la souris (menu, MDC, chat…).
- Réglages : `config.lua` (commande, mode par défaut des nouveaux joueurs).

## Installation

```cfg
ensure rp_viser
```

## Performance

Mode « maintenir » ou sans arme à feu : une vérification toutes les 250 ms ; arme à feu en main en mode « appuyer » :
lecture du clic droit à chaque image (comme le jeu).
