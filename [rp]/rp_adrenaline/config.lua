--[[
    RP Adrénaline - configuration
    ==============================
    Quand le joueur est TOUCHÉ PAR BALLE, le script compte les coups de feu entendus à moins de ShotRange m autour de
    lui (soi, autres joueurs, PNJ : rp_weaponscontrol) pendant les ShotWindow dernières secondes :
      - ADRÉNALINE HAUTE : au moins High.MinBullets balles reçues ET plus de High.MinShots tirs autour ->
        chutes au hasard pendant High.Duration s, une toutes les High.Every[1] à High.Every[2] s ;
      - ADRÉNALINE BASSE : au moins Low.MinBullets balle ET moins de Low.MaxShots tirs autour -> chutes pendant
        Low.Duration s (mêmes intervalles au hasard) ;
      - entre les deux (Medium) : chutes pendant Medium.Duration s.
    À chaque chute, l'arme à feu tenue est lâchée au sol une fois sur DropChance (3 = une fois sur trois) : elle se
    reprend avec l'œil (« Ramasser », rp_vehicleprops). Une nouvelle blessure plus grave prolonge / relève le niveau.
    Chutes à pied seulement : en véhicule, la chute prévue est sautée (les suivantes ont lieu si on descend avant la fin).
]]

AdrenalineConfig = {
    ShotRange = 30.0,      -- m autour du joueur
    ShotWindow = 30,       -- s : tirs comptés sur les 30 dernières secondes
    BulletWindow = 20,     -- s : balles reçues comptées sur les 20 dernières secondes

    High   = { MinBullets = 2, MinShots = 10, Duration = 50, Every = { 3, 10 } },   -- plus de 10 tirs
    Low    = { MinBullets = 1, MaxShots = 5, Duration = 15, Every = { 3, 10 } },    -- moins de 5 tirs
    Medium = { MinBullets = 1, Duration = 30, Every = { 3, 10 } },                  -- de 5 à 10 tirs

    RagdollTime = { 1200, 2600 }, -- ms au sol à chaque chute (au hasard entre les deux)
    DropChance = 3,               -- 1 chance sur 3 de lâcher l'arme à feu tenue à chaque chute (0 : jamais)
    Debug = false,                -- détails dans la console F8
}
