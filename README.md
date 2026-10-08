# MDC Standalone (FiveM)

Mobile Data Computer de police **100% standalone** (sans ESX / QBCore / vRP), interface NUI en HTML/CSS/Vanilla JS, style « Windows classique » sombre.

## Installation

1. Copiez le dossier dans `resources/` et nommez-le `mdc_standalone` (le nom importe peu, le NUI le détecte automatiquement).
2. Ajoutez `ensure mdc_standalone` dans votre `server.cfg`.
3. En jeu : touche **K** (modifiable dans *Paramètres > Raccourcis clavier > FiveM*) ou `/mdc`. **Échap** pour fermer.

## Fenêtre

- Déplacement : glisser la barre de titre.
- Redimensionnement : bords et coins de la fenêtre.
- Agrandir / rétrécir : bouton ☐ ou double-clic sur la barre de titre. Bouton ↺ : position par défaut.
- La position est gardée d'une ouverture à l'autre et réinitialisée à chaque reconnexion.

## Barre latérale

- **NOM RP** : à saisir une fois ; il s'affiche alors en haut à gauche et dans les unités (le pseudo Steam/FiveM n'est jamais affiché). Mémorisé chez le joueur.
- **Statut de l'unité** : Disponible (vert), En route (jaune), Sur place (orange), Indisponible (rouge). Le statut est celui de l'unité rejointe.

## Onglets

| Onglet | Rôle |
|---|---|
| Unités | Deux listes, une par service : **Atlanta Police Department** et **Georgia State Patrol** (chacun voit les deux). Bouton **Créer une unité** par service (service, nom, tag facultatif, couleur). Chacun peut rejoindre, quitter, modifier ou supprimer une unité (une seule unité à la fois par joueur) |
| Interventions | Liste des interventions (civils) et incidents (unités) : titre, priorité, adresse, bloc ; chaque ligne est surlignée de la couleur de sa priorité. N° d'incident `XX-XXXX`. Cliquer pour afficher le détail, recliquer pour le masquer. Rejoindre / quitter l'appel (unités uniquement), notes en majuscules modifiables, « Intervention terminée » (grisée dans la liste). Les rapports liés apparaissent avec les notes (ouvrir / modifier) et un rapport peut être rédigé directement depuis l'intervention. Bouton **Nouvel incident** pour les unités |
| Recherches | Identité : nom de famille\* + date de naissance\*, prénom et SSN facultatifs. Véhicule : immatriculation ou VIN. Historique : les nouveaux résultats s'ajoutent en haut, les précédents restent en dessous |
| Rapports | DOT-523 (Georgia Uniform Crash Report), Arrest Report, Incident Report, Citation, Traffic Ticket, Ticket, Warning. Chaque rapport est lié à une intervention / un incident (en cours ou terminé). Liste filtrable (type, texte, mes rapports), lecture, modification par l'auteur. Permanents |
| Paramètres | Réglages du HUD (affichage, éléments visibles, taille, position) et du MDC (taille de l'interface, onglet à l'ouverture, fenêtre). Gardés chez le joueur, même après une reconnexion |
| Créations | Réservé aux civils : identité, véhicule, intervention (requérant, téléphone généré, priorité, adresse, bloc, description). Bouton **Registre** : vos identités et véhicules, modifiables |

Unités, interventions et incidents sont gardés en mémoire : ils disparaissent au redémarrage du serveur.

### HUD

Deux affichages séparés, au thème du MDC (fond noir transparent, bordure grise fine et arrondie), visibles même MDC fermé
lorsque le joueur fait partie d'une unité :

- **PLD** (Player Localisation Display) : rue, croisement, direction (N / NE / E / SE / S / SW / W / NW) et bloc.
  Les blocs se dessinent sur la carte dans **`config/blocks.json`** (cercles, rectangles, polygones, filtre par rue) :
  voir `config/LISEZMOI.txt`. La commande `/mdc_pos` ou **Paramètres > Lire ma position** donne la ligne à copier.
- **Display MDC** : nom de l'unité, tag, statut et n° d'incident de l'appel en cours.

Onglet **Paramètres** : afficher / masquer chaque HUD et chacun de ses éléments, taille (50 à 200 %), et
**Placer les HUD à l'écran** (glisser à la souris, molette = taille). Pour afficher le HUD en permanence (hors unité),
passez `ShowWhen = 'always'` dans `client/hud.lua`.

Performance : hors unité, aucune boucle (0.00ms). En unité, le PLD lit la position toutes les 500 ms
(`Interval` dans `client/hud.lua`) et n'envoie que les changements ; le display MDC n'a aucune boucle (le serveur
envoie les changements d'unité, de statut et d'appel).

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

Prénom\*, middle name, nom de famille\*, date de naissance\*, adresse\*, SSN\* (généré), emploi ;
licence de conduite (classe, condition : Suspension / Révocation / Annulation / Disqualification pour les CDL, n° généré, État d'émission) ;
interdictions, condition (Recherché + raison et date de début) ; **Antécédents** (infraction, date, horaire, adresse, explication).
**Remplissage aléatoire** : prénom, middle name, nom, DoB, adresse, SSN et emploi.

### Véhicules

Immatriculation\*, statut de l'immatriculation\*, marque\*, modèle\*, année, couleur\*, propriétaire (une de vos identités),
VIN\* (généré), dernier contrôle technique\* (jamais après aujourd'hui) ; assurance (statut\*, n° de police\* généré et compagnie\* sauf « Non-Assuré ») ;
véhicule volé / abandonné / commercial ; **Historique** (infraction administrative ou de stationnement).
**Véhicule actuel** : reprend modèle, marque, couleur et plaque du véhicule où vous êtes.
**Remplissage aléatoire** : statut d'immatriculation, contrôle technique et assurance.

Les listes du générateur (noms, rues, emplois…) se modifient dans `html/script.js`, section « GÉNÉRATEURS ALÉATOIRES ».
Les numéros de téléphone générés commencent par un indicatif régional de Géorgie compris entre 470 et 678
(470, 478, 678 : liste `GEORGIA_AREA_CODES` dans `server/server.lua` et `html/script.js`).

## Données (permanentes)

Identités, véhicules et rapports : `data/identities.json`, `data/vehicles.json` et `data/reports.json`, écrits à chaque création / modification.
Ils survivent aux déconnexions et aux redémarrages. **Le script ne supprime jamais rien.**
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
