# RP Chat (FiveM)

Chat écrit rôleplay **100% standalone** (sans ESX / QBCore / vRP) qui **remplace le chat d'origine** de FiveM.
Interface NUI en HTML/CSS/Vanilla JS, même thème que le HUD et le display du MDC (fond noir à 62 %, contour gris arrondi).
Conçu pour fonctionner avec le MDC du même dépôt (`mdc_standalone`), mais utilisable seul.

## Installation

1. Copiez le dossier `rp_chat` dans `resources/` (à côté du MDC, pas à l'intérieur).
2. Dans `server.cfg` :
   ```cfg
   # ensure chat              <- à retirer (ou commenter avec #)
   # ensure chat-theme-gtao   <- à retirer (ou commenter avec #)
   ensure rp_chat             # le plus haut possible, avant vos autres scripts
   ensure mdc_standalone
   ```
3. **OneSync recommandé** : le serveur filtre alors lui-même les `/me` par distance. Sans OneSync, le filtrage se fait
   chez chaque joueur (le message est envoyé à tous, puis ignoré au-delà de 100 m).

### Remplacer le chat d'origine (`chat` et `chat-theme-gtao`)

- **Ne supprimez pas leurs dossiers** : beaucoup d'hébergeurs et txAdmin les remettent automatiquement (dossier
  `[cfx-default]` / `[gameplay]`). Ce n'est pas un problème : une ressource présente dans `resources/` mais **non
  démarrée** ne fait rien. Seules les lignes `ensure` / `start` comptent.
- `chat-theme-gtao` n'est pas un second chat : c'est l'habillage « GTA Online » du chat d'origine (il ne fonctionne
  qu'avec `chat`).
- **rp_chat les arrête automatiquement** s'ils sont démarrés quand même (ligne oubliée dans `server.cfg`, liste de
  ressources du panel de l'hébergeur…) : au démarrage de rp_chat et chaque fois que l'un d'eux redémarre. La console
  serveur indique alors quelle ligne retirer, par exemple :
  `[RP Chat] Ressource d'origine "chat" arrêtée : rp_chat la remplace. Retirez "ensure chat" de votre server.cfg…`
- **Exception** : si une autre ressource déclare `dependency 'chat'` dans son `fxmanifest.lua`, arrêter `chat` l'arrêterait
  aussi. rp_chat laisse alors `chat` démarré et l'indique dans la console : retirez cette ligne `dependency 'chat'`
  (rp_chat déclare `provide 'chat'` et gère `chat:addMessage`, ces ressources fonctionnent sans le chat d'origine).
- Si la console affiche « Impossible d'arrêter "chat" », retirez la ligne `ensure chat` ou ajoutez dans `server.cfg` :
  `add_ace resource.rp_chat command.stop allow`.
- Panel d'hébergeur (ZAP-Hosting, etc.) avec une page « Ressources » : désactivez-y `chat` et `chat-theme-gtao`.
- Le **chat intégré de GTA Online** (celui du jeu, sans rapport avec ces ressources) est désactivé par rp_chat, comme le
  faisait le chat d'origine.
- Pour garder le chat d'origine actif malgré tout : `StopDefaultChat = false` dans `config.lua`.

## Utilisation

- **Ouvrir** : touche **T** par défaut. Chaque joueur peut la changer :
  *Échap > Paramètres > Raccourcis clavier > FiveM > « Chat : ouvrir / fermer »*.
- **Fermer** : **Échap**, ou la même touche quand la ligne de saisie est vide (sinon la lettre s'écrit normalement).
- **Entrée** envoie ; **Tab** complète la commande ; **↑ / ↓** rappellent les lignes déjà envoyées (ou parcourent les
  suggestions) ; **Page ↑ / Page ↓** font défiler les messages.
- Chat fermé : les nouveaux messages s'affichent quelques secondes puis disparaissent (réglable).

## Commandes

| Commande | Affichage | Qui le voit |
|---|---|---|
| `/nomrp John Carter` | « Nom RP : John Carter » (confirmation) | le joueur |
| `/me jette l'arme au sol` | **John Carter** jette l'arme au sol — vert pâle | joueurs dans un rayon de **100 m** au moment de l'envoi |
| `/info Route fermée` | Route fermée — rouge Torino surligné de rouge pâle, **sans nom RP** | tout le monde |
| `/qst Qui est dispo ?` | <ins>**John Carter**</ins> **Question :** Qui est dispo ? — orange pâle | tout le monde |
| `/rep Adam-12 dispo` | <ins>**John Carter**</ins> **Réponse :** Adam-12 dispo — violet pâle | tout le monde |

Mise en forme du nom RP : en gras pour `/me`, en gras et souligné pour `/qst` et `/rep` (« Question : » et
« Réponse : » en gras, non soulignés).

- **`/nomrp` d'abord** : sans nom RP, aucune autre commande n'est possible (même celles des autres ressources tapées dans le
  chat), et le MDC refuse de rejoindre une unité.
- Le nom RP est **le même que celui du MDC** : le changer dans le MDC le change dans le chat, et inversement. Il est gardé dans
  l'état du joueur côté serveur (`Player(source).state.rpName`) et **remis à zéro à chaque déconnexion**.
- `/me` : un joueur qui entre dans le rayon après coup ne voit pas les anciens messages ; un joueur qui en sort garde ceux déjà reçus.
- `/info`, `/qst`, `/rep` restent dans le chat : les 50 derniers sont aussi envoyés aux joueurs qui se connectent
  (gardés en mémoire, perdus au redémarrage du serveur).
- Un texte sans `/` n'est pas envoyé : le chat rappelle la liste des commandes. Les autres commandes (`/mdc`, commandes
  d'autres ressources) sont exécutées normalement.
- 250 caractères max par message, 1 message par seconde max (`config.lua`).

## Réglages (par joueur)

Dans le MDC : onglet **Paramètres > Chat écrit et commandes**. Gardés chez chaque joueur (KVP `rpchat_settings`), même après une reconnexion :

- Teinte du fond (de noir à gris), opacité du fond, taille du texte, largeur et hauteur du chat ;
- Contour : affiché ou non, couleur (couleurs proposées ou code `#rrggbb`), épaisseur ;
- Nouveaux messages, chat fermé : affichés quelques secondes / toujours affichés / masqués ;
- **Affichage des /me** : dans le chat écrit (par défaut), ou **au-dessus de la tête** des joueurs. Ce choix ne concerne que
  le joueur qui l'a fait : il voit alors ses `/me` et ceux des autres au-dessus des têtes, en vert pâle, sans fond et en
  plus grand que dans le chat. La taille suit la distance : le texte grandit quand on s'approche du joueur et rétrécit
  quand on recule (jusqu'à ~30 m, puis taille minimale lisible), et grossit avec le zoom de la caméra (visée).

Le chat apparaît en aperçu pendant les réglages. Sans le MDC, les réglages par défaut s'appliquent.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `DefaultKey` | touche d'ouverture par défaut (`T`) |
| `MeDistance` | rayon des `/me` (100 m) |
| `MaxLength`, `Cooldown` | longueur max d'un message, délai entre deux messages |
| `NameMin`, `NameMax` | longueur du nom RP (2 à 40) |
| `GlobalHistory` | nombre de `/info`, `/qst`, `/rep` envoyés aux nouveaux connectés |
| `Permissions` | permission ACE facultative par commande, ex. `info = 'rpchat.info'` puis `add_ace group.admin rpchat.info allow` |
| `OverheadDuration`, `OverheadMaxLines` | durée d'un `/me` au-dessus d'une tête, nombre max par joueur |
| `OverheadScale`, `OverheadMinScale`, `OverheadMaxScale` | taille du `/me` au-dessus des têtes (à ~4 m), facteurs min (au loin) et max (tout près) |

Si vous renommez le dossier, mettez le nouveau nom dans `ChatResource` (`client/client.lua` du MDC).

## Compatibilité avec le chat d'origine

Les autres ressources peuvent continuer à utiliser `TriggerClientEvent('chat:addMessage', ...)`, `chatMessage`,
`chat:clear` ou `exports.chat:addMessage(...)` : leurs messages s'affichent dans ce chat. Les suggestions de commandes
du chat d'origine sont ignorées.

## Performance

- Aucune boucle côté client quand rien n'est affiché au-dessus des têtes (0.00 ms dans le resmon).
- `/me` au-dessus des têtes : une boucle de dessin tourne uniquement pendant qu'un `/me` est affiché (7 s environ), puis s'arrête.
