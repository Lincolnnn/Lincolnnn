# RP Flares (FiveM, standalone)

**Fusées de détresse posées au sol**, sans framework (ni ESX, ni QBCore, ni vRP).

## Installation

1. Copier le dossier `rp_flares` dans `resources/`.
2. Dans `server.cfg` : `ensure rp_flares`.
3. Pour les retirer avec l'œil : `rp_interact` (déjà configuré : `ExternalObjects` dans son `config.lua`).

## Utilisation

- **Fusée en main** (`WEAPON_FLARE`) : touche **G** (modifiable : *Échap > Paramètres > Raccourcis clavier > FiveM >
  « Fusée de détresse : poser au sol »*). Le personnage se baisse et pose une fusée **allumée**, **debout**, à 70 cm
  devant lui, posée sur le sol.
- La fusée **reste dans ses armes** : il peut en poser **autant qu'il veut** (`MaxPerPlayer` pour limiter).
- **Retirer** : avec l'**œil** (rp_interact, **Alt**), viser la fusée : **« Retirer la fusée »** (n'importe quel
  joueur, à moins de 2,5 m).
- **Lumière** : rouge vive, qui **vacille** comme une vraie flamme, vue par tous les joueurs proches. **La nuit**
  (19 h – 7 h), elle est **bien plus forte** et éclaire large (lumière principale avec ombres + grande lueur autour) ;
  le jour, plus discrète. Plus une flamme (particules du jeu) au sommet.
- Les fusées sont créées **par le serveur** : elles restent quand le joueur se déconnecte. `BurnMinutes` (0 par
  défaut : jusqu'à ce qu'on la retire) les éteint toutes seules au bout d'un moment.

## Configuration (`config.lua`)

| Clé | Rôle |
|---|---|
| `Weapon`, `Key` | arme tenue (`WEAPON_FLARE`), touche par défaut (`G`) |
| `Model`, `FallbackModel` | objet posé (`prop_flare_01`, sinon `w_am_flare`) ; redressé tout seul (son plus grand côté à la verticale) |
| `PlaceDistance`, `PlaceTime` | distance devant le joueur, durée du geste |
| `MaxPerPlayer` | fusées posées en même temps par joueur (0 : illimité) |
| `BurnMinutes` | durée de combustion (0 : illimitée) |
| `RemoveDistance` | distance max pour la retirer (vérifiée par le serveur) |
| `Effect` | flamme (particules du jeu : `Asset`, `Name`, `Scale`, `Distance`) |
| `Light` | couleur, distance d'affichage, hauteur, vacillement, jour / nuit (portée, intensité, lueur), heures de nuit, ombres |

## Performance

- Aucune boucle sans fusée posée.
- Fusées connues : vérification toutes les secondes ; lumière dessinée **à chaque image seulement** quand une fusée
  est à moins de `Light.Distance` m (150).
- Serveur : aucune boucle.
