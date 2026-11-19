# Mise à jour vers MDC 6.1 (site 6.1.0, rp_mdc 6.1.0, rp_chat 1.30.0)

| | 6.0 | 6.1 |
|---|---|---|
| Actions du dispatch en jeu | notifications « … par le dispatch » | **aucune** : comme si un joueur l'avait fait (statut : notification de statut ; le reste : son `dsp`) |
| Sons d'un appel | `assign` / `deassign` / `dsp` | **`dsp.wav`** (sinon `dsp.mp3`) pour tout changement d'un appel où l'on est affecté ; nouvelle intervention : `inter.wav` |
| Journal d'un appel | « Adam 12 affectée » | **avec les agents** : « Adam 12 (Sam Carter) a rejoint / quitté l'appel », « … affectée / retirée par le dispatch » |
| Appel terminé / annulé | unités toujours rattachées | **unités détachées** (l'appel disparaît de leur appel en cours) ; **« Unités présentes »** gardées dans la fiche |
| Note de service | toujours affichée, modifiable par la police | **absente si vide** ; création / modification : **dispatch et superviseurs (SUP.)** |
| Messagerie | fil par intervention (« Dispatch — RD… ») | **retiré** (fiche du site et section DISPATCH en jeu) |
| LiveView | plein écran par superposition (instable) | **plein écran réel** (API du navigateur, Échap), vidéo jamais recréée (plus d'écran noir) |
| Nouvelle commande | — | **`JEUX <texte>`** : « DISPATCH : texte » dans le chat de tous les joueurs |

Étapes : remplacez `rp_mdc`, `rp_chat` et le site, redémarrez. La migration `006_v61` (colonne `past_units`)
s'applique seule. Son `dsp.wav` : déposez-le dans `rp_mdc/html/sounds/` (déjà déclaré par `html/sounds/*.wav`) ;
tant qu'il n'y est pas, le `dsp.mp3` fourni est joué à sa place.
