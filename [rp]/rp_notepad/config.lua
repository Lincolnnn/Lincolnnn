--[[
    RP Notepad - configuration
    /notepad (ou la touche, U par défaut ; chaque joueur peut la changer : Paramètres > Raccourcis clavier > FiveM)
    ouvre le bloc-notes ; à nouveau : le ferme. En « mode visuel » (bouton œil) : le bloc reste affiché, on peut
    marcher ; la touche revient à l'écriture.
]]

NotepadConfig = {
    Command = 'notepad',
    Key = 'U',               -- touche par défaut (J est déjà « à genoux » dans les tips d'arrestation)
    MaxPages = 30,           -- pages au plus
    Lines = 13,              -- lignes par page (le texte qui dépasse passe à la page suivante)
    -- Animations (personnage + props tenus) : choisies dans le bloc-notes ; la première est celle par défaut
    Anims = {
        { id = 'notepad', label = 'Bloc-notes', dict = 'missheistdockssetup1clipboard@base', anim = 'base',
          props = {
              { model = 'prop_notepad_01', bone = 18905, pos = { 0.1, 0.02, 0.05 }, rot = { 10.0, 0.0, 0.0 } },
              { model = 'prop_pencil_01', bone = 58866, pos = { 0.11, -0.02, 0.001 }, rot = { -120.0, 0.0, 0.0 } },
          } },
        { id = 'pen', label = 'Stylo pointé', dict = 'pointpen@cartoon', anim = 'pointpen_clip', -- pack d'animations (facultatif)
          props = {
              { model = 'prop_pencil_01', bone = 36029, pos = { 0.062, 0.031, 0.010 }, rot = { 21.55, 42.39, -41.31 } },
              { model = 'prop_notepad_01', bone = 6286, pos = { 0.055, 0.026, -0.037 }, rot = { 179.14, -6.25, 162.11 } },
          } },
        { id = 'none', label = 'Sans animation', props = {} },
    },
}
