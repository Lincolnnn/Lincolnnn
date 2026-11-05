# RP Stamina

**Endurance de sprint selon les armes portées**, pour pousser à ranger les armes longues dans les véhicules.
100 % standalone, Lua 5.4.

Le système s'applique **dès qu'une arme qui pèse est dans l'inventaire** (pas seulement en main). Seul le **sprint**
est limité : la **course normale (footing) n'a jamais de limite**. Sprint épuisé : le joueur passe à la course normale
jusqu'à avoir repris 25 % de son endurance. **Pas d'arme qui pèse = pas d'endurance** (celle du jeu, sans barre).

## Police (joueur dans une unité du MDC)

Armes longues = **fusils à pompe et fusils d'assaut** (beanbag compris) :

| Sur soi | Sprint |
|---|---|
| 2 armes longues ou plus | **7 s** |
| 1 arme longue | **10 s** |
| aucune arme longue (arme de poing, Taser…) | **pas de limite** |

## Civils (mode civil, ou ni civil ni dans une unité)

Chaque arme pèse, **sauf les armes de poing** ; avec plusieurs armes, **la plus lourde** (le sprint le plus court)
compte :

| Arme | Sprint |
|---|---|
| fusils d'assaut | 25 s |
| fusils à pompe | 25 s |
| pistolets-mitrailleurs / mitrailleuses légères | 25 s |
| armes de jet (grenade, Molotov, fusée…) | 45 s |
| armes lourdes (lance-roquettes, minigun…) | 15 s |
| fusils de précision | 35 s |
| armes blanches longues (batte, club de golf, pied-de-biche, queue de billard, hache, machette, clé…) | 30 s |
| armes blanches courtes (couteau, poing américain, matraque, lampe…) | 50 s |

Sans arme (ou seulement des armes de poing pour un civil) : endurance normale du jeu.

## Récupération

Sprint arrêté : toute l'endurance revient en **20 s** à l'arrêt ou en marchant, en **45 s** en courant. Prendre une
arme plus lourde garde la même part d'endurance (ex. 60 % de 10 s -> 60 % de 7 s).

## Barre et notification

En **haut au milieu de l'écran**, aux couleurs du serveur (noir et rouge ; mode nuit du MDC : sa couleur) :
« ENDURANCE » et la barre (sans autre texte) ; épuisé : « ESSOUFFLÉ », barre grise qui pulse, repère du niveau où le
sprint revient. Affichée pendant le sprint et tant que l'endurance n'est pas pleine, puis 3 s
(`Bar.AlwaysShow = true` : toujours, tant qu'une arme pèse).

Quand une arme se met à peser (prise en main ou dans l'inventaire, ou plus lourde que la précédente) : une courte
**notification** sous la barre (`Notify`) : « Votre arme longue pèse sur vous : votre endurance est réduite. » (police)
ou « L'arme que vous portez pèse : votre endurance est réduite. » (civil).

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
