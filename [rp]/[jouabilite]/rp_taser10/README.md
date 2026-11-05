# TASER 10 (`rp_taser10`)

Script **AXON TASER 10** de Cartoon (version 1.7.0), adapté pour ce serveur : **plus de dépendance à `ox_target`**.
Son option à l'œil passe par **l'œil de `rp_interact`** (Alt). Tout le reste du script est inchangé. Le README
d'origine (en anglais, détaillé) est dans [`README_original.md`](README_original.md).

## Installation

1. Le dossier est déjà dans `[rp]/`. Dans `server.cfg` : `ensure rp_taser10` (après `rp_interact`).
2. `rp_interact` l'ajoute à son œil (`config.lua` : `TargetProviders`, déjà fait). `ox_target` n'est plus nécessaire.
3. Le modèle des sondes (`stream/prong.ydr`, `prong.ytyp`) est chargé par la ressource : ne pas y toucher.

## Ce qui change par rapport au script d'origine

| Avant (ox_target) | Maintenant (œil de rp_interact) |
|---|---|
| Option ox_target « Remove Taser Prongs » sur les joueurs et les PNJ | Œil (Alt) sur un joueur ou un PNJ qui a des sondes plantées : **« Retirer les sondes du Taser (n) »**, à 2 m au plus (`Config.RemoveProngs.TargetDistance`), si vous en avez le droit (`Config.RemoveProngs`) |
| — | Œil sur **soi-même**, Taser en main : **« Recharger le Taser »** (comme `/reloadtaser` ; `Config.Target.Reload`) |
| `dependency 'ox_target'` | aucune dépendance ; police d'icônes externe (CDN) retirée du NUI, inutilisée |
| Touches en anglais | Touches en français dans *Paramètres > Raccourcis clavier > FiveM* |

### Poser le Taser au sol (sondes gardées)

Taser en main, **œil (Alt) en visant n'importe où** (sol, mur, véhicule, personne) : **« Poser le Taser au sol »**
(« … (sondes gardées) » quand des sondes sont reliées). Le policier le pose devant lui : **les sondes restent dans le
suspect et reliées**, le fil part désormais **du Taser posé** (vu par tous), la distance maximale du fil est comptée
**depuis lui** (côté client et serveur) ; on peut donc s'en éloigner. Pas de mise en veille tant qu'il est au sol.
**« Reprendre le Taser »** (œil sur le Taser, son propriétaire seulement) : il revient en main et **marche comme
avant** : sondes toujours reliées, et il revient **dans l'état d'avant la pose** (posé ARMÉ : il repasse ARMÉ tout
seul, sans décharge ; au sol il est en SÉCURITÉ).

**Réactiver les sondes déjà plantées : DOUBLE APPUI** sur la touche du sélecteur (`B`), en main ou repris du sol,
joueur ou PNJ, **quel que soit l'état** : ARMÉ -> SÉCURITÉ puis ARMÉ + décharge ; SÉCURITÉ -> ARMÉ puis, au 2e
appui (moins de 1,5 s, `SelectorReactivationWindow`), il **reste ARMÉ + décharge** (avant : il repassait en SÉCURITÉ,
d'où 3 appuis ou plus quand on avait remis la sécurité après la première décharge). La décharge relancée est
**envoyée tout de suite** au serveur, qui vérifie la connexion, le suspect et la distance (avant : le client exigeait
que les sondes visibles soient accrochées chez lui, ce qui échouait souvent sur un joueur) ; son de connexion à
chaque décharge relancée (retour clair). 0,8 s au moins entre deux réactivations (`ReactivationCooldown`, avant 2 s). Le Taser posé est gardé localement dès la réponse du serveur : la connexion n'est
plus coupée (« changement d'arme ») dans l'instant où il n'est ni en main ni encore marqué posé. `Config.Target.Drop = false` pour retirer
l'option. Objet réseau marqué `rpTaserDropped`, état du joueur `taserDropped` ; supprimé si le joueur se déconnecte.

**Écran (CID)** : l'icône de la batterie a la même taille que les emplacements des cartouches (ses images ont la
taille de tout l'écran, batterie à droite : elles étaient réduites dans un petit cadre, d'où une batterie minuscule).

La commande `/removeprongs [id serveur]` fonctionne toujours. Le serveur vérifie la distance et la permission dans
les deux cas.

## Touches et commandes (par défaut)

| Touche / commande | Action |
|---|---|
| `B` | Sélecteur **SÉCURITÉ / ARMÉ** ; SÉCURITÉ puis ARMÉ rapidement : relance la décharge sur des sondes connectées |
| Clic gauche (en visant, ARMÉ) | Tirer une cartouche (deux sondes sur la même cible = connexion, la cible tombe) |
| `R` | Alerte sonore et lampe stroboscopique (ARMÉ) |
| `G` | Sélecteur vers le bas : 3 appuis en SÉCURITÉ = mode discret ; maintenu 3 s = test de fonctionnement |
| `/reloadtaser` | Recharger les 10 cartouches (batterie remplacée si elle est vide) |
| `/removeprongs [id]` | Retirer les sondes du joueur / PNJ visé ou le plus proche |

## Configuration (`config.lua`)

Toutes les options d'origine (cartouches, portée, temps au sol, laser, lampe, fils, sondes, sons, batterie, webhook
Discord facultatif) sont décrites dans le README d'origine. Ajouté pour ce serveur :

| Clé | Rôle |
|---|---|
| `Config.RemoveProngs.TargetDistance` | distance maximale de l'option de l'œil (remplace `OxTargetDistance`) |
| `Config.Target.RemoveLabel` | texte de l'option « Retirer les sondes du Taser » |
| `Config.Target.Reload`, `ReloadLabel` | option « Recharger le Taser » sur soi-même (désactivable) |

Réserver le retrait des sondes : `Config.RemoveProngs.RequirePermission = true` et, dans `server.cfg` :
`add_ace group.admin axon_taser10.removeprongs allow`.
