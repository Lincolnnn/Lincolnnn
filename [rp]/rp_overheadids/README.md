# rp_overheadids

En **maintenant une touche** (par défaut **Début / HOME**), au-dessus de la tête de chaque joueur proche : son **nom
RP** (`/nomrp`, en gros) et, **en dessous**, son **numéro sur le serveur** (ID). Jamais le nom Steam / FiveM. Pas encore
de nom RP : son numéro seul. On relâche : tout disparaît. Aucun framework.

- Touche modifiable par chaque joueur : Échap > Paramètres > Raccourcis clavier > FiveM > « Afficher les noms RP et
  numéros des joueurs (maintenir) ». Par défaut pour tous : `Key` dans `config.lua`.
- Le nom RP est celui de `/nomrp` (rp_chat, partagé avec le MDC : état du joueur `rpName`, `NameState`).
- Joueurs à moins de `Distance` m (25), visibles seulement (`LineOfSight` : pas à travers un mur) ; son propre
  numéro aussi (`ShowSelf`).
- Un joueur qui **parle** (pma-voice ou micro du jeu) : nom en bleu clair (`TalkingColor`).

## Installation

Copiez `rp_overheadids` dans `resources/`, puis `ensure rp_overheadids` dans `server.cfg`.

## Performance

Rien tant que la touche n'est pas maintenue (raccourci FiveM, aucune boucle : 0.00 ms). Pendant l'appui : liste des
joueurs proches revue toutes les 250 ms, textes dessinés à chaque image.
