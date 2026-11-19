# MDC 6.2 — LiveMAP, JEUX, journal neutre, son dsp partout

À mettre à jour : la ressource **rp_mdc** (jeu) ET le site **mdc-web** (redémarrer `node src/server.js`).
Aucune migration MySQL.

## LiveMAP (nouveau)
- Bouton **carte** dans la barre d'outils de droite (ou commande `MAP`, `MAP Adam 12`).
- Fenêtre flottante : déplacer par la barre de titre, **redimensionner par le coin bas-droit**, plein écran,
  molette = zoom, glisser = déplacer, double-clic = zoomer, flèches du clavier.
- Position **exacte** de chaque unité (point coloré selon le statut, flèche = cap, nom + n° d'intervention),
  déplacement animé ; survol : agents, rue, vitesse. Clic sur un marqueur : menu de l'unité (statut,
  message, affectation, LiveView). Liste à droite : clic = centrer, double-clic = suivre.
- Filtre Toutes / KCSO / WSP. Position de plus de 60 s : marqueur estompé.
- Envoi par le jeu : seulement les agents **dans une unité**, seulement si le site est relié
  (`mdc_web_key` + `mdc_web_url`), 1 envoi / s au plus quand l'agent bouge (3 m / 12°) ou toutes les 15 s.
  0,00 ms sinon.
- Carte : tuiles générées depuis les 6 images `minimap_*.png` (4 niveaux de zoom, WebP) dans
  `public/assets/map/tiles`. Calage dans `public/assets/map/map.json` (coins de la minimap :
  x −4140 → 4860, y 8400 → −5100). À ajuster seulement si les unités apparaissent décalées.

## Commande JEUX
- Accepte `JEUX texte`, `jeux texte`, `/jeux texte`. Le message affiché confirme le nombre de joueurs touchés,
  une erreur du serveur FiveM s'affiche clairement.
- Les fichiers du site ne restent plus en cache dans le navigateur : une mise à jour s'applique au
  rechargement (cause probable de « JEUX ne marche pas » : ancien `app.js` gardé en cache).
- `Config.ChatResource` (facultatif) si le chat ne s'appelle pas `rp_chat` ; sans rp_chat : `chat:addMessage`.

## Interventions
- Plus aucun « par le dispatch » dans le journal des appels : « Adam 12 (agents) a rejoint l'appel »,
  « … a quitté l'appel », « Modifiée : … », « Clôturée », « Rouverte », « Annulée »…
- Les messages du dispatch aux unités ne sont plus copiés dans le journal de l'appel.
- La ligne « Dispatch : Validée par … » n'apparaît plus dans la fiche en jeu (sauf « En attente de validation »).
- **Son dsp.wav pour TOUTE modification d'un appel**, chez TOUS les agents rattachés (auteur compris) :
  notes, notes modifiées, fiches liées, statuts des unités, modifications, clôture, réouverture… Un seul son
  par action (pas de doublon avec le son d'affectation).

## LiveView
- L'incrustation (PiP) se **redimensionne à la souris** : poignée dans le coin tourné vers le centre de
  l'écran ; la taille est gardée dans le navigateur.
