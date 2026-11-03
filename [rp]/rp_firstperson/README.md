# RP First Person

**Posture normale à la 1re personne**, armé ou non. 100 % standalone, Lua 5.4.

## Le problème

En vue à la 1re personne, le jeu met souvent le personnage en **« mode action »** : posture de combat **courbée**,
démarche tactique, épaules rentrées. Pas seulement avec une arme à feu : aussi **mains nues** (après un coup, poings
levés), avec une **arme blanche**, une lampe, un objet, après un tir ou une bagarre à côté… Et cette posture se voit
chez le joueur **et chez les joueurs autour** : chaque personnage est animé par le jeu de son joueur, puis
synchronisé chez les autres.

## La correction

Tant que le joueur est à la 1re personne à pied, **à chaque image** : le mode action est interdit (reset flag 200
`PRF_DisableActionMode`) et, s'il y est déjà, il en sort tout de suite (`SetPedUsingActionMode(false)`). Posture
normale **pour lui et pour tout le monde** : la correction faite par son client est synchronisée comme le reste de
son personnage. **Côté serveur, rien n'est possible** : aucun serveur ne peut changer l'animation d'un joueur ; c'est
pour ça que la ressource est côté client, chez chaque joueur (elle est envoyée à tous automatiquement).

Rien d'autre n'est touché : visée, tir, rechargement, accroupi / furtif, emotes, course.

Limite : la position des mains et de l'arme propre à la vue 1re personne (arme levée devant soi quand on vise) est
celle du jeu.

## Installation

Dans `[rp]/`, puis dans `server.cfg` :

```cfg
ensure rp_firstperson
```

Elle remplace le module « posture à la 1re personne » de `rp_weaponscontrol` (retiré de ce script : la correction
n'y valait que pour les armes, ici elle vaut pour tout).

## Réglages (`config.lua`)

| Clé | Rôle |
|---|---|
| `Enabled` | correction activée |
| `OnFoot` | à pied, à la 1re personne (armé ou non) |
| `ThirdPerson` | `true` : aussi à la 3e personne (posture de combat qui reste après un tir, un coup…) |
| `InVehicle` | `true` : aussi dans un véhicule |
| `CheckMs` | hors 1re personne : délai entre deux vérifications (ms) |
| `Command` | **`/fpsposture`** (F8 ou chat) : coupe / remet la correction pour comparer en jeu (non gardé) |

## Exports (client)

```lua
exports.rp_firstperson:isActive()        -- correction en cours (1re personne à pied…)
exports.rp_firstperson:setEnabled(false) -- couper / remettre la correction (ex. une cinématique)
exports.rp_firstperson:fixPosture(ped)   -- retirer le mode action d'un personnage pour cette image
```

## Performance

Hors 1re personne : une vérification toutes les 250 ms (**0.00 ms**). À la 1re personne : deux natives par image.
