# RP Ganghunt

Vagues d'ennemis qui **traquent le joueur qui les appelle**. 100 % standalone (ni ESX, ni QBCore, ni vRP), Lua 5.4,
menu NUI en Vanilla JS au style des autres scripts (MDC, rp_TrafficControl, rp_RoleplayZone).

Volontairement **absent du MDC et du `/tuto`** : seule la commande l'ouvre.

## Installation

1. Copier le dossier `rp_Ganghunt` dans `resources/` (avec vos musiques MP3 dans `html/music/`, voir plus bas).
2. `ensure rp_Ganghunt` dans `server.cfg`.
3. Avec **rp_NPCcontrol** (« everyone ignore player ») : version **1.7.0** ou plus, sinon les ennemis ne voient pas
   le joueur. Pendant une chasse, « ignore player » est coupé pour le joueur traqué seulement.

**Mode nuit** (réglé dans le MDC : *Paramètres > MDC > Apparence*, appliqué à toutes les interfaces ou aux menus extérieurs) : **vert sur fond noir** pour le menu et le HUD de la chasse (`client/theme.lua` ; sans le MDC : thème jour).

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

2. **Vagues** : de **1 à 10 vagues**, de **1 à 30 ennemis par vague**. **Vague suivante** :
   - **à la fin de la précédente** : 7 s après que tous les ennemis sont éliminés ;
   - **après un délai** choisi (15 s à 10 min, par pas de 15 s) : elle arrive à l'heure, même si la précédente n'est
     pas éliminée (60 ennemis vivants au plus : sinon elle attend qu'il y ait de la place, `MaxAlive`).
3. **Renforts** :
   - **Véhicules** de la faction : ils arrivent **en convoi**, tous depuis le même point, à la file (4 par véhicule
     au plus) ; arrivés à 35 m de vous, **tout le monde descend** ;
   - **Hélicoptère** de la faction : un pilote et deux tireurs, au-dessus du point du convoi. Il reste en l'air : il
     vous suit, ses tireurs tirent, et il survole la zone de recherche (projecteur).
4. **Armes** :
   - **Aléatoire** : chaque ennemi reçoit une arme au hasard parmi celles de sa faction ;
   - **Choisies** : jusqu'à **10 armes**, chacune avec son **pourcentage d'usage** (curseur ou saisie), le total doit
     faire **100 %**. « Répartir également » partage 100 % entre toutes. Une arme ajoutée prend ce qui reste.
   - **Armes spéciales** : lance-grenades (et compact), RPG, lance-missiles à tête chercheuse, minigun, railgun,
     lance-feux d'artifice.
   - **Arme de poing** : chaque ennemi en a une. Si l'arme tirée au sort est une arme de poing, il n'a **que** celle-là ;
     sinon (arme longue ou spéciale), il a **aussi un pistolet de combat** (`DefaultSidearm`).
5. **Intensité** :
   - **Neutres** : ils ne vous attaquent **que si vous les attaquez** (une balle ou un coup sur l'un d'eux, l'un d'eux
     tué, un tir à moins de 25 m de l'un d'eux, ou leur véhicule touché). Avant : ils flânent près de vous (s'approchent
     si vous vous éloignez à plus de 90 m ; les véhicules viennent se garer à 40 m et tout le monde descend,
     l'hélicoptère tourne au-dessus). Une fois attaqués, tous sont hostiles jusqu'à ce que tous soient éliminés ; la
     vague suivante arrive de nouveau neutre ;
   - **Silencieux** sur toutes les armes qui l'acceptent (vérifié par le jeu) : on les entend moins ;
   - **Grenades** : une partie des ennemis en a quelques-unes et en lance une de temps en temps (au hasard, toutes
     les 7 à 15 s, d'un ennemi à pied entre 8 et 40 m qui vous voit). Gangs : cocktails Molotov, grenades, bombes
     artisanales ; Organisations : grenades, Molotov, fumigènes ; Forces : gaz lacrymogène, fumigènes, grenades ;
   - **Musique** : vos fichiers MP3 (dossier `html/music/`), joués à la suite et en boucle pendant toute la traque,
     avec un **fondu d'entrée** au lancement et un **fondu de sortie** quand la traque est terminée (pas entre deux
     vagues). Case cochée : réglage du **volume** (appliqué tout de suite, même pendant la traque, gardé d'une fois à
     l'autre) et bouton ▶ pour écouter le premier morceau.

**HUD en haut au milieu** pendant la chasse :
- l'état, comme la police du jeu : **REPÉRÉ** (gyrophares rouge / bleu), **ILS VOUS CHERCHENT** (gris, avec le temps
  passé hors de leur vue), **NEUTRES** (vert, option) ou **VAGUE SUIVANTE** (compte à rebours ; avec « après un
  délai », le compte à rebours est aussi affiché pendant le combat) ;
- la faction et la vague ;
- une **barre de la vague** (ennemis éliminés sur ceux de la vague) et une **barre de la chasse** (éliminés sur le
  total) ; les ennemis restants.

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

## Comportement des ennemis (comme la police du jeu)

- **Ils ne s'entretuent pas** : tous dans le même groupe (`RP_GANGHUNT`), compagnons entre eux, tir ami coupé.
- **Animosité au maximum** : jamais de fuite ni de reddition, combat « suicidaire » au plus près, ils chargent,
  contournent, avancent quand ils ne peuvent pas tirer, et **finissent au corps à corps** à moins de 2,6 m.
- **Apparition** : tous dans un rayon de **70 m** autour de vous, de préférence **hors de votre vue**, **jamais dans
  l'eau, sur un toit ou dans un intérieur**. À pied : **n'importe où** (trottoirs, parcs, ruelles, terrains), par
  groupes de 3, au niveau du sol ; véhicules : sur la route.
- **Ils ne s'arrêtent jamais de tirer** : munitions illimitées, et pendant toute la chasse le joueur n'est jamais
  « ignoré » (le jeu ou rp_NPCcontrol pouvaient le faire ignorer, surtout des policiers / SWAT / militaires).
- **Repéré** : il suffit qu'**un** ennemi vous voie (ou vous tire dessus / vous combatte de lui-même) pour que
  **toute la faction** sache où vous êtes (radio) et que **tous convergent vers vous**, comme la police du jeu : à
  plus de 60 m ils foncent en courant ; plus près, ils combattent en avançant (zone de combat centrée sur vous,
  déplacée dès que vous bougez, sans s'arrêter à couvert) ; les véhicules foncent sur vous, l'hélicoptère vous suit.
  En plein
  combat, un ennemi qui vous a en ligne de vue vous garde jusqu'à 150 m, dans toutes les directions. Pour vous
  **retrouver**, il doit vous avoir **devant lui**, à portée (75 m ; moins la nuit ou si vous êtes accroupi / furtif,
  plus si vous êtes en véhicule ; 150 m depuis l'hélicoptère) et sans obstacle ; à 5 m il vous trouve de toute façon.
  Il vous **entend tirer** (120 m ; 20 m avec un silencieux) et sait d'où vient une balle qui le touche.
- **Recherche** : si **personne** ne vous voit pendant 8 s, ils vous perdent. Une **zone de recherche** (cercle rouge
  sur la carte) apparaît autour de votre dernière position connue et s'agrandit (35 à 140 m) : à pied ils la
  fouillent, les véhicules la sillonnent, l'hélicoptère la survole au projecteur. Sans vous retrouver, la zone se
  rapproche de vous toutes les 20 s (renseignements). Revu, entendu ou touché : tous reviennent sur vous.
- **Ils vous traquent** : en véhicule, ils vous poursuivent (les passagers tirent) ; à pied trop loin (160 m, ou 70 m
  si vous êtes en véhicule), ils **reprennent un véhicule** (le leur s'il est à côté, sinon un nouveau de la faction ;
  sous vos yeux ils courent y monter) ; près de vous à pied, ils descendent et combattent.
- Ils restent sous le contrôle du joueur qui a lancé la chasse (ils ne passent pas à un autre joueur). Ils sont
  hostiles aux joueurs : un joueur qui se trouve à côté peut être pris pour cible lui aussi.
- **Musique** (option) : `gtav_wantedlevel1.mp3`, `gtav_wantedlevel2.mp3`, `gtav_wantedlevel3.mp3` (dans
  `html/music/`, liste `Music.Tracks`), joués dans l'ordre (ou au hasard : `Shuffle`) et en boucle, fondu enchaîné
  de 3 s entre deux morceaux, fondu d'entrée de 4 s au lancement, fondu de sortie de 5 s à la fin de la traque
  (réussite, mort ou `/ganghunt stop`). Un fichier absent est sauté ; si aucun n'est lisible, le joueur est prévenu.
- **Aucun indice de recherche** pendant la chasse (même en tuant des ennemis policiers) : pas d'étoiles, pas de
  minimap rouge / bleu.
- Points rouges sur la carte (`Blips`). Les corps disparaissent au bout de 20 s.

## Configuration (`config.lua`)

| Réglage | Rôle |
|---|---|
| `Command` | nom de la commande (`ganghunt`) |
| `MaxWaves`, `MaxWaveSize`, `WaveSize`, `NextWaveDelay` | vagues au plus, ennemis par vague au plus / par défaut, délai après une vague éliminée |
| `WaveTimer`, `MaxAlive` | mode « après un délai » : délai par défaut / min / max / pas, ennemis vivants au plus |
| `Passive` | option « Neutres » : distance d'un tir qui les provoque, flânerie, approche |
| `MaxWeapons`, `DefaultSidearm` | armes choisies au plus, arme de poing donnée avec une arme longue / spéciale |
| `SpawnDistance`, `ConvoySpacing`, `HeliHeight`, `StreetLevel` | apparition (rayon 40-70 m), convoi, hélicoptère, écart de hauteur au sol accepté |
| `ConvergeDistance`, `ConvergeRadius` | repéré : au-delà, les ennemis à pied foncent vers lui en courant ; en deçà, ils combattent en avançant jusqu'à ce rayon autour de lui |
| `Accuracy`, `Health`, `Armour`, `Blips`, `Melee` | précision, vie, armure, points sur la carte, corps à corps |
| `FarDistance`, `VehicleChaseDistance`, `DismountDistance` | quand reprendre un véhicule, quand descendre |
| `DriveSpeed`, `SearchDriveSpeed`, `DrivingStyle` | conduite vers le joueur / pendant la recherche |
| `Search` | vue, champ de vision, nuit, furtivité, ouïe, zone de recherche, renseignements |
| `Grenades` | fréquence, portée, part des ennemis qui en ont, grenades par catégorie |
| `Suppressors`, `Music`, `Sounds` | silencieux essayés, musique (fichiers, ordre, fondus, volume de départ), sons repéré / perdu |
| `Weapons` | armes du menu (`handgun` : arme de poing ; `special` : arme spéciale) |
| `Categories`, `Factions` | catégories et factions du menu (`grenades` possible par faction) |

## Performance

- Aucune chasse : **aucune boucle** (0.00 ms).
- Pendant une chasse : une vérification par seconde des ennemis de la chasse (8 lignes de vue au plus par seconde).
- Menu : rien ne tourne côté Lua pendant qu'il est ouvert.
