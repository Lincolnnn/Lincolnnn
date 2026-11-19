-- MDC 6.0 : plus de corbeille. Les suppressions sont définitives (une copie des fiches supprimées reste dans
-- mdc_audit). Ce qui était encore à la corbeille est effacé pour de bon, et ses tables retirées.
-- Note de service : gardée dans mdc_settings (nom service_note), aucune table à créer.

DELETE FROM mdc_calls WHERE deleted_at IS NOT NULL;
DELETE FROM mdc_messages WHERE deleted_at IS NOT NULL;
DROP TABLE IF EXISTS mdc_trash;

-- MDC Web : les fenêtres flottantes (et leur disposition par dispatcher) n'existent plus
DROP TABLE IF EXISTS mdc_web_layouts;
