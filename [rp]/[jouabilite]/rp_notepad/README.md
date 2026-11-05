# rp_notepad — bloc-notes en jeu

**Standalone**, Lua 5.4, `cerulean`. Pour **tous les joueurs**. Aucune boucle (0,00 ms).

`/notepad` (ou `/blocnotes`) ou la touche **F2** (modifiable : Paramètres > Raccourcis clavier > FiveM ; U est la portière
du véhicule) : ouvre / ferme le bloc-notes.
Le personnage prend le bloc et le crayon (animation et props, vus par tous). Inspiré d'un bloc-notes fourni, **réécrit**
au style du serveur : barre noire à bandeau rouge (couleur du mode nuit du MDC), papier de bloc à spirale dessiné en CSS
(lignes bleues, marge rouge), écriture manuscrite **Kalam** (licence libre SIL OFL, `html/fonts/OFL-Kalam.txt`).

| Fonction | Détail |
|---|---|
| **Texte** | écriture sur les lignes du papier ; une page pleine (13 lignes, `Lines`) : la suite passe **toute seule** à la page suivante (coupée à un espace) ; Retour arrière au début d'une page : retour à la fin de la précédente |
| **Dessin** | à la souris : encre bleue, noire, rouge, **gomme** |
| **Pages** | ‹ › (› sur la dernière : nouvelle page), 30 au plus (`MaxPages`) ; corbeille : effacer la page (deux clics) |
| **Animation** | liste dans la barre : Bloc-notes, Stylo pointé (pack d'animations, facultatif), Sans animation |
| **Mode visuel** (œil) | le bloc reste affiché sans curseur : on marche, plus d'animation ; la touche revient à l'écriture |
| **Fenêtre** | déplacer par la barre, agrandir / réduire par le coin ; gardé pour la prochaine fois |

**Tout est gardé chez le joueur** (stockage du client FiveM) : texte de chaque page, dessins, animation choisie et
**dernière page utilisée** : à l'ouverture, le bloc revient sur cette page, curseur à la fin du texte.

**MDC** : note de l'unité > **« Retranscription du notepad »** : le texte des pages écrites (« — Page n — » devant
chacune s'il y en a plusieurs) est ajouté à la fin de la note (2000 caractères au plus). Les dessins ne sont pas
retranscrits.

Exports (client) : `transcript()`, `pages()` (textes, page en cours), `isOpen()`.

## Installation

```
ensure rp_notepad
```
