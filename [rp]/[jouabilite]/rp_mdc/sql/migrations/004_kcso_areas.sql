-- MDC 5.1 : secteurs du KCSO précisés à la création d'un appel (case « KCSO » cochée par un civil ou le dispatch)
-- Valeurs séparées par « + » : uninc (Non-incorporé), maplevalley (Maple Valley), kenmore (Kenmore). Vide : aucun.
ALTER TABLE mdc_calls ADD COLUMN kcso_areas VARCHAR(40) NOT NULL DEFAULT '';
