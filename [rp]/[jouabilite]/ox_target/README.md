# ox_target (pont vers l'œil de rp_interact)

Certains scripts **exigent ox_target** (dans leur `fxmanifest.lua` : `dependencies { 'ox_target' }`) et ne démarrent pas
sans lui : c'est le cas de **riven_spikes** (herses de Riven Systems). Cette ressource porte le **même nom**, offre les
**mêmes exports**, et affiche leurs options dans **notre œil** (Alt, `rp_interact`) : rien à changer dans leur code.

Ce n'est **pas** le vrai ox_target : ne pas installer les deux (même nom de dossier). Standalone, aucun framework.

## Installation

1. Le dossier `[rp]/ox_target/` est déjà là (le nom du dossier doit rester **ox_target**).
2. `server.cfg` : `ensure ox_target` (après `rp_interact`, avant les scripts qui l'exigent).
3. `rp_interact/config.lua` : `'ox_target'` est déjà dans `TargetProviders`.

## Ce qui est pris en charge

| Export d'ox_target | |
|---|---|
| `addGlobalVehicle`, `addGlobalPed`, `addGlobalPlayer`, `addGlobalObject`, `addGlobalOption` (et `removeGlobal…`) | options sur tous les véhicules, PNJ, joueurs, objets |
| `addModel`, `addEntity` (n° réseau), `addLocalEntity` (et `remove…`) | options sur des modèles / entités précis |
| `addSphereZone`, `addBoxZone` (avec rotation), `addPolyZone`, `removeZone`, `zoneExists` | options sur un endroit (le sol visé est dans la zone) |
| `disableTargeting` | coupe toutes ces options |

Libellés traduits (`config.lua` : `Translations`, par script) : les options de riven_spikes s'affichent **en
français dans l'œil** quelle que soit la langue réglée (« Prendre la herse dans le coffre », « Ranger la herse dans le
coffre », « Saisir le cordon », « Ramasser la herse »…).

Dans une option : `label`, `icon` (icône Font Awesome remplacée par une icône de l'œil, `config.lua` : `Icons`),
`distance` (7 m si absente), `bones` (partie du véhicule visée, ex. `boot` = coffre), `canInteract`, et l'action :
`onSelect`, `event`, `serverEvent`, `command` ou `export`. **Pas de `groups` / `items`** (aucun framework) : ces
conditions sont ignorées. Les options d'un script disparaissent quand il s'arrête.

`PoliceOnly` (`config.lua`) : les options de ces scripts ne sont proposées qu'aux **policiers en service** (dans une
unité du MDC). Par défaut : `riven_spikes`.

Options **mises en avant** dans l'œil (surlignées, en tête) : celles liées à une partie précise visée (`bones` : le
coffre…) et celles des scripts `PoliceOnly` (herses).

Options **cachées** dans l'œil (`HiddenPrefixes` : nom qui commence par…) : aucune par défaut. Elles restent utilisables par nos menus
avec l'export client **`runOption(nom, entité)`** (point visé = la partie demandée par l'option ; `canInteract`
respecté) → `true, 'ok'` ou `false, 'missing' | 'unavailable' | 'disabled'`.
Options d'autres scripts **retirées de l'œil par leur libellé** (`HiddenLabels`, majuscules et espaces ignorés) :
« Manage props » (script de props du serveur) par défaut.

Performance : rien ne tourne ; le travail se fait seulement pendant que l'œil vise.

## riven_spikes (herses, script payant)

Script de **Riven Systems** (licence, clé `riven_auth.token` liée au serveur) : **jamais dans ce dépôt** (`.gitignore`).

1. Installez **ox_lib** (gratuit : `ox_lib`, dernière version) dans `resources/` : riven_spikes s'en sert (textes,
   barre de progression, touches, notifications).
2. Copiez `riven_spikes/` tel que vous l'avez acheté (avec `riven_auth.token` et `stream/`) dans `resources/[rp]/`.
3. Remplacez son `config.lua` par la version fournie à part (lignes marquées `[RP]`), et dans `locales/` mettez
   `fr.json` **et** `en.json` fournis à part (tous deux en français : le texte reste français même sans
   `setr ox:locale fr`) : aides à l'écran (« [E] Maintenir pour lancer »…), barres de progression, notifications :
   - **sans inventaire** (`Config.Inventory = false`) : pas besoin d'ox_inventory ;
   - **un Stop Stick dans le coffre de chaque véhicule d'urgence** (classe 18 ; ni herse, ni Terminator) : œil sur
     le coffre, **« Prendre le Stop Stick dans le coffre »**, et une fois en main **« Ranger le Stop Stick dans le
     coffre »** ;
   - pas de commande `/spikestrip` (la herse se prend au coffre), outils de réglage coupés ;
   - textes en français (« Herse », « Glisser » / « Arracher »…).
4. `server.cfg` :
   ```
   setr ox:locale fr
   ensure ox_lib
   ensure ox_target
   ensure riven_spikes
   ```
   OneSync doit être activé (exigé par riven_spikes).

En jeu (policier en service) : **œil sur le coffre** d'un véhicule de police → **Prendre la herse dans le coffre** ;
**E** maintenu : lancer (relâcher) ; **X** ne la range plus dans la poche (elle revient en main) : la lancer / poser, ou
la ranger au coffre (œil) ; herse posée : l'œil sur la herse ou le bout du cordon → **Saisir le cordon** /
**Ramasser la herse** ; cordon en main : **E** pour la ramener, **Q** : mode (glisser / arracher).
Le **pistolet radar** se prend et se range dans le menu **Équipement** du coffre (`rp_equipment`, touche E).

Notifications de riven_spikes : celles d'**ox_lib** (en français avec les `.json` fournis), pas les messages privés
du chat : elles sont affichées par ox_lib lui-même.
