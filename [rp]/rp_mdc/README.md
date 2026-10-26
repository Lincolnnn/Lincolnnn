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
├── rp_doorlock/         portes verrouillées, frapper, enfoncer (police)
├── rp_vehicleprops/     objets collés sur les véhicules (œil)
├── rp_taser10/          TASER 10 (sondes, fils, laser, lampe ; œil)
├── rp_TrafficControl/   gestion du trafic
├── rp_RoleplayZone/     scènes de roleplay
└── rp_Ganghunt/         vagues d'ennemis (/ganghunt)
```

1. Copiez le dossier **`[rp]`** tel quel dans `resources/` (FiveM trouve les ressources dans les dossiers entre
   crochets).
2. Dans `server.cfg`, démarrez celles que vous voulez, le MDC en premier :
   ```
   ensure rp_chat
   ensure rp_mdc
   ensure rp_vehiclecontrol
   ensure rp_interact
   ensure rp_equipment
   ensure rp_camshake
   ensure rp_NPCcontrol
   ensure rp_flares
   ensure rp_doorlock
   ensure rp_vehicleprops
   ensure rp_taser10
   ensure rp_TrafficControl
   ensure rp_RoleplayZone
   ensure rp_Ganghunt
   ```
   Le MDC publie son nom de ressource (`GlobalState.mdcResource`) : son dossier peut être renommé.
3. En jeu : touche **K** (modifiable dans *Paramètres > Raccourcis clavier > FiveM*) ou `/mdc`. **Échap** pour fermer.

Le dépôt contient aussi le **menu d'interactions (au clavier) / fiches civiles / Eye Target** dans [`rp_interact/`](../rp_interact/README.md)
(ressource séparée : un joueur y est « policier » quand il est dans une unité du MDC, voir l'export serveur
`getPlayerUnit(source)` et l'état `Player(source).state.mdcUnit`). Le MDC publie son nom de ressource
(`GlobalState.mdcResource`) : le nom de son dossier n'a pas d'importance.

Le dépôt contient aussi **Vehicle Control** dans [`rp_vehiclecontrol/`](../rp_vehiclecontrol/README.md) : essence (plein à
la pompe avec un vrai pistolet, jerrican), dégâts réalistes, ceinture, moteur toujours allumé, portières depuis l'intérieur, clignotants et poussée ; il
alimente le car HUD du MDC.

Le dépôt contient aussi le **chat écrit RP** dans le dossier [`rp_chat/`](../rp_chat/README.md) : c'est une ressource
séparée, à copier à part dans `resources/` (voir son README). Elle partage le nom RP avec le MDC et ses réglages
se font dans l'onglet « Paramètres » du MDC. Le MDC fonctionne aussi sans elle.

Et **RP CamShake** dans [`rp_camshake/`](../rp_camshake/README.md) : petit script indépendant de tremblement de la caméra
(marche, course, sprint, chocs, accidents).

Et **RP NPC Control** dans [`rp_NPCcontrol/`](../rp_NPCcontrol/README.md) : plus de police / pompiers / ambulanciers du
jeu (ni leurs véhicules), plus d'indice de recherche, PNJ qui ignorent les joueurs, densité du trafic et des piétons
de 0.0 à 3.0.

Et **RP Flares** dans [`rp_flares/`](../rp_flares/README.md) : fusées de détresse posées au sol (touche G, fusée en main),
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

Et **RP Ganghunt** dans [`rp_Ganghunt/`](../rp_Ganghunt/README.md) : `/ganghunt`, n'importe quel joueur fait venir des
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
| **Washington State Patrol** | Unités, Interventions, Recherches, Rapports, Paramètres | policiers WSP |
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

- **Thème clair (jour)** : fond gris très clair, cartes blanches, texte foncé, accent bleu. Les HUD affichés sur le
  jeu (PLD, display MDC, car HUD) et les notifications restent sombres, pour rester lisibles sur l'image du jeu.
- **Volet de navigation à gauche** : en haut, le **nom RP** (sans image de profil) et le MDC utilisé ; les **pages** du MDC ; pour les
  polices, juste en dessous des pages, les **4 statuts listés l'un sous l'autre** : chaque bouton est **entièrement
  de la couleur de son statut**, celui de l'unité est mis en avant (opaque, cerclé, ✓) ; puis les **BOLO actifs**
  (cases repliées : un clic affiche les détails, **Voir BOLO** ouvre la page des BOLOs sur celui-ci) ; tout en bas,
  **Paramètres**.
- **Au centre** : le **titre de la page** et son sous-titre, puis le contenu, en cartes.
- **Note de l'unité** (polices) : bouton **en haut à droite** de la fenêtre (barre de titre, un point bleu quand une
  note existe) : il ouvre / ferme un **panneau à droite** avec la note propre à l'unité (500 caractères, plusieurs
  lignes, partagée par ses membres, enregistrée pendant la frappe ; gardée dans l'unité côté serveur). Panneau ouvert
  ou fermé : gardé chez le joueur.
- **En bas** : la disponibilité et l'heure du jeu.

La fenêtre est **légèrement transparente** (opacité **97 %** par défaut, de 50 à 100 %, *Paramètres > MDC*). Il n'y a
plus de flou de l'arrière-plan.

### Mode nuit (*Paramètres > MDC > Apparence*)

- **Apparence** : **Jour** (thème clair, par défaut) ou **Nuit** : **fond noir**, tout dans **une seule couleur**
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
  pose `data-theme="night"` et `data-night-color` sur la page (dans le MDC : `data-theme` sur la fenêtre `#mdc` et
  sur la couche des HUD `#hudLayer`, jamais `color-scheme` sur la racine ; jamais de `color-mix()`, inconnu du
  navigateur du jeu) (couleurs : variables `--n-*` en haut du bloc « mode
  nuit » de chaque `style.css`).

- **NOM RP** : il s'affiche en haut à gauche et dans les unités (le pseudo Steam/FiveM n'est jamais affiché). **Obligatoire pour
  rejoindre une unité.** Il est partagé avec le chat écrit : `/nomrp John Carter` dans le chat change aussi celui du MDC, et
  inversement. Il n'est enregistré nulle part : il est remis à zéro à chaque déconnexion (état `rpName` du joueur côté serveur).
- **Statut de l'unité** : Disponible (vert), En route (jaune), Sur place (orange), Indisponible (rouge). Le statut est celui de l'unité rejointe.

## Onglets

| Onglet | Rôle |
|---|---|
| Unités | (polices) Une liste : les unités **de votre police** seulement. Bouton **Créer une unité** (nom, **tag** au menu déroulant : Aucun, **SUP.** (superviseur) ou **Autre** à saisir, couleur) ; l'unité appartient à la police du MDC (pastille **WSP** bleue / **KCSO** verte). Chacun peut rejoindre une unité de sa police (4 joueurs max par unité) ; **une seule unité à la fois** : dans une unité, le bouton « Rejoindre » des autres disparaît, il faut d'abord **quitter** la sienne (le serveur refuse aussi). **Modifier** et **Supprimer** : réservés aux **membres** de l'unité. Les membres d'une unité partagent leurs recherches et leurs rapports (voir plus bas) |
| Interventions | **Police** : les appels de **sa police** (toujours ouverts), puis les **appels communs** (WSP & KCSO) ; les appels de l'autre police ne sont **pas** visibles. Seules les polices visées peuvent rejoindre un appel (vérifié par le serveur). Incident : police de l'unité déclarante toujours cochée, **case** pour y ajouter l'autre police (incident commun). **Générique** : les listes de **chaque police** et les appels communs, **en lecture** (pas de « Rejoindre ») ; bouton **Modifier** sur les **interventions** (appels des civils) pour les corriger directement. Interventions (civils) et incidents (unités) : titre, priorité, adresse, bloc ; chaque ligne est surlignée de la couleur de sa priorité. N° d'incident `XX-XXXX`. Cliquer pour afficher le détail, recliquer (ou **✕** en haut du panneau) pour le masquer : **sans appel choisi, le panneau des détails est réduit à une fine colonne** et la liste prend toute la place. Rejoindre / quitter l'appel (unités uniquement), notes en majuscules modifiables, « Intervention terminée » (grisée dans la liste). Les rapports liés apparaissent avec les notes (ouvrir / modifier) et un rapport peut être rédigé directement depuis l'intervention. **Personnes et véhicules** : les unités sur l'appel y ajoutent les fiches de l'historique des recherches (bouton « Fiche » pour la consulter). Bouton **Nouvel incident** pour les unités |
| Recherches | (polices) Identité : nom de famille\* + date de naissance\*, prénom et SSN facultatifs. Véhicule : immatriculation ou VIN. Historique : les nouveaux résultats s'ajoutent en haut, les précédents restent en dessous. Bouton **BOLOs** (en haut à droite) : voir plus bas |
| Rapports | **Communs à tous les MDC**. DOT-523 (Georgia Uniform Crash Report), Arrest Report, Incident Report, Citation (identité seule), Traffic Citation (type d'infraction : Excès de vitesse / Conduite / Contrôle, intitulé, description ; sans amende), Convocation, Warning (infraction routière : identité complète avec licence et véhicule ; autre infraction : identité), Incident Report (« Impliqués » : individus et véhicules enregistrés) ; « Charges » pour l'Arrest Report. Les anciens Tickets restent lisibles. Chaque rapport est lié à une intervention / un incident (en cours ou terminé). Liste filtrable (type, texte, mes rapports), lecture, modification par l'auteur. Permanents |
| Paramètres | Tout en haut, **MDC utilisé** (changer de MDC). Puis trois catégories repliables, toutes fermées à l'ouverture : **MDC** (taille de l'interface, **apparence jour / nuit**, couleur du mode nuit et où il s'applique, transparence de la fenêtre, onglet à l'ouverture, fenêtre, notifications, son et son volume de 0 à 100 %), **HUD & Display** (PLD, display MDC et car HUD : affichage, éléments visibles, taille, position ; volume des sons du véhicule ; le Menu Interaction de `rp_interact` n'est plus réglable : il est toujours en haut à gauche, comme les menus du jeu) et **Chat écrit et commandes** (apparence du chat, affichage des /me, liste des commandes ; ressource `rp_chat`). Gardés chez le joueur, même après une reconnexion |
| Créations | MDC **Générique** : identité, véhicule, intervention (requérant, téléphone généré, priorité, **polices** en **cases à cocher** (WSP, KCSO : une case = appel de cette police ; les deux = appel commun), **nombre idéal d'unités** (1 à 4), adresse, croisement, bloc, description ; bouton « Position actuelle »). Bouton **Registre** : vos identités et véhicules, modifiables |

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

Affichages séparés, au thème du MDC (fond sombre « Mica », contour fin, coins arrondis ; le car HUD, lui, sans
fond), visibles même MDC fermé :

- **PLD** (Player Localisation Display), **affiché pour chaque joueur dès sa connexion**, sans utiliser le MDC
  (ni nom RP, ni unité) ; désactivable et réglable dans « Paramètres », réglages propres à chaque joueur
  (`PldForEveryone` dans `client/hud.lua` pour le réserver aux joueurs ayant accès au MDC) : direction en gros
  et en gras (N / NE / E / SE / S / SW / W / NW), rue actuelle en gros et, à sa droite, la **zone géographique**
  (ex. Cypress Flats, West Vinewood ; masquable), **croisement le plus proche** en petit et en
  italique (toujours présent : largeur stable), **bloc** : celui où se trouve le joueur, sinon le plus proche, et
  sur la même ligne, décalée d'environ 2,5 cm, l'**heure du jeu** (HH:MM, sans libellé, masquable dans « Paramètres » ;
  écart réglable : `--pld-time-gap` dans `html/style.css`).
  **Priorité au PLD, au car HUD et au display MDC** : tant que le PLD est affiché, les textes du jeu qui s'y
  superposent (nom de la rue, de la zone, du véhicule et sa classe) sont masqués (`HideGameHud` dans
  `client/hud.lua`). Les scripts de HUD concurrents listés dans `ConflictingHuds` (`server/server.lua` : street
  labels, compteurs de vitesse, boussoles…) sont **arrêtés** au démarrage du MDC ou dès qu'ils démarrent (sauf si une
  autre ressource en dépend : message dans la console) ; ajoutez-y le dossier de tout autre script de ce genre
  (`StopConflictingHuds = false` pour ne rien arrêter). Pour que les HUD du MDC passent aussi **au-dessus** de
  l'interface d'un autre script, démarrez `rp_mdc` **après** lui dans `server.cfg` (la dernière interface
  chargée s'affiche au-dessus).
  **Noms des rues et des quartiers** : **uniquement** ceux de **`config/atlanta_streets.lua`** (aucun autre fichier,
  aucune autre ressource) : `streets` (nom du jeu -> nom d'Atlanta), `pool` (rues non listées : un nom de la liste,
  toujours le même pour une même rue ; `autoRenameUnmapped = false` pour garder leur nom du jeu), `zones` (quartiers,
  renommés aussi sur la carte du menu pause), `countyZones` / `cityName` / `countyName`. Utilisés par le PLD, le bouton
  « Position actuelle » et les exports `GetStreetName`, `GetDistrictName`, `GetLocationText`, `RenameStreet`.
  Le filtre `"street"` de `config/blocks.json` utilise le nom **affiché** (d'Atlanta, ex. « Aberdeen Pkwy »).
  Commande **`/mdc_streets`** (F8) : noms à votre position (et ceux du jeu), pour vérifier.
  Les blocs se dessinent dans **`config/blocks.json`** (cercles, rectangles, polygones, filtre par rue) : voir
  `config/LISEZMOI.txt` ; la commande `/mdc_pos` (console F8) donne la ligne à copier.
- **Display MDC** : affiché seulement dans une unité : « **[N° d'unité] • [POLICE]** » (ex. `417 • WSP`, pastille
  WSP bleue / KCSO verte) suivi du tag spécial (ex. SUP.), statut, n° d'incident (uniquement quand l'unité est sur un
  appel) et **secteur** (zone de jeu) choisi dans le Menu Interaction (`rp_interact`, Police > Display MDC) : « aucun
  sélectionné » tant que rien n'est choisi. Chaque ligne se masque dans « Paramètres ».
- **Car HUD**, à bord d'un véhicule : **toujours affiché pour le conducteur**, entièrement **grisé moteur coupé** et
  qui **s'illumine au démarrage** ; seulement le logo de la ceinture pour les passagers ; **au-dessus de la minimap** et **sans aucun fond** (ni opaque, ni transparent,
  ni coloré ; seulement une ombre portée pour la lisibilité) : la **vitesse en MPH** (un simple nombre), une fine **barre horizontale
  d'accélération** (régime du moteur, rouge près du maximum), une **jauge d'essence verticale** (orange sous 15 %, rouge
  sous 5 %), le petit **logo de la ceinture** (contour noir : vide = détachée, blanc = attachée, clignote en rouge pâle
  en roulant sans ceinture) et, à côté, un **logo du moteur** : **orange** quand le moteur est **très abîmé**
  (palier 1 : il roule lentement, cale, fume), sinon jamais visible sauf quand le moteur est **détruit** (palier 2,
  véhicule hors d'usage) : le car HUD reste alors **allumé, tout en rouge vif clignotant**, ce logo du moteur
  est **rouge foncé, fixe** ; le logo de la ceinture ne clignote plus : attachée, rempli de **rouge fixe** ;
  détachée, seulement son **contour en rouge**, centre transparent, fixe. À droite, le **rapport** (conducteur) :
  **R** au-dessus de **D**, une pastille glisse en douceur de l'un à l'autre (jaune en marche arrière, touche **↑**). En montant côté conducteur, une **notification glisse depuis la gauche juste au-dessus
  du car HUD** et présente la touche du moteur (**O**) ; elle disparaît après 8 secondes. Déplaçable et redimensionnable comme les autres HUD ; chaque
  élément se masque dans « Paramètres », avec le volume des sons de la ceinture.
  Les données (essence, dégâts, ceinture, moteur) viennent de **Vehicle Control**
  ([`rp_vehiclecontrol/`](../rp_vehiclecontrol/README.md)) : sans cette ressource, le car HUD n'apparaît pas
  (`client/carhud.lua` ne fait que relayer ses données au NUI, sans boucle).
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
  « Paramètres ». Un son accompagne les nouveaux appels (deux tons) et incidents (trois tons) : son **volume (0 à 100 %)**
  se règle dans *Paramètres > MDC > Notifications et sons* (bouton « Tester »). Le son est généré par l'interface :
  aucun fichier audio n'est nécessaire.

Onglet **Paramètres** : afficher / masquer chaque HUD et ses éléments, taille (50 à 200 %), **Placer les HUD à
l'écran** (glisser à la souris, molette = taille), notifications et son.

Performance : le PLD lit la position toutes les 500 ms (`Interval` dans `client/hud.lua`) et n'envoie que les
changements (~0.01ms) ; PLD désactivé : 0.00ms. Le display MDC et les notifications n'ont aucune boucle.
Car HUD : aucune boucle dans le MDC (données envoyées par rp_vehiclecontrol, seulement quand elles changent).

### Rapports

Chaque rapport reçoit un n° `XX-XXXX`, l'auteur (nom RP) et son unité. La **première ligne** du formulaire choisit
l'intervention ou l'incident lié (obligatoire) : une fois enregistré, le rapport apparaît dans le déroulé de cette
intervention, avec les notes, d'où il peut être ouvert, modifié et ré-enregistré. Après un redémarrage, le lien reste
affiché sur le rapport (intervention « archivée »).

**Antécédents** : un rapport (écrit depuis la page « Rapports » ou depuis une intervention) qui mentionne une
personne enregistrée aux fichiers apparaît automatiquement dans le pli « Antécédents » de sa fiche d'identité
(Recherches et Registre), sous les antécédents saisis à la main : type et n° du rapport, rôle (victime, suspect,
témoin…) s'il y en a un, date, auteur, intervention et résumé. Cliquer dessus ouvre le rapport. Correspondance :
nom de famille + prénom, et date de naissance quand le rapport en donne une (un homonyme né un autre jour n'est pas
concerné). Modifier le rapport met la fiche à jour (une personne retirée du rapport n'a plus ce rapport).

Sur les champs **Nom de famille** et **Immatriculation**, une liste déroulante propose les fiches de l'historique de
l'onglet « Recherches » : en choisir une remplit tous les champs liés (identité, licence, véhicule, propriétaire, assurance).
Les rapports ne contiennent ni caution ni chefs d'accusation ; seules les infractions des tickets / citations ont une amende.

**DOT-523** : 0 - Amorce (date, horaire, météo, luminosité, chaussée, comté, service, nb d'unités de police) ;
1 - Impliqués (autant d'« Units » que nécessaire : type Véhicule / Piéton / H&R / Commercial, conducteur et licence,
DWI, occupants, véhicule, et partie commerciale si cochée : compagnie, USDOT, type d'unité, cargo body type, poids,
surcharge → MCE, matières dangereuses, tests DWI obligatoires) ; 2 - Type de collision (lieu précis, causes à cocher
pour chaque unit, vitesses et distances par unit, lieu) ; 3 - Partie narrative.

Les formulaires sont décrits dans **`server/reports.lua`** : ajoutez un champ ou une option à cet endroit uniquement,
l'interface et la validation serveur suivent automatiquement.

### Identités

Prénom\*, middle name, nom de famille\*, date de naissance\*, sexe ((M) Male / (F) Female), adresse\*, SSN\* (généré), emploi ;
licence de conduite (case à cocher, puis État d'émission : GA - Georgia, FL - Floride, TN - Tennessee,
SC - South Carolina, NC - North Carolina, AL - Alabama ; type de licence selon l'État : en Géorgie Class C - Standard,
Class F - Lourd, Class E - Combiné, Class M - Moto, CDL A/B/C, Probatoire - Class CP/D/MP ; ailleurs standard, moto,
CDL A/B/C (+ Class G - Cyclomoteur en Caroline du Sud) ; n° généré ; condition : Valide / Suspension / Révocation / Annulation /
Disqualification pour les CDL) ;
interdictions cumulables (Port d'arme, Conduite de jour uniquement, Interdiction de rouler sur Interstate),
condition (Recherché + raison et date de début) ; **Antécédents** (infraction, date, horaire, adresse, explication).
**Remplissage aléatoire** : prénom, middle name, nom, DoB, adresse, SSN et emploi.

### Véhicules

Immatriculation\*, statut de l'immatriculation\*, marque\*, modèle\*, année, couleur\*, propriétaire (une de vos identités),
VIN\* (généré), dernier contrôle technique\* (jamais après aujourd'hui) ; assurance (statut\*, n° de police\* généré et compagnie\* sauf « Non-Assuré ») ;
véhicule volé / abandonné / commercial ; **Historique** (infraction administrative ou de stationnement).
**Véhicule actuel** : reprend modèle, marque, couleur et plaque du véhicule où vous êtes.
**Remplissage aléatoire** : statut d'immatriculation, contrôle technique et assurance.

Les listes du générateur (noms, adresses, emplois…) se modifient dans `html/script.js`, section « GÉNÉRATEURS ALÉATOIRES ».
Adresses générées : adresses réelles de Géorgie au format « 225 Baker Street NW, Atlanta, Fulton Co., GA » — 80 % Atlanta,
10 % autres villes du comté de Fulton, 10 % reste de la Géorgie (liste `ADDRESSES`, bâtiments publics et lieux connus).
Les numéros de téléphone générés commencent par un indicatif régional de Géorgie compris entre 470 et 678
(470, 478, 678 : liste `GEORGIA_AREA_CODES` dans `server/server.lua` et `html/script.js`).

## Données (permanentes)

Identités, véhicules, rapports et BOLOs : `data/identities.json`, `data/vehicles.json`, `data/reports.json` et `data/bolos.json`,
écrits à chaque création / modification. Ils survivent aux déconnexions et aux redémarrages. **Le script ne supprime
jamais rien**, sauf les BOLOs supprimés depuis le MDC (BOLO levé).
Pour retirer une entrée (cadres) : éditez le fichier puis tapez `mdc_reload` dans la console serveur.
Voir `data/LISEZMOI.txt`. ⚠ Ne remplacez pas le dossier `data/` lors d'une mise à jour.

## Relier une base de données

Cherchez `>>> BASE DE DONNÉES` dans `server/server.lua` : seules les fonctions `loadStore()` / `saveStore()` sont à remplacer.

## Permissions (optionnel)

Dans `server/server.lua`, passez `UseAcePermission = true` puis dans `server.cfg` :

```
add_ace group.police mdc.use allow
add_principal identifier.license:xxxxxxxx group.police
```
