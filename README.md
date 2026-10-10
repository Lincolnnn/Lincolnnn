# MDC Standalone (FiveM)

Mobile Data Computer de police **100% standalone** (sans ESX / QBCore / vRP), interface NUI en HTML/CSS/Vanilla JS, style « Windows classique » sombre.

## Installation

1. Copiez le dossier dans `resources/` et nommez-le `mdc_standalone` (le nom importe peu, le NUI le détecte automatiquement).
2. Ajoutez `ensure mdc_standalone` dans votre `server.cfg`.
3. En jeu : touche **K** (modifiable dans *Paramètres > Raccourcis clavier > FiveM*) ou `/mdc`. **Échap** pour fermer.

Le dépôt contient aussi le **chat écrit RP** dans le dossier [`rp_chat/`](rp_chat/README.md) : c'est une ressource
séparée, à copier à part dans `resources/` (voir son README). Elle partage le nom RP avec le MDC et ses réglages
se font dans l'onglet « Paramètres » du MDC. Le MDC fonctionne aussi sans elle.

## Fenêtre

- Déplacement : glisser la barre de titre.
- Redimensionnement : bords et coins de la fenêtre.
- Agrandir / rétrécir : bouton ☐ ou double-clic sur la barre de titre. Bouton ↺ : position par défaut.
- La position est gardée d'une ouverture à l'autre et réinitialisée à chaque reconnexion.

## Barre latérale

- **NOM RP** : il s'affiche en haut à gauche et dans les unités (le pseudo Steam/FiveM n'est jamais affiché). **Obligatoire pour
  rejoindre une unité.** Il est partagé avec le chat écrit : `/nomrp John Carter` dans le chat change aussi celui du MDC, et
  inversement. Il n'est enregistré nulle part : il est remis à zéro à chaque déconnexion (état `rpName` du joueur côté serveur).
- **Statut de l'unité** : Disponible (vert), En route (jaune), Sur place (orange), Indisponible (rouge). Le statut est celui de l'unité rejointe.

L'heure affichée en bas à droite du MDC est l'heure du jeu.

## Onglets

| Onglet | Rôle |
|---|---|
| Unités | Deux listes, une par service : **Atlanta Police Department** et **Georgia State Patrol** (chacun voit les deux). Bouton **Créer une unité** par service (service, nom, tag facultatif, couleur). Chacun peut rejoindre (4 joueurs max par unité), quitter, modifier ou supprimer une unité (une seule unité à la fois par joueur). Les membres d'une unité partagent leurs recherches et leurs rapports (voir plus bas) |
| Interventions | Liste des interventions (civils) et incidents (unités) : titre, priorité, adresse, bloc ; chaque ligne est surlignée de la couleur de sa priorité. N° d'incident `XX-XXXX`. Cliquer pour afficher le détail, recliquer pour le masquer. Rejoindre / quitter l'appel (unités uniquement), notes en majuscules modifiables, « Intervention terminée » (grisée dans la liste). Les rapports liés apparaissent avec les notes (ouvrir / modifier) et un rapport peut être rédigé directement depuis l'intervention. **Personnes et véhicules** : les unités sur l'appel y ajoutent les fiches de l'historique des recherches (bouton « Fiche » pour la consulter). Bouton **Nouvel incident** pour les unités |
| Recherches | Identité : nom de famille\* + date de naissance\*, prénom et SSN facultatifs. Véhicule : immatriculation ou VIN. Historique : les nouveaux résultats s'ajoutent en haut, les précédents restent en dessous. Bouton **BOLOs** (en haut à droite) : voir plus bas |
| Rapports | DOT-523 (Georgia Uniform Crash Report), Arrest Report, Incident Report, Citation (identité seule), Traffic Citation (type d'infraction : Excès de vitesse / Conduite / Contrôle, intitulé, description ; sans amende), Convocation, Warning (infraction routière : identité complète avec licence et véhicule ; autre infraction : identité), Incident Report (« Impliqués » : individus et véhicules enregistrés) ; « Charges » pour l'Arrest Report. Les anciens Tickets restent lisibles. Chaque rapport est lié à une intervention / un incident (en cours ou terminé). Liste filtrable (type, texte, mes rapports), lecture, modification par l'auteur. Permanents |
| Paramètres | Trois catégories repliables, toutes fermées à l'ouverture : **MDC** (taille de l'interface, onglet à l'ouverture, fenêtre, notifications, son et son volume de 0 à 100 %), **HUD & Display** (PLD et display MDC : affichage, éléments visibles, taille, position) et **Chat écrit et commandes** (apparence du chat, affichage des /me, liste des commandes ; ressource `rp_chat`). Gardés chez le joueur, même après une reconnexion |
| Créations | Réservé aux civils : identité, véhicule, intervention (requérant, téléphone généré, priorité, adresse, croisement, bloc, description ; bouton « Position actuelle »). Bouton **Registre** : vos identités et véhicules, modifiables |

Unités, interventions et incidents sont gardés en mémoire : ils disparaissent au redémarrage du serveur.

### BOLOs (Recherches → bouton « BOLOs »)

Page des **BOLOs actifs** (n°, type, motif, résumé ; filtre Individus / Véhicules), mise à jour en direct.
**Ajouter un BOLO** : on choisit d'abord **Individu** ou **Véhicule**.

- **Individu** : motif\*, identité facultative (choisie dans l'historique des recherches), description
  (cheveux ☐ → couleur, pilosité faciale ☐ → type + couleur, couleur de peau, origine(s) : Inconnue / Blanc /
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

Affichages séparés, au thème du MDC (fond noir transparent, bordure grise fine et arrondie), visibles même MDC fermé :

- **PLD** (Player Localisation Display), **affiché pour chaque joueur dès sa connexion**, sans utiliser le MDC
  (ni nom RP, ni unité) ; désactivable et réglable dans « Paramètres », réglages propres à chaque joueur
  (`PldForEveryone` dans `client/hud.lua` pour le réserver aux joueurs ayant accès au MDC) : direction en gros
  et en gras (N / NE / E / SE / S / SW / W / NW), rue actuelle en gros, **croisement le plus proche** en petit et en
  italique (toujours présent : largeur stable), et **bloc** : celui où se trouve le joueur, sinon le plus proche.
  Les blocs se dessinent dans **`config/blocks.json`** (cercles, rectangles, polygones, filtre par rue) : voir
  `config/LISEZMOI.txt` ; la commande `/mdc_pos` (console F8) donne la ligne à copier.
- **Display MDC** : affiché seulement dans une unité : nom, tag, statut, et le n° d'incident uniquement quand
  l'unité est sur un appel.
- **Notifications** (en haut à droite) : toutes les notifications du MDC, et, même MDC fermé : nouvel appel
  (titre, priorité, adresse, croisement, bloc) et nouvel incident (titre, unité créatrice, adresse, croisement, bloc)
  pour **tous les joueurs en jeu** ; changement de statut pour les membres de l'unité. Chacune se désactive dans
  « Paramètres ». Un son accompagne les nouveaux appels (deux tons) et incidents (trois tons) : son **volume (0 à 100 %)**
  se règle dans *Paramètres > MDC > Notifications et sons* (bouton « Tester »). Le son est généré par l'interface :
  aucun fichier audio n'est nécessaire.

Onglet **Paramètres** : afficher / masquer chaque HUD et ses éléments, taille (50 à 200 %), **Placer les HUD à
l'écran** (glisser à la souris, molette = taille), notifications et son.

Performance : le PLD lit la position toutes les 500 ms (`Interval` dans `client/hud.lua`) et n'envoie que les
changements (~0.01ms) ; PLD désactivé : 0.00ms. Le display MDC et les notifications n'ont aucune boucle.

### Rapports

Chaque rapport reçoit un n° `XX-XXXX`, l'auteur (nom RP) et son unité. La **première ligne** du formulaire choisit
l'intervention ou l'incident lié (obligatoire) : une fois enregistré, le rapport apparaît dans le déroulé de cette
intervention, avec les notes, d'où il peut être ouvert, modifié et ré-enregistré. Après un redémarrage, le lien reste
affiché sur le rapport (intervention « archivée »).

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
