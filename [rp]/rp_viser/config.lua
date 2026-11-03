--[[
    RP Viser - configuration
    /viser             : passe d'un mode à l'autre (et dit lequel est actif)
    /viser maintenir   : MAINTENIR le clic droit pour viser (comme de base dans le jeu)
    /viser appuyer     : APPUYER une fois pour viser, encore une fois pour arrêter (comme un jeu de tir)
    Le choix est gardé chez chaque joueur.
]]

ViserConfig = {
    Command = 'viser',
    Default = 'hold',            -- 'hold' (maintenir) ou 'toggle' (appuyer) pour un joueur qui n'a jamais choisi
    AimControl = 25,             -- clic droit (INPUT_AIM) ; manette : gâchette gauche (même contrôle)
    -- Mode « appuyer » : la visée s'arrête toute seule si l'arme est rangée / changée, en véhicule, à terre, mort,
    -- menotté, ou quand une interface (menu, MDC, chat…) prend la souris
    ChatTitle = 'Visée',
}
