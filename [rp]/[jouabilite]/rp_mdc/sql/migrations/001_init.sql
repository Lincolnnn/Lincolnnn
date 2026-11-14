-- =====================================================================================================================
-- MDC (rp_mdc) - schéma MySQL / MariaDB, version 1
-- Appliqué AUTOMATIQUEMENT au démarrage de la ressource (server/db.lua, table mdc_schema_migrations).
-- Import manuel possible (phpMyAdmin, HeidiSQL, mysql < 001_init.sql) : les instructions sont rejouables.
-- Dates : secondes depuis 1970 (os.time() de Lua, Date.now()/1000 côté Web).
-- Fiches (identités, véhicules, rapports, BOLO) : colonnes indexées pour les recherches et les relations, et la fiche
-- complète dans `data` (JSON) pour ne perdre aucun champ (casier, permis, historique…).
-- Ne pas mettre de point-virgule dans les commentaires ou les textes : le fichier est découpé sur ce caractère.
-- =====================================================================================================================

CREATE TABLE IF NOT EXISTS mdc_settings (
    name        VARCHAR(64)  NOT NULL PRIMARY KEY,
    value       TEXT         NULL,
    updated_at  INT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Agents (joueurs) : nom RP, grade, dernier MDC utilisé
CREATE TABLE IF NOT EXISTS mdc_agents (
    identifier      VARCHAR(80)  NOT NULL PRIMARY KEY,
    rp_name         VARCHAR(40)  NOT NULL DEFAULT '',
    grade           VARCHAR(40)  NOT NULL DEFAULT '',
    agency          VARCHAR(16)  NOT NULL DEFAULT '',
    last_server_id  INT          NULL,
    last_seen       INT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Fiches créées par les civils (MDC générique) et consultées par les polices
CREATE TABLE IF NOT EXISTS mdc_identities (
    id          INT UNSIGNED NOT NULL PRIMARY KEY,
    created_by  VARCHAR(80)  NOT NULL DEFAULT '',
    lastname    VARCHAR(40)  NOT NULL DEFAULT '',
    firstname   VARCHAR(40)  NOT NULL DEFAULT '',
    dob         VARCHAR(10)  NOT NULL DEFAULT '',
    ssn         VARCHAR(11)  NOT NULL DEFAULT '',
    data        LONGTEXT     NOT NULL,
    created_at  INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at  INT UNSIGNED NOT NULL DEFAULT 0,
    KEY idx_identities_name (lastname, firstname),
    KEY idx_identities_creator (created_by)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mdc_vehicles (
    id          INT UNSIGNED NOT NULL PRIMARY KEY,
    created_by  VARCHAR(80)  NOT NULL DEFAULT '',
    plate       VARCHAR(16)  NOT NULL DEFAULT '',
    vin         VARCHAR(17)  NOT NULL DEFAULT '',
    owner_id    INT UNSIGNED NULL,
    data        LONGTEXT     NOT NULL,
    created_at  INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at  INT UNSIGNED NOT NULL DEFAULT 0,
    KEY idx_vehicles_plate (plate),
    KEY idx_vehicles_creator (created_by),
    KEY idx_vehicles_owner (owner_id),
    CONSTRAINT fk_vehicles_owner FOREIGN KEY (owner_id) REFERENCES mdc_identities (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Unités de police (persistantes) et leurs membres connectés
CREATE TABLE IF NOT EXISTS mdc_units (
    id          INT UNSIGNED NOT NULL PRIMARY KEY,
    agency      VARCHAR(16)  NOT NULL,
    name        VARCHAR(30)  NOT NULL,
    tag         VARCHAR(10)  NOT NULL DEFAULT '',
    color       VARCHAR(16)  NOT NULL DEFAULT 'gray',
    status      VARCHAR(16)  NOT NULL DEFAULT 'available',
    memo        TEXT         NULL,
    shared      LONGTEXT     NULL,
    created_at  INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at  INT UNSIGNED NOT NULL DEFAULT 0,
    KEY idx_units_agency (agency)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mdc_unit_members (
    unit_id     INT UNSIGNED NOT NULL,
    identifier  VARCHAR(80)  NOT NULL,
    server_id   INT          NOT NULL,
    joined_at   INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (unit_id, identifier),
    KEY idx_members_identifier (identifier),
    CONSTRAINT fk_members_unit FOREIGN KEY (unit_id) REFERENCES mdc_units (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Historique des statuts (dispatch : changements en temps réel, statistiques)
CREATE TABLE IF NOT EXISTS mdc_unit_status_log (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    unit_id     INT UNSIGNED NOT NULL,
    status      VARCHAR(16)  NOT NULL,
    changed_by  VARCHAR(80)  NOT NULL DEFAULT '',
    source      VARCHAR(16)  NOT NULL DEFAULT 'game',
    created_at  INT UNSIGNED NOT NULL DEFAULT 0,
    KEY idx_status_unit (unit_id, id),
    CONSTRAINT fk_status_unit FOREIGN KEY (unit_id) REFERENCES mdc_units (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Interventions (appels des civils) et incidents (déclarés par les unités)
-- dispatch_state : NULL (envoyé directement aux unités), awaiting (en attente du dispatch), validated, refused, cancelled
CREATE TABLE IF NOT EXISTS mdc_calls (
    id              INT UNSIGNED NOT NULL PRIMARY KEY,
    number          VARCHAR(12)  NOT NULL,
    kind            VARCHAR(16)  NOT NULL,
    title           VARCHAR(60)  NOT NULL,
    caller          VARCHAR(60)  NOT NULL DEFAULT '',
    phone           VARCHAR(20)  NOT NULL DEFAULT '',
    priority        VARCHAR(16)  NOT NULL DEFAULT '',
    response_code   TINYINT      NULL,
    agency          VARCHAR(32)  NOT NULL DEFAULT '',
    ideal_units     TINYINT      NULL,
    address         VARCHAR(80)  NOT NULL DEFAULT '',
    cross_street    VARCHAR(80)  NOT NULL DEFAULT '',
    block           VARCHAR(40)  NOT NULL DEFAULT '',
    sector          VARCHAR(40)  NOT NULL DEFAULT '',
    description     TEXT         NULL,
    unit_name       VARCHAR(30)  NOT NULL DEFAULT '',
    backup          TINYINT(1)   NOT NULL DEFAULT 0,
    requested_by    VARCHAR(16)  NOT NULL DEFAULT '',
    coords          VARCHAR(64)  NULL,
    closed          TINYINT(1)   NOT NULL DEFAULT 0,
    clear_code      CHAR(1)      NULL,
    dispatch_state  VARCHAR(16)  NULL,
    dispatch_reason VARCHAR(200) NOT NULL DEFAULT '',
    dispatch_by     VARCHAR(60)  NOT NULL DEFAULT '',
    dispatch_at     INT UNSIGNED NULL,
    created_by      VARCHAR(80)  NOT NULL DEFAULT '',
    created_by_name VARCHAR(60)  NOT NULL DEFAULT '',
    created_at      INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at      INT UNSIGNED NULL,
    updated_by_name VARCHAR(60)  NOT NULL DEFAULT '',
    closed_at       INT UNSIGNED NULL,
    closed_by_name  VARCHAR(60)  NOT NULL DEFAULT '',
    next_note_id    INT UNSIGNED NOT NULL DEFAULT 1,
    UNIQUE KEY uq_calls_number (number),
    KEY idx_calls_open (closed, dispatch_state),
    KEY idx_calls_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Unités affectées à un appel
CREATE TABLE IF NOT EXISTS mdc_call_units (
    call_id     INT UNSIGNED NOT NULL,
    unit_id     INT UNSIGNED NOT NULL,
    assigned_at INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (call_id, unit_id),
    KEY idx_call_units_unit (unit_id),
    CONSTRAINT fk_call_units_call FOREIGN KEY (call_id) REFERENCES mdc_calls (id) ON DELETE CASCADE,
    CONSTRAINT fk_call_units_unit FOREIGN KEY (unit_id) REFERENCES mdc_units (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Notes du déroulé d'un appel (unités et dispatch)
CREATE TABLE IF NOT EXISTS mdc_call_notes (
    call_id     INT UNSIGNED NOT NULL,
    note_id     INT UNSIGNED NOT NULL,
    unit_id     INT UNSIGNED NULL,
    unit_name   VARCHAR(30)  NOT NULL DEFAULT '',
    unit_tag    VARCHAR(10)  NOT NULL DEFAULT '',
    unit_color  VARCHAR(16)  NOT NULL DEFAULT '',
    author_name VARCHAR(60)  NOT NULL DEFAULT '',
    text        TEXT         NOT NULL,
    backup      VARCHAR(8)   NULL,
    dispatch    TINYINT(1)   NOT NULL DEFAULT 0,
    created_at  INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at  INT UNSIGNED NULL,
    PRIMARY KEY (call_id, note_id),
    CONSTRAINT fk_notes_call FOREIGN KEY (call_id) REFERENCES mdc_calls (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Identités / véhicules liés à un appel
CREATE TABLE IF NOT EXISTS mdc_call_links (
    call_id     INT UNSIGNED NOT NULL,
    kind        VARCHAR(16)  NOT NULL,
    record_id   INT UNSIGNED NOT NULL,
    added_by    VARCHAR(60)  NOT NULL DEFAULT '',
    added_at    INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (call_id, kind, record_id),
    CONSTRAINT fk_links_call FOREIGN KEY (call_id) REFERENCES mdc_calls (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mdc_reports (
    id          INT UNSIGNED NOT NULL PRIMARY KEY,
    number      VARCHAR(12)  NOT NULL DEFAULT '',
    type        VARCHAR(32)  NOT NULL DEFAULT '',
    call_id     INT UNSIGNED NULL,
    created_by  VARCHAR(80)  NOT NULL DEFAULT '',
    data        LONGTEXT     NOT NULL,
    created_at  INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at  INT UNSIGNED NOT NULL DEFAULT 0,
    KEY idx_reports_number (number),
    KEY idx_reports_call (call_id),
    CONSTRAINT fk_reports_call FOREIGN KEY (call_id) REFERENCES mdc_calls (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mdc_bolos (
    id          INT UNSIGNED NOT NULL PRIMARY KEY,
    number      VARCHAR(12)  NOT NULL DEFAULT '',
    kind        VARCHAR(16)  NOT NULL DEFAULT '',
    agency      VARCHAR(16)  NOT NULL DEFAULT '',
    data        LONGTEXT     NOT NULL,
    created_at  INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at  INT UNSIGNED NOT NULL DEFAULT 0,
    KEY idx_bolos_number (number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Messagerie. Canaux : u:A:B (unité A et unité B), d:u:ID (dispatch et une unité), d:c:ID (dispatch et les unités
-- d'un appel), d:civ (groupe civil et dispatch)
CREATE TABLE IF NOT EXISTS mdc_messages (
    id                BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    channel           VARCHAR(32)  NOT NULL,
    call_id           INT UNSIGNED NULL,
    sender_type       VARCHAR(16)  NOT NULL,
    sender_unit_id    INT UNSIGNED NULL,
    sender_name       VARCHAR(60)  NOT NULL DEFAULT '',
    sender_identifier VARCHAR(80)  NOT NULL DEFAULT '',
    text              TEXT         NOT NULL,
    created_at        INT UNSIGNED NOT NULL DEFAULT 0,
    KEY idx_messages_channel (channel, id),
    KEY idx_messages_call (call_id),
    CONSTRAINT fk_messages_call FOREIGN KEY (call_id) REFERENCES mdc_calls (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dernier message lu, par canal et par lecteur (unit:ID, dispatch, civ:IDENTIFIANT)
CREATE TABLE IF NOT EXISTS mdc_message_reads (
    channel     VARCHAR(32)     NOT NULL,
    reader      VARCHAR(96)     NOT NULL,
    last_id     BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (channel, reader)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Journal des actions importantes (dispatch Web et jeu)
CREATE TABLE IF NOT EXISTS mdc_action_log (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    source      VARCHAR(16)  NOT NULL,
    actor_id    VARCHAR(80)  NOT NULL DEFAULT '',
    actor_name  VARCHAR(60)  NOT NULL DEFAULT '',
    action      VARCHAR(48)  NOT NULL,
    call_id     INT UNSIGNED NULL,
    unit_id     INT UNSIGNED NULL,
    details     TEXT         NULL,
    created_at  INT UNSIGNED NOT NULL DEFAULT 0,
    KEY idx_log_created (created_at),
    KEY idx_log_source (source, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
