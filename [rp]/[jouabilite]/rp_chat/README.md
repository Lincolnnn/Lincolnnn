# RP Chat (FiveM)

Chat écrit rôleplay **100% standalone** (sans ESX / QBCore / vRP) qui **remplace le chat d'origine** de FiveM.
Interface NUI en HTML/CSS/Vanilla JS, fond sombre « bleu nuit » (à 80 %), **contour blanc** fin et coins presque carrés comme le MDC (contour affiché ou non et épaisseur réglables par joueur ; sa couleur suit le thème : blanc le jour, couleur du mode nuit la nuit) pour rester lisible sur le jeu ; la page `/tuto` reprend le thème clair du MDC.
Conçu pour fonctionner avec le MDC du même dépôt (`rp_mdc`), mais utilisable seul.

## Installation

1. Copiez le dossier `rp_chat` dans `resources/` (à côté du MDC, pas à l'intérieur).
2. Dans `server.cfg` :
   ```cfg
   # ensure chat              <- à retirer (ou commenter avec #)
   # ensure chat-theme-gtao   <- à retirer (ou commenter avec #)
   ensure rp_chat             # le plus haut possible, avant vos autres scripts
   ensure rp_mdc
   ```
3. **OneSync recommandé** : le serveur filtre alors lui-même les `/me` par distance. Sans OneSync, le filtrage se fait
   chez chaque joueur (le message est envoyé à tous, puis ignoré au-delà de 50 m).

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

**Mode nuit** (réglé dans le MDC : *Paramètres > MDC > Apparence*, appliqué à toutes les interfaces ou aux menus extérieurs) : **fond noir et couleur du mode nuit** (vert, jaune, rouge ou bleu) pour la page `/tuto`, et le **contour du chat** prend la couleur du mode nuit (le chat garde son fond et les couleurs des commandes) (`client/theme.lua` ; sans le MDC : thème jour).

## Utilisation

- **Ouvrir** : touche **T** par défaut. Chaque joueur peut la changer :
  *Échap > Paramètres > Raccourcis clavier > FiveM > « Chat : ouvrir / fermer »*.
- **Fermer** : **Échap**, ou la même touche quand la ligne de saisie est vide (sinon la lettre s'écrit normalement).
- **Entrée** envoie ; **Tab** complète la commande ; **↑ / ↓** rappellent les lignes déjà envoyées (ou parcourent les
  suggestions).
- **Naviguer dans la conversation** : **Page ↑** remonte, **Page ↓** redescend, chat **ouvert ou fermé** (chat fermé,
  il s'affiche le temps de lire puis disparaît). Chat ouvert : aussi la **molette** de la souris. Quand on est remonté,
  un repère « ▼ Messages plus récents en bas » s'affiche et les nouveaux messages ne font pas sauter la lecture.
  Touches modifiables : *Raccourcis clavier > FiveM > « Chat : remonter / descendre dans la conversation »*.
- Chat fermé : les nouveaux messages s'affichent quelques secondes puis disparaissent (réglable).

## Commandes

| Commande | Affichage | Qui le voit |
|---|---|---|
| `/nomrp John Carter` | « Nom RP : John Carter » (confirmation) | le joueur |
| `/me jette l'arme au sol` | **John Carter** jette l'arme au sol — vert pâle | joueurs dans un rayon de **50 m** au moment de l'envoi |
| `/info Route fermée` | Route fermée — rouge Torino surligné de rouge pâle, **sans nom RP** | tout le monde |
| `/qst Qui est dispo ?` | <ins>**John Carter**</ins> **Question :** Qui est dispo ? — orange pâle | tout le monde |
| `/rep Adam-12 dispo` | <ins>**John Carter**</ins> **Réponse :** Adam-12 dispo — violet pâle | tout le monde |
| `/hrp je reviens` | HRP **John Carter** : je reviens — **gris discret** (hors RP ; grisée dans la liste des commandes pour ne pas la mettre en avant) | tout le monde |
| `/dv` | « Véhicule supprimé. » | le joueur |
| `/eup` | ouvre le menu des tenues (ressource `rp_interact`) | le joueur |
| `/tuto` | affiche les touches et fonctionnalités en haut de l'écran, au milieu ; `/tuto` à nouveau la retire | le joueur |

Mise en forme du nom RP : en gras pour `/me`, en gras et souligné pour `/qst` et `/rep` (« Question : » et
« Réponse : » en gras, non soulignés).

- **`/nomrp` d'abord** : sans nom RP, aucune autre commande n'est possible (même celles des autres ressources tapées dans le
  chat), et le MDC refuse de rejoindre une unité. **Exceptions** : `/tuto`, `/dv`, `/fichecivil`, `/eup` et `/repair` marchent aussi sans nom RP.
- **`/tuto`** : une **affiche** en haut de l'écran, au milieu, large et peu haute, au thème des menus (fond noir, contour
  gris) : en haut « Tapez /tuto pour fermer cette page », puis cinq colonnes (Chat écrit, MDC & menus, Véhicule,
  Bodycam — commandes de CartoonBodycam : `/bwc`, touche O, `/bwc off`, `/bwcsize`, `/bwcedit`, `/bwcanim` —, Interpellations) de lignes « touche — description ». Elle ne prend **ni la souris ni le clavier** : on continue de
  jouer, d'ouvrir le MDC, les menus, le chat… ; elle reste jusqu'à ce que le joueur refasse `/tuto`. Visible
  uniquement par lui. Textes modifiables dans `config.lua` (`Tuto.Title`, `Tuto.Sections` : `{ touche, description }`,
  `Tuto.Footer`). À **chaque connexion**, quelques secondes après l'arrivée
  en jeu, un message privé rappelle : « Faites /tuto pour découvrir les fonctionnalités du serveur ! »
  (`Tuto.JoinMessage`, `''` pour le retirer).
- Le nom RP est **le même que celui du MDC** : le changer dans le MDC le change dans le chat, et inversement. Il est gardé dans
  l'état du joueur côté serveur (`Player(source).state.rpName`) et **remis à zéro à chaque déconnexion**.
- `/me` : un joueur qui entre dans le rayon après coup ne voit pas les anciens messages ; un joueur qui en sort garde ceux déjà reçus.
- `/dv` supprime **un seul véhicule** : celui où se trouve le joueur, sinon **celui qu'il regarde**, sinon le **plus proche**,
  dans un rayon de **5 m** (`DvDistance`). Le serveur vérifie la distance et refuse un véhicule où se trouve **un autre
  joueur**. Permission ACE facultative (`Permissions.dv`). Si une autre ressource du serveur définit déjà `/dv`, retirez
  l'une des deux.
- `/info`, `/qst`, `/rep` restent dans le chat : les 50 derniers sont aussi envoyés aux joueurs qui se connectent
  (gardés en mémoire, perdus au redémarrage du serveur).
- Un texte sans `/` n'est pas envoyé : le chat rappelle la liste des commandes. Les autres commandes (`/mdc`, commandes
  d'autres ressources) sont exécutées normalement.
- 250 caractères max par message, 1 message par seconde max (`config.lua`).

### `/id` et `/idconfig` : fiche d'identité du MDC à l'écran

- **`/id`** : choisir (à la souris) une de vos **5 dernières identités enregistrées** dans le MDC (Créations >
  Identité) ; **`/id 1`** à **`/id 5`** : l'afficher directement ; **`/id off`** (ou « Masquer la fiche ») : la retirer.
- La fiche reste à l'écran (pense-bête RP) : **nom, prénom, middle name**, **DoB**, **adresse**, **téléphone**,
  **Driver License** (type et État / province, seulement si la personne en a un), **Canadian Citizen** (seulement
  pour un Canadien ; « US & Canadian Citizen » en double nationalité).
- **`/idconfig`** : la déplacer (glisser à la souris), l'agrandir / la réduire (molette, − / +), **Enregistrer**
  (gardé chez vous, même après une reconnexion), Par défaut, Annuler (Échap).
- Données lues dans le MDC (export `rp_mdc:getRecentIdentities`) ; utilisable sans nom RP.

### `/modiftouche` : changer les touches de nos scripts (sans le menu pause)

**`/modiftouche [script] [spécificité] [touche]`** — pour vous seulement, **gardé** (même après une reconnexion).
- `/modiftouche` seul : liste des scripts ; `/modiftouche MDC` : ses spécificités et leurs touches actuelles ;
- `/modiftouche MDC ouvrir F5` : le MDC s'ouvre avec **F5**, et l'ancienne touche (K) **ne fait plus rien** ;
- `/modiftouche MDC ouvrir defaut` : touche d'origine.
- **Suggestions en tapant** : `/modiftouche ` (avec l'espace) propose les **scripts** ; **Tab** (ou clic) complète, puis
  après l'espace suivant ce sont les **spécificités** de ce script, avec leur **touche actuelle** (« (perso) » si vous
  l'avez changée). Il ne reste qu'à taper la nouvelle touche.
- Touches : `A` à `Z`, `0` à `9`, `F1` à `F24`, `NUMPAD0` à `NUMPAD9`, et en français `ESPACE`, `ENTREE`, `MAJ`, `CTRL`,
  `ALT`, `VERRMAJ`, `TAB`, `HAUT`, `BAS`, `GAUCHE`, `DROITE`, `DEBUT`, `FIN`, `PAGEHAUT`, `PAGEBAS`, `INSER`, `SUPPR`,
  `CLICGAUCHE`, `CLICDROIT`, `CLICMOLETTE` (noms FiveM aussi acceptés : `LSHIFT`, `LCONTROL`, `LMENU`…). Majuscules
  et accents sans importance. Une touche déjà prise par une autre spécificité : avertissement.

Comment : FiveM ne laisse pas un script changer un raccourci. `/modiftouche` crée donc un **nouveau raccourci** sur la
touche choisie (visible dans Raccourcis clavier > FiveM : « Touche perso : … »), et l'**ancienne** touche est
neutralisée : chaque script charge `keyguard.lua` (même fichier partout, avant ses autres scripts), qui demande au chat
si sa commande peut partir. Une commande tapée dans le chat (`/mdc`, `/trafic`…) n'est jamais bloquée. Catalogue :
`touches.lua` (une ligne par touche à ajouter).

| Script | Spécificité | Action | Touche d'origine |
|---|---|---|---|
| **MDC** | `ouvrir` | Ouvrir le MDC | K |
| **MDC** | `accepter` | Accepter l'appel proposé | Y |
| **MDC** | `refuser` | Refuser l'appel proposé | N |
| **CHAT** | `ouvrir` | Ouvrir / fermer le chat | T |
| **CHAT** | `monter` | Remonter dans la conversation | PAGEUP |
| **CHAT** | `descendre` | Descendre dans la conversation | PAGEDOWN |
| **VEHICULE** | `moteur` | Allumer / couper le moteur | O |
| **VEHICULE** | `ceinture` | Attacher / détacher la ceinture | G |
| **VEHICULE** | `portiere` | Ouvrir / fermer sa portière | U |
| **VEHICULE** | `portieres` | Les deux portières avant (conducteur) | I |
| **VEHICULE** | `clignogauche` | Clignotant gauche | LEFT |
| **VEHICULE** | `clignodroit` | Clignotant droit | RIGHT |
| **VEHICULE** | `warnings` | Warnings (feux de détresse) | DOWN |
| **VEHICULE** | `rapport` | Marche avant (D) / arrière (R) | UP |
| **INTERACTION** | `menu` | Menu Interaction | F1 |
| **INTERACTION** | `oeil` | Œil (maintenir) | LMENU (maintenir) |
| **INTERACTION** | `lacherbras` | Police : lâcher le bras | X |
| **INTERACTION** | `debattre` | Civil : se débattre (tenu par le bras) | SPACE |
| **INTERACTION** | `mainsenlair` | Tips d'arrestation : mains en l'air | H |
| **INTERACTION** | `genoux` | Tips d'arrestation : à genoux | J |
| **INTERACTION** | `allonger` | Tips d'arrestation : s'allonger | L |
| **EQUIPEMENT** | `menu` | Menu Équipement du véhicule | E |
| **EQUIPEMENT** | `poser` | Poser au sol (plot, sac médical porté) | G |
| **EQUIPEMENT** | `radar` | Prendre / ranger le pistolet radar (à l'avant) | aucune |
| **FUSEE** | `poser` | Poser la fusée au sol | G |
| **PROJECTEUR** | `allumer` | Allumer / éteindre | LCONTROL (maintenir) |
| **PROJECTEUR** | `viser` | Viser (maintenir) | MOUSE_RIGHT (maintenir) |
| **ARMES** | `tir` | Coup par coup / automatique | B |
| **ARMES** | `stroboscope` | Stroboscope de la lampe | F7 |
| **TASER** | `securite` | Sélecteur ARMÉ / SÉCURITÉ | B (maintenir) |
| **TASER** | `alerte` | Alerte sonore et lampe stroboscopique | R (maintenir) |
| **TASER** | `test` | Sélecteur vers le bas (discret, test) | G (maintenir) |
| **BLOCNOTES** | `ouvrir` | Ouvrir / fermer | F2 |
| **TRAFIC** | `ouvrir` | Ouvrir la gestion du trafic | aucune |
| **SCENE** | `ouvrir` | Ouvrir /scene | aucune |
| **SCENE** | `oeildaigle` | Œil d'aigle (policiers) | CAPITAL |
| **SCENE** | `lacherarme` | Mode civil : lâcher son arme | G |
| **NUMEROS** | `afficher` | Afficher (maintenir) | HOME (maintenir) |
| **CARTES** | `miranda` | Carte Miranda | aucune |
| **CARTES** | `alphabet` | Alphabet phonétique | aucune |

## Réglages (par joueur)

Dans le MDC : onglet **Paramètres > Chat écrit et commandes**. Gardés chez chaque joueur (KVP `rpchat_settings`), même après une reconnexion :

- Teinte du fond (de noir à gris), opacité du fond, taille du texte, largeur et hauteur du chat ;
- Contour : affiché ou non, épaisseur (couleur automatique : blanc en mode jour, couleur du mode nuit en mode nuit) ;
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
| `ScrollUpKey`, `ScrollDownKey` | touches par défaut pour remonter / descendre dans le chat (`PAGEUP`, `PAGEDOWN`) |
| `MeDistance` | rayon des `/me` (50 m) |
| `MaxLength`, `Cooldown` | longueur max d'un message, délai entre deux messages |
| `NameMin`, `NameMax` | longueur du nom RP (2 à 40) |
| `GlobalHistory` | nombre de `/info`, `/qst`, `/rep` envoyés aux nouveaux connectés |
| `Permissions` | permission ACE facultative par commande, ex. `info = 'rpchat.info'` puis `add_ace group.admin rpchat.info allow` |
| `OverheadDuration`, `OverheadMaxLines` | durée d'un `/me` au-dessus d'une tête, nombre max par joueur |
| `OverheadScale`, `OverheadMinScale`, `OverheadMaxScale` | taille du `/me` au-dessus des têtes (à ~4 m), facteurs min (au loin) et max (tout près) |
| `PrivateLimit` | anti-spam des messages privés (`addPrivate`) : `SameText` (même texte, 20 s), `Max` par `Window` (4 par 10 s) |

Si vous renommez le dossier, mettez le nouveau nom dans `ChatResource` (`client/client.lua` du MDC).

## Compatibilité avec le chat d'origine

Les autres ressources peuvent continuer à utiliser `TriggerClientEvent('chat:addMessage', ...)`, `chatMessage`,
`chat:clear` ou `exports.chat:addMessage(...)` : leurs messages s'affichent dans ce chat. Les suggestions de commandes
du chat d'origine sont ignorées.

## Performance

- Aucune boucle côté client quand rien n'est affiché au-dessus des têtes (0.00 ms dans le resmon).
- `/me` au-dessus des têtes : une boucle de dessin tourne uniquement pendant qu'un `/me` est affiché (7 s environ), puis s'arrête.

## Export pour les autres ressources

`exports.rp_chat:sendMe(source, texte)` (serveur) : envoie un `/me` au nom du joueur, avec les mêmes règles (nom RP
obligatoire, rayon de 50 m). Utilisé par `rp_interact` pour les annonces RP (« fouille le coffre du véhicule »…).

`exports.rp_chat:addPrivate({ title, subject, text })` (client) : message **privé**, affiché uniquement chez ce joueur
avec l'étiquette `PRIVÉ` (résultats d'inspection / de fouille de `rp_interact`).
**Anti-spam** (`PrivateLimit` dans `config.lua`) : un même texte n'est pas répété avant `SameText` s (20), et au plus
`Max` messages privés (4) par `Window` s (10) ; le reste est ignoré. `Enabled = false` pour tout laisser passer.

Le chat publie son nom de ressource (`GlobalState.rpChatResource`) : le MDC et `rp_interact` le retrouvent même si le
dossier a été renommé.

## Commandes des autres ressources

Une ressource peut faire proposer ses commandes en tapant « / » (ex. `rp_teleport` : `/goto`, `/back`, `/blip`,
`/players`, `/bring` selon le rang du joueur) :

```lua
TriggerEvent('rp_chat:client:addCommands', GetCurrentResourceName(), {
    { name = 'goto', usage = '/goto [ID]', desc = 'Se téléporter à un joueur', noName = true },
})
```

La liste remplace la précédente de cette ressource ; `noName = true` : utilisable sans nom RP ; retirée quand la
ressource s'arrête. Les commandes du chat lui-même (`/me`, `/nomrp`…) ne peuvent pas être remplacées.
