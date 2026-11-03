# RP Teleport (ex `onesync-tp`)

Téléportation entre joueurs et **blips sur toute la carte**, à n'importe quelle distance, avec OneSync. 100 %
standalone, Lua 5.4.

## Pourquoi

Avec OneSync, un client ne « voit » que les joueurs à environ 424 m de lui : au-delà, leur position est inconnue de son
côté, et les téléportations des menus (vMenu…) qui la lisent côté client échouent. Ici, les positions sont lues
**côté serveur**, où elles sont toujours connues ; le client ne fait que se déplacer, en attendant que le décor et les
collisions de la zone soient chargés (sinon on tombe sous la map).

## Installation

Remplace l'ancienne ressource **`onesync-tp`** (à retirer de `server.cfg` : mêmes commandes). Dans `[rp]/` :

```cfg
set onesync on
ensure rp_permissions   # rangs Discord (avant)
ensure rp_chat          # messages privés et commandes proposées en tapant « / »
ensure rp_teleport
```

Rien d'autre : les droits viennent du rang Discord donné par `rp_permissions`.

## Commandes (dans le chat)

| Commande | Effet | Par défaut |
|---|---|---|
| `/goto [ID]` | se téléporter **à côté** d'un joueur (à côté de son véhicule s'il conduit), toute distance | tous les joueurs |
| `/back` | revenir à sa position d'avant la dernière téléportation (`/back` encore = aller-retour) | tous |
| `/blip [ID]` | **suivre un joueur sur la carte / la minimap**, toute distance ; encore une fois pour le retirer ; `/blip off` : tout retirer (10 au plus) | tous |
| `/players` | joueurs connectés : ID, nom (nom RP), distance, même très loin | tous |
| `/bring [ID]` | amener un joueur à soi (il peut faire `/back`) | admins |

Les commandes sont **proposées dans le chat en tapant « / »** (seulement celles que le joueur a le droit d'utiliser,
mises à jour si son rang Discord change) et marchent **sans nom RP** (utilitaires). Tous les messages arrivent en
**privé** dans le chat. Les IDs des joueurs : `/players` ou la touche des noms au-dessus des têtes (rp_overheadids).
`/goto` prévient le joueur rejoint (`NotifyTarget`) ; 3 s entre deux téléportations (`Cooldown`, pas pour les admins) ;
refusé si le joueur est dans une autre instance (routing bucket).

## Réglages (`config.lua`)

`Permissions` : l'ACE de chaque commande (`'rp.nonofficiel'` = tous les joueurs whitelistés, `'rp.membre'`,
`'rp.admin'`, ou n'importe quelle ACE ; `false` = tout le monde). Lue sur le rang Discord (`rpRank` de
rp_permissions) ou sur l'ACE de `permissions.cfg`. Aussi : distance d'arrivée à côté du joueur / du véhicule, délai de
chargement, fondu au noir, blips (fréquence, nombre, sprite, couleur).

## Corrections par rapport à `onesync-tp`

- **Le script ne démarrait pas** : `goto` est un mot réservé de Lua 5.4 ; `Permissions = { goto = … }` et
  `Config.Permissions.goto` étaient des erreurs de syntaxe -> `['goto']`.
- Arrivée **à côté** du joueur (avant : dans lui, ou dans son véhicule) puis **posé sur le sol** trouvé une fois la zone
  chargée.
- Deux téléportations rapprochées : la seconde attend la première (avant : perdue).
- Passager d'un véhicule : sort normalement ; fondu au noir limité à 1 s (pas d'écran noir bloqué).
- Messages privés dans le chat (rp_chat), une seule fiche pour `/players`, ID vérifié (nombre entier, joueur connecté).
- Nouveau : `/blip`, permissions par rang Discord, commandes proposées dans le chat.

## Exports (serveur)

```lua
local coords, heading = exports.rp_teleport:GetPlayerPosition(playerId)   -- même très loin
exports.rp_teleport:TeleportPlayer(playerId, vector3(x, y, z), heading)   -- chargement de la zone compris
```

Client : `exports.rp_teleport:teleport(vector3(x, y, z), heading)`.

## Performance

Aucune boucle sans action : le serveur n'envoie les positions des blips (toutes les 1,5 s) que tant que quelqu'un suit
un joueur ; le client n'a aucun thread permanent.

## Avec vMenu (téléportation au-delà de 400 m)

vMenu (Joueurs en ligne > Se téléporter / dans le véhicule) ne cherche les joueurs à **toute distance** (liste et
position demandées au serveur) que si la convar `onesync_enableInfinity` vaut `"true"`. Les FiveM récents activent
OneSync avec `onesync on` et ne posent plus cette ancienne convar : vMenu se croyait limité au rayon du joueur
(~400 m). **rp_teleport la pose au démarrage** dès que OneSync est actif (`VMenuInfinity = true`). Démarrez
`rp_teleport` **avant** `vMenu` ; les joueurs déjà connectés doivent se reconnecter. Sinon, dans `server.cfg` :
`set onesync_enableInfinity true`.
