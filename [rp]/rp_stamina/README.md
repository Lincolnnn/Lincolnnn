# RP Stamina

**Endurance de sprint selon les armes portées**, pour pousser à ranger les armes longues dans les véhicules.
100 % standalone, Lua 5.4.

Le système s'applique **dès qu'une arme est dans l'inventaire** (pas seulement en main). Sprint épuisé : le joueur
passe à la **course normale, illimitée**, jusqu'à avoir repris 25 % de son endurance.

## Police (joueur dans une unité du MDC)

Armes longues = **fusils à pompe et fusils d'assaut** (beanbag compris) :

| Sur soi | Sprint |
|---|---|
| 2 armes longues ou plus | **15 s** |
| 1 arme longue | **25 s** |
| aucune arme longue (arme de poing, Taser…) | **1 min 30** |

## Civils (mode civil, ou ni civil ni dans une unité)

Chaque arme pèse, **sauf les armes de poing** ; avec plusieurs armes, **la plus lourde** (le sprint le plus court)
compte :

| Arme | Sprint |
|---|---|
| fusils d'assaut | 35 s |
| fusils à pompe | 40 s |
| pistolets-mitrailleurs / mitrailleuses légères | 35 s |
| armes de jet (grenade, Molotov, fusée…) | 1 min 10 |
| armes lourdes (lance-roquettes, minigun…) | 15 s |
| fusils de précision | 35 s |
| armes blanches longues (batte, club de golf, pied-de-biche, queue de billard, hache, machette, clé…) | 40 s |
| armes blanches courtes (couteau, poing américain, matraque, lampe…) | 1 min 10 |

Sans arme (ou seulement des armes de poing pour un civil) : endurance normale du jeu.

## Récupération

Sprint arrêté : toute l'endurance revient en **20 s** à l'arrêt ou en marchant, en **45 s** en courant. Ranger ou
prendre une arme garde la même part d'endurance (ex. 60 % de 25 s -> 60 % de 1 min 30).

## Barre

En **haut au milieu de l'écran**, aux couleurs du serveur (noir et rouge ; mode nuit du MDC : sa couleur) :
« ENDURANCE » + la raison (« Police · 1 arme longue », « Fusil d'assaut »…) ; épuisé : « ESSOUFFLÉ », barre grise
qui pulse, repère du niveau où le sprint revient. Affichée pendant le sprint et tant que l'endurance n'est pas pleine,
puis 3 s (`Bar.AlwaysShow = true` : toujours, tant qu'une arme pèse).

## Installation

```cfg
ensure rp_mdc        # unités (police) ; avant
ensure rp_stamina
```

## Réglages (`config.lua`)

`Police` (groupes des armes longues, sprint selon leur nombre), `Civil` (sprint par type d'arme, armes blanches
longues), `Regen`, `ResumeAt`, `Bar`, `CheckMs`, `Weapons` (armes vérifiées dans l'inventaire : le jeu ne sait pas les
énumérer ; une **arme ajoutée** au serveur n'a qu'à y figurer, son type est lu dans le jeu).

Export client : `exports.rp_stamina:state()` -> `{ active, seconds, max, exhausted, label }`.

## Performance

Sans arme qui pèse : une lecture de l'inventaire par seconde (**0.00 ms**). Avec : une vérification toutes les
100 ms, et à chaque image seulement quand le sprint est bloqué (touche de sprint coupée).
