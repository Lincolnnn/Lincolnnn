# RP Ganghunt

Vagues d'ennemis qui **traquent le joueur qui les appelle**. 100 % standalone (ni ESX, ni QBCore, ni vRP), Lua 5.4,
menu NUI en Vanilla JS au style des autres scripts (MDC, rp_TrafficControl, rp_RoleplayZone).

Volontairement **absent du MDC et du `/tuto`** : seule la commande l'ouvre.

## Installation

1. Copier le dossier `rp_Ganghunt` dans `resources/`.
2. `ensure rp_Ganghunt` dans `server.cfg`.
3. Avec **rp_NPCcontrol** (« everyone ignore player ») : version **1.5.0** ou plus, sinon les ennemis ne voient pas
   le joueur. Pendant une chasse, « ignore player » est coupé pour le joueur traqué seulement.

## Utilisation

| Commande | Effet |
|---|---|
| `/ganghunt` | ouvre / ferme le menu (Échap le ferme) |
| `/ganghunt stop` | arrête la chasse en cours (tous les ennemis et leurs véhicules sont retirés) |

N'importe quel joueur peut lancer **sa** chasse ; une seule à la fois par joueur.

Dans le menu :

1. **Ennemis** : trois catégories.

   | Catégorie | Factions |
   |---|---|
   | **Gang** | Bikers (The Lost MC), Ballas, Families, Vagos |
   | **Organisation** | Chinois (Triades), Arméniens, Coréens (Kkangpae), Mexicains (cartel Madrazo), Salvadoriens (Marabunta Grande), Merryweather |
   | **Forces** | Police (LSPD), Armée, Sheriff (BCSO), NOOSE (SWAT) |

2. **Vagues** : de 1 à 10 ; **une vague = 10 ennemis**. La suivante arrive 7 s après la fin de la précédente.
3. **Armes** :
   - **Aléatoire** : chaque ennemi reçoit une arme au hasard parmi celles de sa faction ;
   - **Choisies** : jusqu'à **10 armes**, chacune avec son **pourcentage d'usage** (curseur ou saisie), le total doit
     faire **100 %** (ex. fusil à pompe 30 %, carabine 40 %, SMG 30 %). « Répartir également » partage 100 % entre
     toutes. Une arme ajoutée prend ce qui reste.
   - **Arme de poing** : chaque ennemi en a une. Si l'arme tirée au sort est une arme de poing, il n'a **que** celle-là ;
     si c'est une arme longue, il a **aussi un pistolet de combat** (`DefaultSidearm`).
4. **Renforts** :
   - **Véhicules** de la faction (4 ennemis par véhicule au plus) ;
   - **Hélicoptère** de la faction : un pilote et deux tireurs dans chaque vague.

Un petit cadre en haut à droite indique la faction, la vague et les ennemis restants.

La chasse se termine quand toutes les vagues sont éliminées (« chasse réussie »), si le joueur **meurt**, avec
`/ganghunt stop`, ou s'il se déconnecte (le serveur retire alors tout ce qui reste).

## Véhicules par faction (jeu de base)

| Faction | Véhicules | Hélicoptère |
|---|---|---|
| Bikers | Gang Burrito, Slamvan, Hexer, Daemon | Maverick |
| Ballas | Buccaneer, Peyote, Tornado, Baller | Maverick |
| Families | Emperor, Manana, Voodoo, Baller | Maverick |
| Vagos | Chino, Tornado, Buccaneer, Faction | Maverick |
| Chinois | Oracle, Schafter, Cavalcade, Fugitive | Swift |
| Arméniens | Schafter, Baller, Tailgater, Felon | Frogger |
| Coréens | Sultan, Futo, Kuruma, Feltzer | Maverick |
| Mexicains | Cavalcade, Patriot, Granger, Bison | Frogger |
| Salvadoriens | Chino, Voodoo, Emperor, Buccaneer (versions custom / abîmées) | Maverick |
| Merryweather | Mesa (armée), Crusader, Dubsta, Granger | Annihilator |
| Police | Police Cruiser, Buffalo, Interceptor, Transporter | Police Maverick |
| Armée | Crusader, Mesa, Barracks | Buzzard |
| Sheriff | Sheriff Cruiser, Sheriff SUV | Police Maverick (livrée sheriff) |
| NOOSE | RIOT, FIB Granger, FIB Buffalo | Annihilator |

Tout est modifiable dans `config.lua` (`Factions` : modèles de PNJ, véhicules, hélicoptère, armes « aléatoire »,
gilet pare-balles des forces).

## Comportement des ennemis

- **Ils ne s'entretuent pas** : tous dans le même groupe (`RP_GANGHUNT`), compagnons entre eux, tir ami coupé.
- **Aucun périmètre** : vue et ouïe à 1,5 km, jamais de fuite ni de reddition, combat offensif. Toutes les secondes,
  chacun est relancé sur le joueur s'il l'a perdu.
- **Ils le traquent** : un ennemi à pied trop loin (160 m, ou 70 m si le joueur est en véhicule) reçoit un véhicule de
  sa faction (jusqu'à 4 par véhicule) et le poursuit ; les véhicules le poursuivent à pleine vitesse, les passagers
  tirent ; près du joueur à pied (30 m), ou véhicule hors d'usage, ils descendent et combattent ; l'hélicoptère le
  suit et ses tireurs tirent.
- Apparition **hors de vue**, à 90-150 m (sur la route la plus proche pour les véhicules), hélicoptère à 260 m.
- Ils restent sous le contrôle du joueur qui a lancé la chasse (ils ne passent pas à un autre joueur), donc leur ordre
  « traquer » n'est jamais perdu. Ils sont hostiles aux joueurs : un joueur qui se trouve à côté peut être pris pour
  cible lui aussi.
- Points rouges sur la carte (`Blips`). Les corps disparaissent au bout de 20 s.

## Configuration (`config.lua`)

| Réglage | Rôle |
|---|---|
| `Command` | nom de la commande (`ganghunt`) |
| `MaxWaves`, `WaveSize`, `NextWaveDelay` | vagues au plus, ennemis par vague, délai entre deux vagues |
| `MaxWeapons`, `DefaultSidearm` | armes choisies au plus, arme de poing donnée avec une arme longue |
| `SpawnDistance`, `HeliDistance`, `HeliHeight` | apparition |
| `Accuracy`, `Health`, `Armour`, `Blips` | précision, vie, armure, points sur la carte |
| `FarDistance`, `VehicleChaseDistance`, `DismountDistance` | traque : quand reprendre un véhicule, quand descendre |
| `ManagerInterval`, `BodyCleanup` | vérification des ennemis, retrait des corps |
| `Weapons` | armes proposées dans le menu (`handgun = true` : arme de poing) |
| `Categories`, `Factions` | catégories et factions du menu |

## Performance

- Aucune chasse : **aucune boucle** (0.00 ms).
- Pendant une chasse : une vérification par seconde des ennemis de la chasse.
- Menu : rien ne tourne côté Lua pendant qu'il est ouvert.
