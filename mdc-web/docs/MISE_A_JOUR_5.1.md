# MDC 5.1 — notes de mise à jour

`rp_mdc` **5.1.0** et `mdc-web` **3.1.0**, à mettre à jour ensemble (après la 5.0 : [MISE_A_JOUR_5.0.md](MISE_A_JOUR_5.0.md)).

## Changements

| Sujet | Ce qui change |
|---|---|
| **Blocs** | Plus aucun bloc automatique : supprimés `config/blocs.json`, `config/LISEZMOI.txt`, l'éditeur `/blocs` (`client/blockeditor.lua`, `html/blockeditor.js`, `Config.BlockEditorAce`) et la commande `/mdc_pos` ; plus de bloc sur le **PLD**, ni dans **« Position actuelle »** (adresse et croisement seulement), ni dans la position des unités envoyée au **MDC Web**, ni dans les **rapports**. Le **bloc** ne reste que dans la **localisation des interventions et incidents** (champ « Bloc », saisi à la main). |
| **Secteurs du KCSO** | Case **KCSO** cochée à la création d'un appel (civil, police, dispatch) : cases **Non-incorporé**, **Maple Valley**, **Kenmore** (une à trois, au moins une). Affichés dans la fiche, la notification des unités, les listes du site ; modifiables avec l'intervention. |
| **Données de démonstration** | `mdc_demo` refait **comme un vrai joueur** : personnage enregistré puis ajouté au registre ; pour les rapports, personnes et véhicules enregistrés, intervention créée, traitée et clôturée, rapport lié à l'intervention. Dates entre **10 mois en arrière et aujourd'hui**, jamais dans le futur. La purge retire aussi les véhicules et interventions de démonstration. |

## Migration

1. Sauvegardez la base.
2. Remplacez `rp_mdc` (les fichiers des blocs n'existent plus : supprimez l'ancien dossier avant de copier le nouveau,
   ou retirez `config/blocs.json`, `config/LISEZMOI.txt`, `client/blockeditor.lua`, `html/blockeditor.js`) et
   redémarrez la ressource : la migration **`004_kcso_areas.sql`** (colonne `mdc_calls.kcso_areas`) s'applique seule.
3. Remplacez les fichiers du site (gardez `.env`), `npm install --omit=dev`, redémarrez. Aucun nouveau droit MySQL.
4. Données de démonstration déjà présentes (ancienne version) : `mdc_demo regen` dans la console du serveur (purge
   puis création).

Appels KCSO créés **avant** la 5.1 : ils n'ont pas de secteur ; à leur prochaine **modification** (en jeu ou sur le
site), le formulaire demande d'en cocher au moins un.

## Retour arrière (vers 5.0)

Remettez les dossiers 5.0 (`rp_mdc`, `mdc-web`) et redémarrez. La 5.0 ignore la colonne `kcso_areas` (les secteurs
saisis restent dans la base, invisibles). Pour l'effacer (facultatif, après sauvegarde) :

```sql
ALTER TABLE mdc_calls DROP COLUMN kcso_areas;
DELETE FROM mdc_schema_migrations WHERE version = '004_kcso_areas';
```

La 5.0 attend `config/blocs.json` : remettez le fichier de la 5.0 (sinon le PLD affiche seulement un avertissement
dans la console, sans bloc). Données de démonstration : `mdc_demo regen` après le retour arrière.

## Tests manuels

- [ ] PLD : rue, zone, croisement, heure — **aucun** « Bloc ».
- [ ] Créations > Intervention > « Position actuelle » : adresse et croisement remplis, **bloc vide** (à saisir).
- [ ] `/blocs` et `/mdc_pos` n'existent plus.
- [ ] MDC Web, fenêtre Unités : position « rue · croisement », sans bloc.
- [ ] Civil : cocher **KCSO** → 3 cases de secteur ; enregistrer sans secteur → refus ; cocher Maple Valley + Kenmore →
      appel créé, « Secteur KCSO : Maple Valley, Kenmore » dans la fiche et la notification des unités KCSO.
- [ ] Décocher KCSO (WSP seule) : les cases disparaissent.
- [ ] Site : nouvelle intervention / nouvel incident avec KCSO : mêmes cases, même refus ; modification des secteurs
      (entrée « Secteur KCSO » au journal de l'intervention).
- [ ] `mdc_demo regen` : Recherches > Sex / Kidnapping Offenders remplis ; un rapport de démonstration s'ouvre avec son
      intervention (n° RD) ; les personnes et véhicules du rapport se trouvent dans Recherches ; toutes les dates entre
      il y a 10 mois et aujourd'hui ; `mdc_demo purge` retire tout (fiches des joueurs intactes).

## Tests automatiques exécutés

Serveur (Lua réel + MariaDB) : toutes les suites, dont `test_kcso_areas` (13 vérifications) et `test_demo` refait
(33 vérifications : parcours joueur, dates, liens, purge, regen). MDC en jeu (Chromium) : formulaire d'appel avec
secteurs, PLD et « Position actuelle » sans bloc, non-régression. Site de bout en bout : 79 vérifications (dont
secteurs KCSO à la création et à la modification, positions sans bloc). Non testé : le vrai client FiveM.
