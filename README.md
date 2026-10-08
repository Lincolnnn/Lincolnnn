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

## Onglets

| Onglet | Rôle |
|---|---|
| Unités | Agents en service et leur statut (temps réel) |
| Recherches | Recherche d'identités (nom, prénom, middle name, date de naissance, SSN, n° de licence) et d'immatriculations |
| Interventions | Interventions en cours : prendre l'appel, se retirer, clôturer |
| Créations | Enregistrer une identité, un véhicule ou une intervention. Bouton **Registre** : vos propres créations |

### Identités

Champs : prénom\*, middle name, nom de famille\*, date de naissance\*, adresse\*, SSN\* (`XXX-XX-XXXX`, généré automatiquement s'il est vide), emploi, licence de conduite (classe, numéro, État d'émission), interdictions (choix multiple), condition (N/A, Recherché, Personne disparue, Personne décédée). Si « Recherché » : raison et date de début.
Le bouton **Remplissage aléatoire** remplit toutes les cases (listes de noms, rues, emplois… modifiables dans `html/script.js`, section « GÉNÉRATEUR D'IDENTITÉS ALÉATOIRES »).

## Données (persistantes)

Les identités, véhicules et interventions sont enregistrés dans `data/*.json` sur le serveur.
**Le script ne supprime jamais rien** : une intervention clôturée reste dans le fichier (`"closed": true`).
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
