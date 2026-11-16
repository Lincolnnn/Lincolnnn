# MDC 5.0 — notes de mise à jour, retour arrière, tests manuels

Concerne la ressource FiveM **`rp_mdc` 5.0.0** et le site **`mdc-web` 3.0.0**. Les deux se mettent à jour **ensemble**.

## 1. Lots livrés

| Lot | Contenu |
|---|---|
| **1. Design verre** | nouveau système visuel (verre dépoli sombre, accents Dispatch / KCSO / WSP, thème jour), repli automatique **sans flou** si l'affichage est lent, bouton « transparence réduite », respect de « réduire les animations » |
| **2. Fenêtres flottantes** | chaque outil est une fenêtre **déplaçable, redimensionnable, réductible, agrandissable, épinglable, fermable** ; **dock** (fenêtres ouvertes, badges) ; **espaces de travail** *Dispatch / Enquête / Supervision* ; position et taille **gardées par dispatcher sur le serveur** (table `mdc_web_layouts`, repli navigateur) ; **palette de commandes** (Ctrl + K : actions, fenêtres, interventions, unités, conversations, joueurs) ; **menus clic droit** (intervention, unité, conversation, fiche, écran LiveView) ; squelettes de chargement ; **confirmation** avant toute action destructive ; tablette (fenêtres empilées) ; accessibilité (fenêtres nommées, dock et boutons libellés, clavier) |
| **3. Gestion** | **supprimer** (corbeille), **modifier**, **rouvrir** : interventions et incidents (même terminés), identités, véhicules, rapports, BOLO, conversations (vider / supprimer) ; **corbeille** (30 jours, `Config.TrashDays`) avec **restauration** et **purge définitive** ; **journal automatique** dans les notes de l'intervention (création, validation, affectations, statuts des unités, modifications, messages du dispatch, clôture, réouverture), filtre *Tout / Notes / Journal* ; **journal d'audit séparé** (`mdc_audit` : qui, quoi, quand, avant / après) ; propagation **en temps réel** (jeu et site), en jeu **son seul** pour une modification |
| **4. Registres** | sur le site, les registres du jeu avec **les mêmes champs, libellés et filtres** et **la même source de données** (le site interroge le serveur FiveM) : *Sex Offenders*, *Kidnapping Offenders* (niveau, inscriptions terminées, recherche), **BOLO** (type, recherche, fiche, modification, suppression), **Rapports** (type, recherche, 25 par page, fiche générée depuis les modèles du jeu, modification des champs) |
| **5. LiveView WebRTC** | vidéo ~2 images/s par **serveur relais LiveKit avec TURN**, une salle par joueur, jetons signés par le site, consultation journalisée, retrait côté relais, plafonds de flux / taille / débit, mosaïque, épingler, masquer, retirer, glisser-déposer, filtres (service, unité, nom), **incrustation (PiP)** déplaçable et plein écran qui reste visible partout, indicateurs i/s / délai / résolution ; **repli automatique** sur les images JPEG — voir [LIVEVIEW_WEBRTC.md](LIVEVIEW_WEBRTC.md) |
| **6. Tests, documentation** | ce document, le guide LiveView, `deploy/livekit.yaml` |

## 2. Migration

1. **Sauvegardez la base** (`mysqldump fivem > avant-5.0.sql`) et gardez une copie des dossiers `rp_mdc/` et `mdc-web/`
   actuels (voir *Retour arrière*).
2. **FiveM** : remplacez le dossier `rp_mdc` (le nouveau contient `html/vendor/livekit-client.umd.js`, la bibliothèque
   WebRTC chargée seulement pendant une diffusion LiveView) et redémarrez la ressource. La migration
   **`003_v5.sql`** s'applique seule au démarrage :
   - colonnes `deleted_at` sur `mdc_calls` et `mdc_messages` (+ index) ;
   - tables `mdc_trash`, `mdc_audit`, `mdc_web_layouts`.
   Les données existantes ne sont ni modifiées ni supprimées.
3. **Site** : remplacez les fichiers (gardez `.env`), `npm install --omit=dev`, redémarrez.
4. **Droits MySQL de l'utilisateur du site** (si vous utilisez un utilisateur limité, section 2 du README) :
   ```sql
   GRANT SELECT ON fivem.mdc_trash TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_audit TO 'mdc_web'@'localhost';
   GRANT SELECT, INSERT, UPDATE ON fivem.mdc_web_layouts TO 'mdc_web'@'localhost';
   ```
5. **Facultatif — vidéo WebRTC** : installez le relais et ajoutez au `.env` :
   `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` (+ `LIVEKIT_API_URL`, `LIVE_MAX_KBPS`) — guide
   [LIVEVIEW_WEBRTC.md](LIVEVIEW_WEBRTC.md). Sans ces variables : LiveView en images comme en 4.0.
6. Les dispatchers retrouvent l'espace *Dispatch* par défaut ; leur disposition est ensuite gardée sur le serveur.

Nouvelles variables `.env` (toutes facultatives) : `LIVEKIT_URL`, `LIVEKIT_API_URL`, `LIVEKIT_API_KEY`,
`LIVEKIT_API_SECRET`, `LIVEKIT_ROOM_PREFIX` (`mdc-live-`), `LIVE_MAX_KBPS` (900).
Nouveau réglage FiveM : `Config.TrashDays` (30) dans `server/server.lua`.

## 3. Retour arrière (vers 4.0.1)

La 4.0.1 **ignore** les nouvelles colonnes et tables : on peut revenir en arrière **sans toucher à la base**.

1. Arrêtez le site et la ressource `rp_mdc`.
2. Remettez les dossiers `rp_mdc/` et `mdc-web/` de la 4.0.1 (copie gardée, ou `git checkout <commit 4.0.1> -- "[rp]/[jouabilite]/rp_mdc" mdc-web`),
   `npm install --omit=dev` dans `mdc-web`.
3. Redémarrez la ressource puis le site.

À savoir :
- les éléments **dans la corbeille** au moment du retour arrière : les **interventions** et **messages** corbeillés
  **réapparaissent** en 4.0.1 (elle ne lit pas `deleted_at`) ; les **fiches** (identités, véhicules, rapports, BOLO)
  corbeillées restent absentes (elles ne sont que dans `mdc_trash`). Restaurez ce qui doit l'être **avant** de
  revenir en arrière, ou videz la corbeille ;
- les notes « JOURNAL » ajoutées aux interventions restent visibles comme des notes ordinaires ;
- pour effacer complètement la 5.0 de la base (facultatif, **après** sauvegarde) :
  ```sql
  DROP TABLE mdc_trash; DROP TABLE mdc_audit; DROP TABLE mdc_web_layouts;
  ALTER TABLE mdc_calls DROP KEY idx_calls_deleted, DROP COLUMN deleted_at;
  ALTER TABLE mdc_messages DROP KEY idx_messages_deleted, DROP COLUMN deleted_at;
  DELETE FROM mdc_schema_migrations WHERE version = '003_v5';
  ```
- relais LiveKit : il suffit de retirer `LIVEKIT_*` du `.env` (le site repasse en images) ; le relais peut rester
  arrêté.

## 4. Tests manuels sur le serveur

Cochez sur votre serveur (deux joueurs au moins : un civil, une unité KCSO ou WSP ; un dispatcher sur le site).

**Fenêtres et ergonomie**
- [ ] Connexion : espace *Dispatch* (Indicateurs, File de validation, Unités, Interventions).
- [ ] Déplacer, redimensionner, réduire (dock), agrandir (double-clic sur l'en-tête), épingler, fermer une fenêtre.
- [ ] Changer d'espace (*Enquête*, *Supervision*) puis revenir : fenêtres à leur place ; recharger la page : idem ;
      autre navigateur, même compte Discord : idem.
- [ ] Ctrl + K : chercher « corbeille », un n° RD, une unité, un joueur.
- [ ] Clic droit sur une intervention, une unité, une conversation, une fiche de registre, un écran LiveView.
- [ ] Bouton « transparence réduite » ; thème jour ; tablette (≈ 1024 px).

**Gestion**
- [ ] Appel d'un civil (mode Dispatch actif) → valider avec une unité → notes « Journal » : création, validation,
      affectation ; changer le statut de l'unité en jeu → entrée « Journal ».
- [ ] Modifier l'intervention (site) → en jeu : **son seul**, nouvelles valeurs, « INTERVENTION MODIFIÉE ».
- [ ] Clôturer → **Rouvrir** → modifier après clôture.
- [ ] Supprimer l'intervention → disparaît du jeu et du site → **Corbeille** → Restaurer → réapparaît partout.
- [ ] Vider une conversation, écrire de nouveau (fil recréé) ; restaurer depuis la corbeille.
- [ ] Modifier / supprimer / restaurer une identité, un véhicule, un rapport, un BOLO ; **purge définitive**.
- [ ] **Audit** : chaque opération ci-dessus listée avec avant / après ; filtres type / action / recherche.
- [ ] Redémarrer la ressource : la corbeille est toujours là, les éléments corbeillés restent masqués.

**Registres**
- [ ] Sex / Kidnapping Offenders : mêmes personnes et mêmes filtres que dans le MDC en jeu.
- [ ] BOLO créé en jeu → visible sur le site → modifié sur le site → modifié dans le jeu.
- [ ] Rapports : filtre par type, recherche, pages, fiche lisible, modification d'un champ visible en jeu.

**LiveView** (avec relais configuré)
- [ ] Cocher un joueur : tuile en **WebRTC** (i/s ≈ 2, délai, 640x360) ; décocher : diffusion arrêtée en jeu.
- [ ] Incrustation (PiP) puis plein écran : 1280x720 ; fermer la fenêtre LiveView : l'incrustation reste.
- [ ] Masquer une tuile : plus d'image envoyée ; épingler ; glisser-déposer pour réordonner ; filtres service / unité.
- [ ] Dispatcher derrière un réseau restrictif (4G, entreprise) : la vidéo passe (TURN).
- [ ] Relais arrêté : la tuile repasse en **images** au bout de quelques secondes.
- [ ] Journal : « LiveView : écran consulté » (voie `webrtc` ou `images`).
- [ ] Retirer le rôle Discord du dispatcher : la vidéo s'arrête, la session se ferme.
- [ ] Performance en jeu du joueur regardé (F8 `resmon`) : rien hors LiveView ; pendant la diffusion, coût de
      `screenshot-basic` à 2 i/s acceptable sur votre matériel (sinon baisser la cadence côté site).

## 5. Tests automatiques exécutés avant livraison

- serveur (Lua réel + MariaDB) : persistance, dispatch, appels, justice, permis, export /id, 4.0, démo, **5.0**
  (journal, versions, modification après clôture, réouverture, corbeille et restauration de chaque type, purge,
  redémarrage) ;
- bout en bout (site Node réel + vraie base + vrai code serveur + vrais NUI dans Chromium) : **73 vérifications**
  (fenêtres, dock, espaces, persistance, palette, menus, journal automatique, son seul en jeu, clôture / réouverture,
  corbeille, conversations, registres, BOLO jeu ↔ site, rapports, identités, audit, jetons WebRTC, repli images,
  PiP, tablette, accessibilité, rôle retiré) ;
- NUI en jeu : publication WebRTC du canevas (bibliothèque simulée), changement de mode, arrêt, repli JPEG ;
- non-régression des MDC en jeu (recherches, permis, appels, blocs, carte /id) et du PLD.

Non testé ici : transport vidéo réel par un serveur LiveKit et TURN (voir le guide), rendu dans le vrai client FiveM.
