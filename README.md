# MDC Standalone (FiveM)

Mobile Data Computer de police **100% standalone** (sans ESX / QBCore / vRP), interface NUI en HTML/CSS/Vanilla JS, style sombre moderne : boutons principaux en verre teinté (contour lumineux fin), élément sélectionné en surbrillance claire avec un trait d'accent (couleur réglable : `--accent` / `--accent-rgb` à la fin de `html/style.css`).

## Installation

1. Copiez le dossier dans `resources/` et nommez-le `mdc_standalone` (le nom importe peu, le NUI le détecte automatiquement).
2. Ajoutez `ensure mdc_standalone` dans votre `server.cfg`.
3. En jeu : touche **K** (modifiable dans *Paramètres > Raccourcis clavier > FiveM*) ou `/mdc`. **Échap** pour fermer.

Le dépôt contient aussi le **menu d'interactions / fiches civiles / Eye Target** dans [`rp_interact/`](rp_interact/README.md)
(ressource séparée : un joueur y est « policier » quand il est dans une unité du MDC, voir l'export serveur
`getPlayerUnit(source)` et l'état `Player(source).state.mdcUnit`). Le MDC publie son nom de ressource
(`GlobalState.mdcResource`) : le nom de son dossier n'a pas d'importance.

Le dépôt contient aussi **Vehicle Control** dans [`rp_vehiclecontrol/`](rp_vehiclecontrol/README.md) : essence (plein à
la pompe avec un vrai pistolet, jerrican), dégâts réalistes, ceinture, moteur toujours allumé, portières depuis l'intérieur, clignotants et poussée ; il
alimente le car HUD du MDC.

Le dépôt contient aussi le **chat écrit RP** dans le dossier [`rp_chat/`](rp_chat/README.md) : c'est une ressource
séparée, à copier à part dans `resources/` (voir son README). Elle partage le nom RP avec le MDC et ses réglages
se font dans l'onglet « Paramètres » du MDC. Le MDC fonctionne aussi sans elle.

Et **RP CamShake** dans [`rp_camshake/`](rp_camshake/README.md) : petit script indépendant de tremblement de la caméra
(marche, course, sprint, chocs, accidents).

Et **RP NPC Control** dans [`rp_NPCcontrol/`](rp_NPCcontrol/README.md) : plus de police / pompiers / ambulanciers du
jeu (ni leurs véhicules), plus d'indice de recherche, PNJ qui ignorent les joueurs, densité du trafic et des piétons
de 0.0 à 3.0.

Et **RP Flares** dans [`rp_flares/`](rp_flares/README.md) : fusées de détresse posées au sol (touche G, fusée en main),
retirées avec l'œil, lumière rouge renforcée la nuit.

## Fenêtre

- Déplacement : glisser la barre de titre.
- Redimensionnement : bords et coins de la fenêtre.
- Agrandir / rétrécir : bouton ☐ ou double-clic sur la barre de titre. Bouton ↺ : position par défaut.
- La position est gardée d'une ouverture à l'autre et réinitialisée à chaque reconnexion.

## Disposition de la fenêtre

Interface moderne (mêmes couleurs, plus aucun effet « Windows ») en trois colonnes :
- **à gauche, en haut** : le **nom RP** puis le **statut de l'unité**, à la verticale ; en dessous, les **BOLO
  actifs** (type, numéro, motif ; mis à jour en direct). Chaque BOLO est une case **repliée** : un clic l'ouvre et
  affiche ses détails (description ou véhicule, lieu, détails, date), comme les cases des fiches des Recherches ;
  le bouton **Voir BOLO** ouvre la vraie page des BOLOs (Recherches > BOLOs) sur ce BOLO ;
- **au centre** : le contenu de la page ouverte ;
- **à droite** : les **6 pages à la verticale** (Unités, Interventions, Recherches, Rapports, Créations, Paramètres) ;
- **en bas** : une **case de notes propre à l'unité** (rappels, observations… 160 caractères, partagée par tous ses
  membres, enregistrée automatiquement pendant la frappe ; Entrée pour valider), puis la disponibilité et l'heure.
  La note est **gardée dans l'unité** (serveur) : elle reste en changeant de page ou en rouvrant le MDC ; en changeant
  d'unité, on voit la note de la nouvelle unité, et on retrouve l'ancienne en y revenant.

Tous les boutons colorés de statut sont **carrés** (liste des statuts et listes des unités) ; le statut choisi n'est
plus que légèrement surligné. La fenêtre est **légèrement transparente** (opacité **93 %** par défaut, de 50 à
100 %) et, MDC ouvert, le **jeu** derrière elle est **flouté** (flou des menus du jeu) : une **case** dans
*Paramètres > MDC* l'active ou le désactive. Les **HUD (PLD, display MDC, car HUD) restent toujours nets**. La
**minimap** est dessinée par le jeu par-dessus l'image : aucun flou ne peut l'atteindre, elle est donc **masquée** tant
que le flou est actif, puis réaffichée si elle l'était. Le flou est retiré à la fermeture du MDC et pendant le placement
des HUD.

- **NOM RP** : il s'affiche en haut à gauche et dans les unités (le pseudo Steam/FiveM n'est jamais affiché). **Obligatoire pour
  rejoindre une unité.** Il est partagé avec le chat écrit : `/nomrp John Carter` dans le chat change aussi celui du MDC, et
  inversement. Il n'est enregistré nulle part : il est remis à zéro à chaque déconnexion (état `rpName` du joueur côté serveur).
- **Statut de l'unité** : Disponible (vert), En route (jaune), Sur place (orange), Indisponible (rouge). Le statut est celui de l'unité rejointe.

L'heure affichée en bas à droite du MDC est l'heure du jeu.

## Onglets

| Onglet | Rôle |
|---|---|
| Unités | Trois listes, une par service : **Atlanta Police Department**, **Georgia State Patrol** et **Fayette County Sheriff Office** (chacun voit les trois). Bouton **Créer une unité** par service (service, nom, **tag** au menu déroulant : Aucun, **SUP.** (superviseur) ou **Autre** à saisir, couleur). Chaque unité porte aussi un **tag de service**, séparé du tag spécial : **APD** (bleu foncé), **GSP** (orange vif) ou **FCSO** (vert foncé). Chacun peut rejoindre (4 joueurs max par unité), quitter, modifier ou supprimer une unité (une seule unité à la fois par joueur). Les membres d'une unité partagent leurs recherches et leurs rapports (voir plus bas) |
| Interventions | Une liste par service (**APD**, **GSP**, **FCSO**) et une liste des **appels communs** (appels de plusieurs services, avec leurs tags), affichée seulement s'il y en a et visible par les **trois** services. Policier : la liste de **son service** est en haut et toujours ouverte, la liste commune vient en deuxième et est toujours ouverte, les listes des autres services sont fermées (il peut les ouvrir pour consulter, **sans pouvoir rejoindre** leurs appels). Seuls les **services cochés** peuvent rejoindre un appel (ex. appel GSP & FCSO : visible dans la liste commune par l'APD, mais l'APD ne peut pas le rejoindre ; vérifié par le serveur). Hors unité : APD, communs, GSP, FCSO. Incident : service de l'unité déclarante toujours coché, **cases** pour y ajouter d'autres services (incident commun). Interventions (civils) et incidents (unités) : titre, priorité, adresse, bloc ; chaque ligne est surlignée de la couleur de sa priorité. N° d'incident `XX-XXXX`. Cliquer pour afficher le détail, recliquer (ou **✕** en haut du panneau) pour le masquer : **sans appel choisi, le panneau des détails est réduit à une fine colonne** et la liste prend toute la place. Rejoindre / quitter l'appel (unités uniquement), notes en majuscules modifiables, « Intervention terminée » (grisée dans la liste). Les rapports liés apparaissent avec les notes (ouvrir / modifier) et un rapport peut être rédigé directement depuis l'intervention. **Personnes et véhicules** : les unités sur l'appel y ajoutent les fiches de l'historique des recherches (bouton « Fiche » pour la consulter). Bouton **Nouvel incident** pour les unités |
| Recherches | Identité : nom de famille\* + date de naissance\*, prénom et SSN facultatifs. Véhicule : immatriculation ou VIN. Historique : les nouveaux résultats s'ajoutent en haut, les précédents restent en dessous. Bouton **BOLOs** (en haut à droite) : voir plus bas |
| Rapports | DOT-523 (Georgia Uniform Crash Report), Arrest Report, Incident Report, Citation (identité seule), Traffic Citation (type d'infraction : Excès de vitesse / Conduite / Contrôle, intitulé, description ; sans amende), Convocation, Warning (infraction routière : identité complète avec licence et véhicule ; autre infraction : identité), Incident Report (« Impliqués » : individus et véhicules enregistrés) ; « Charges » pour l'Arrest Report. Les anciens Tickets restent lisibles. Chaque rapport est lié à une intervention / un incident (en cours ou terminé). Liste filtrable (type, texte, mes rapports), lecture, modification par l'auteur. Permanents |
| Paramètres | Trois catégories repliables, toutes fermées à l'ouverture : **MDC** (taille de l'interface, transparence de la fenêtre, flou de l'arrière-plan (le jeu ; HUD toujours nets), case à cocher, onglet à l'ouverture, fenêtre, notifications, son et son volume de 0 à 100 %), **HUD & Display** (PLD, display MDC et car HUD : affichage, éléments visibles, taille, position ; volume des sons du véhicule ; **Menu Interaction** de `rp_interact` : taille, et emplacement avec « Placer les HUD à l'écran », appliqués aussitôt — le menu se montre un instant) et **Chat écrit et commandes** (apparence du chat, affichage des /me, liste des commandes ; ressource `rp_chat`). Gardés chez le joueur, même après une reconnexion |
| Créations | Affichée **uniquement quand le mode civil est activé** (menu d'interactions F1 > Civil, rp_interact). Réservé aux civils : identité, véhicule, intervention (requérant, téléphone généré, priorité, **services de police** en **cases à cocher** (APD, GSP, FCSO : une case = appel réservé à ce service ; deux ou trois = appel commun, rejoignable par les services cochés seulement), **nombre idéal d'unités** (1 à 4), adresse, croisement, bloc, description ; bouton « Position actuelle »). Bouton **Registre** : vos identités et véhicules, modifiables |

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
avec **Modifier** (puis Enregistrer) et **Supprimer** (deux clics). Tous les agents peuvent créer, modifier et
supprimer un BOLO. Dans les Recherches, une fiche visée par un BOLO affiche une alerte (et l'étiquette `BOLO`
dans les résultats) ; une immatriculation correspondant à un BOLO véhicule partiel affiche « Correspondance possible ».

### Unité : espace partagé

Les membres d'une même unité (4 au maximum) partagent en direct :
- les **recherches** : chacun voit l'autre écrire, voit le résultat s'afficher, et l'historique est commun ;
- le **rapport en cours de rédaction** : chacun voit l'autre écrire et peut compléter ; n'importe quel membre peut
  l'enregistrer (une modification de rapport est ouverte par son auteur, puis enregistrable par l'unité) ;
- les **changements de statut** (notification chez chaque membre).

### HUD et notifications

Affichages séparés, au thème du MDC (fond noir transparent, bordure grise fine et arrondie ; le car HUD, lui, sans
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
  l'interface d'un autre script, démarrez `mdc_standalone` **après** lui dans `server.cfg` (la dernière interface
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
- **Display MDC** : affiché seulement dans une unité : « **[N° d'unité] • [SERVICE]** » (ex. `417 • GSP`, tag de
  service APD bleu foncé / GSP orange vif / FCSO vert foncé) suivi du tag spécial (ex. SUP.), statut, n° d'incident (uniquement quand
  l'unité est sur un appel), **secteur** (zone de jeu) et **service principal** (APD, GSP, FCSO ou plusieurs) choisis dans le
  menu d'interactions (`rp_interact`, Police, tout en bas) : « aucun sélectionné » tant que rien n'est choisi. Chaque
  ligne se masque dans « Paramètres ».
- **Car HUD**, à bord d'un véhicule : **toujours affiché pour le conducteur**, entièrement **grisé moteur coupé** et
  qui **s'illumine au démarrage** ; seulement le logo de la ceinture pour les passagers ; **au-dessus de la minimap** et **sans aucun fond** (ni opaque, ni transparent,
  ni coloré ; seulement une ombre portée pour la lisibilité) : la **vitesse en MPH** (un simple nombre), une fine **barre horizontale
  d'accélération** (régime du moteur, rouge près du maximum), une **jauge d'essence verticale** (orange sous 15 %, rouge
  sous 5 %), le petit **logo de la ceinture** (contour noir : vide = détachée, blanc = attachée, clignote en rouge pâle
  en roulant sans ceinture) et, à côté, un **logo du moteur** : **orange** quand le moteur est **très abîmé**
  (palier 1 : il roule lentement, cale, fume), sinon jamais visible sauf quand le moteur est **détruit** (palier 2,
  véhicule hors d'usage) : le car HUD reste alors **allumé, tout en rouge vif clignotant**, ce logo du moteur
  est **rouge foncé, fixe** ; le logo de la ceinture ne clignote plus : attachée, rempli de **rouge fixe** ;
  détachée, seulement son **contour en rouge**, centre transparent, fixe. En montant côté conducteur, une **notification glisse depuis la gauche juste au-dessus
  du car HUD** et présente la touche du moteur (**O**) ; elle disparaît après 8 secondes. Déplaçable et redimensionnable comme les autres HUD ; chaque
  élément se masque dans « Paramètres », avec le volume des sons de la ceinture.
  Les données (essence, dégâts, ceinture, moteur) viennent de **Vehicle Control**
  ([`rp_vehiclecontrol/`](rp_vehiclecontrol/README.md)) : sans cette ressource, le car HUD n'apparaît pas
  (`client/carhud.lua` ne fait que relayer ses données au NUI, sans boucle).
- **Notifications** (en haut à droite) : toutes les notifications du MDC, et, même MDC fermé : nouvel appel
  (titre, service, priorité, adresse, croisement, bloc) et nouvel incident (titre, unité créatrice, adresse,
  croisement, bloc) pour **les membres des unités du service de l'appel uniquement** ; changement de statut pour les
  membres de l'unité.
- **Unités les plus proches** : quand un civil émet un appel, les unités **Disponibles** du service choisi les plus
  proches du civil (autant que le nombre idéal d'unités, 4 max ; jamais une unité au tag **SUP.**, c'est alors la
  suivante qui est choisie) reçoivent à la place une notification différente : « **Vous êtes l'une des unités les plus
  proches** », avec **Y** pour accepter (l'unité est rattachée à l'appel et passe « En route », sans ouvrir le MDC) ou
  **N** pour refuser (30 s pour répondre, `OfferTimeout`). Refus ou sans réponse : l'unité suivante la plus proche est
  sollicitée. Les autres unités du service gardent la notification habituelle et peuvent rejoindre l'appel depuis le
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
