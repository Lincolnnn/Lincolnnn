# Mise à jour vers MDC 6.0 (site 6.0.0, ressource rp_mdc 6.0.0)

## Ce qui change

| | 5.x | 6.0 |
|---|---|---|
| Site | fenêtres flottantes, dock, espaces de travail | **console CAD** : colonnes Unités · En attente · Actives, panneau d'outil à droite, ligne de commande |
| Affectation | listes déroulantes | **glisser une unité sur une carte** (ou `AS <unité> <n°>`) |
| Interventions | modifiables | modifiables **en cours, à valider ou terminées** — sur le site **et en jeu** (police) |
| Suppression | corbeille (30 jours, restauration) | **définitive**, avec confirmation ; copie des fiches supprimées dans l'**audit** |
| Note de service | — | **nouvelle** : bandeau commun au site et au MDC de police en jeu, modifiable des deux côtés |
| LiveView | ~2 images / s (captures + relais LiveKit) | **vidéo WebRTC jusqu'à 30 i/s**, écrite de zéro, sans relais ni `screenshot-basic` |
| Sons en jeu | — | intervention qui apparaît : **inter.wav** ; affectation par le dispatch : **son de notification seul** |

## Étapes

1. **Sauvegardez la base MySQL** (la migration supprime ce qui était encore à la corbeille).
2. Ressource : remplacez `rp_mdc` (gardez votre `config/`), redémarrez-la. La migration `005_v6` s'applique seule :
   - interventions et messages encore à la corbeille : **effacés pour de bon** ;
   - tables `mdc_trash` et `mdc_web_layouts` : **retirées**.
3. `screenshot-basic` n'est plus nécessaire au LiveView (gardez-la si une autre ressource s'en sert).
4. Site : remplacez les fichiers (gardez `.env`), `npm install --omit=dev`.
   - dans `.env`, **supprimez** `LIVEKIT_*`, `LIVE_UPLOAD_URL`, `LIVE_MAX_KBPS` ;
   - **ajoutez** au besoin `LIVE_TURN_URLS` + `LIVE_TURN_SECRET` (conseillé), voir
     [LIVEVIEW_WEBRTC.md](LIVEVIEW_WEBRTC.md) et `.env.example` ;
   - le serveur relais LiveKit peut être arrêté (`deploy/livekit.yaml` n'existe plus).
5. Droits MySQL de l'utilisateur du site : les lignes `mdc_trash` et `mdc_web_layouts` ne servent plus.
6. Redémarrez le site.

## Réglages en jeu (`rp_mdc`, `server/server.lua` → `Config`)

- `ServiceNoteLength = 1500` : longueur maximale de la note de service.
- `ServiceNoteEditInGame = true` : les agents de police (KCSO, WSP) peuvent la modifier en jeu ; `false` : dispatch seul.
- `TrashDays` n'existe plus.

## Tests à faire après la mise à jour

1. Site : les colonnes s'affichent, la note de service est en haut ; `?` ouvre l'aide des commandes.
2. Glisser une unité sur une intervention en attente : elle passe dans *Actives* avec l'étiquette de l'unité.
3. En jeu (police) : la note de service est en haut du MDC ; une nouvelle intervention joue **inter.wav** ; une
   affectation par le dispatch ne joue **que** le son de notification.
4. Clôturer une intervention, la modifier depuis *Terminées*, puis la supprimer : elle disparaît du jeu et du site,
   l'audit garde la trace.
5. LiveView : cocher un joueur, la vidéo démarre en quelques secondes ; agrandir (double-clic) ; le pied de tuile
   indique ~30 i/s et *direct* ou *TURN*.

## Retour arrière

Restaurez la sauvegarde MySQL, remettez les fichiers 5.1 de `rp_mdc` et du site, et l'ancien `.env`.
