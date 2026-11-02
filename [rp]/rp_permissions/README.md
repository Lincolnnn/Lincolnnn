# RP Permissions — rôles Discord → permissions du serveur

Toutes les permissions du serveur viennent des **rôles Discord** (plus aucun identifiant Steam) :

| Rôle Discord | ID | Groupe ACE | Pour qui |
|---|---|---|---|
| **Admin** | `1562210128667611216` | `group.admin` | équipe d'administration : tout |
| **Membre** | `1562214435886465055` | `group.membre` | membres recrutés : presque tout le vMenu, MDC de la WSP |
| **Joueur non-officiel** | `1562213048163242004` | `group.nonofficiel` | joueurs non recrutés : permissions de base |

Inspiré de **DiscordWhitelist** (FAXES, licence CC0 1.0), réécrit en Lua : pas de Node, pas de `node_modules`.

## Fonctionnement

**Hiérarchie** : un joueur qui a plusieurs de ces rôles reçoit **le plus haut** (admin > membre > joueur non-officiel).
Chaque rang a **toutes les permissions des rangs en dessous** + les siennes : rp_permissions pose lui-même cet héritage
(`add_principal group.admin group.membre`, `group.membre group.nonofficiel`) et les repères `rp.admin` / `rp.membre` /
`rp.nonofficiel` au démarrage (en plus de `permissions.cfg`), et nos scripts lisent aussi directement le rang du joueur
(état `rpRank`) : un admin a toujours accès à ce qui est réservé aux membres.

1. **Connexion** : le serveur demande à Discord (bot) les rôles du joueur. **Liste blanche** : sans aucun des trois
   rôles (ou pas sur le serveur Discord, ou Discord fermé), connexion refusée avec un message en français.
2. Le rôle **le plus haut** donne son groupe à l'identifiant Discord du joueur
   (`add_principal identifier.discord:… group.…`) avant son arrivée en jeu : vMenu et tous les scripts lisent les
   permissions de ce groupe (`permissions.cfg`).
3. **En jeu** : rang revérifié toutes les 15 min (rôle donné / retiré sur Discord) ; `rpperms_refresh [id]` (console ou
   admin) pour le faire tout de suite. vMenu relit ses permissions à la reconnexion du joueur.
4. État du joueur `rpRank` (`admin`, `membre`, `nonofficiel`, `aucun`), visible par son client.

**Chaque rôle sert à la fois de liste blanche et de permissions** : il faut **au moins un des trois** pour se
connecter, et chacun donne ses propres permissions en jeu. Rôles impossibles à vérifier (Discord en panne, token absent
ou refusé) : **connexion refusée** (`Whitelist.OnApiError = 'deny'`, par défaut) ; `'allow'` laisserait entrer sans
rôle (déconseillé).

## Installation

**Token du bot** : dans `config.lua`, ligne `BotToken = "",` (entre les guillemets). Ce fichier n'est lu que par le
serveur (jamais envoyé aux joueurs) ; ne le remettez **jamais** rempli sur GitHub. Ou, à la place, dans `server.cfg` :
`set rp_discord_token "TOKEN_DU_BOT"` (« set », pas « setr » ; passe avant `BotToken`).

`server.cfg` :

```
exec @vMenu/config/permissions.cfg
ensure rp_permissions
ensure vMenu
# … puis les scripts rp_
```

`permissions.cfg` doit contenir (déjà dans la version fournie) :

```
add_ace resource.rp_permissions command.add_principal allow
add_ace resource.rp_permissions command.remove_principal allow
add_ace resource.rp_permissions command.add_ace allow
add_ace resource.rp_permissions command.remove_ace allow
add_ace resource.rp_permissions command.quit allow
add_principal group.admin group.membre
add_principal group.membre group.nonofficiel
add_ace group.membre "rp.membre" allow
add_ace group.admin "rp.admin" allow
```

Bot Discord : sur le serveur Discord (ID dans `config.lua`, `GuildId`, ou convar `rp_discord_guild`), avec l'intent
**Server Members** activé (Discord Developer Portal > Bot > Privileged Gateway Intents). Au démarrage, la console
affiche « connecté au serveur Discord » ou l'erreur (token refusé, bot absent…). **Ne lancez plus DiscordWhitelist** en
même temps (double vérification).

## Réservé aux membres (`MembersOnly`)

Les **loadouts d'armes enregistrés de vMenu** (menu *Weapon Loadouts* : créer, équiper, équiper au respawn) sont
réservés aux **Membres et Admins**. `permissions.cfg` ne les donne qu'à `group.membre` ; en plus, rp_permissions pose
à la connexion un **refus** (`add_ace identifier.discord:<id> vMenu.WeaponLoadouts.… deny`) sur l'identifiant de
chaque joueur **non-officiel** : un refus l'emporte sur un « allow » donné ailleurs (un autre `.cfg`,
`builtin.everyone`), et comme il est posé sur l'identifiant (pas sur `group.nonofficiel`, dont héritent les membres),
il ne touche que ce joueur. Devenu Membre (rôle Discord), le refus est retiré (`remove_ace`). Liste dans
`config.lua` > `MembersOnly` (`{}` = rien de réservé ici). Demande `command.add_ace` et `command.remove_ace` (voir
Installation) ; sans ces droits, un avertissement dans la console et seul `permissions.cfg` les réserve.
Limite : un joueur à qui un `.cfg` donne `vMenu.Everything` garde tout (ne le donnez qu'aux admins).

## Statut du serveur sur Discord (`StatusConfig`)

Fichier `server/discord_status.lua` (fait par un membre de l'équipe, **pas dans ce dépôt** : à poser dans
`rp_permissions/server/`) : embed de statut, embed des joueurs connectés et alertes de connexion / déconnexion dans
les salons de `StatusConfig.Channels`. Le manifeste charge `server/discord_*.lua` **s'il est là** (rien ne casse
sinon). Il réutilise le bot des rôles (`BotToken`) ; il retient les IDs de ses messages dans `discord_messages.json`
(ignoré par git).

## Session whitelist (`/whiteliston`, `/whitelistoff`)

Réservées aux **admins** (rang Discord Admin, ACE `rp.admin`) et à la console du serveur.

- **`/whiteliston`** : l'accès devient **réservé aux membres recrutés** (Membre, Admin) : les **Joueurs non-officiels
  ne peuvent plus se connecter** (message clair). Annoncé à tous (bannière des sessions de rp_RoleplayZone + chat),
  rappels à 20, 10 et 5 s, puis **redémarrage du serveur 30 s après** (`RestartSeconds`) : joueurs prévenus et
  déconnectés, puis `quit` (`RestartCommand`) : **txAdmin relance le serveur** tout seul. Au retour, le mode est
  toujours actif (gardé dans la mémoire du serveur). Pendant les 30 s, les non-officiels sont déjà refusés.
- **`/whitelistoff`** : accès **rétabli tout de suite** pour tous les membres du Discord (à partir de Joueur
  non-officiel), annoncé, **sans redémarrage** ; annule un redémarrage en cours.

À ajouter dans `server.cfg` pour le redémarrage : `add_ace resource.rp_permissions command.quit allow` (sans ce droit,
le mode est activé quand même et la console demande de redémarrer depuis txAdmin). Sans txAdmin, `quit` arrête le
serveur : relancez-le vous-même (ou `RestartCommand = ''` : déconnexion des joueurs seulement). Textes et rang minimal :
`config.lua` > `Whitelist.Session`. Autres scripts : `exports.rp_permissions:isMembersOnly()`,
`GlobalState.rpWhitelistMembersOnly`.

## Pour les scripts

- Le plus simple : `IsPlayerAceAllowed(src, 'rp.admin')` / `'rp.membre'` (repères donnés aux groupes).
- Exports serveur : `getRank(src)`, `hasRank(src, 'membre')` (membre ou plus haut), `isAdmin(src)`, `isMember(src)`,
  `refresh(src)`.

## Commandes (console du serveur ou admins)

| Commande | Effet |
|---|---|
| `rpperms` | liste des joueurs connectés et de leur rôle |
| `rpperms_refresh [id]` | revérifie les rôles auprès de Discord (tous, ou un joueur) |

## Performance

Aucune boucle par image : une demande à Discord par connexion (gardée 10 min), une revérification toutes les 15 min.
