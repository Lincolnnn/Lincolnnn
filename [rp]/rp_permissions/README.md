# RP Permissions — rôles Discord → permissions du serveur

Toutes les permissions du serveur viennent des **rôles Discord** (plus aucun identifiant Steam) :

| Rôle Discord | ID | Groupe ACE | Pour qui |
|---|---|---|---|
| **Admin** | `1562210128667611216` | `group.admin` | équipe d'administration : tout |
| **Membre** | `1562214435886465055` | `group.membre` | membres recrutés : presque tout le vMenu, MDC de la WSP |
| **Joueur non-officiel** | `1562213048163242004` | `group.nonofficiel` | joueurs non recrutés : permissions de base |

Inspiré de **DiscordWhitelist** (FAXES, licence CC0 1.0), réécrit en Lua : pas de Node, pas de `node_modules`.

## Fonctionnement

1. **Connexion** : le serveur demande à Discord (bot) les rôles du joueur. **Liste blanche** : sans aucun des trois
   rôles (ou pas sur le serveur Discord, ou Discord fermé), connexion refusée avec un message en français.
2. Le rôle **le plus haut** donne son groupe à l'identifiant Discord du joueur
   (`add_principal identifier.discord:… group.…`) avant son arrivée en jeu : vMenu et tous les scripts lisent les
   permissions de ce groupe (`permissions.cfg`).
3. **En jeu** : rang revérifié toutes les 15 min (rôle donné / retiré sur Discord) ; `rpperms_refresh [id]` (console ou
   admin) pour le faire tout de suite. vMenu relit ses permissions à la reconnexion du joueur.
4. État du joueur `rpRank` (`admin`, `membre`, `nonofficiel`, `aucun`), visible par son client.

Discord injoignable (panne) : `Whitelist.OnApiError = 'allow'` (par défaut) laisse entrer sans rôle (permissions de
base seulement), `'deny'` refuse.

## Installation

`server.cfg` (**le token ne va jamais dans un fichier du dépôt**) :

```
set rp_discord_token "TOKEN_DU_BOT"
exec @vMenu/config/permissions.cfg
ensure rp_permissions
ensure vMenu
# … puis les scripts rp_
```

`permissions.cfg` doit contenir (déjà dans la version fournie) :

```
add_ace resource.rp_permissions command.add_principal allow
add_ace resource.rp_permissions command.remove_principal allow
add_principal group.admin group.membre
add_principal group.membre group.nonofficiel
add_ace group.membre "rp.membre" allow
add_ace group.admin "rp.admin" allow
```

Bot Discord : sur le serveur Discord (ID dans `config.lua`, `GuildId`, ou convar `rp_discord_guild`), avec l'intent
**Server Members** activé (Discord Developer Portal > Bot > Privileged Gateway Intents). Au démarrage, la console
affiche « connecté au serveur Discord » ou l'erreur (token refusé, bot absent…). **Ne lancez plus DiscordWhitelist** en
même temps (double vérification).

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
