-- MDC 4.0 : n° de version des interventions (modifications du dispatch, conflits d'édition)
ALTER TABLE mdc_calls ADD COLUMN rev INT UNSIGNED NOT NULL DEFAULT 0;
