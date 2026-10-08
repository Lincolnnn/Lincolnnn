# MDC Standalone (FiveM)

Mobile Data Computer de police **100% standalone** (sans ESX / QBCore / vRP), interface NUI en HTML/CSS/Vanilla JS.

## Installation

1. Copiez le dossier dans `resources/` et nommez-le `mdc_standalone` (le nom importe peu, le NUI le détecte automatiquement).
2. Ajoutez `ensure mdc_standalone` dans votre `server.cfg`.
3. En jeu : touche **K** (modifiable dans *Paramètres > Raccourcis clavier > FiveM*) ou `/mdc`. **Échap** pour fermer.

## Structure

```
fxmanifest.lua
client/client.lua   -- ouverture/fermeture, callbacks NUI, relais vers le serveur (aucune boucle)
server/server.lua   -- statuts, unités, recherches, interventions, créations (stockage en mémoire)
html/index.html     -- structure de l'UI
html/style.css      -- thème sombre (couleurs dans :root)
html/script.js      -- navigation, statuts, rendu des pages
```

## Relier une base de données

Cherchez `>>> BASE DE DONNÉES` dans `server/server.lua` : chaque emplacement indique la requête à brancher (exemples oxmysql fournis).

## Permissions (optionnel)

Dans `server/server.lua`, passez `UseAcePermission = true` puis dans `server.cfg` :

```
add_ace group.police mdc.use allow
add_principal identifier.license:xxxxxxxx group.police
```
