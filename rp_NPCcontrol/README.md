# RP NPC Control (FiveM, standalone)

Gestion des **PNJ** du serveur, sans framework (ni ESX, ni QBCore, ni vRP). Seuls les PNJ **créés par le jeu** sont
concernés : un joueur, un menu de spawn ou un script peut **toujours** faire apparaître un véhicule de police, une
ambulance, un camion de pompiers ou un policier.

## Installation

1. Copier le dossier `rp_NPCcontrol` dans `resources/`.
2. Dans `server.cfg` : `ensure rp_NPCcontrol`.
3. (Facultatif) commandes pour un groupe : `add_ace group.admin command.npcdensity allow` et
   `add_ace group.admin command.npcmanhunt allow`.

## Ce que fait le script

### Plus de police, pompiers ni ambulanciers du jeu (`DisableEmergencyServices`)

- Ni eux **ni leurs véhicules** (voitures, motos, fourgons, hélicoptère, bateau, camion de pompiers, ambulance)
  n'apparaissent plus : **commissariats, casernes, hôpitaux, trafic, à pied**.
- Plus de **courses-poursuites ajoutées au hasard** dans le trafic, plus de **renforts** envoyés par le jeu
  (crimes, incendies, blessés : ils ne se déplacent plus sur les interventions), plus de sirènes lointaines ni de
  radio de police du jeu.
- **Définitif** : le serveur refuse la création de ces PNJ / véhicules par le jeu avant même qu'ils existent
  (`entityCreating`), pour tous les joueurs ; chaque client retire aussi ces modèles de la population du jeu et coupe
  les services d'urgence. Ceux déjà présents au démarrage de la ressource sont retirés (sauf un véhicule où se trouve
  un joueur).
- Listes modifiables : `EmergencyPeds`, `EmergencyVehicles`, `EmergencyScenarios`.

### Plus d'indice de recherche (`DisableWantedLevel`)

Jamais d'étoiles, pour personne.

### Mode « chasse à l'homme » (`Manhunt`, désactivé par défaut)

`Manhunt = false` dans `config.lua` (par défaut). Avec `true` (ou la commande **`npcmanhunt on`**, console ou
permission ACE `command.npcmanhunt`, sans redémarrer), **la police du jeu redevient normale** :
- **indice de recherche** (étoiles) de retour ;
- **policiers PNJ** et leurs véhicules, motos et hélicoptères **réapparaissent** (trafic, commissariats) ;
- **renforts** envoyés (voitures, hélicoptères, SWAT, barrages) ;
- ils **ne vous ignorent plus** : ils viennent vous chercher, vous poursuivent et vous tirent dessus. Le script ne les
  calme jamais (pas de remise en conduite normale, pas de « pas de peur »).

Les **pompiers et ambulanciers** restent supprimés (`NonPoliceModels`). Les autres PNJ (civils, gangs…) gardent leurs
réglages « ignore player ». **`npcmanhunt off`** : étoiles effacées, policiers du jeu retirés. Au redémarrage, la
valeur de `config.lua` revient.

### « Everyone ignore player » (`EveryoneIgnorePlayer`, `NoFear`, `SuppressShockingEvents`)

Les PNJ **ne réagissent plus aux joueurs** (ni agressions, ni insultes, ni fuite), **plus aux fusillades ni aux
explosions**, et **n'ont plus peur** : piétons, passagers **et conducteurs**. Réglé sur chaque PNJ du jeu par le client
qui le contrôle (les PNJ créés par un script ne sont pas touchés).

**rp_Ganghunt** : pendant une chasse (`/ganghunt`), pour le **joueur traqué seulement** : « everyone ignore player »
**et** « police ignore player » sont coupés (sinon ses ennemis, policiers / SWAT / militaires compris, cessent de
tirer au bout de quelques secondes), et son indice de recherche n'est plus effacé (option « Musique » : étoiles
cachées). L'état est gardé même si cette ressource redémarre pendant la chasse. Ses ennemis ne sont jamais calmés.
Tout revient dès la fin de la chasse ; les PNJ du jeu restent calmés.

Renforcé :
- **Perception coupée** (`NoPerception`, `SeeingRange`, `HearingRange`) : les PNJ du jeu ne **voient** plus les morts
  ni les armes et n'**entendent** plus les tirs ni les klaxons. Ils n'ont donc **pas peur en voyant un PNJ mort**.
- **Jamais hostiles** : les groupes de PNJ (civils, vigiles, dealers, gangs : `CalmGroups`) sont en « respect » envers
  les joueurs, ne cherchent jamais le combat ; l'énervement (klaxon, bousculade, véhicule volé) est supprimé à chaque
  image.
- **Alerte** : dès que le joueur **vise, tire, vole un véhicule** (tire le conducteur dehors), **klaxonne**, **se bat**,
  ou qu'une **explosion** ou un **PNJ mort** est à proximité, pendant `AlertTime` ms (4 s) :
  - les **conducteurs** du jeu à moins de `DriverRange` m (80) reprennent une **conduite normale** (`DriverSpeed`,
    `DrivingStyle`), encore dès qu'ils se remettent à fuir ;
  - les **piétons** à moins de `CalmRange` m (40) qui fuient ou **veulent se battre** avec un joueur (le conducteur
    qu'on vient de sortir de sa voiture, celui qu'on a klaxonné…) se **calment** et reprennent leur promenade.
  - le **PNJ mis en joue** (celui que le joueur vise) est traité **en premier**, à chaque passage : le script en
    demande le contrôle s'il ne l'a pas, le recalme et, s'il fuit, le remet sur sa route ou sa promenade.
- **Ni plongeon ni recroquevillement** : les PNJ ne se jettent plus au sol et ne se cachent plus derrière un abri
  quand on les vise.

### Densité des PNJ (`Density`)

| Clé | Rôle |
|---|---|
| `Traffic` | véhicules qui circulent |
| `Parked` | véhicules garés |
| `Peds` | piétons (et PNJ des scénarios) |

`1.0` = **jeu de base**, `0.0` = **aucun**, jusqu'à `3.0` (**le triple**). Au-dessus de `1.0`, le script autorise la
population maximale du jeu et lui demande autant de PNJ que la valeur ; le jeu en ajoute autant que sa mémoire le
permet (au-delà d'environ `2.0`, la différence se voit moins).

Pour essayer sans redémarrer (console serveur, ou joueur avec la permission ACE `command.npcdensity`) :

```
npcdensity traffic 2.0
npcdensity peds 0.5
npcdensity all 1.0
```

La valeur revient à celle de `config.lua` au redémarrage (c'est le fichier qui fait foi).

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `DisableEmergencyServices` | police / pompiers / ambulanciers du jeu supprimés |
| `DisableWantedLevel` | indice de recherche supprimé |
| `EveryoneIgnorePlayer`, `NoFear` | PNJ qui ignorent les joueurs, sans peur |
| `SuppressShockingEvents` | réactions « choquées » des passants (coups de feu, explosions) supprimées à chaque image |
| `DriverRange`, `DriverSpeed`, `DrivingStyle`, `AlertTime` | conducteurs calmés pendant une alerte (distance, vitesse et style de conduite repris, durée de l'alerte) |
| `CalmRange` | piétons calmés pendant une alerte (fuite, bagarre avec un joueur) |
| `NoPerception`, `SeeingRange`, `HearingRange` | perception des PNJ du jeu coupée (ne voient plus les morts / armes, n'entendent plus tirs / klaxons) |
| `CalmGroups` | groupes de PNJ toujours en « respect » envers les joueurs |
| `Density` | densités `Traffic`, `Parked`, `Peds` (0.0 à 3.0) |
| `DensityCommand` | nom de la commande (`npcdensity`) |
| `EmergencyPeds`, `EmergencyVehicles`, `EmergencyScenarios` | modèles et scénarios des services d'urgence |

## Performance

- Boucle d'**1 seconde** (PNJ du jeu à proximité : réglages « sans peur », retrait des services d'urgence) :
  ~0.01 ms.
- PNJ proches calmés : boucle de 250 ms **seulement pendant une alerte** (le joueur vise, tire, vole un véhicule,
  klaxonne, se bat, explosion ou PNJ mort à proximité).
- Boucle **à chaque image** seulement si une densité n'est pas `1.0` (le jeu exige qu'elle soit redonnée à chaque
  image) ou si `SuppressShockingEvents` est actif : ~0.01 ms. Avec toutes les densités à `1.0` et
  `SuppressShockingEvents = false`, il n'y en a aucune.
- Serveur : aucune boucle.
- Ressource arrêtée : le jeu reprend ses règles par défaut.
