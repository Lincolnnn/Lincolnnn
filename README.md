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

- **NOM RP** : à saisir une fois ; il s'affiche alors en haut à gauche et dans l'onglet Unités (le pseudo Steam/FiveM n'est jamais affiché).
- **MATRICULE** et **statut** de l'agent. Le nom RP et le matricule sont mémorisés chez le joueur.

## Onglets

| Onglet | Rôle |
|---|---|
| Unités | Agents en service (nom RP, matricule, statut) en temps réel |
| Recherches | Identité : nom de famille\* + date de naissance\*, prénom et SSN facultatifs. Véhicule : immatriculation ou VIN |
| Interventions | Interventions en cours : prendre l'appel, se retirer, clôturer (effacées au redémarrage) |
| Créations | Identité, véhicule, intervention. Bouton **Registre** : vos identités et véhicules, modifiables |

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

## Données (permanentes)

Identités et véhicules : `data/identities.json` et `data/vehicles.json`, écrits à chaque création / modification.
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
