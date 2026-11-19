-- MDC 6.1 : une intervention terminée ou annulée est détachée de ses unités (elle disparaît de leur appel en cours)
-- mais garde la liste des unités et des agents qui y étaient (affichée dans sa fiche, jeu et site).
ALTER TABLE mdc_calls ADD COLUMN past_units VARCHAR(1000) NULL;
