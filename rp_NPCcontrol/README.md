# RP NPC Control (FiveM, standalone)

Gestion des **PNJ** du serveur, sans framework (ni ESX, ni QBCore, ni vRP). Seuls les PNJ **créés par le jeu** sont
concernés : un joueur, un menu de spawn ou un script peut **toujours** faire apparaître un véhicule de police, une
ambulance, un camion de pompiers ou un policier.

## Installation

1. Copier le dossier `rp_NPCcontrol` dans `resources/`.
2. Dans `server.cfg` : `ensure rp_NPCcontrol`.
3. (Facultatif) commande de densité pour un groupe : `add_ace group.admin command.npcdensity allow`.

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

### « Everyone ignore player » (`EveryoneIgnorePlayer`, `NoFear`, `SuppressShockingEvents`)

Les PNJ **ne réagissent plus aux joueurs** (ni agressions, ni insultes, ni fuite), **plus aux fusillades ni aux
explosions**, et **n'ont plus peur** : piétons, passagers **et conducteurs**. Réglé sur chaque PNJ du jeu par le client
qui le contrôle (les PNJ créés par un script ne sont pas touchés).

Les **conducteurs** paniquent autrement que les piétons (ils accélèrent, slaloment, s'enfuient en voiture) : dès que
le joueur **vise, tire** ou qu'une **explosion** a lieu, les conducteurs du jeu à moins de `DriverRange` m (80)
reprennent aussitôt une **conduite normale** (`DriverSpeed`, `DrivingStyle`), et encore pendant `AlertTime` ms (4 s)
dès qu'ils se remettent à fuir.

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
| `DriverRange`, `DriverSpeed`, `DrivingStyle`, `AlertTime` | conducteurs calmés quand le joueur vise / tire (distance, vitesse et style de conduite repris, durée de l'alerte) |
| `Density` | densités `Traffic`, `Parked`, `Peds` (0.0 à 3.0) |
| `DensityCommand` | nom de la commande (`npcdensity`) |
| `EmergencyPeds`, `EmergencyVehicles`, `EmergencyScenarios` | modèles et scénarios des services d'urgence |

## Performance

- Boucle d'**1 seconde** (PNJ du jeu à proximité : réglages « sans peur », retrait des services d'urgence) :
  ~0.01 ms.
- Conducteurs : boucle de 250 ms **seulement pendant une alerte** (le joueur vise, tire, explosion proche).
- Boucle **à chaque image** seulement si une densité n'est pas `1.0` (le jeu exige qu'elle soit redonnée à chaque
  image) ou si `SuppressShockingEvents` est actif : ~0.01 ms. Avec toutes les densités à `1.0` et
  `SuppressShockingEvents = false`, il n'y en a aucune.
- Serveur : aucune boucle.
- Ressource arrêtée : le jeu reprend ses règles par défaut.
