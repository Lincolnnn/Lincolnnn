# weapon_t7 — taser addon `WEAPON_T7`

Deuxième taser, en **arme addon** : il s'ajoute au jeu sans toucher au `WEAPON_STUNGUN`
(votre taser replace reste en place). 100 % standalone, aucun framework.

## Comportement

Copie du taser du jeu (`WEAPON_STUNGUN`) :

- dégâts électriques non mortels : la cible tombe au sol et se relève ensuite ;
- portée 11 m, environ 2,8 s entre deux tirs (recharge) ;
- munitions infinies (`AMMO_STUNGUN`) ;
- animations, sons et effets du taser ;
- rangé dans la catégorie « taser » de la roue des armes, avec son propre emplacement
  (`SLOT_WEAPON_T7`) : les deux tasers peuvent être portés en même temps.

Le nom affiché en jeu est **Taser T7** (`client.lua`).

## Installation

1. Mettez le dossier `weapon_t7` dans `resources`.
2. Placez votre modèle dans `stream/`, renommé en `w_pi_t7.ydr` et `w_pi_t7.ytd` (voir `stream/LISEZMOI.txt`).
3. Ajoutez `ensure weapon_t7` dans `server.cfg`, avant les scripts qui donnent l'arme.
4. Redémarrez le serveur. Une ressource d'arme addon ne se recharge pas proprement à chaud
   (`restart weapon_t7`) : les joueurs doivent se reconnecter.

## Donner l'arme

- **Menu d'interactions** (F1 > Équipements) : ajoutez ce lot dans `rp_interact/data/loadouts.json`
  (ou mettez `WEAPON_T7` dans un lot existant), puis tapez `rpi_vehicles` dans la console serveur :

  ```json
  {
      "Name": "Taser T7",
      "Replace": false,
      "Weapons": [
          { "Weapon": "WEAPON_T7", "Ammo": 1, "Components": [] }
      ]
  }
  ```
- **Depuis un script** : `GiveWeaponToPed(PlayerPedId(), GetHashKey('WEAPON_T7'), 1, false, true)`.

## Pas de modèle 3D ?

L'arme fonctionne, mais elle est invisible en main. Pour reprendre le modèle du taser du jeu (ou de votre replace) :

1. dans `meta/weapon.meta`, remplacez `<Model>w_pi_t7</Model>` par `<Model>w_pi_stungun</Model>` ;
2. dans `fxmanifest.lua`, retirez les deux lignes `weaponarchetypes.meta`.

## Performance

Aucune boucle : un seul `AddTextEntry` au démarrage, donc 0.00 ms.

## Crédits

Les fichiers `meta/` sont adaptés du modèle `WEAPON_STUNGUN` de
[CENSOR37/FiveM-AddonWeaponTemplates](https://github.com/CENSOR37/FiveM-AddonWeaponTemplates),
sous licence MIT (© 2022 CENSOR_1337). Le texte de la licence est dans `LICENSE-TEMPLATE.txt`.
