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

## `/configtetes` : maintenir ou appuyer

`/configtetes` ouvre un petit choix (souris, ou flèches + Entrée ; Échap : fermer), gardé chez chaque joueur :
- **Maintenir touche** : les noms s'affichent **tant que la touche est maintenue** ;
- **Appuyer pour activer** : **un appui** affiche les noms, **un autre appui** les retire.

Par défaut pour tous : `DefaultMode` (`'hold'` ou `'toggle'`). Commande : `ConfigCommand`.

## Installation

Copiez `rp_overheadids` dans `resources/`, puis `ensure rp_overheadids` dans `server.cfg`.

## Performance

Rien tant que les noms ne sont pas affichés (raccourci FiveM, aucune boucle : 0.00 ms). Pendant l'affichage : liste
des joueurs proches revue toutes les 250 ms, textes dessinés à chaque image.
