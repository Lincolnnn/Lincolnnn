--[[
    RP First Person - configuration

    En vue à la 1re personne, le jeu met souvent le personnage en « MODE ACTION » : posture de combat courbée, démarche
    tactique, épaules rentrées. Pas seulement avec une arme à feu : aussi mains nues (après un coup, poings levés),
    avec une arme blanche, une lampe, un objet, après un tir ou une bagarre proche… Cette posture se voit chez le
    joueur ET chez les joueurs autour (le personnage est animé par son jeu puis synchronisé chez les autres).
    Ici, le mode action est coupé à chaque image tant que le joueur est à la 1re personne : posture normale, pour lui
    et pour tout le monde. Rien d'autre n'est touché (visée, tir, accroupi / furtif, emotes, course).
]]

FirstPersonConfig = {
    Enabled = true,

    -- Où la correction s'applique
    OnFoot = true,          -- à pied, à la 1re personne (armé ou non)
    ThirdPerson = false,    -- true : aussi à la 3e personne (posture de combat qui reste après un tir, un coup…)
    InVehicle = false,      -- true : aussi dans un véhicule (personnage qui en sort / y monte en mode action)

    -- Hors 1re personne (ou correction inutile) : une vérification toutes les CheckMs ms (0.00 ms)
    CheckMs = 250,

    -- Commande de test : coupe / remet la correction pour comparer en jeu ('' = aucune). Réglage non gardé.
    Command = 'fpsposture',
}
