-- MDC 5.0 : corbeille (suppression logique, restaurable), journal d'audit, dispositions des fenêtres du MDC Web

-- Interventions / incidents mis à la corbeille (la fiche reste, masquée, jusqu'à la purge)
ALTER TABLE mdc_calls ADD COLUMN deleted_at INT UNSIGNED NULL;
ALTER TABLE mdc_calls ADD KEY idx_calls_deleted (deleted_at);

-- Messages d'une conversation mis à la corbeille (tous ceux d'un même effacement portent la même date)
ALTER TABLE mdc_messages ADD COLUMN deleted_at INT UNSIGNED NULL;
ALTER TABLE mdc_messages ADD KEY idx_messages_deleted (channel, deleted_at);

-- Corbeille : un élément par suppression, restaurable jusqu'à expires_at (puis purge définitive automatique)
CREATE TABLE IF NOT EXISTS mdc_trash (
    id            INT UNSIGNED NOT NULL PRIMARY KEY,
    kind          VARCHAR(16)  NOT NULL,
    record_id     VARCHAR(40)  NOT NULL,
    label         VARCHAR(160) NOT NULL DEFAULT '',
    data          LONGTEXT     NULL,
    deleted_by    VARCHAR(60)  NOT NULL DEFAULT '',
    deleted_by_id VARCHAR(80)  NOT NULL DEFAULT '',
    deleted_at    INT UNSIGNED NOT NULL DEFAULT 0,
    expires_at    INT UNSIGNED NOT NULL DEFAULT 0,
    KEY idx_trash_kind (kind, record_id),
    KEY idx_trash_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Journal d'audit : chaque suppression, restauration, modification ou réouverture (qui, quoi, quand, avant, après)
CREATE TABLE IF NOT EXISTS mdc_audit (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    source      VARCHAR(16)  NOT NULL,
    actor_id    VARCHAR(80)  NOT NULL DEFAULT '',
    actor_name  VARCHAR(60)  NOT NULL DEFAULT '',
    action      VARCHAR(32)  NOT NULL,
    kind        VARCHAR(16)  NOT NULL,
    record_id   VARCHAR(40)  NOT NULL DEFAULT '',
    label       VARCHAR(160) NOT NULL DEFAULT '',
    before_data LONGTEXT     NULL,
    after_data  LONGTEXT     NULL,
    created_at  INT UNSIGNED NOT NULL DEFAULT 0,
    KEY idx_audit_created (created_at),
    KEY idx_audit_record (kind, record_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- MDC Web : fenêtres et espaces de travail de chaque dispatcher (identifiant Discord)
CREATE TABLE IF NOT EXISTS mdc_web_layouts (
    user_id     VARCHAR(32)  NOT NULL PRIMARY KEY,
    data        MEDIUMTEXT   NOT NULL,
    updated_at  INT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
