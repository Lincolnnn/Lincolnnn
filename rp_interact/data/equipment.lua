--[[
    RP Interact - Équipements du menu d'interactions (F1 > Équipements)
    ===================================================================
    Remplissez les listes ci-dessous à la main (même format que les exemples).

    TENUES (EUP) : Outfits
      name     : nom affiché dans le menu
      service  : 'Atlanta Police Department' | 'Georgia State Patrol' | nil (toutes)
      gender   : 'male' (mp_m_freemode_01) | 'female' (mp_f_freemode_01) ; seules les tenues du
                 personnage du joueur sont proposées
      components : [n° du composant] = { drawable, texture }
          1 masque, 3 bras/torse, 4 jambes, 5 sac, 6 chaussures, 7 accessoires (cravate…),
          8 sous-haut (t-shirt), 9 gilet pare-balles, 10 badges / décals, 11 haut (veste)
      props    : [n° de l'accessoire] = { drawable, texture } ; drawable -1 = retiré
          0 chapeau / casquette, 1 lunettes, 2 oreilles, 6 montre, 7 bracelet

    ARMES : Loadouts
      name     : nom affiché
      weapons  : { { weapon = 'WEAPON_…', ammo = munitions, components = { 'COMPONENT_…' } }, … }
      replace  : true = retire les armes du joueur avant de donner celles-ci

    Accès : réservé aux policiers en service (unité du MDC) si EquipmentPoliceOnly = true (config.lua).
    Après une modification : redémarrez la ressource (restart rp_interact).
]]

InteractEquipment = {
    Outfits = {
        -- Exemples (numéros de vêtements à adapter à votre pack EUP)
        { name = 'Patrouille APD (chemise manches courtes)', service = 'Atlanta Police Department', gender = 'male',
          components = { [3] = { 11, 0 }, [4] = { 35, 0 }, [6] = { 25, 0 }, [8] = { 58, 0 }, [9] = { 0, 0 }, [10] = { 0, 0 }, [11] = { 55, 0 } },
          props = { [0] = { -1, 0 } } },
        { name = 'Patrouille APD (chemise manches courtes)', service = 'Atlanta Police Department', gender = 'female',
          components = { [3] = { 14, 0 }, [4] = { 34, 0 }, [6] = { 25, 0 }, [8] = { 35, 0 }, [9] = { 0, 0 }, [10] = { 0, 0 }, [11] = { 48, 0 } },
          props = { [0] = { -1, 0 } } },
        { name = 'Trooper GSP (chapeau)', service = 'Georgia State Patrol', gender = 'male',
          components = { [3] = { 11, 0 }, [4] = { 35, 0 }, [6] = { 25, 0 }, [8] = { 58, 0 }, [11] = { 55, 0 } },
          props = { [0] = { 13, 0 } } },
    },

    Loadouts = {
        { name = 'Patrouille (pistolet, taser, lampe, matraque)', replace = true, weapons = {
            { weapon = 'WEAPON_COMBATPISTOL', ammo = 120, components = { 'COMPONENT_AT_PI_FLSH' } },
            { weapon = 'WEAPON_STUNGUN', ammo = 1 },
            { weapon = 'WEAPON_FLASHLIGHT', ammo = 1 },
            { weapon = 'WEAPON_NIGHTSTICK', ammo = 1 },
        } },
        { name = 'Fusil de patrouille (carabine)', replace = false, weapons = {
            { weapon = 'WEAPON_CARBINERIFLE', ammo = 180, components = { 'COMPONENT_AT_AR_FLSH', 'COMPONENT_AT_SCOPE_MEDIUM' } },
        } },
        { name = 'Fusil à pompe', replace = false, weapons = {
            { weapon = 'WEAPON_PUMPSHOTGUN', ammo = 40, components = { 'COMPONENT_AT_AR_FLSH' } },
        } },
    },
}
