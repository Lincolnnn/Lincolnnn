# rp_overheadids

En **maintenant une touche** (par défaut **Début / HOME**), le **numéro** de chaque joueur proche (son ID sur le
serveur) et son **nom** s'affichent au-dessus de sa tête. On relâche : tout disparaît. Aucun framework.

- Touche modifiable par chaque joueur : Échap > Paramètres > Raccourcis clavier > FiveM > « Afficher les numéros des
  joueurs (maintenir) ». Par défaut pour tous : `Key` dans `config.lua`.
- `Show` : `'id'` (numéro seul), `'name'` (nom FiveM seul) ou `'both'` (numéro, et le nom en dessous).
- Joueurs à moins de `Distance` m (25), visibles seulement (`LineOfSight` : pas à travers un mur) ; son propre
  numéro aussi (`ShowSelf`).
- Un joueur qui **parle** (pma-voice ou micro du jeu) : numéro en bleu clair (`TalkingColor`).

## Installation

Copiez `rp_overheadids` dans `resources/`, puis `ensure rp_overheadids` dans `server.cfg`.

## Performance

Rien tant que la touche n'est pas maintenue (raccourci FiveM, aucune boucle : 0.00 ms). Pendant l'appui : liste des
joueurs proches revue toutes les 250 ms, textes dessinés à chaque image.
