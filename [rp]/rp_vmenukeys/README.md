# rp_vmenukeys

Empêche vMenu de s'ouvrir sur **V** : la touche d'ouverture, celle du noclip et le nom des raccourcis de vMenu sont
**imposés par le serveur**, quel que soit le `permissions.cfg` de vMenu. vMenu n'est pas modifié ; aucun framework.

## Pourquoi V ?

vMenu (3.6 et après) ouvre son menu avec un **raccourci FiveM** (`vMenu:<id>:MenuToggle`), dont la touche par défaut
vient de `vmenu_menu_toggle_key` et le nom de `vmenu_keymapping_id`. Ces réglages attendent un **nom de touche**
(`M`, `F2`). Une mise à jour automatique remet un ancien `permissions.cfg` avec des **numéros de contrôle** (`244`,
`289`), qui ne sont pas des noms de touches. Chez vous, vMenu se retrouve alors sur V. Le raccourci est ensuite
mémorisé chez chaque joueur sous ce nom, ce qui explique pourquoi changer le fichier ne suffit pas toujours.

## Ce que fait le script

- Il impose `vmenu_menu_toggle_key` (`MenuKey`, M), `vmenu_noclip_toggle_key` (`NoClipKey`, F2) et
  `vmenu_keymapping_id` (`MappingId`, `rp_m`). Il le fait au démarrage, une image plus tard, quand vMenu redémarre et
  à chaque connexion d'un joueur, avant que son vMenu ne démarre.
- **Nouveau nom de raccourci** (`rp_m`) : aucun joueur n'a de touche enregistrée sous ce nom, donc **M s'applique à
  tout le monde**. L'ancien raccourci réglé sur V (`vMenu:Default:MenuToggle`…) n'existe plus et ne fait plus rien.
- Si un autre fichier `.cfg` remet une autre valeur, la console l'affiche une fois en jaune.
- Au démarrage, la console affiche les valeurs trouvées puis celles imposées :
  `[rp_vmenukeys] vMenu : ouverture M, noclip F2, raccourcis vMenu:rp_m:* (avant : …)`.
- `/vmenutouches` (chat ou F8) : affiche chez le joueur les réglages que son vMenu a reçus.

## Installation

1. Copiez `rp_vmenukeys` dans `resources/`.
2. Dans `server.cfg` : `ensure rp_vmenukeys`, de préférence **avant** `ensure vMenu`. L'ordre par rapport à la ligne
   `exec` du `permissions.cfg` n'a pas d'importance.
3. Redémarrez le serveur, puis **reconnectez-vous** : vMenu lit ces réglages à la connexion.

Chaque joueur peut ensuite choisir sa touche : Échap > Paramètres > Raccourcis clavier > FiveM >
« vMenu Toggle Button ». Pour imposer une autre touche à tout le monde, changez `MenuKey` **et** `MappingId`
(`rp_m2`…).

## Performance

Aucune boucle : seulement des événements (démarrage, connexion d'un joueur).
