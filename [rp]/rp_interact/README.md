# RP Interact (FiveM)

Menu d'interactions, **fiches civiles** (profils et véhicules) et **Eye Target** (« l'œil »), **100% standalone**
(sans ESX / QBCore / vRP), NUI en HTML/CSS/Vanilla JS. Relié au MDC (`rp_mdc`) et au chat écrit (`rp_chat`)
du même dépôt.

Le but : limiter les échanges écrits entre civils et policiers. Le civil prépare à l'avance ce que la police découvrira
(inspection, fouille, détail notoire) ; le policier l'obtient en visant la personne ou le véhicule avec l'œil.

## Installation

1. Copiez le dossier `rp_interact` dans `resources/` (à côté du MDC et du chat, pas à l'intérieur).
2. Dans `server.cfg` (après le MDC et le chat) : `ensure rp_interact`
3. **OneSync recommandé** : il permet au serveur de vérifier les distances et de supprimer le profil d'un véhicule
   dès que le véhicule disparaît.
4. **Emotes** : les emotes (`/e menotté2`, `/e tenirlebras`, `/e serendre17`…) viennent du mode
   d'emotes du serveur (dossier **RPEMOTES** / rpemotes / rpemotes-reborn), détecté automatiquement
   (`EmotesResource = 'auto'`). Au démarrage, le serveur lit l'**animation exacte** de chaque emote dans ses fichiers
   et l'écrit dans la console : `[RP Interact] Emotes lues dans "RPEMOTES" : menotté2 (…), tenirlebras (…)…`. Une emote
   introuvable est signalée en jaune : vérifiez son nom dans `config.lua` (`Emotes`, `Surrender`) ou ajoutez le
   fichier qui la définit à `EmoteFiles`. `rpi_emotes` (console) relit les fichiers.
5. **Son de la radio** : rien à installer. Le lecteur de ce script fait le son 3D et l'effet étouffé (voir Radio).
   **olisound** (OilPMMS.zip) n'est plus nécessaire ; `RadioEngine = 'olisound'` pour l'utiliser quand même.

**Mode nuit** (réglé dans le MDC : *Paramètres > MDC > Apparence*, appliqué à toutes les interfaces ou aux menus extérieurs) : **fond noir et couleur du mode nuit** (vert, jaune, rouge ou bleu) pour le Menu Interaction, le `/eup`, la fiche civile, l'œil, les résultats, barres, tips et notifications (`client/theme.lua` ; sans le MDC : thème jour).

## Menu Interaction (touche F1)

Un **vrai menu de jeu, au clavier** (comme `/eup`, même apparence), **sans souris** : vous continuez de bouger
pendant qu'il est ouvert. **F1** l'ouvre et le ferme (modifiable : Échap > Paramètres > Raccourcis clavier > FiveM).

| Touche | Action |
|---|---|
| **↑ / ↓** (maintenues : défilement) | choisir une ligne |
| **Entrée** | valider : ouvrir une page, faire l'action, cocher / décocher, écrire dans un champ |
| **→** | ouvrir une page ; sur une liste de valeurs (‹ valeur ›) : valeur suivante |
| **←** | valeur précédente sur une liste ; ailleurs : revenir |
| **Retour arrière** | revenir à la page précédente (sur l'accueil : fermer) |
| **Échap** | fermer |

En haut, une **bannière** (titre de la page, sous-titre, couleur de la partie ou de votre police : bleu WSP, vert KCSO),
puis le chemin (ex. *Menu Interaction › Voiture › Radio*) et le numéro de la ligne choisie ; en bas, l'**aide de la
ligne** et le rappel des touches. Les lignes grisées sont indisponibles (Entrée affiche pourquoi). **Champs de texte**
(secteur, lien de la radio, nom d'un équipement) : Entrée ouvre la saisie (le clavier passe au menu le temps de
l'écrire, Ctrl+V pour coller), **Entrée** valide, **Échap** annule.

L'accueil est en deux parties : **Usage** (**Police**, **Civil**) et **Configuration** (**Équipements**, **Voiture**,
**Météo**).
Le menu est **toujours en haut à gauche**, comme les menus du jeu (il n'est plus réglable), avec une **bannière** de
couleur en haut, comme le `/eup` : le **logo de la police** (WSP, KCSO) y est affiché pour un policier en service
(accueil, page Police) et sur les pages WSP / KCSO du `/eup`. Thème clair du MDC (coins presque carrés) ; la
**fiche civile** est une fenêtre blanche, comme le MDC. Notifications, barres et tips, affichés sur le jeu, restent
sombres. Ouvrir `/eup` ferme ce
menu (un seul menu au clavier à la fois). L'œil (Alt) reste utilisable menu ouvert (les touches du menu attendent).

**Permissions** (`Permissions` dans `config.lua`) — **temporairement désactivées** (`Enabled = false` : tout le
monde a accès à toutes les catégories ; remettre `true` pour les réactiver) : les catégories listées dans `Sections` (par défaut **Équipements**
et **Voiture** : spawn, radio) sont réservées aux joueurs dont l'**identifiant Steam hex** est dans `Players`
(`steam:11000013ca597a9`, `steam:11000011977aecd`, `steam:110000114f6ac4d`). Les autres les voient **grisées**
(« Réservé ») et le serveur refuse leurs demandes. `Sections = {}` : ouvert à tous. Les règles « police en
service » (`SpawnPoliceOnly`, `EquipmentPoliceOnly`) s'appliquent en plus.

Page **Police** : en service ou non (unité et police du MDC choisi : **Washington State Patrol** ou **King County
Sheriff Office**), puis les actions **Menotter**, **Prendre par le bras**, **Placer l'individu à l'arrière du
véhicule** et **Faire s'asseoir l'individu** : toujours affichées, **grisées** tant que personne (joueur ou PNJ) n'est
assez près (2 m ; véhicule à 6 m pour placer), mises à jour en direct. Elles agissent sur l'individu le plus proche (le
menu se ferme). En bas, **Display MDC > Secteur** (zone de jeu, saisi à la main), enregistré aussitôt, gardé chez le
joueur et affiché sur le display du MDC. Il n'y a plus de « service principal » : la police est celle du MDC choisi.
Page **Civil** : rappel du **profil actif**, la case **Mode civil**, puis **Créer un profil** et **Créer un véhicule**
(ouvrent la **fiche civile** et ferment le menu) et, en mode civil, **Tips arrestation**.
Page **Équipements** : **Tenues** → **Accéder aux tenues** (ferme ce menu et ouvre le menu `/eup`, ci-dessous) ;
**Armes** (réservées aux policiers en service, `EquipmentPoliceOnly`) :
- **Équipement WSP**, **Équipement KCSO** : donnent **tout l'équipement de départ** de la police
  (arme de service, taser, lampe, matraque, **10 fusées de détresse** à poser au sol avec `rp_flares`…), en remplaçant
  les armes portées : **toujours l'équipement de base**, jamais modifié automatiquement. Chaque police a **son propre
  équipement** (fichier **`equipment_services.json`**, fourni et modifiable). L'équipement pris est **coché** ; au
  départ, **aucun** : le joueur choisit lui-même.
- **Équipements modifiés** : page des équipements que le joueur a **personnalisés, nommés et enregistrés** (10 au
  maximum, `MaxCustomEquipment`), avec la pastille de leur police. **Entrée** les **équipe** (et les sélectionne) ;
  **→** les modifie. Ils sont **gardés pour toujours** (reconnexion, redémarrage du serveur) et **propres au joueur**
  (sa licence Rockstar) : **lui seul** y a accès. Ceux enregistrés avec les anciens services sont repris
  (GSP → WSP, FCSO → KCSO).
- **Customiser équipement** : reconnaît l'**équipement sélectionné** (de base ou modifié) et propose **uniquement les
  modifications de sa police**. Champ **Nom** (vide : « Équipement WSP modifié »…), puis **un onglet par arme**, qui
  s'ouvre avec un **crochet** comme les onglets du MDC (Entrée / → : ouvrir ; Entrée / ←, ou clic : refermer). Onglet
  ouvert :
  - ses réglages : **Prendre cette arme** (l'arme de service et le taser sont **obligatoires**), ses accessoires
    (case, ou liste ‹ › : lampe, chargeur, viseur…), sa **teinte** ;
  - la **souris apparaît** (seulement là) : le **survol** choisit l'élément (sa description s'affiche), le **clic**
    coche / décoche, passe à la valeur suivante (‹ : précédente) ; clic sur l'en-tête d'un onglet : l'ouvrir / le
    refermer ; molette : élément précédent / suivant. Un clic n'est jamais pris pour « Entrée » (le jeu lie aussi
    le clic gauche à Entrée : ignoré tant que la souris est affichée). Les touches marchent toujours ;
  - **zoom sur l'arme** en main (`EquipmentZoom`) : caméra accrochée au personnage et visée sur sa main droite par
    le jeu (pas de recalage à chaque image, pas d'à-coup quand un accessoire change) ; le personnage reste immobile ;
    le cadrage dépend de la **taille de l'arme** : proche pour les armes de poing et les petits objets, **plus loin
    et plus large** pour les armes longues (fusils, fusils à pompe, précision, mitrailleuses : `EquipmentZoom.Long`) ;
  - chaque changement est **visible tout de suite** : l'arme est **équipée automatiquement** (accessoires mis /
    retirés, teinte), plus besoin d'« Équiper ».
  Reste **Enregistrer** : depuis un équipement de base, il **s'ajoute** aux Équipements modifiés (l'équipement de base
  ne change pas) ; depuis un équipement modifié, il le **met à jour**. **Supprimer cet équipement modifié** (Entrée
  deux fois). Le serveur revérifie chaque choix (seulement ce que le fichier prévoit pour cette police).
- **Autres armes** : lots de **`data/loadouts.json`** (facultatif, affiché s'il en contient) ; **Retirer mes armes**.
Page **Voiture** :
- **Spawn** : en haut, deux cases gardées chez le joueur : **Supprimer l'ancien véhicule** (le dernier que vous avez
  fait apparaître, s'il n'y a pas d'autre joueur dedans) et **Apparaître dans le véhicule** (sinon devant vous). Puis
  une page par **catégorie principale** (`Principale` : Police, Civil…), avec les véhicules **groupés par
  sous-catégorie** (`subCategory`, avec la pastille WSP / KCSO pour ces polices). Seuls les véhicules de
  **`data/vehicle.json`** sont proposés :
  ```json
  { "vehicles": [
      { "spawnName": "wspcharger", "Principale": "Police", "subCategory": "Washington State Patrol",
        "menuName": "Dodge Charger 2020", "extras": { "1": true } },
      { "spawnName": "police3", "Principale": "Police", "subCategory": "King County Sheriff Office",
        "menuName": "Interceptor", "extras": {} }
  ] }
  ```
  `menuName` : nom affiché ; `extras` : `true` activé / `false` désactivé (s'il y en a, ceux qui ne sont pas listés
  sont désactivés ; `{}` : extras d'origine) ; `livery` facultatif. Le même `spawnName` peut être listé plusieurs fois
  (extras différents). Catégorie **Police** : réservée aux policiers en service (`SpawnPoliceOnly`). Attention au JSON :
  pas de virgule après le dernier élément, guillemets fermés. L'ancien `data/vehicles.json` n'est lu qu'en l'absence de
  `vehicle.json`.
  `rpi_vehicles` (console) relit les fichiers JSON. Le véhicule apparaît moteur coupé, plein fait (Vehicle Control).
- **Radio** : **Lien** (Entrée, collez le lien d'une vidéo / musique YouTube, ou un lien direct vers un fichier audio,
  un podcast, une radio en ligne, Entrée) puis **Lancer ce lien** : le son est joué **dans le véhicule**, tel quel
  (lecteur YouTube, ou lecteur audio pour un lien direct ; aucun effet ajouté). Tout le monde l'entend **au même moment
  et au même volume de base**. À bord : normalement. Dehors, plus bas avec la distance : entendu jusqu'à **15 m** tout
  fermé (`RadioRangeClosed`, volume réduit : `RadioInsulation`) et **25 m** avec une portière (coffre, capot) ouverte
  ou une vitre baissée (`RadioRangeOpen`). Seules les vitres que le véhicule possède comptent.
  **Ajouter à « Écouter ensuite »** : met le lien dans la file (jusqu'à **5** morceaux ; radio éteinte : il est lancé
  tout de suite). À la fin d'un morceau, le suivant démarre pour tout le monde. Une ligne de la file : Entrée la retire.
  Passé directement dans un **nouveau véhicule** depuis une place avant (Spawn, avec Vehicle Control) : la radio de
  l'ancien véhicule, laissé vide à l'avant, **s'arrête**.
  **Morceau en cours**, pour tout le monde : **Pause / Reprendre** (reprend là où il était, au même moment pour tous) ·
  **Début du morceau** (**deux fois** en moins de 2,5 s : **morceau précédent**, 5 gardés) · **Morceau suivant** ·
  **Arrêter la radio** (vide la file) · **Volume du véhicule** (← →, par pas de 5 %).
  Réglable seulement par les **places avant**, ou avec l'**œil** en visant l'intérieur avant du véhicule, **portière
  avant ouverte** (option « Radio du véhicule » : le menu s'ouvre, ou va, sur la page Radio).
  **Son 3D et effet étouffé** (lien audio direct : mp3, ogg, m4a, radio en ligne…) :
  - on entend **de quel côté** est le véhicule, d'après la **caméra** : à gauche, à droite, devant, **derrière**
    (spatialisation HRTF ; un véhicule derrière soi sonne aussi un peu plus sourd : `RadioBehindHz`) ;
  - dehors, **portières et vitres fermées** : son **étouffé** (aigus coupés au-dessus de `RadioMuffleHz`, 550 Hz),
    comme une musique entendue à travers la carrosserie ; une portière ou une vitre ouverte : son clair ;
  - à bord : normal, devant soi.
  Si le site du lien refuse que le jeu traite son son (en-tête CORS absent), la musique est jouée **sans effet**.
  **Lien YouTube** : le lecteur YouTube ne laisse **aucun** effet s'appliquer (ni son 3D, ni étouffé : c'est une
  limite de YouTube, pas réglable) ; seul le **volume selon la distance** marche. La page Radio l'indique. Pour avoir
  les effets avec YouTube, il faut un service à vous qui renvoie l'audio de la vidéo avec l'en-tête CORS
  (`RadioYouTubeAudio`, ex. `'https://audio.mon-serveur.fr/yt/{id}'`).
  **pma-voice** : il ne transporte que la **voix des joueurs** (micro) ; il ne peut pas diffuser une musique depuis un
  lien. La musique est donc jouée par le navigateur du jeu (NUI), avec les mêmes règles de distance.

**En service** = dans une unité du MDC : dès que vous rejoignez une unité, les fouilles et détails notoires
apparaissent dans l'œil (notification) ; dès que vous la quittez, ils sont retirés (et refusés par le serveur).

## Menu des tenues (`/eup`)

S'ouvre avec **`/eup`** dans le chat écrit (même sans nom RP défini avec `/nomrp`), ou par **Menu Interaction >
Équipements > Accéder aux tenues**. Même menu **au clavier** que le Menu Interaction (pas de souris, vous pouvez
continuer à bouger), en haut à gauche : **↑ / ↓** (maintenues : défilement), **Entrée** ou **→** pour ouvrir / mettre
la tenue, **← / Retour arrière** pour revenir, **Échap** pour fermer (`/eup` à nouveau aussi). Bannière sobre, à la
couleur de la police ouverte (bleu WSP, vert KCSO).
- **Police** : **Washington State Patrol (WSP)** et **King County Sheriff Office (KCSO)**, puis les autres polices
  trouvées dans le fichier (ex. `NCSHP`) ;
- **Civil** : la liste des tenues civiles (ou leurs groupes, si vous en indiquez dans `Category2`).
Seules les tenues du personnage (**homme / femme**, personnage multijoueur) sont listées ; la tenue mise est cochée.
Les tenues se configurent **uniquement dans `[rp]/rp_interact/data/outfits.json`** (relu avec `rpi_vehicles` en
console ou au redémarrage de la ressource) : une **liste** `[ ... ]`, un objet par tenue, au format EUP habituel
(le fichier fourni contient 3 tenues d'exemple à remplacer par les vôtres) :

```json
{
    "Name": "NCSHP Class Regular", "Gender": "Male", "Category": "EUP", "Category2": "NCSHP", "Cate": "Police",
    "Hat": "24:1", "Glasses": "0:0", "Ear": "0:0", "Watch": "0:0", "Mask": "0:0", "Top": "38:1",
    "UpperSkin": "87:1", "Decal": "0:0", "UnderCoat": "330:1", "Pants": "240:1", "Shoes": "28:2",
    "Accessories": "244:1", "Armor": "15:1", "Parachute": "13:1"
}
```

- `Cate` : `Police` ou `Civil` ; `Category2` : la police (`WSP`, `KCSO` ou leur nom complet ; autre valeur =
  autre police, listée à part) ; `Gender` : `Male` / `Female` (absent : les deux) ; `Category` n'est pas utilisé.
- Chaque pièce : `"modèle:texture"`, **comptés à partir de 1** comme dans les menus EUP habituels (`Eup.OneBased`,
  `false` si vos numéros commencent à 0). Accessoires (`Hat`, `Glasses`, `Ear`, `Watch`, `Bracelet`) à `0:0` :
  retirés. Pièces : `Mask` (1), `UpperSkin` (3, bras), `Pants` (4), `Parachute` (5, sac), `Shoes` (6),
  `Accessories` (7), `UnderCoat` (8), `Armor` (9), `Decal` (10), `Top` (11).
- Une virgule en trop ou un guillemet manquant rend le fichier invalide : la console serveur l'indique.
- `Eup.PoliceOnly = true` réserve les tenues de police aux policiers en service (par défaut : tout le monde, pour
  pouvoir s'habiller avant de prendre son service). `Eup.Command` : nom de la commande.

### Modifier ma tenue (`data/modifoutfits.json`)

Bouton **Modifier ma tenue**, sous la liste (Police, Civil) : ajoute ou retire des **pièces** (gilet, casquette,
lunettes…) à la tenue que vous portez, selon son **service** :
- le service est celui de la **dernière tenue mise avec `/eup`** (WSP, KCSO, autre police du fichier, ou Civil) ;
  sans tenue mise avec `/eup` : la police de votre unité du MDC, sinon Civil. La ligne **Service** (← →) permet d'en
  choisir un autre ;
- la tenue actuelle est **lue sur le personnage** : une pièce déjà portée est **cochée** ; **Entrée** la met, ou la
  retire (la pièce de la tenue d'origine revient ; un accessoire de la tenue d'origine est enlevé) ;
- **Remettre la tenue d'origine** : la tenue telle qu'elle était (mise avec `/eup`, ou à la première ouverture de
  « Modifier ma tenue »).

Les pièces se configurent dans **`[rp]/rp_interact/data/modifoutfits.json`** : une liste par service (`WSP`, `KCSO`,
`Civil`, une autre police du fichier des tenues, ou **`Tous`** : proposée pour tous les services). Une pièce = un nom
et **une ou plusieurs parties**, avec les mêmes noms et le même format que `outfits.json` (`Hat`, `Glasses`, `Ear`,
`Watch`, `Bracelet`, `Mask`, `UpperSkin`, `Pants`, `Parachute`, `Shoes`, `Accessories`, `UnderCoat`, `Armor`,
`Decal`, `Top`) :

```json
{
    "WSP": [
        { "Name": "Gilet de Haute Visibilité", "Category": "Gilets", "Gender": "Male", "Armor": "110:1" },
        { "Name": "Chapeau de campagne", "Category": "Couvre-chefs", "Hat": "14:1" }
    ],
    "KCSO": [ { "Name": "Casquette KCSO", "Gender": "Female", "Hat": "46:1" } ],
    "Civil": [ { "Name": "Veste en cuir", "Gender": "Male", "Top": "7:1", "UpperSkin": "1:1" } ],
    "Tous": [ { "Name": "Sans couvre-chef", "Hat": "0:0" } ]
}
```

- `Category` (facultatif) : les pièces d'une même catégorie sont regroupées dans un sous-menu ; `Gender` (facultatif) :
  `Male` / `Female`, sinon pour les deux. Accessoire à `0:0` : l'enlever (ex. « Sans couvre-chef »).
- Numéros comptés comme dans `outfits.json` (`Eup.OneBased`). Relu avec `rpi_vehicles` (console) ; une pièce sans
  `Name` ou sans partie est ignorée (la console l'indique).
- Avec `Eup.PoliceOnly = true`, les pièces des polices ne sont envoyées qu'aux policiers en service.

## Mode civil (case à cocher, gardée chez chaque joueur)

Ajoute des options visuelles propres au rôle de civil. La première : les **tips d'arrestation**, un mini menu
**non interactif** en haut au milieu de l'écran :

| Touche (par défaut) | Action | Commande lancée |
|---|---|---|
| **H** | Mains en l'air | `/e serendre17` |
| **J** | À genoux | `/e serendre3` |
| **L** | S'allonger | `/e serendre6` |
| **X** (fixe) | Arrêter l'emote en cours | arrêt par RPEMOTES (export `EmoteCancel`) |

- Il apparaît quand un **policier** (joueur dans une unité du MDC) vous **met en joue avec une arme** : visée directe
  ou à moins de **5 m** autour de vous (titre « Un policier vous tient en joue »).
- Sans mise en joue : Menu > Civil > **Tips arrestation** l'affiche.
- La case est publiée au serveur (état `rpiCivilMode`), pour les autres scripts. Portes (`rp_doorlock`) : tout joueur
  qui n'est pas policier en service (civil ou sans rôle) peut **verrouiller / déverrouiller** une porte.
- Il ne se ferme **qu'avec la touche Échap** (rappel « Échap : fermer » écrit en tout petit, en gris foncé, en bas du
  mini menu) : il **reste affiché quand le policier arrête de viser** (le titre redevient « Tips arrestation »).
  Pendant qu'il est affiché, Échap ferme les tips **sans ouvrir le menu pause ni la carte** (la pause reste bloquée
  jusqu'au relâchement de la touche).
- Les touches ne font l'emote **que pendant que le mini menu est affiché** (et jamais quand une fenêtre est ouverte).
  Chaque touche est un **raccourci de la commande `/e …`** de RPEMOTES (exactement comme si le joueur la tapait).
- **X** : l'emote est arrêtée par RPEMOTES lui-même (export `EmoteCancel`), ce script prend le dessus sur le X de
  RPEMOTES : plus de message « ^1Help^0 : No emote to cancel ». (Ancienne version de rpemotes sans cet export :
  `/e c` n'est envoyé que si une emote est réellement jouée.)
- Touches modifiables par chaque joueur : Échap > Paramètres > Raccourcis clavier > FiveM > « Civil : … ».
  Commandes et touches par défaut dans `config.lua` (`Surrender`).
- **Détection fiable** côté policier : tant qu'il est en service (unité du MDC), sa visée est surveillée en continu
  (aucune touche à maintenir : clic droit, manette ou raccourci modifié fonctionnent), les joueurs visés sont
  envoyés au serveur toutes les 150 ms pendant la visée et confirmés chaque seconde ; le serveur vérifie l'unité et la
  distance, et la mise en joue expire seule si le policier se déconnecte. Le civil doit avoir coché **Mode civil**.

Thème : celui du HUD (contour gris fin, angles légèrement arrondis), fond noir foncé transparent à 20 %.

### Configuration > Météo (météo et heure du serveur, pour tout le monde)

| Réglage | Choix |
|---|---|
| **Temps** | grand soleil, dégagé, nuageux, couvert, éclaircies, brumeux, brouillard, pluie, orage, neige légère, neige, blizzard, Noël, Halloween (`Weather.Types`) |
| **Défilement de la météo** | **Fixe** (ne change plus) ; **Beau temps** (passe d'un temps clair à un autre : grand soleil, dégagé, nuageux) ; **Pluvieux** (pluie, orage, brumeux, brouillard) ; un nouveau temps toutes les 20 min (`CycleMinutes`), en douceur |
| **Coupure de courant** | éclairage de la ville éteint (lampadaires, bâtiments) ; les phares des véhicules restent allumés |
| **Neige au sol** | sol enneigé + traces des véhicules et des pas, avec n'importe quel temps (automatique avec Noël et les temps de neige) |
| **Heure** | à la minute près (champ « HH:MM », ex. 21:45) |
| **Défilement du temps** | **Fixe** (l'heure ne bouge plus) ; **De base** (rapide : 2 s par minute du jeu, comme GTA) ; **Réaliste** (40 000 ms par minute du jeu : une journée en 16 h, `RealisticMs`) ; **Personnalisé** (secondes réelles par minute du jeu, de 0,1 à 600 : 60 = temps réel) |
| **Accès public** | (administrateurs seulement) ouvre le réglage à tout le monde ; décoché : réservé aux administrateurs |

On règle tout, puis **« Appliquer à tout le serveur »**. La ligne du haut rappelle l'état actuel. Réglages gardés après un
redémarrage (`data/weather.json`). Administrateurs : joueurs de `Permissions` (section **weather**) — tant que les
permissions sont désactivées, **tout le monde** — ou ceux qui ont la permission ACE `rp_interact.weather`
(`add_ace group.admin rp_interact.weather allow`).

**Une seule autorité.** vMenu a sa propre synchro de la météo et de l'heure (`vmenu_enable_weather_sync`,
`vmenu_enable_time_sync`, plus sa météo dynamique) : avec les deux, l'heure et le temps « sautent » d'un script à l'autre.
Avec `Weather.TakeOverVMenu = true` (par défaut), rp_interact coupe la synchro de vMenu au démarrage (convars répliqués) :
ses menus Météo / Heure disparaissent aussi. Vaut pour les joueurs qui se connectent ensuite (ceux déjà connectés avant
le démarrage de rp_interact se reconnectent une fois). Pour le faire aussi dans la config de vMenu (`permissions.cfg`) :
`setr vmenu_enable_weather_sync false`, `setr vmenu_enable_dynamic_weather false`, `setr vmenu_enable_time_sync false`.
Désactivez aussi vSync / qb-weathersync / la météo de txAdmin s'ils sont lancés (ou mettez `Weather.Enabled = false` ici).
Le serveur tient l'heure et la republie toutes les 15 s (`SyncSeconds`) ; chaque joueur avance avec sa propre horloge à
partir de là (petits écarts rattrapés en douceur, jamais de saut). La météo, une fois la transition finie, est fixée
(comme vSync) et vérifiée toutes les 5 s, ainsi que la coupure de courant et la neige.

## Fiche civile (style MDC, en dehors du MDC)

S'ouvre par Menu Interaction > Civil (**Créer un profil** / **Créer un véhicule**) ou par la commande **`/fichecivil`**
(`EditorCommand` ; à nouveau : la ferme).

### Profils (permanents : `data/profiles.json`)

Liste de **vos** profils uniquement (20 max). Cliquer sur un profil affiche son détail avec **Définir comme profil
actif**, **Modifier** (puis Enregistrer) et **Supprimer**. Le premier profil créé devient actif automatiquement.

| Partie | Cases | Non coché / vide |
|---|---|---|
| Nom du profil | obligatoire | — |
| **Inspection** — *Observations visuelles et olfactives* | ☐ Visuel, ☐ Olfactif | « Rien à signaler » / « Rien d'anormal » / « Tout est correct » |
| **Fouille** — *Contenu de ce que détient votre personnage* | ☐ Partie supérieure du corps, ☐ Partie inférieure du corps | « Rien à signaler » / « Aucun élément » / « Rien d'illégal » |
| **Détail notoire** | texte facultatif | « Aucun détail notoire » |

Pour une même personne, la réponse par défaut choisie dans la liste est toujours la même.

### Odeur détectée automatiquement (profil et véhicule)

Dans **Inspection** (profil) et **Inspection olfactive** (véhicule) : des pastilles à cocher, **2 odeurs au plus**
(combinables), facultatif. Un **policier en service** (unité du MDC) qui passe à **moins de 6 m** du joueur civil
(profil **actif**) ou du véhicule qui a le profil reçoit aussitôt, en haut au milieu de l'écran, une notification
comme l'entrée dans une zone de recherche de `/scene` : **ODEUR DÉTECTÉE · Individu à proximité** (ou *Véhicule à
proximité*) et ce qu'il sent (« Une odeur d'alcool et une odeur de cannabis fumé. »), avec un court son. Une fois par
source tant qu'il reste à côté ; de nouveau après s'être éloigné et une minute (`Smell.Cooldown`). Les odeurs
s'ajoutent aussi au résultat de l'**inspection olfactive** (avant le texte écrit par le joueur).

| Groupe | Odeurs (`config.lua` : `Smells`) |
|---|---|
| Drogues | Cannabis (herbe), Cannabis fumé, Méthamphétamine (ammoniaque / solvant), Crack fumé (plastique brûlé), Héroïne (vinaigre), PCP (éther), Opium fumé (fumée douceâtre), Lean (sirop codéiné) |
| Alcool | Alcool, Alcool fort (haleine chargée) |
| Autres | Tabac froid, Poudre (tirs récents), Essence, Brûlé / fumée, Sang, Décomposition, Javel / produits ménagers, Parfum très fort, Vomi |

La cocaïne n'y est pas : elle ne sent presque rien. Seuls les policiers en service reçoivent la liste des odeurs
(jamais les autres joueurs) ; un joueur entré dans une unité du MDC n'a plus d'odeur de profil.

### Véhicule (temporaire)

Le véhicule dans lequel vous êtes, sinon le plus proche (6 m). Le profil est **lié au véhicule physique** : il disparaît
quand le véhicule est supprimé ou au redémarrage du serveur, et n'est pas enregistré dans vos profils. Seul son créateur
peut le modifier ou le supprimer.

| Partie | Non rempli |
|---|---|
| ☐ **Inspection visuelle** → Intérieur, Extérieur | « Rien d'anormal » / « Tout semble normal » / « Rien de suspect » / « Rien à signaler » |
| **Inspection olfactive** (texte) + **odeur détectée automatiquement** (2 au plus) | « Rien d'anormal » / « Rien de suspect » |
| **Détail notoire** | « Aucun détail notoire » |
| **Fouille** : Habitacle, Banquette arrière, Coffre | « Rien à signaler » / « Aucun élément » / « Rien d'illégal » |

## Eye Target (maintenir Alt)

Un œil apparaît au centre de l'écran ; il s'allume (bleu) quand la cible propose des options, avec son nom.
**Clic gauche** : liste des options, à droite de l'œil et **centrée verticalement sur lui** (défile si elle est plus haute que l'écran) ; clic sur une option pour l'exécuter. **Échap**, clic droit ou clic à côté : fermer.

Options rangées par **groupes**, séparés par un trait : **inspections et détail notoire** (personne, véhicule,
occupant) · **fouilles** · **actions de police** · **ouvrir / fermer la portière visée** · le reste · tout en bas,
les options « en bas de liste » d'un script (`last = true` : **Pousser le véhicule** de Vehicle Control…).
Options **principales** mises en avant (surlignées dans la couleur du thème) : les **inspections et le détail
notoire**, ce qui est **visé précisément** (portière visée, radio, banc, poubelle, objet d'un autre script, porte de
`rp_doorlock`, herse au coffre ou au sol…) et **les options de police** (sauf « Faire s'asseoir / se relever ») ;
**« Monter (place visée) » n'est pas surlignée**. Un script de l'œil peut en proposer avec `primary = true`. Les
options sont plus espacées.

Fonctionne partout : **tous les joueurs**, **les PNJ**, **vous-même** (test : visez votre personnage en vue à la
3e personne, `AllowSelfTarget`), **tous les véhicules** (avec ou sans profil, enregistrés ou non) et les objets configurés.

| Cible | Tout le monde | Policier (dans une unité du MDC) en plus |
|---|---|---|
| Personne | Inspection visuelle, Inspection olfactive (10 m) | Détail notoire (10 m) ; Fouiller la partie supérieure / inférieure du corps (3 m, **6 s** chacune) ; Menotter / Retirer les menottes, Prendre / Lâcher le bras, Faire s'asseoir / se relever (2 m) |
| Véhicule | Inspection visuelle intérieure / extérieure, Inspection olfactive (10 m), puis **Inspection visuelle / olfactive de l'occupant le plus proche** (conducteur, passager avant…, selon la portière dont on est le plus près ; seul à bord : lui) | Détail notoire (10 m) ; Fouille de l'habitacle, de la banquette arrière, du coffre (3 m, **35 s**) ; Placer l'individu à l'arrière du véhicule (portière arrière **visée**, 6 m, bras **lâché**, un joueur civil à moins de 4 m de cette portière, place libre) ; Faire sortir l'individu (arrière) |

- **Occupants d'un véhicule** : on peut aussi viser directement la personne assise (si le rayon l'atteint, par
  une vitre ouverte par exemple) : ses options de personne s'affichent. Sinon, en visant le véhicule, les
  inspections de l'occupant le plus proche sont proposées juste après celles du véhicule.
- **Distances** : les observations se font jusqu'à **10 m**, les fouilles à **3 m**, menottes et bras à **2 m**. Les options
  apparaissent au fur et à mesure qu'on s'approche (elles ne sont jamais grisées pour une question de distance).
  Seule exception : **Supprimer**, proposée jusqu'à **50 m** (`DeleteDistance`) aux joueurs autorisés ; c'est la seule
  option visible au-delà de 10 m.
- **Fouilles** : barre de chargement (thème du HUD, barre bleue) — **6 s** par partie du corps (supérieure / inférieure) pour une personne, **35 s** pour un véhicule.
  Pendant la fouille on ne se déplace pas ; **X** l'annule (elle s'interrompt aussi si la cible s'éloigne). Le serveur ne
  donne le résultat qu'une fois le temps écoulé.
- Une personne est toujours présentée comme « **Individu** » : ni identité, ni nom du profil actif, ni mention PNJ.
- **Corps** laissé sur place par un joueur réanimé ([`rp_revive`](../rp_revive/README.md)) : présenté comme
  « **Corps** », avec la description du **profil actif** du joueur au moment de sa mort (sans l'odeur détectée
  automatiquement) ; inspections et fouilles, mais ni menottes ni « prendre par le bras » (export serveur
  `rememberCorpse(source, netId)`).
- Les résultats d'une personne sont **ceux de son profil actif** ; sans profil (ou PNJ) : réponses par défaut.
- Les inspections sont listées en premier, puis les actions sur l'environnement :
  - véhicule : **ouvrir / fermer la portière visée** (avant gauche, avant droite, arrière…), le capot ou le coffre,
    **monter** à la place correspondante (si libre ; impossible si le véhicule est verrouillé). Une portière ouverte
    ainsi est **refermée par le joueur** dès qu'il est à bord et que le véhicule commence à avancer. **Tout le monde**
    peut monter dans **tous** les véhicules, y compris ceux de police, en tout temps et en tout lieu ;
  - personne : saluer ;
  - **props posé avec le script de props du serveur** (dossier `props`) : **Déplacer le props** (il suit la visée au
    sol, jusqu'à 6 m de vous ; ← / → ou molette : tourner ; **E** : poser ; **Retour arrière** : annuler) et
    **Supprimer le props**, à 3 m (`Props` dans `config.lua` : distance, accès `everyone` / `police` / `owner`).
  - **Objets d'autres scripts** reconnus par leur état (`ExternalObjects` dans `config.lua`) : par défaut la **fusée
    de détresse** posée avec `rp_flares` (« Fusée de détresse » sous l'œil) : **Retirer la fusée** (à 2,5 m), et le
    **plot de circulation** posé avec `rp_equipment` : **Ramasser le plot** ou **Ramasser les plots autour** (tous
    ceux posés près de lui, d'un coup ; policiers en service), et l'**arme lâchée** avec `rp_RoleplayZone`
    (« Arme au sol ») : **Ramasser l'arme** (à 2 m, avec ses munitions, tout le monde). Un objet peut avoir plusieurs
    actions (`Options`). Ces objets sont aussi trouvés quand le rayon touche le **sol juste à côté** (`ExternalSnap`,
    0,7 m) : une arme couchée est très fine à viser.
  - **Herse de Riven en main** (`riven_spikes` : herse tenue, cordon tenu, lancer) : **priorité à Riven** (ses touches
    E, G, X, Q, molette). L'œil ne propose que les options passées par `ox_target` (ranger la herse au coffre…) ; le Menu
    Interaction (F1), `/eup` et les touches des tips d'arrestation ne s'ouvrent pas (« Herse en main : posez-la,
    lancez-la ou rangez-la d'abord. »). Pareil dans les autres scripts : MDC (K), menu Équipement (E) et pose d'un plot
    (G) de `rp_equipment`, `/trafic`, `/scene`, œil d'aigle et lâcher son arme (G) de `rp_RoleplayZone`, pose d'une
    fusée (G) de `rp_flares`, pousser un véhicule (K) de `rp_vehiclecontrol`.
  - **Options d'autres scripts** (`TargetProviders`, par défaut `rp_RoleplayZone`, `rp_doorlock`, `rp_vehicleprops`, `rp_taser10`, `rp_vehiclecontrol` et `ox_target`) : ajoutées à l'œil,
    y compris sur un **point du sol ou d'un mur** (aucune entité : « Lieu ») ; ex. **Fouiller les lieux / l'objet / le
    véhicule** et **Modifier la description** des scènes de `rp_RoleplayZone`, **Verrouiller / Déverrouiller /
    Frapper à / Enfoncer la porte** de `rp_doorlock`, **Ajouter / Déplacer / Retirer un objet** sur un véhicule de
    `rp_vehicleprops`, **Retirer les sondes du Taser** / **Recharger le Taser** de `rp_taser10`, **Nettoyer les débris** d'un accident de
    `rp_vehiclecontrol`. Le script fournit les exports client
    `targetOptions(info)` -> `{ label, options = { { id, label, icon } } }` et `targetSelect(id, info)`.
  - **Secteur d'une scène de roleplay** (`SceneResource`, `rp_RoleplayZone` : zone / lieu / objet + 70 m) : **ni
    « Supprimer » ni « Supprimer le props »** à l'œil, et le serveur refuse la suppression (rien ne doit disparaître).
    Les **portes** reconnues par `rp_doorlock` (export `isDoor`) ne sont jamais proposées à la suppression.
    Reconnaissance automatique (OneSync) : à chaque objet créé par un script, le serveur demande à son créateur quel
    script l'a fait apparaître ; si c'est `props`, l'objet est marqué pour tout le monde. Votre script de props peut
    aussi marquer ses objets (`exports.rp_interact:registerProp(entity)`) ou être reconnu par un état / un export
    (`StateKeys`, `Export`), et être prévenu des suppressions / déplacements (`DeletedEvent`, `MovedEvent`, pour sa
    sauvegarde) ;
  - **Supprimer** (jusqu'à **50 m**) : PNJ, véhicule sans joueur à bord, objet — **y compris les véhicules et objets
    créés par des joueurs ou des scripts**. Ouvert à **tous les joueurs** (`DeleteAccess = 'everyone'` ;
    `'police'` pour le réserver aux policiers en service, ou permission ACE `rpinteract.delete`). Jamais un joueur, ni un véhicule où se trouve un joueur. Avec OneSync, le serveur supprime
    l'élément pour tout le monde ; s'il est encore là, le client en prend le contrôle et le supprime. Une notification
    confirme « Élément supprimé. » (ou explique l'échec). Les objets de la carte sont masqués chez tous les joueurs
    (`rpi_showprops` en console pour tout réafficher) ;
  - bancs, chaises, abribus : **s'asseoir** (à la place la plus proche sur un banc ; X ou se déplacer pour se lever) ;
  - poubelles, bennes : fouiller la poubelle.
- Le résultat est **privé** : la fiche « Résultat » (à droite de l'écran) et sa copie dans le chat écrit (étiquette
  `PRIVÉ`) ne s'affichent que chez le joueur qui inspecte.
- L'annonce RP, elle, est publique : un `/me` automatique (mêmes règles qu'un `/me` : joueurs dans un rayon de 50 m)
  « observe attentivement l'individu », « fouille le coffre du véhicule »…
- Véhicule observé : seul le **modèle** est affiché (jamais la plaque d'immatriculation).
- Le serveur revérifie tout : police (unité du MDC), distances (10 m / 3 m / 2 m), durée des fouilles, délais.

### Police : menottes, prendre par le bras, véhicule (joueurs ET PNJ, pour tester seul)

- **Menotter** (2 m, **7 s** de barre) : **comportement de base de GTA 5**, sans emote : menottes du jeu
  (`SetEnableHandcuffs`) et animation « mains dans le dos » du jeu (`CuffAnim` : `mp_arresting idle`), avec les
  menottes aux poignets (`p_cs_cuffs_02_s`, dans leur toute première position). Si l'animation s'arrête (bousculé,
  monté dans un véhicule…), elle est **relancée automatiquement** ; menotté, il ne peut plus courir, sauter, frapper,
  viser ni monter seul dans un véhicule (les menottes du jeu sont levées le temps d'être placé / sorti par un
  policier). **Retirer les menottes** : 3 s.
- **Prendre par le bras** (individu le plus proche, 2 m ; joueur ou PNJ) : le policier fait **`/e tenirlebras`**,
  l'individu est **tenu de force** à sa droite, un peu devant (`DragOffset`). Il est accroché au **centre** du
  policier (pas à un os : l'os du bassin le couchait à 90°) : il reste **droit**, sur son propre axe, et tourne avec
  le policier. Il **marche quand le policier marche**, trottine s'il trottine, recule s'il recule, et **s'arrête quand
  il s'arrête** (ses jambes suivent la vitesse du policier, `DragMove` / `DragMoves`). **Menotté** : mains dans le dos
  (menottes du jeu, marche menottée) ; **pas menotté** : démarche normale du personnage, aucune emote. Accroché une
  seule fois (pas de ré-accrochage). Le policier qui le tient **ne peut pas sprinter** ni sauter. L'individu ne peut
  ni bouger seul, ni sauter, ni frapper, ni viser.
  Policier au sol : l'individu est décroché le temps qu'il se relève, puis raccroché. **Lâcher le bras** (œil,
  menu) ou touche **X** (`DragReleaseKey`, modifiable : Raccourcis clavier > FiveM > « Police : lâcher le bras »).
- **Se débattre** (tenu par le bras **sans être menotté**) : une jauge apparaît, **ESPACE** à répétition (`Struggle.Key`)
  la remplit, elle redescend toute seule. Chaque appui **fait trembler l'écran** du civil **et** celui du policier.
  Jauge pleine : il **se dégage** (le policier le lâche ; impossible de le reprendre pendant 5 s). Si **un autre
  policier** arrive à moins de **2 m** pendant qu'il se débat, il **perd** : plus moyen de se débattre jusqu'à ce qu'on
  le lâche. Si un ou plusieurs autres policiers étaient **déjà là** quand il a commencé, il peut se débattre, mais a
  **85 %** de chances de perdre en remplissant la jauge (`Struggle.LoseChance`). Décidé par le serveur (distance des
  autres unités de police en service).
- **Faire s'asseoir l'individu** (2 m, à pied, **menotté uniquement**, pas tenu par le bras) : il fait l'emote
  **`/e menotté2`** (RPEMOTES) et **reste assis** (déplacements bloqués). Si l'emote s'arrête, c'est **la même**
  (`/e menotté2`, puis son animation exacte lue dans RPEMOTES) qui est relancée : plus de changement d'emote.
  La pose assise est celle de l'emote, telle quelle (plus d'inclinaison).
  **Faire se relever l'individu** : l'emote assise est arrêtée, il reprend la posture menotté du jeu. Le prendre par le
  bras ou le placer dans un véhicule le relève aussi.
- **Menottes** : position réglable (`CuffPropPlacement`, par défaut leur toute première position : rotation
  265 / 155 / 80, prévue pour l'animation du jeu).
- **Placer l'individu à l'arrière du véhicule** : le policier **lâche d'abord le bras** (X), puis **vise la portière
  arrière** avec l'œil (6 m) : l'option n'apparaît que sur une portière arrière, si un **joueur civil** (pas dans une
  unité du MDC) est à **moins de 4 m de cette portière** et que la place est libre (`PlaceDoorDistance`). La portière
  **s'ouvre toute seule**, l'individu **monte lui-même** (sans téléportation), même dans un véhicule d'urgence.
  **Le civil ne ferme jamais la portière** : le jeu ne la referme pas, et elle est **gardée ouverte** (le joueur qui
  contrôle le véhicule la rouvre si elle se ferme) jusqu'à ce qu'**un policier** la referme : œil (« Fermer la
  portière arrière… »), ou en démarrant au volant. Un civil qui essaie avec l'œil : « Seul un policier peut refermer
  cette portière. » Assis à l'arrière, le civil **ne peut pas descendre seul** (touche « sortir » bloquée), **sauf si
  sa portière est déjà ouverte** ; il ne passe pas non plus à l'avant. **Faire sortir l'individu (arrière)** : le
  policier ouvre la portière, l'individu descend et la laisse ouverte ; le policier la referme avec l'œil.
- Sur un PNJ, le client du policier fait tout lui-même (animation de l'emote lue dans RPEMOTES ; à défaut, les
  animations de secours `CuffAnim` / `SeatedAnim`).

### Menottes : modèle `p_cs_cuffs_02_s`

Le modèle existe déjà dans le jeu. Pour utiliser votre propre fichier, créez le dossier **`rp_interact/stream/`** et
placez-y **`rp_interact/stream/p_cs_cuffs_02_s.ydr`** (FiveM le charge automatiquement, aucune ligne à ajouter dans
`fxmanifest.lua`), puis redémarrez la ressource. Autre nom de modèle : `CuffProp` dans `config.lua`.

### Véhicules de police

Aucune restriction : **tout le monde** (policier ou non, mode civil ou non) monte dans **tous les véhicules de
police**, en tout temps et en tout lieu. Les anciennes commandes `/policeon` et `/policeoff` sont supprimées.

### Arme à feu en main : ni coup de crosse, ni roulade

- **Plus de corps à corps avec une arme à feu** (`NoFirearmMelee`) : impossible de donner un **coup de crosse** à
  quelqu'un ou de **taper dans le vide** (attaques légère, lourde et alternative du jeu bloquées). Viser, tirer et
  recharger fonctionnent normalement.
- **Plus de roulade** (`NoCombatRoll`) : le saut est bloqué pendant la visée (c'est ce qui déclenche la roulade).
- Mains nues ou arme blanche (couteau, matraque…) : rien ne change.

Les modèles de bancs, chaises et poubelles se règlent dans `config.lua` (`Seats`, `TrashBins`).

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `MenuKey`, `TargetKey` | touches par défaut (F1, Alt gauche) ; chaque joueur les change dans Échap > Paramètres > Raccourcis clavier > FiveM |
| `MdcResource`, `ChatResource` | noms des dossiers du MDC et du chat |
| `SpawnPoliceOnly`, `EquipmentPoliceOnly` | véhicules de police (Voiture > Spawn) et armes réservés aux policiers en service |
| `MaxCustomEquipment` | équipements modifiés (nommés, enregistrés) par joueur (10) |
| `Eup` | menu des tenues : commande (`eup`), `PoliceOnly` (tenues de police réservées aux policiers en service, `false` par défaut), `OneBased` (numéros des tenues comptés à partir de 1) |
| `RadioRangeClosed`, `RadioRangeOpen`, `RadioInsulation`, `RadioMaxVolume`, `RadioMuffleHz`, `RadioMuffleBoost`, `RadioBehindHz`, `RadioYouTubeAudio`, `RadioEngine` | radio du véhicule : portée dehors tout fermé (15 m) / ouvert (25 m), volume quand tout est fermé, volume maximal, effet étouffé (coupure des aigus, volume compensé), son un peu plus sourd derrière soi, service audio pour YouTube (facultatif), moteur du son (`'nui'` : ce script ; `'olisound'` ; `'auto'`) |
| `ObserveDistance`, `SearchDistance`, `ActionDistance`, `DoorDistance`, `ObjectDistance`, `DeleteDistance` | distances : observations (10 m), fouilles (3 m), menottes / bras / assis (2 m), portières (3 m), bancs et poubelles (2,5 m), supprimer (50 m) |
| `AllowSelfTarget` | viser son propre personnage (test) ; `false` en production si vous préférez |
| `InspectCooldown`, `SearchDurations` | délai entre deux observations ; durée des fouilles (6 s par partie du corps, 35 s véhicule) |
| `EmotesResource`, `EmoteFiles` | mode d'emotes (RPEMOTES, `'auto'` = détecté) et fichiers supplémentaires où lire les emotes |
| `CuffPropPlacement` | position / orientation des menottes |
| `EquipmentZoom` | Customiser équipement : caméra rapprochée sur l'arme de l'onglet ouvert (position `Offset`, point visé par rapport à la main droite `Target`, champ de vision `Fov`) ; armes longues (groupes `LongGroups`) : cadrage `Long` (plus loin, plus large) |
| `CopyPed` | `/copyped` : copies par joueur (`Max`), visibles par tous (`Networked`), pose figée (`FreezePose`), accessoires en plus (`ExtraComponents`) |
| `CuffDuration`, `UncuffDuration`, `Emotes`, `CuffAnim`, `SeatedAnim`, `CuffProp`, `DragOffset`, `DragMove`, `DragMoves`, `DragReleaseKey`, `PlaceVehicleDistance` | police : durées, emotes (`/e menotté2`, `/e tenirlebras`, `/e c`), animation menotté debout du jeu (`CuffAnim`) et animation assise de secours (si l'emote est introuvable dans RPEMOTES), menottes, position de l'individu tenu, allures et animations de ses jambes, touche pour lâcher le bras, distance du véhicule |
| `Struggle` | se débattre (tenu sans menottes) : activé, touche (ESPACE), gain par appui / baisse par seconde de la jauge, rayon des autres policiers (2 m), chance de perdre s'ils étaient déjà là (85 %), délai avant de pouvoir le reprendre (5 s), tremblement des écrans |
| `DeleteAccess`, `DeleteAce` | qui peut supprimer (PNJ, véhicules sans joueur, objets) : `'everyone'` (défaut) ou `'police'`, + permission ACE |
| `AdminAce` | permission ACE des commandes d'administration (rechargement des emotes et des véhicules) |
| `NoFirearmMelee`, `NoCombatRoll` | arme à feu en main : pas de coup de crosse / coup dans le vide ; pas de roulade |
| `MaxProfiles`, `TextMax` | profils par joueur, longueur des textes |
| `AnnounceWithMe`, `ResultsInChat`, `ResultDuration` | `/me` automatiques, copie dans le chat, durée d'affichage |
| `Defaults` | réponses par défaut |
| `Seats`, `TrashBins` | objets de l'environnement |
| `Surrender` | tips d'arrestation : commande, touche par défaut, libellé et emote de chaque action |
| `AimRadius`, `AimRange`, `AimRefresh` | mise en joue : rayon autour du civil, portée, confirmation |
| `PlaceDoorDistance` | placer à l'arrière : le civil doit être à moins de 4 m d'une portière arrière libre |
| `Weather` | page Météo : activée, permission ACE, prise de main sur vMenu (`TakeOverVMenu`), temps par défaut, vitesses du temps (de base / réaliste / personnalisée par défaut), défilement de la météo (minutes, transition, listes beau temps / pluvieux), temps proposés |
| `Smell`, `Smells` | odeurs détectées automatiquement : activées, distance (6 m), 2 au plus, durée de la notification, délai avant d'être prévenu de nouveau, volume du son ; liste des odeurs (`id` à ne pas changer, nom dans la fiche, ce que sent le policier) |

## Liens avec le MDC et le chat

- **Policier** = joueur dans une unité du MDC : export serveur `getPlayerUnit(source)` du MDC (vérification fiable,
  lue à chaque fouille) et état `Player(source).state.mdcUnit` (affichage des options côté joueur, mis à jour à
  chaque entrée / sortie d'unité).
- **Noms des ressources** : le MDC et le chat publient eux-mêmes leur nom (`GlobalState.mdcResource`,
  `GlobalState.rpChatResource`) : peu importe le nom de leurs dossiers. Si le MDC est introuvable ou trop ancien
  (avant v1.18), la console serveur l'indique au démarrage.
- **Annonces RP** : export serveur `sendMe(source, texte)` du chat ; résultats privés : export client `addPrivate`.
- Sans le MDC, personne n'est policier (inspections visuelles et olfactives seulement) ; sans le chat, pas d'annonce ni
  de copie dans le chat. Le reste fonctionne.

## Données

`data/profiles.json` et `data/custom_equipment.json` (équipements modifiés, nommés et enregistrés par les joueurs,
rempli par le serveur ; l'ancien format de la v2.8, un par service, est converti tout seul), voir `data/LISEZMOI.txt`. **À remplir vous-même**, en **JSON** : `data/vehicle.json`
(véhicules du menu Voiture > Spawn), `data/loadouts.json` (autres lots d'armes du menu Équipements) et
`data/outfits.json` (tenues du menu `/eup`) ; `rpi_vehicles` (console) les relit, ainsi que
**`equipment_services.json`** (à la racine de la ressource, fourni avec deux exemples : WSP et KCSO).

### `equipment_services.json` : équipement de chaque police

Un objet par bouton « Équipement … », dans l'ordre d'affichage :

```json
{
    "Service": "Washington State Patrol",
    "Name": "Équipement WSP",
    "Replace": true,
    "Weapons": [
        {
            "Weapon": "WEAPON_PISTOL50", "Label": "Arme de service (Pistol .50)", "Ammo": 120, "Required": true,
            "Components": ["COMPONENT_AT_PI_FLSH"],
            "Options": [
                { "Label": "Lampe tactique", "Choices": [ { "Label": "Lampe sur le canon", "Component": "COMPONENT_AT_PI_FLSH" } ] },
                { "Label": "Chargeur", "Choices": [ { "Label": "Chargeur grande capacité", "Component": "COMPONENT_PISTOL50_CLIP_02" } ] }
            ],
            "Tints": true
        },
        { "Weapon": "WEAPON_FIREEXTINGUISHER", "Label": "Extincteur", "Ammo": 2000, "Default": false }
    ]
}
```

| Champ | Rôle |
|---|---|
| `Service` | `Washington State Patrol` ou `King County Sheriff Office` (ou `WSP` / `KCSO` : pastille de la police) ; un autre nom est accepté (sans pastille) |
| `Name` | texte du bouton |
| `Replace` | `true` : les armes portées sont retirées avant (défaut) |
| `Weapon`, `Label`, `Ammo` | arme, nom affiché, munitions |
| `Required` | `true` : toujours donnée, impossible à retirer en personnalisant |
| `Default` | `false` : pas dans l'équipement de base, le joueur peut l'**ajouter** en personnalisant |
| `Components` | accessoires de l'équipement de base |
| `Options` | ce que le joueur peut choisir : un groupe = un emplacement (une case à cocher s'il n'a qu'un choix, sinon une liste « Aucun / … ») ; un seul accessoire par groupe |
| `Tints` | `true` : teinte de l'arme au choix (8 teintes des armes classiques ; pas pour les armes Mk II) (un nombre > 0 vaut `true`) |
| `Tint` | teinte **par défaut** (équipement de base et réinitialisation) : n° 0 à 7 ou nom (`noir`, `vert`, `or`, `rose`, `kaki`, `bleu`, `orange`, `platine`) ; ex. le beanbag : `"Tint": "orange"` |

Un équipement modifié ne garde que ce que le fichier prévoit encore : un accessoire retiré du fichier n'est
plus donné, une arme ajoutée apparaît avec son réglage de base. Pour une base de données : remplacez `loadProfiles()` / `saveProfiles()`
dans `server/server.lua`. Console serveur : `rpi_reload` recharge le fichier.

## Arme tenue : exports pour les autres scripts

- `exports.rp_interact:captureWeapon()` : arme en main telle quelle : `{ hash, label, ammo, tint, components,
  componentTints, light, torch }` (accessoires de `equipment_services.json`, armes addon comprises, et accessoires du
  jeu ; `light` : lampe allumée, celle de l'arme ou de CartoonFlashlight) ;
- `exports.rp_interact:giveWeapon(data, equip)` : la rend à l'identique et rallume sa lampe (via `rp_weaponscontrol`).

Utilisés par `rp_vehicleprops` (arme posée sur un véhicule ou au sol). L'œil reconnaît aussi le **Taser posé au sol**
(`rpTaserDropped` : « Reprendre le Taser », `ExternalObjects` dans `config.lua`).

## `/copyped` : copier son personnage (photos)

`/copyped` : un **double** de votre personnage apparaît **exactement à votre place** (position, orientation, tenue),
puis vous pouvez vous déplacer pour prendre la photo. Il reprend :
- l'**arme tenue en main**, avec ses **accessoires** (ceux de l'arme dans `equipment_services.json`, armes addon
  comprises, + `CopyPed.ExtraComponents`) et sa **teinte** ; en train de **viser** : il vise dans la même direction ;
- l'**animation en cours** : l'**emote** du mode d'emotes (**RPEMOTES** / rpemotes : le serveur lit toutes ses emotes,
  une fois), **au même moment** de l'animation et **figée** (`FreezePose`), avec les **props** de l'emote (téléphone,
  carnet…) ; un **scénario** (fumer, café…) ; ou une animation de ce script (menotté…) ;
- les **objets accrochés** au personnage (menottes…).
Le double ne bouge pas et ne prend pas de dégâts. **`/copyped suppr`** supprime vos doubles ; au-delà de
`CopyPed.Max` (5), le plus ancien est remplacé. À pied seulement.

## Performance

- Aucune boucle quand rien n'est utilisé (0.00 ms dans le resmon). Radio : une vérification toutes les 150 ms
  seulement tant qu'une radio est allumée dans un véhicule à portée réseau.
- Menu Interaction et menu `/eup` (au clavier) : lecture des touches à chaque image **uniquement pendant qu'un menu
  est ouvert** ; aucune boucle sinon.
- Arme à feu : une vérification toutes les 250 ms (arme en main) ; touches bloquées à chaque image **seulement tant
  qu'une arme à feu est en main**, à pied.
- L'œil tourne uniquement pendant que la touche est maintenue (visée toutes les 50 ms, tir bloqué) et s'arrête ensuite.
- Assis sur un banc : une petite boucle attend la touche pour se lever, puis s'arrête.
- Portière ouverte avec l'œil : surveillance légère (250 ms) jusqu'à ce qu'elle soit refermée.
- Policier en service : une lecture de la visée toutes les 250 ms (~0.00 ms) ; pendant qu'il vise, détection des
  joueurs visés toutes les 150 ms. Hors service : aucune boucle.
- Barre de chargement : boucle uniquement pendant la fouille / le menottage.
- Odeurs détectées : policier en service ET au moins une odeur en jeu : une distance par source toutes les 500 ms ;
  sinon aucune boucle. Civil placé à l'arrière : la touche « sortir » est bloquée à chaque image seulement tant qu'il
  y est assis.
- Menotté : boucle pendant qu'on est menotté (contrôles bloqués, emote vérifiée chaque seconde) ; tenu par le bras :
  accroche et marche vérifiées toutes les 100 ms UNIQUEMENT tant qu'on est tenu ; PNJ menottés : 1 s tant qu'il y en a.
- Lâcher le bras avec X : raccourci FiveM (aucune boucle).
- Tips d'arrestation : les touches fixes X et Échap sont lues uniquement pendant que les tips sont affichés.
- L'œil d'un joueur autorisé à supprimer vise jusqu'à 60 m (50 m + caméra) au lieu de 25 m : même coût (un rayon).
