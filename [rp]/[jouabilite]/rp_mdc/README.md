# MDC Standalone (FiveM)

Mobile Data Computer **100% standalone** (sans ESX / QBCore / vRP), interface NUI en HTML/CSS/Vanilla JS, au look
**Windows 11** clair (jour) et sobre (fenêtre « Mica » claire aux coins presque carrés, volet de navigation à gauche,
cartes blanches, boutons et champs Fluent, accent bleu). Les couleurs se changent dans les variables en haut de
`html/style.css` (`--accent`, `--mica`, `--radius`…). Les autres menus (`rp_interact`, `rp_RoleplayZone`,
`rp_equipment`, `rp_TrafficControl`, `rp_Ganghunt`, `/tuto` de `rp_chat`) reprennent ce thème.

**Trois MDC**, choisis à la première ouverture : **Générique** (rôleplay civil), **Washington State Patrol** (WSP) et
**King County Sheriff Office** (KCSO). Même apparence pour les trois : seuls le titre (à côté de « Mobile Data
Computer ») et le contenu changent. Il n'y a plus de services APD / GSP / FCSO. Le **logo** de la barre de titre est
celui de la police choisie (**badge WSP** ou **étoile KCSO**, `html/img/`, fond transparent) ; bouclier pour le MDC
Générique. Les deux logos sont aussi sur l'écran de choix du MDC.

## Installation

Toutes les ressources sont rangées côte à côte dans le dossier **`[rp]`** (le MDC dans `rp_mdc`, chaque autre
script dans son propre dossier à côté, jamais à l'intérieur du MDC) :

```
[rp]/
├── rp_mdc/              MDC (ce dossier)
├── rp_vehiclecontrol/   véhicules : essence, dégâts, ceinture, car HUD…
├── rp_chat/             chat écrit RP
├── rp_interact/         menu d'interactions, fiches civiles, Eye Target
├── rp_equipment/        équipements / armurerie
├── rp_camshake/         tremblement de caméra
├── rp_NPCcontrol/       PNJ, services d'urgence, densité
├── rp_flares/           fusées de détresse
├── rp_doorlock/         portes verrouillées (civils), frapper, enfoncer (tout le monde)
├── rp_revive/           réanimation sur place ou à l'hôpital, corps laissé sur place
├── rp_weaponscontrol/   recul, effets au tir, acouphènes, flash et fumée du canon
├── rp_vehicleprops/     objets collés sur les véhicules (œil)
├── rp_taser10/          TASER 10 (sondes, fils, laser, lampe ; œil)
├── ox_target/           pont : les scripts qui exigent ox_target utilisent l'œil (herses de riven_spikes)
├── rp_TrafficControl/   gestion du trafic
├── rp_RoleplayZone/     scènes de roleplay
└── rp_Ganghunt/         vagues d'ennemis (/ganghunt)
```

Facultatif : **Riven Impact Dynamics** (script payant, installé à part dans `[rp]/riven-impact-dynamics/`, jamais
dans ce dépôt) ; `rp_vehiclecontrol` lui laisse alors les accidents et la ceinture, et ses **voyants de dégâts
s'affichent juste au-dessus du car HUD** (même place, même taille, affichés avec lui ; voir le README de
`rp_vehiclecontrol`), et son **frein de parking** serré affiche un **(P) rouge** sur le car HUD.
Facultatif aussi : **riven_spikes** (herses, script payant de Riven, jamais dans ce dépôt) : il exige `ox_lib` (gratuit,
à installer) et `ox_target`, remplacé ici par le **pont [`ox_target/`](../ox_target/README.md)** branché sur l'œil.

1. Copiez le dossier **`[rp]`** tel quel dans `resources/` (FiveM trouve les ressources dans les dossiers entre
   crochets, même imbriqués). Il est rangé en trois dossiers :
   - **`[jouabilite]`** : ox_target (pont), rp_adrenaline, rp_chat, rp_doorlock, rp_interact, rp_mdc, rp_notepad,
     rp_overheadids, rp_policecards, rp_spotlight, rp_revive, rp_RoleplayZone, rp_stamina, rp_taser10, rp_teleport, rp_TrafficControl,
     rp_vehiclecontrol, rp_vehicleprops, rp_viser, rp_weaponscontrol ;
   - **`[autres]`** : rp_Ganghunt, rp_permissions ;
   - **`[ambiance-fonctionnement]`** : rp_camshake, rp_equipment, rp_flares, rp_freecam, rp_holster, rp_NPCcontrol.
   Les noms des ressources ne changent pas : les lignes `ensure` ci-dessous marchent telles quelles (l'ordre compte,
   c'est pourquoi elles sont listées une par une plutôt qu'avec `ensure [jouabilite]`).
2. Dans `server.cfg`, démarrez celles que vous voulez, **rp_permissions** (rôles Discord, voir
   [son README](../../%5Bautres%5D/rp_permissions/README.md) : token du bot en convar, permissions.cfg) puis le MDC en premier :
   ```
   set rp_discord_token "TOKEN_DU_BOT"   # jamais dans un fichier du dépôt
   exec @vMenu/config/permissions.cfg
   ensure rp_permissions
   ensure rp_chat
   ensure rp_mdc
   # ensure riven-impact-dynamics   (facultatif, script payant : AVANT rp_vehiclecontrol)
   ensure rp_vehiclecontrol
   ensure rp_interact
   # ensure olisound              (facultatif, plus nécessaire : rp_interact fait le son 3D de la radio)
   ensure ox_target                 # le pont vers l'œil (PAS le vrai ox_target), après rp_interact
   # ensure ox_lib                  (facultatif : seulement pour riven_spikes)
   # ensure riven_spikes            (facultatif, script payant : après ox_lib et ox_target)
   ensure rp_equipment
   ensure rp_camshake
   ensure rp_NPCcontrol
   ensure rp_flares
   ensure rp_doorlock
   ensure rp_revive
   ensure rp_weaponscontrol
   ensure rp_adrenaline             # ragdolls et arme lâchée quand on est touché
   ensure rp_viser                  # /viser : visée maintenue ou bascule
   ensure rp_teleport               # téléportations (Menu Interaction > Joueurs, commandes)
   ensure rp_stamina                # endurance de sprint selon les armes portées
   ensure rp_holster                # holsters EUP pleins / vides selon l'arme de poing
   ensure rp_freecam                # /freecam : mode photo (caméra libre, minimap / HUD masqués, zoom)
   ensure rp_notepad                # /notepad (F2) : bloc-notes ; retranscrit dans la note de l'unité du MDC
   ensure rp_policecards            # /miranda, /alphabet : cartes aide-mémoire (Menu Interaction > Police)
   ensure rp_spotlight              # projecteurs de portière par véhicule (remplace px_spotlight)
   ensure rp_vehicleprops
   ensure rp_taser10
   ensure rp_TrafficControl
   ensure rp_RoleplayZone
   ensure rp_Ganghunt
   ensure rp_overheadids            # noms RP et numéros des joueurs au-dessus des têtes (touche maintenue)
   ```
   Le MDC publie son nom de ressource (`GlobalState.mdcResource`) : son dossier peut être renommé.
3. En jeu : touche **K** (modifiable dans *Paramètres > Raccourcis clavier > FiveM*) ou `/mdc`. **Échap** pour fermer.

Le dépôt contient aussi le **menu d'interactions (au clavier) / fiches civiles / Eye Target** dans [`rp_interact/`](../rp_interact/README.md)
(ressource séparée : un joueur y est « policier » quand il est dans une unité du MDC, voir l'export serveur
`getPlayerUnit(source)` et l'état `Player(source).state.mdcUnit`). Le MDC choisi est publié aussi : états
`mdcAgency` (`wsp`, `kcso`, …) et `mdcPolice` (`true` pour un MDC de police) ; rp_interact s'en sert pour retirer le
mode civil quand on rejoint le MDC WSP ou KCSO. Le MDC publie son nom de ressource
(`GlobalState.mdcResource`) : le nom de son dossier n'a pas d'importance.

Le dépôt contient aussi **Vehicle Control** dans [`rp_vehiclecontrol/`](../rp_vehiclecontrol/README.md) : essence (plein à
la pompe avec un vrai pistolet, jerrican), dégâts réalistes, ceinture, moteur toujours allumé, portières depuis l'intérieur, clignotants et poussée ; il
alimente le car HUD du MDC.

Le dépôt contient aussi le **chat écrit RP** dans le dossier [`rp_chat/`](../rp_chat/README.md) : c'est une ressource
séparée, à copier à part dans `resources/` (voir son README). Elle partage le nom RP avec le MDC et ses réglages
se font dans l'onglet « Paramètres » du MDC. Le MDC fonctionne aussi sans elle.

Et **RP CamShake** dans [`rp_camshake/`](../../%5Bambiance-fonctionnement%5D/rp_camshake/README.md) : petit script indépendant de tremblement de la caméra
(marche, course, sprint, chocs, accidents).

Et **RP NPC Control** dans [`rp_NPCcontrol/`](../../%5Bambiance-fonctionnement%5D/rp_NPCcontrol/README.md) : plus de police / pompiers / ambulanciers du
jeu (ni leurs véhicules), plus d'indice de recherche, PNJ qui ignorent les joueurs, densité du trafic et des piétons
de 0.0 à 3.0.

Et **RP Flares** dans [`rp_flares/`](../../%5Bambiance-fonctionnement%5D/rp_flares/README.md) : fusées de détresse posées au sol (touche G, fusée en main),
retirées avec l'œil, lumière rouge renforcée la nuit.

Et **RP Doorlock** dans [`rp_doorlock/`](../rp_doorlock/README.md) : avec l'œil, les joueurs **verrouillent /
déverrouillent** les portes du jeu (porte double en entier, gardé après un redémarrage), **frappent** à une porte, et
les policiers en service **enfoncent** une porte verrouillée à coups de pied.

Et **RP VehicleProps** dans [`rp_vehicleprops/`](../rp_vehicleprops/README.md) : avec l'œil sur un véhicule, **ajouter,
déplacer ou retirer des objets collés** dessus (sac, arme, radio, carton…), vus par tous les joueurs.

Et le **TASER 10** dans [`rp_taser10/`](../rp_taser10/README.md) : script de Cartoon adapté sans `ox_target` (retirer
les sondes et recharger avec l'œil).

Et **RP TrafficControl** dans [`rp_TrafficControl/`](../rp_TrafficControl/README.md) : gestion du trafic **sans supprimer
de véhicules**, sur un tronçon précis (**une voie**, **un sens** ou **la route entière**) : fermeture (nœuds du jeu
fermés, PNJ rabattus sur une voie du même sens ou demi-tour), ralentissement et arrêt du trafic, posés en visant la
route (`/trafic`, policiers en service).

Et **RP RoleplayZone** dans [`rp_RoleplayZone/`](../rp_RoleplayZone/README.md) : scènes préparées par les civils
(`/scene`, vue du jeu ou caméra libre) : **zone de recherche** (cercle de 15 à 60 m, description affichée aux policiers
qui y entrent, son d'intrigue, cercle sur la carte), **périmètre à fouiller** et **objet ou véhicule à fouiller**
(fouillés avec l'œil, contenu trouvé à la fouille, description visuelle affichée au-dessus à 10 m), **arme jetée ou posée** au sol par les civils (G, arme en main ; ramassée à l'œil), et l'**œil d'aigle** des policiers (Verr. Maj : onde radar de 15 m,
contours blancs, zone proche pointée). Rien ne disparaît autour des scènes (protégées des « ClearArea »).

Et **RP Ganghunt** dans [`rp_Ganghunt/`](../../%5Bautres%5D/rp_Ganghunt/README.md) : `/ganghunt`, n'importe quel joueur fait venir des
**vagues d'ennemis** (1 à 10 vagues de 1 à 30) qui le traquent et le **cherchent** quand ils le perdent de vue, comme
la police du jeu (gangs, organisations ou forces de l'ordre) : armes réparties en pourcentages ou aléatoires (armes
spéciales comprises), convoi de véhicules et hélicoptère de la faction, silencieux, grenades, musique de poursuite du
jeu, HUD en haut de l'écran. Volontairement absent du MDC et du `/tuto`.

## Trois MDC (choisis à l'ouverture)

À la **première ouverture** du MDC, une fenêtre demande lequel utiliser. Ce choix est **oublié à chaque connexion et
à chaque redémarrage du serveur** (il est redemandé). On en change à tout moment, **tout en haut des Paramètres**
(« MDC utilisé » : un clic choisit, un deuxième clic confirme ; changer de police fait quitter son unité).

| MDC | Pages | Pour qui |
|---|---|---|
| **Générique** | Interventions, Créations, Rapports, Paramètres | rôleplay civil : voir **tous** les appels (sans les rejoindre), **modifier directement** les appels (interventions) depuis la page Interventions, créer identités, véhicules et appels |
| **Washington State Patrol** | Unités, Interventions, Recherches, Rapports, Paramètres | policiers WSP : **membres recrutés et admins** seulement (carte grisée pour les autres) |
| **King County Sheriff Office** | Unités, Interventions, Recherches, Rapports, Paramètres | policiers KCSO |

Les deux MDC de police sont **séparés mais liés** : chacun a **ses unités, ses appels et ses recherches** ; les **BOLOs sont communs** ;
un appel peut viser **les deux polices** (appel commun, visible et rejoignable par les deux) ; les **Rapports sont
communs** à tous les MDC. Côté serveur : export `getPlayerAgency(source)` (`'generic'`, `'wsp'`, `'kcso'` ou nil) et
`getPlayerUnit(source)` qui donne aussi `agency`, `agencyLabel`, `agencyShort`. Polices et libellés : `Config.Agencies`
dans `server/server.lua`.

## Fenêtre

- Barre de titre Windows 11 : logo de la police (ou bouclier), « Mobile Data Computer » et le **nom du MDC choisi**, boutons réduire /
  agrandir / fermer. Déplacement : glisser la barre de titre ; redimensionnement : bords et coins ; agrandir /
  rétrécir : bouton ☐ ou double-clic sur la barre de titre ; ↺ : position par défaut.
- La position est gardée d'une ouverture à l'autre et réinitialisée à chaque reconnexion.

## Disposition de la fenêtre

- **Thème de jour** (couleurs du logo du serveur : noir, blanc, rouge entre Torino et bordeaux) : fond **gris doux**
  (pas de blanc éclatant), cartes gris clair, texte foncé, **barre de titre noire soulignée de rouge**, accent **rouge
  foncé** (boutons principaux, page choisie, focus). Les HUD affichés sur le jeu (PLD, display MDC, car HUD) et les
  notifications restent sombres, aux couleurs du logo (jauges blanches : le rouge et l'orange restent des alertes).
- **Menus des autres scripts** (œil, Menu Interaction, `/eup`, fiche civile, `/scene`, coffre / équipement, trafic,
  Ganghunt, chat, `/tuto`, portes, fiche du véhicule…) : **toujours sombres**. De jour : **noir avec touches de rouge
  foncé** (bandeaux, sélection, boutons), textes clairs ; de nuit : la couleur du mode nuit du MDC, même côté sombre.
  Jamais de texte foncé sur fond sombre.
- **Volet de navigation à gauche** : en haut, le **nom RP** (sans image de profil) et le MDC utilisé ; les **pages** du MDC ; pour les
  polices, juste en dessous des pages, les **4 statuts listés l'un sous l'autre** : chaque bouton est **entièrement
  de la couleur de son statut**, celui de l'unité est mis en avant (opaque, cerclé, ✓) ; puis les **BOLO actifs**
  (cases repliées : un clic affiche les détails, **Voir BOLO** ouvre la page des BOLOs sur celui-ci) ; tout en bas,
  **Paramètres**.
- **Au centre** : le **titre de la page** et son sous-titre, puis le contenu, en cartes.
- **Note de l'unité** (polices) : bouton **en haut à droite** de la fenêtre (barre de titre, un point bleu quand une
  note existe) : il ouvre / ferme un **panneau à droite** avec la note propre à l'unité (2000 caractères, plusieurs
  lignes, partagée par ses membres, enregistrée pendant la frappe ; gardée dans l'unité côté serveur). Panneau ouvert
  ou fermé : gardé chez le joueur. Bouton **« Retranscription du notepad »** : ajoute à la fin de la note le texte de
  votre bloc-notes (`rp_notepad`, `/notepad`), page par page.
- **Messagerie entre unités** (polices) : bouton **Messages** juste à côté de la note de l'unité (pastille rouge : nombre
  de messages non lus). Il ouvre un **panneau à droite** : la liste des **autres unités** de police (WSP et KCSO ; les
  conversations récentes d'abord, avec le dernier message et ses non-lus), puis la **conversation** avec l'unité
  choisie. Messages **uniquement d'unité à unité** (il faut être dans une unité ; jamais à sa propre unité ; pas de
  messages privés entre joueurs) : chaque membre des deux unités voit la conversation (auteur = nom RP), « lu » pour
  toute l'unité dès qu'un membre l'ouvre. **Entrée** envoie, **Maj + Entrée** va à la ligne (300 caractères,
  `UnitMessageLength`). Nouveau message reçu, MDC ouvert ou non : **notification avec un son** (se désactive :
  *Paramètres > MDC > Notifications et sons*, « Messages entre unités »). Gardés en mémoire côté serveur
  (`MaxUnitMessages` = 60 derniers par conversation ; supprimés avec l'unité, perdus au redémarrage). Anti-spam :
  `UnitMessageCooldown` (800 ms). Ces trois réglages sont en haut de `server/server.lua`.
- **En bas** : la disponibilité et l'heure du jeu.

La fenêtre est **légèrement transparente** (opacité **97 %** par défaut, de 50 à 100 %, *Paramètres > MDC*). Il n'y a
plus de flou de l'arrière-plan.

### Mode nuit (*Paramètres > MDC > Apparence*)

- **Apparence** : **Jour** (gris doux et rouge du logo, par défaut) ou **Nuit** : **fond noir**, couleurs sombres (textes et accents
  foncés, rien d'éblouissant), tout dans **une seule couleur**
  au choix (**Couleur du mode nuit** : **vert** par défaut, **jaune**, **rouge** ou **bleu**). Les écarts de couleur
  du mode jour deviennent des écarts de contraste et d'intensité de cette couleur : **titres plus foncés**, **texte
  plus clair**, zones, boutons, pastilles (polices, tags d'unité, priorités des appels, BOLO, alertes) plus ou moins
  vifs, logos WSP / KCSO teintés. Les quatre couleurs ont exactement les mêmes contrastes. **Seuls les statuts des unités** (Disponible, En route, Sur place, Indisponible) **gardent leurs
  couleurs**. Les HUD (PLD, display, car HUD) et les notifications prennent aussi cette couleur ; les alertes du car
  HUD se lisent alors à l'intensité de la couleur et au clignotement.
- **Le mode nuit s'applique à** : **toutes les interfaces** (MDC, HUD, PLD et menus, par défaut), **seulement le MDC**
  (la fenêtre du MDC uniquement : HUD, PLD, car HUD et notifications gardent leur thème habituel), ou **seulement les
  menus extérieurs** (pas la fenêtre du MDC) : HUD (PLD, display, car HUD) et notifications du MDC, Menu Interaction
  et `/eup`, fiche civile, œil, `/scene`, équipement du véhicule, gestion du trafic, Ganghunt, page `/tuto`, barre pour
  enfoncer une porte, message « pousser ». Le **contour du chat écrit** n'est plus réglable en couleur : **blanc** en
  mode jour, **couleur du mode nuit** (vert, jaune, rouge ou bleu) quand le mode nuit s'applique aux menus ; le chat
  garde son fond et les couleurs des commandes.
- Gardé chez le joueur, comme les autres réglages. Pour les développeurs : exports client `uiTheme()` ('night' ou
  'day', pour les menus extérieurs) et `uiNightColor()` ('green', 'yellow', 'red', 'blue'), événement client
  `mdc:uiTheme` (theme, color) à chaque changement ; chaque ressource les envoie à son NUI (`client/theme.lua`), qui
  pose toujours `data-theme="night"` (structure sombre) et `data-night-color` sur la page : la couleur du mode nuit, ou
  `logo` de jour (dans le MDC : `data-theme` sur la fenêtre `#mdc` ; la couche des HUD `#hudLayer` est toujours sombre,
  `data-night-color` = couleur du mode nuit ou `logo` ; jamais `color-scheme` sur la racine ; jamais de `color-mix()`,
  inconnu du navigateur du jeu). Couleurs : variables `--n-*` du bloc « Couleurs des interfaces sombres » de chaque
  `style.css` (vert, jaune, rouge, bleu, logo).

- **NOM RP** : il s'affiche en haut à gauche et dans les unités (le pseudo Steam/FiveM n'est jamais affiché). **Obligatoire pour
  rejoindre une unité.** Il est partagé avec le chat écrit : `/nomrp John Carter` dans le chat change aussi celui du MDC, et
  inversement. Il n'est enregistré nulle part : il est remis à zéro à chaque déconnexion (état `rpName` du joueur côté serveur).
- **Statut de l'unité** : Disponible (vert), En route (jaune), Sur place (orange), Indisponible (rouge). Le statut est celui de l'unité rejointe.

## Onglets

| Onglet | Rôle |
|---|---|
| Unités | (polices) Une liste : les unités **de votre police** seulement. Bouton **Créer une unité** (nom, **tag** au menu déroulant : Aucun, **SUP.** (superviseur) ou **Autre** à saisir, couleur) ; l'unité appartient à la police du MDC (pastille **WSP** bleue / **KCSO** verte). Chacun peut rejoindre une unité de sa police (4 joueurs max par unité) ; **une seule unité à la fois** : dans une unité, le bouton « Rejoindre » des autres disparaît, il faut d'abord **quitter** la sienne (le serveur refuse aussi). **Modifier** et **Supprimer** : réservés aux **membres** de l'unité. Les membres d'une unité partagent leurs recherches et leurs rapports (voir plus bas) |
| Interventions | **Police** : les appels de **sa police** (toujours ouverts), puis les **appels communs** (WSP & KCSO) ; les appels de l'autre police ne sont **pas** visibles. Seules les polices visées peuvent rejoindre un appel (vérifié par le serveur). Incident : police de l'unité déclarante toujours cochée, **case** pour y ajouter l'autre police (incident commun). **Générique** : les listes de **chaque police** et les appels communs, **en lecture** (pas de « Rejoindre ») ; bouton **Modifier** sur les **interventions** (appels des civils) pour les corriger directement. Interventions (civils) et incidents (unités) : titre, priorité, adresse, bloc ; chaque ligne est surlignée de la couleur de sa priorité. N° d'incident `XX-XXXX`. Cliquer pour afficher le détail, recliquer (ou **✕** en haut du panneau) pour le masquer : **sans appel choisi, le panneau des détails est réduit à une fine colonne** et la liste prend toute la place. Rejoindre / quitter l'appel (unités uniquement), notes en majuscules modifiables, « Intervention terminée » (grisée dans la liste). Les rapports liés apparaissent avec les notes (ouvrir / modifier) et un rapport peut être rédigé directement depuis l'intervention. **Personnes et véhicules** : les unités sur l'appel y ajoutent les fiches de l'historique des recherches (bouton « Fiche » pour la consulter). Bouton **Nouvel incident** pour les unités ; à côté, bouton **orange foncé « Demande de renforts »** : intitulé, description et localisation complète (route, croisement, **secteur** — prérempli avec celui du Menu Interaction —, bloc ; bouton « Position actuelle ») ; il crée un **incident commun aux deux polices** (étiquette « Renforts », notification « DEMANDE DE RENFORTS » chez toutes leurs unités), l'unité qui demande est placée dessus |
| Interventions : priorités, renforts, clôture | Voir « Priorités de réponse, renforts et clôture des appels » ci-dessous |
| Recherches | (polices) Identité : nom de famille\* + date de naissance\*, prénom et SSN facultatifs. Véhicule : immatriculation ou VIN. Historique : les nouveaux résultats s'ajoutent en haut, les précédents restent en dessous. En haut à droite : boutons **Sex Offenders** et **Kidnapping Offenders** (registre des délinquants, **même liste pour la WSP et le KCSO** : voir « Casier judiciaire et registre ») et **BOLOs** (voir plus bas). Résultat d'une personne inscrite : étiquettes **SO** / **KO** |
| Rapports | **Communs à tous les MDC**. Formulaires de l'**État de Washington** : Notice of Infraction (NOI), Criminal Citation and Notice to Appear, Written Warning, Arrest Report, DUI Arrest Report, Police Traffic Collision Report (PTCR), Incident Report, Vehicle Impound / Inventory Report. Infractions choisies dans le **catalogue RCW** (classification + infraction liées, pénalité automatique). Les anciens modèles (DOT-523, Citation, Traffic Citation, Convocation, Warning, Ticket) restent lisibles. Chaque rapport est lié à une intervention / un incident (en cours ou terminé). Liste filtrable (type, texte, mes rapports), lecture, modification par l'auteur. Permanents |
| Paramètres | Tout en haut, **MDC utilisé** (changer de MDC). Puis trois catégories repliables, toutes fermées à l'ouverture : **MDC** (taille de l'interface, **apparence jour / nuit**, couleur du mode nuit et où il s'applique, transparence de la fenêtre, onglet à l'ouverture, fenêtre, notifications, son et son volume de 0 à 100 %), **HUD & Display** (PLD, display MDC et car HUD : taille et position seulement, tous leurs éléments sont toujours affichés ; volume des sons du véhicule ; le Menu Interaction de `rp_interact` n'est plus réglable : il est toujours en haut à gauche, comme les menus du jeu) et **Chat écrit et commandes** (apparence du chat, affichage des /me, liste des commandes ; ressource `rp_chat`). Gardés chez le joueur, même après une reconnexion |
| Créations | MDC **Générique** : identité, véhicule, intervention (requérant, téléphone généré, **polices** en **cases à cocher** (WSP, KCSO : une case = appel de cette police ; les deux = appel commun) **puis la priorité** de cette police (voir plus bas), **nombre idéal d'unités** (1 à 4), adresse, croisement, bloc, description ; bouton « Position actuelle »). Bouton **Mes créations** : vos identités et véhicules, modifiables. En dessous, pour une identité **déjà créée** : **Casier judiciaire** et **Registre Sex / Kidnapping Offender** (voir « Casier judiciaire et registre ») |

Unités, interventions et incidents sont gardés en mémoire : ils disparaissent au redémarrage du serveur.

### BOLOs (Recherches → bouton « BOLOs »)

Page des **BOLOs actifs** (n°, type, motif, résumé ; filtre Individus / Véhicules), mise à jour en direct.
**Ajouter un BOLO** : on choisit d'abord **Individu** ou **Véhicule**.

- **Individu** : motif\*, identité facultative (choisie dans l'historique des recherches), description
  (cheveux ☐ → couleur, pilosité faciale ☐ → type + couleur, couleur de peau, origine (**une seule**) : Inconnue / Nord-Américain / Européen /
  Hispanique / Afro-américain / Asiatique / Natif / Moyen-Orient, tatouages ☐ → détails, taille en cm,
  tenue vestimentaire), lieu, détails (narratif) et **Ajouter un véhicule** (5 max) : immatriculation
  facultative (partielle possible, `*` = caractère inconnu) ou véhicule de l'historique ; une immatriculation
  enregistrée remplit automatiquement marque, modèle et couleur. Type : Compact, Sedan, SUV, Coupé, Break,
  Muscle, Sport, Pick-up, Van, Moto, Camion, Autre.
- **Véhicule** : motif\*, immatriculation **incomplète** (ex. `AB*12`), marque, modèle, couleur, type, détails.
  Une immatriculation complète est refusée : c'est son propriétaire qui est recherché (bouton
  « Créer un BOLO Individu avec ce véhicule », propriétaire présélectionné).

Une description non cochée ou non renseignée est affichée **Inconnue**. Cliquer sur un BOLO affiche ses détails,
avec **Modifier** (puis Enregistrer) et **Supprimer** (deux clics). Les **BOLOs sont communs aux deux polices** (WSP et KCSO), sans
rien à choisir : tout BOLO créé par une police est vu, modifié et supprimé par les agents des deux (la pastille de la
police qui l'a émis est affichée à côté de son numéro), et ses alertes apparaissent dans les Recherches des deux MDC. Dans les Recherches, une fiche visée par un BOLO affiche une alerte (et l'étiquette `BOLO`
dans les résultats) ; une immatriculation correspondant à un BOLO véhicule partiel affiche « Correspondance possible ».

### Unité : espace partagé

Les membres d'une même unité (4 au maximum) partagent en direct :
- les **recherches** : chacun voit l'autre écrire, voit le résultat s'afficher, et l'historique est commun ;
- le **rapport en cours de rédaction** : chacun voit l'autre écrire et peut compléter ; n'importe quel membre peut
  l'enregistrer (une modification de rapport est ouverte par son auteur, puis enregistrable par l'unité) ;
- les **changements de statut** (notification chez chaque membre).

### HUD et notifications

Affichages séparés, visibles même MDC fermé. Le **PLD** et le **car HUD** n'ont **ni fond ni contour** (lisibles sur
le jeu par l'ombre du texte) ; le display MDC et les notifications sont des cartes sombres. Couleurs : de jour celles
du logo (blanc, rouge), de nuit la couleur du mode nuit. **Tous leurs éléments sont toujours affichés** : dans
« Paramètres > HUD & Display », on règle seulement leur **taille** et leur **position** (« Placer les HUD à l'écran »).

- **PLD** (Player Localisation Display), **affiché pour chaque joueur dès sa connexion**, sans utiliser le MDC
  (ni nom RP, ni unité) ; taille et position propres à chaque joueur (`PldForEveryone` dans `client/hud.lua` pour le
  réserver aux joueurs ayant accès au MDC). Composition : à gauche le **cap** (petite flèche rouge tournée vers la
  direction, puis la lettre en gros : N / NE / E / SE / S / SW / W / NW), un **trait rouge**, puis la **rue** en gros,
  la **zone géographique** en petites capitales rouges (ex. Cypress Flats ; absente : rien), et une ligne
  « **× croisement le plus proche** (italique, toujours présent : largeur stable) · **BLOC** n° (celui où se trouve le
  joueur, sinon le plus proche) · **🕘 heure du jeu** ».
  **Priorité au PLD, au car HUD et au display MDC** : tant que le PLD est affiché, les textes du jeu qui s'y
  superposent (nom de la rue, de la zone, du véhicule et sa classe) sont masqués (`HideGameHud` dans
  `client/hud.lua`). Les scripts de HUD concurrents listés dans `ConflictingHuds` (`server/server.lua` : street
  labels, compteurs de vitesse, boussoles…) sont **arrêtés** au démarrage du MDC ou dès qu'ils démarrent (sauf si une
  autre ressource en dépend : message dans la console) ; ajoutez-y le dossier de tout autre script de ce genre
  (`StopConflictingHuds = false` pour ne rien arrêter). Pour que les HUD du MDC passent aussi **au-dessus** de
  l'interface d'un autre script, démarrez `rp_mdc` **après** lui dans `server.cfg` (la dernière interface
  chargée s'affiche au-dessus).
  **Noms des rues, quartiers et villes : État de Washington (King County)**, **uniquement** ceux de
  **`config/washington.json`** (liste complète et lisible : **`config/WASHINGTON_CARTE.md`**) : `streets` (nom du jeu ->
  nom affiché : **I-5** (autoroutes de la ville), **I-90** (Great Ocean Hwy), **I-405** (Palomino Fwy), **US-2** (Senora
  Fwy), **US-12** (Route 68), routes de l'État (SR 169, SR 18, SR 203, SR 516, SR 522, SR 202) et routes du comté),
  `zones` (les 90 zones du jeu : quartiers de Seattle et de Bellevue, villes sous contrat, zones géographiques ; aussi
  renommées sur la carte du menu pause), `municipalities` (ville affichée et police compétente : Seattle PD, Bellevue
  PD, KCSO Précinct 2 / 3). Les rues des villes absentes de `streets` gardent leur nom du jeu. Utilisés par le PLD,
  le bouton « Position actuelle » et les exports `GetStreetName`, `GetDistrictName`, `GetLocationText`,
  `RenameStreet`, `GetJurisdiction` (police compétente et municipalité). Commande **`/mdc_streets`** (F8) : noms à votre
  position (et ceux du jeu), pour vérifier.
  Les blocs se dessinent dans **`config/blocs.json`** (vide au départ, modèles dans `exemples`) : bloc **point** (une
  coordonnée, rayon facultatif) ou **carré** (4 coins, pour une grande zone sous un seul bloc), et toujours cercles,
  rectangles, polygones, filtre par rue (nom **affiché**, ex. « I-90 ») : voir `config/LISEZMOI.txt` ; la commande
  `/mdc_pos` (console F8) donne la ligne à copier.
  **`/blocs` (admins : `Config.BlockEditorAce` = `rp.admin`, ACE ou rang Discord, ou l'ACE `command`)** : éditeur de blocs. Panneau à droite : **Point** (rayon)
  ou **Carré** (largeur, hauteur, rotation), nom du bloc ; le bloc se dessine **en jeu** (jaune) et **sur la carte**
  (rayon / zone), au centre du joueur (« Suivre ma position ») ou figé (« Fixer ici »). « **Ajouter le bloc** » : il
  passe en vert et sa ligne rejoint la liste (✕ pour la retirer) ; « **Copier tout** » : les lignes à coller dans
  `"blocks"` de `config/blocs.json`. « Se déplacer » rend la souris (le panneau reste), `/blocs` la reprend. Rien
  n'est écrit sur le serveur ; redémarrer `rp_mdc` après avoir collé les lignes.
- **Display MDC** : affiché seulement dans une unité : « **[N° d'unité] • [POLICE]** » (ex. `417 • WSP`, pastille
  WSP bleue / KCSO verte) suivi du tag spécial (ex. SUP.), statut, n° d'incident (uniquement quand l'unité est sur un
  appel) et **secteur** (zone de jeu) choisi dans le Menu Interaction (`rp_interact`, Police > Display MDC) : « aucun
  sélectionné » tant que rien n'est choisi.
- **Car HUD**, à bord d'un véhicule, **au-dessus de la minimap**, sans fond : **toujours affiché pour le conducteur**,
  **grisé moteur coupé** (sauf le frein de parking) et qui **s'illumine au démarrage** ; seulement le voyant de la
  ceinture pour les passagers. Composition :
  - à gauche, la **vitesse** en gros chiffres, **MPH** dessous ;
  - au centre, en haut, les **voyants** : **ceinture** (blanche attachée ; **rouge** détachée, clignote en roulant),
    **frein de parking** de Riven (**(P) rouge** tant qu'il est serré), **moteur** (sans Riven : **orange** très abîmé
    — il roule lentement, cale, fume — **rouge** détruit) ; dessous, le **compte-tours** : **une seule barre, fine**,
    blanche, puis la **zone rouge** au bout (le dernier cinquième environ), séparées par un simple trait, puis la **jauge d'essence graduée en quarts** avec sa pompe (orange : réserve
    sous 15 %, rouge : sous 5 %) ;
  - à droite, le **rapport** dans un cadre : **D**, ou **R** sur fond ambre en marche arrière (touche **↑**).
  Véhicule hors d'usage (moteur détruit) : vitesse, compte-tours et essence **clignotent en rouge**, voyant moteur
  rouge fixe. En montant côté conducteur, une **notification glisse depuis la gauche juste au-dessus du car HUD** et
  présente la touche du moteur (**O**) ; elle disparaît après 8 secondes. Volume des sons du véhicule dans
  « Paramètres ».
  Les données (essence, dégâts, ceinture, moteur) viennent de **Vehicle Control**
  ([`rp_vehiclecontrol/`](../rp_vehiclecontrol/README.md)) : sans cette ressource, le car HUD n'apparaît pas
  (`client/carhud.lua` ne fait que relayer ses données au NUI, sans boucle).
- **Minimap** (non réglable) : **masquée à pied** (le GPS avec) et **affichée dès que le joueur monte dans un
  véhicule** ; à pied, elle reste masquée même si un autre script la réaffiche (en véhicule, un script qui la masque un
  moment, photo ou cinématique, est respecté). En véhicule, un **contour noir** l'entoure, avec une **ombre noir nacré rouge** (reflet rouge discret mais visible)
  (trait à l'extérieur, jamais sur la carte). Il n'est pas posé « au hasard » : sa place est **calculée comme le jeu
  place la minimap** (zone de sécurité de l'affichage du joueur, format et résolution de l'écran, écran du milieu en
  triple écran) et recalculée dès que l'un d'eux change ; masqué dans le menu pause et avec la grande carte. Si chez un
  joueur il est décalé de quelques pixels, *Paramètres > HUD & Display > Minimap — contour* : décalage horizontal /
  vertical, largeur, hauteur (± 30 px, gardés sur son PC). Une boucle lente (250 ms, ~0.00ms) dans `client/hud.lua`.
- **Notifications** (en haut à droite) : toutes les notifications du MDC, et, même MDC fermé : nouvel appel
  (titre, police, priorité, adresse, croisement, bloc) et nouvel incident (titre, unité créatrice, adresse,
  croisement, bloc) pour **les membres des unités de la police de l'appel uniquement** ; changement de statut pour les
  membres de l'unité.
- **Unités les plus proches** : quand un civil émet un appel, les unités **Disponibles** de la police choisie les plus
  proches du civil (autant que le nombre idéal d'unités, 4 max ; jamais une unité au tag **SUP.**, c'est alors la
  suivante qui est choisie) reçoivent à la place une notification différente : « **Vous êtes l'une des unités les plus
  proches** », avec **Y** pour accepter (l'unité est rattachée à l'appel et passe « En route », sans ouvrir le MDC) ou
  **N** pour refuser (30 s pour répondre, `OfferTimeout`). Refus ou sans réponse : l'unité suivante la plus proche est
  sollicitée. Les autres unités de la police gardent la notification habituelle et peuvent rejoindre l'appel depuis le
  MDC. Touches modifiables : Paramètres > Raccourcis clavier > FiveM > « MDC : accepter / refuser l'appel ».
  Position des joueurs lue par le serveur (**OneSync**) ; à défaut, la position du civil est envoyée par son jeu. Chacune se désactive dans
  « Paramètres ». Volume de tous les sons (0 à 100 %) : *Paramètres > MDC > Notifications et sons* (bouton « Tester »).

### Sons du MDC (`html/sounds/`)

| Son | Quand | Qui l'entend |
|---|---|---|
| `inter.wav` | intervention **créée par un civil** (et proposition « unité la plus proche ») | unités de la police de l'appel |
| `2.mp3` | **nouveau BOLO** (avec une notification « NOUVEAU BOLO ») | **toutes les unités WSP et KCSO** (BOLOs communs) |
| `assign.mp3` / `deassign.mp3` | une unité **rejoint** / **quitte** l'appel | unités sur l'appel (et celle qui part) |
| `dsp.mp3` | **observation**, **rapport**, **identité** ou **véhicule** lié à l'appel | unités sur l'appel |
| `status.mp3` | **changement de statut** de l'unité (disponible, en route, sur place, indisponible…) | membres de l'unité |
| `result.mp3` / `nnul.mp3` | recherche **avec** / **sans** résultat | l'agent qui cherche |
| `click.mp3` | clic de souris dans le MDC | soi |
| `laptop.mp3` | clavier : en boucle **tant que l'on écrit**, s'arrête ~0,5 s après la dernière touche | soi |

Les incidents déclarés par une unité gardent leur son à trois tons et les messages entre unités leur carillon (générés
par l'interface). Réglages : « Sons des appels, BOLOs, unités, fiches liées et recherches » et « Sons de l'interface
(clic de souris, clavier) » (*Paramètres > MDC > Notifications et sons*). Les fichiers sont décodés une seule fois puis
joués sans délai (Web Audio) ; remplacer un fichier par un autre du même nom suffit.

Onglet **Paramètres** : afficher / masquer chaque HUD et ses éléments, taille (50 à 200 %), **Placer les HUD à
l'écran** (glisser à la souris, molette = taille), notifications et son.

Performance : le PLD lit la position toutes les 500 ms (`Interval` dans `client/hud.lua`) et n'envoie que les
changements (~0.01ms). Le display MDC et les notifications n'ont aucune boucle.
Car HUD : aucune boucle dans le MDC (données envoyées par rp_vehiclecontrol, seulement quand elles changent).

### Rapports

Chaque rapport reçoit un n° `XX-XXXX`, l'auteur (nom RP) et son unité. La **première ligne** du formulaire choisit
l'intervention ou l'incident lié (obligatoire) : une fois enregistré, le rapport apparaît dans le déroulé de cette
intervention, avec les notes, d'où il peut être ouvert, modifié et ré-enregistré. Après un redémarrage, le lien reste
affiché sur le rapport (intervention « archivée »).

**Antécédents** : un rapport (écrit depuis la page « Rapports » ou depuis une intervention) qui mentionne une
personne enregistrée aux fichiers apparaît automatiquement dans le pli « Rapports » de sa fiche d'identité
(Recherches et Mes créations) : type et n° du rapport, rôle (victime, suspect,
témoin…) s'il y en a un, date, auteur, intervention et résumé. Cliquer dessus ouvre le rapport. Correspondance :
nom de famille + prénom, et date de naissance quand le rapport en donne une (un homonyme né un autre jour n'est pas
concerné). Modifier le rapport met la fiche à jour (une personne retirée du rapport n'a plus ce rapport).

Sur les champs **Nom de famille** et **Immatriculation**, une liste déroulante propose les fiches de l'historique de
l'onglet « Recherches » : en choisir une remplit tous les champs liés (identité, licence, véhicule, propriétaire, assurance).
#### Formulaires de l'État de Washington (WSP / KCSO)

Noms officiels des documents (Notice of Infraction, Criminal Citation…), classifications (Misdemeanor, Felony…), sigles et
articles **RCW** en anglais ; tout le reste (champs, options, intitulés des infractions) traduit en **français pratique**.

| Formulaire | Quand | Contenu |
|---|---|---|
| **Notice of Infraction (NOI)** | infraction **civile** : *Notice of Traffic Infraction* (RCW 46.63) ou *Notice of Civil Infraction* (RCW 7.80) | date / heure / lieu (milepost, ville, comté), **tribunal** (King County District Court…), conducteur et permis (OLN), CMV / HAZMAT, véhicule (plaque, VIN, propriétaire, assurance), vitesse (radar, lidar, pace, **avion de la WSP**, zone scolaire / de travaux), **3 violations au plus** avec pénalité, réponse sous 30 jours (payer, *mitigation hearing*, *contested hearing*), signature, certification sous peine de parjure |
| **Criminal Citation and Notice to Appear** | délit : **misdemeanor / gross misdemeanor** (un crime = arrestation) | prévenu, véhicule si *criminal traffic*, **3 charges au plus** (DV), tribunal, date et heure de comparution, laissé libre sur citation ou écroué (KCCF, MRJC, SCORE…), signature, certification, *Statement of Probable Cause* |
| **Written Warning** | avertissement, sans pénalité | personne, véhicule (contrôle routier), violations (TI / CI), correction demandée |
| **Arrest Report** | arrestation (délits et crimes) | type (on-view, probable cause, mandat + n°, citoyen), signalement (taille, poids, cheveux, yeux, SMT), **charges** (classification, nombre, DV), droits constitutionnels (Miranda : heure, renonciation / invocation), usage de la force, blessures, examen médical, saisies, établissement d'écrou, véhicule, ***Certification for Determination of Probable Cause*** |
| **DUI Arrest Report** | RCW 46.61.502 / .504 | raison du contact, observations de conduite et au contact, **SFST** (HGN /6, Walk-and-Turn /8, One-Leg Stand /4), PBT, Miranda, **Implied Consent Warning** (RCW 46.20.308), test probant (BAC DataMaster : 2 échantillons ; prise de sang : mandat ou consentement ; refus), DRE, charges, immobilisation 12 h (RCW 46.55.360), écrou |
| **Police Traffic Collision Report (PTCR)** | collision avec blessé, mort ou ≥ 1 000 $ de dégâts (RCW 46.52.030) | lieu (route, intersection, milepost), délit de fuite, blessés / morts, type de collision, météo, éclairage, chaussée, intersection, signalisation, zone de travaux ; **units** (véhicule en circulation, garé, piéton, cycliste, délit de fuite) : conducteur, permis, **blessures KABCO**, ceinture, airbag, éjection, sobriété, distraction, circonstances, transport, **violations citées** ; véhicule, direction, manœuvre, vitesses, dégâts, remorquage, CMV (USDOT) ; passagers |
| **Incident Report** | tout autre événement | nature, DV, **infractions** (toutes classifications), personnes (V, S, A, W, RP, O), véhicules, biens et preuves |
| **Vehicle Impound / Inventory Report** | fourrière (RCW 46.55) | motif légal (RCW 46.55.113, .085, .080, .360…), police hold, véhicule, état, conducteur, dépanneur agréé (RTTO), lieu de stockage, **inventaire** |

**Infractions (`server/offenses.lua`)** : catalogue des infractions de l'État de Washington, avec article **RCW**,
intitulé (en français), **classification** et, pour les infractions civiles, la **pénalité** du barème des tribunaux de
district (IRLJ 6.2, frais légaux compris ; modifiable dans le rapport). Classifications (RCW 9A.20.021) :

| | Classification | Peine maximale |
|---|---|---|
| TI | Traffic Infraction | pénalité civile (RCW 46.63) |
| CI | Civil Infraction (Non-Traffic) | classe 1 à 4, jusqu'à 250 $ (RCW 7.80) |
| M | Misdemeanor | 90 jours et / ou 1 000 $ |
| GM | Gross Misdemeanor | 364 jours et / ou 5 000 $ |
| C FEL | Class C Felony | 5 ans et / ou 10 000 $ |
| B FEL | Class B Felony | 10 ans et / ou 20 000 $ |
| A FEL | Class A Felony | perpétuité et / ou 50 000 $ |

Dans chaque infraction / chef : **Classification** et **Infraction (RCW)**, deux listes déroulantes liées :
- choisir l'infraction règle **automatiquement** sa classification (et la pénalité pour une NOI) ;
- choisir d'abord la classification ne propose **que les infractions de cette classification** (en changer retire
  une infraction qui n'en fait pas partie).

**Plusieurs infractions dans un rapport** : la première ligne est déjà là ; **« + »** (à côté du titre de la liste, ou
« + Ajouter une infraction » en bas) en ajoute une, **✕** en retire une. **Type imposé** quand le formulaire n'en
admet qu'un : **Notice of Infraction** routière (*Notice of Traffic Infraction*) -> **Traffic Infraction seulement**,
civile hors route -> **Civil Infraction seulement** ; **Written Warning** : contrôle routier -> TI, autre contact -> CI.
La classification est alors verrouillée sur toutes les lignes, la liste ne propose que ces infractions, changer le
type d'avis retire les infractions qui ne vont plus, et le serveur refuse le reste (« une infraction d'un autre type
se fait dans un autre rapport »). **Arrest Report, DUI, Criminal Citation, Incident, PTCR** : plusieurs
classifications différentes dans le même rapport (champ `lock` d'`offenseList` dans `server/reports.lua`).

Les infractions sont classées par catégorie (Speed, Moving Violations, Equipment, DUI, Crimes Against Persons,
Property Crimes…). Chaque formulaire n'offre que les classifications qui lui correspondent (NOI : TI / CI ;
Criminal Citation : M / GM ; Arrest / DUI : M à A FEL ; Incident / PTCR : toutes). Le serveur revérifie tout : une
infraction inconnue ou d'une autre classification est refusée, et la classification enregistrée est celle de
l'infraction. Ajouter une infraction : une ligne dans `server/offenses.lua`.

Les formulaires sont décrits dans **`server/reports.lua`** : ajoutez un champ ou une option à cet endroit uniquement,
l'interface et la validation serveur suivent automatiquement.

### Identités

Prénom\*, middle name, nom de famille\*, date de naissance\*, sexe ((M) Male / (F) Female), adresse\*, SSN (généré), emploi ;
**nationalité et documents** et **permis de conduire** (ci-dessous, réglages dans **`config/licenses.lua`**) ;
interdictions cumulables (Port d'arme, Conduite de jour uniquement, Interdiction de rouler sur Interstate),
condition (Recherché + raison et date de début) ; **Casier judiciaire** et **Registre des délinquants** (ci-dessous).
Les anciens antécédents en texte libre restent affichés sur les fiches (pli « Casier judiciaire », « ancien antécédent »).

### Casier judiciaire et registre (Sex Offender / Kidnapping Offender)

**MDC civil (Créations)** : dans le formulaire **Identité** (à la création ou en modification), ou pour une identité
**déjà créée** avec les boutons sous les onglets : **Casier judiciaire** et **Registre Sex / Kidnapping Offender**
(choisir une de vos identités, puis enregistrer).

- **Casier judiciaire** (« + Ajouter une condamnation ») : **charge retenue** dans le catalogue RCW
  (`server/offenses.lua`, Misdemeanor à Class A Felony ; pas les infractions civiles), classification, date des faits,
  date du jugement (📅 : dates cohérentes au hasard selon la date de naissance), **décision** (coupable, plaidé
  coupable, Alford, peine différée, classé, acquitté), tribunal (King County Superior / District Court, Seattle
  Municipal Court…), n° de dossier (généré, ↻), **peine prononcée automatique** selon la charge et un bouton **dé**
  pour **une autre version**, notes.
- **Registre** : case **Sex Offender** et / ou **Kidnapping Offender**. **Charge retenue** parmi les vraies charges du
  registre : infractions sexuelles (RCW 9A.44 : viols, viols sur mineur, child molestation, indecent liberties,
  inconduite sexuelle avec un mineur, voyeurisme ; RCW 9.68A : communication avec un mineur, images
  pédopornographiques, exploitation sexuelle, abus sexuel commercial ; inceste, exhibition aggravée, défaut
  d'inscription) ou d'enlèvement (enlèvement 1er / 2e degré, séquestration d'un mineur). **Niveau de risque** (I à
  III, proposé selon la charge), **statut** (en règle, non conforme, en fuite), **adresse déclarée** (celle de
  l'identité par défaut), **peine automatique** (dé : autre version), tribunal et n° de dossier.
- **Peine automatique** : fourchette standard de la grille de Washington pour un casier vierge (niveau de gravité,
  RCW 9.94A.510), peine **indéterminée** (minimum / perpétuité, ISRB) pour les crimes sexuels les plus graves,
  alternative **SSOSA** quand elle est possible, peine exceptionnelle, peine des Misdemeanors (jours de prison,
  sursis, probation), surveillance (community custody), amende et frais, dédommagement, conditions (contact,
  mineurs, traitement, arme à feu, ADN…), et **durée d'inscription** (RCW 9A.44.140 : Class A **à vie**, Class B
  **15 ans**, Class C / GM **10 ans** après la libération). Le texte reste modifiable.
- **Dates cohérentes** (📅 « Dates automatiques », et à chaque nouvelle version de la peine tant que les dates n'ont
  pas été changées à la main) : faits, jugement 3 à 14 mois après, **libération = jugement + incarcération purgée**,
  inscription 0 à 3 jours après la libération (RCW 9A.44.130), fin de l'inscription calculée ; la personne est
  majeure aux faits quand c'est possible et l'inscription est encore en cours. Le serveur vérifie l'ordre des dates.
- **L'inscription crée automatiquement la condamnation au casier** (même charge, dates, tribunal, dossier, peine,
  « Inscription au registre … le … (niveau …) »). Elle se modifie depuis le registre ; le bouton « Casier judiciaire »
  la montre à part.

**Polices (WSP, KCSO)** : **Recherches > Sex Offenders / Kidnapping Offenders** : liste **commune aux deux polices**
(nom, date de naissance, niveau, charge, adresse déclarée, statut), filtres (texte, niveau, inscriptions terminées),
fiche complète à droite. Fiche d'une personne inscrite : bandeau violet **SEX OFFENDER / KIDNAPPING OFFENDER — NIVEAU
… — inscription à vie / jusqu'au …** (EN FUITE, NON CONFORME), plis **Registre des délinquants** et **Casier judiciaire**.
**Remplissage aléatoire** : prénom, middle name, nom, DoB, adresse, SSN et emploi.

### Nationalité et permis de conduire (`config/licenses.lua`)

**Nationalité** : **citoyen américain**, **citoyen canadien** ou **double nationalité** (Washington est frontalier du
Canada). Pour un Canadien, son **statut aux États-Unis** :
- **visiteur** (exempté de visa) : date d'entrée, **séjour autorisé 6 mois** ; **pas de SSN** ; adresse au Canada ;
  conduit avec le permis de **sa province** (Colombie-Britannique, Alberta) ;
- **résident permanent** (green card), **travailleur** (visa TN, ACEUM), **étudiant** (visa F-1) : vit aux
  États-Unis, SSN, permis d'un État américain ou de sa province, date de fin de la carte / du visa.

Documents : **SIN** (n° d'assurance sociale canadien, XXX-XXX-XXX) pour les Canadiens et la double nationalité,
**passeport** (US : 1 lettre + 8 chiffres ; Canada : 2 lettres + 6 chiffres), carte **NEXUS** (voyageur fiable).
Fiches des polices : nationalité (étiquette **CAN** dans les résultats, SIN à la place du SSN), plis « Permis de
conduire » et « Nationalité et documents », bandeau **SÉJOUR DÉPASSÉ** (visiteur resté plus de 6 mois) ou
**STATUT EXPIRÉ** (green card / visa).

**Permis** : État ou province d'émission, **type**, **mentions**, n° généré **au format réel** de la juridiction,
condition (valide, suspension, révocation, annulation, disqualification pour les permis commerciaux).

| Juridiction | Types de permis | N° |
|---|---|---|
| **WA - Washington** | Driver License (standard), **Enhanced Driver License (EDL)** (citoyens américains : passage de la frontière par la route), Intermediate License (16-17 ans), Instruction Permit, Motorcycle Instruction Permit, CLP, CDL A / B / C | WDL + 9 caractères |
| OR - Oregon | Class C - Standard, Provisional (moins de 18 ans), Instruction Permit, Motorcycle Instruction Permit, CLP, CDL A / B / C | 7 chiffres |
| ID - Idaho | Class D - Standard, Class D - Graduated (moins de 17 ans), Supervised Instruction Permit, CLP, CDL A / B / C | 2 lettres + 6 chiffres + 1 lettre |
| MT - Montana | Class D - Standard, First-Year Restricted, Learner License, CLP, CDL A / B / C | 13 chiffres |
| CA - Californie | Class C - Standard, Provisional, Instruction Permit, Class M1 - Moto, Class M2 - Cyclomoteur, Class A / B non commerciaux, CLP, CDL A / B / C | 1 lettre + 7 chiffres |
| BC - Colombie-Britannique | Class 5 - Standard, Class 7 - Novice (N), Class 7L - Learner (L), Class 6 - Moto, Class 6L, Classes 1 à 4 (commerciales) | 7 chiffres |
| AB - Alberta | Class 5 - Standard, Class 5 GDL, Class 7 - Learner, Class 6 - Moto, Classes 1 à 4 (commerciales) | 6 chiffres - 3 chiffres |

Mentions : **M** (moto, États-Unis) ; permis commerciaux : **H** matières dangereuses, **N** citerne, **P** passagers,
**S** bus scolaire, **T** doubles / triples, **X** citerne + matières dangereuses ; Canada : **Q** freins pneumatiques.

Vérifié par le serveur (et grisé dans le formulaire) : **âge** de chaque type (permis d'apprentissage dès 14 / 15 ans,
probatoires réservés aux mineurs, standard et commerciaux selon la juridiction), **pays** selon la nationalité et le
statut (citoyen américain : permis américain ; visiteur canadien : permis canadien ; double nationalité, résident,
visas : les deux), **EDL réservé aux citoyens américains**, mentions commerciales seulement sur un permis commercial.
Anciennes fiches (Géorgie…) : affichées telles quelles ; en modification, l'État et le type sont à rechoisir. Pour
ajouter un type, une juridiction ou un statut : `config/licenses.lua` uniquement (le serveur, les rapports et
l'interface suivent).

### Véhicules

Immatriculation\*, statut de l'immatriculation\*, marque\*, modèle\*, année, couleur\*, propriétaire (une de vos identités),
VIN\* (généré), dernier contrôle technique\* (jamais après aujourd'hui) ; assurance (statut\*, n° de police\* généré et compagnie\* sauf « Non-Assuré ») ;
véhicule volé / abandonné / commercial ; **Historique** (infraction administrative ou de stationnement).
**Véhicule actuel** : reprend modèle, marque, couleur et plaque du véhicule où vous êtes.
**Remplissage aléatoire** : statut d'immatriculation, contrôle technique et assurance.
**VIN relevé sur le véhicule** : l'œil de rp_interact (**Inspections › Numéro VIN**) lit le VIN enregistré ici pour la
plaque du véhicule (export serveur `getVehicleVin(plaque)` : le VIN, ou `nil` si la plaque n'est pas enregistrée ;
rp_interact affiche alors « Illisible »).

Les listes du générateur (noms, adresses, emplois…) se modifient dans `html/script.js`, section « GÉNÉRATEURS ALÉATOIRES ».
Adresses générées : **King County (État de Washington)**, rues réelles au format « 4521 Fremont Ave N, Seattle, WA 98103 » —
55 % Seattle, 20 % Bellevue (et Medina, Clyde Hill), puis Maple Valley, Kenmore, Carnation, Ravensdale (liste `ADDRESSES`) ;
visiteur canadien : adresse en Colombie-Britannique ou en Alberta. **Téléphone** de chaque identité généré (↻ pour un
autre) : Seattle **206**, est du comté **425** ; Canadien visiteur : indicatif de sa province. N° du requérant d'une
intervention : toujours un numéro de l'**État de Washington** (206, 425, 253, 360 : `WASHINGTON_AREA_CODES` dans
`server/server.lua` et `html/script.js`). **Nationalité par défaut : citoyen américain** ; le remplissage aléatoire
garde la nationalité choisie.

## Priorités de réponse, renforts et clôture des appels

**Création d'un appel** (Créations > Intervention) : on coche d'abord la ou les **polices**, puis la priorité apparaît.
- **KCSO** (seul ou appel commun, `Config.PriorityAgency`) : **Priorité de réponse** : X (critique, danger de mort),
  1 (immédiat), 2 (rapide), 3 (routine), 4 (quand disponible), 0 (911 coupé sans info). Une fois choisie, une
  **légende en rouge** rappelle les différences (la priorité choisie en gras) et le champ **Code de réponse**
  apparaît à côté : Code 1 (normal), Code 2 (urgent, moyen), Code 3 (urgent, rapide). Les deux sont obligatoires.
- **WSP seule** : Non-Urgent, Priorité 1 à 3, sans code de réponse.
Liste : « Priorité X · C3 » ; détail : priorité et sa signification, code de réponse ; couleur de ligne par priorité.

**Fiche d'un appel** : les boutons Rejoindre / Quitter / Modifier / Intervention terminée sont **tout en bas**.
Une fois **rattaché** à l'appel, une barre **RENFORTS** apparaît en haut :
- **+ Ajouter WSP / KCSO à l'appel** : l'appel devient commun, l'autre police le voit et peut le rejoindre (ses
  unités reçoivent la notification d'appel habituelle, **pas** une demande de renfort) ;
- **KCSO** : Code 1 Backup (une unité en plus, sans urgence), Code 2 Backup (renfort, 2 unités idéalement),
  Code 3 Backup (renfort urgent), **10-33** (Officer Needs Help) ; **WSP** : **10-33** seulement (`Config.BackupCodes`) ;
- un Code 1 / 2 / 3 Backup part **à la police de l'unité seulement** ; un **10-33** part **aux deux polices** (l'appel
  devient commun pour que tous puissent le rejoindre). Les unités déjà sur l'appel ne sont pas renotifiées ;
- la demande s'affiche en **notification** (même son qu'une nouvelle intervention ; 10-33 en rouge clignotant) et
  s'inscrit dans le déroulé de l'appel. Une demande par unité toutes les 10 s au plus (`Config.BackupCooldown`).

**Clôture** : une unité **WSP** (`Config.ClearAgency`) qui clique « Intervention terminée » choisit : **Clear A** —
Notice of Infraction (ticket), **Clear B** — Arrestation, retenue ou criminal citation et libération, **Clear C** —
Warning. La clôture est affichée sur l'appel terminé. Les unités KCSO terminent comme avant (deuxième clic pour
confirmer).

## Données (permanentes)

Identités, véhicules, rapports et BOLOs : `data/identities.json`, `data/vehicles.json`, `data/reports.json` et `data/bolos.json`,
écrits à chaque création / modification. Ils survivent aux déconnexions et aux redémarrages. **Le script ne supprime
jamais rien**, sauf les BOLOs supprimés depuis le MDC (BOLO levé).
Pour retirer une entrée (cadres) : éditez le fichier puis tapez `mdc_reload` dans la console serveur.
Voir `data/LISEZMOI.txt`. ⚠ Ne remplacez pas le dossier `data/` lors d'une mise à jour.

## Relier une base de données

Cherchez `>>> BASE DE DONNÉES` dans `server/server.lua` : seules les fonctions `loadStore()` / `saveStore()` sont à remplacer.

## Permissions (rôles Discord)

Les rôles Discord (**Admin**, **Membre**, **Joueur non-officiel**) donnent un groupe ACE à chaque joueur (ressource
`rp_permissions`, repères `rp.admin` / `rp.membre` dans `permissions.cfg`). Dans `Config` (`server/server.lua`) :

| Réglage | Par défaut | Effet |
|---|---|---|
| `AgencyAce` | `{ wsp = 'rp.membre' }` | MDC réservés : la **WSP** aux membres recrutés et aux admins ; les joueurs non-officiels ont le **KCSO** et le MDC **civil** (carte de la WSP grisée, serveur qui refuse) |
| `SupervisorAce` | `'rp.admin'` | tag **SUP.** (superviseur) d'une unité : admins seulement (option masquée pour les autres ; une unité déjà SUP. le garde) |
| `DeleteCallAce` | `'rp.admin'` | bouton **Supprimer de la liste** dans le détail d'une intervention / d'un incident (en cours ou terminé, deux clics) : admins seulement |

`false` : tout le monde. Optionnel, en plus : accès au MDC lui-même par ACE :

Dans `server/server.lua`, passez `UseAcePermission = true` puis dans `server.cfg` :

```
add_ace group.police mdc.use allow
add_principal identifier.license:xxxxxxxx group.police
```
