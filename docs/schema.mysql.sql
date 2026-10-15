-- NOMA v1 initial schema, MySQL 8.4 LTS / InnoDB.
-- Design artifact only: not executed against a MySQL server in this session.
-- Apply only to an empty application database via a versioned migration.
-- Connection initialization MUST set time_zone='+00:00'.
-- UUID bytes use UUID_TO_BIN(value, 0) / BIN_TO_UUID(value, 0).
-- No real-person account, external-service registry or free-form JSON columns.

SET NAMES utf8mb4 COLLATE utf8mb4_0900_bin;
SET time_zone = '+00:00';

CREATE TABLE nomas (
    noma_id BINARY(16) NOT NULL,
    schema_version VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT '1.0',
    revision BIGINT UNSIGNED NOT NULL DEFAULT 1,
    status ENUM('active', 'revoked') NOT NULL DEFAULT 'active',
    name VARCHAR(50) NULL,
    birth_year SMALLINT UNSIGNED NULL,
    photo_id BINARY(16) NULL,
    email VARCHAR(254) NULL,
    issued_at DATETIME(3) NOT NULL,
    updated_at DATETIME(3) NOT NULL,
    revoked_at DATETIME(3) NULL,
    restore_locked_at DATETIME(3) NULL,
    PRIMARY KEY (noma_id),
    CONSTRAINT ck_noma_revision CHECK (revision >= 1),
    CONSTRAINT ck_noma_birth CHECK (birth_year IS NULL OR birth_year BETWEEN 1 AND 9999),
    CONSTRAINT ck_noma_profile CHECK (
        (status = 'active' AND name IS NOT NULL AND CHAR_LENGTH(name) BETWEEN 1 AND 50 AND revoked_at IS NULL)
        OR
        (status = 'revoked' AND name IS NULL AND birth_year IS NULL AND photo_id IS NULL AND email IS NULL AND revoked_at IS NOT NULL)
    ),
    CONSTRAINT ck_noma_email CHECK (email IS NULL OR CHAR_LENGTH(email) BETWEEN 1 AND 254),
    CONSTRAINT ck_noma_times CHECK (updated_at >= issued_at),
    INDEX ix_noma_cleanup (status, revoked_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

CREATE TABLE issuance_intents (
    intent_id BINARY(16) NOT NULL,
    idempotency_hash BINARY(32) NOT NULL,
    result_token_hash BINARY(32) NOT NULL,
    state ENUM('open', 'processing', 'completed', 'failed') NOT NULL DEFAULT 'open',
    completed_noma_id BINARY(16) NULL,
    created_at DATETIME(3) NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    completed_at DATETIME(3) NULL,
    PRIMARY KEY (intent_id),
    UNIQUE KEY uq_issuance_idempotency (idempotency_hash),
    UNIQUE KEY uq_issuance_result (result_token_hash),
    CONSTRAINT fk_issuance_noma FOREIGN KEY (completed_noma_id) REFERENCES nomas(noma_id),
    CONSTRAINT ck_issuance_times CHECK (expires_at > created_at),
    INDEX ix_issuance_expiry (expires_at, state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

CREATE TABLE photos (
    photo_id BINARY(16) NOT NULL,
    owner_noma_id BINARY(16) NULL,
    issuance_intent_id BINARY(16) NULL,
    object_key VARCHAR(160) CHARACTER SET ascii COLLATE ascii_bin NULL,
    sha256 BINARY(32) NOT NULL,
    byte_size INT UNSIGNED NOT NULL,
    width SMALLINT UNSIGNED NOT NULL,
    height SMALLINT UNSIGNED NOT NULL,
    state ENUM('staged', 'active', 'retired', 'deleted') NOT NULL,
    created_at DATETIME(3) NOT NULL,
    retired_at DATETIME(3) NULL,
    deleted_at DATETIME(3) NULL,
    PRIMARY KEY (photo_id),
    UNIQUE KEY uq_photo_object (object_key),
    CONSTRAINT fk_photo_owner FOREIGN KEY (owner_noma_id) REFERENCES nomas(noma_id),
    CONSTRAINT fk_photo_intent FOREIGN KEY (issuance_intent_id) REFERENCES issuance_intents(intent_id) ON DELETE SET NULL,
    CONSTRAINT ck_photo_size CHECK (byte_size > 0 AND byte_size <= 5242880),
    CONSTRAINT ck_photo_dimensions CHECK (width BETWEEN 1 AND 1024 AND height = width),
    CONSTRAINT ck_photo_object CHECK ((state = 'deleted' AND object_key IS NULL) OR (state <> 'deleted' AND object_key IS NOT NULL)),
    INDEX ix_photo_cleanup (state, created_at, retired_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

ALTER TABLE nomas ADD CONSTRAINT fk_noma_photo FOREIGN KEY (photo_id) REFERENCES photos(photo_id);

CREATE TABLE management_passkeys (
    passkey_id BINARY(16) NOT NULL,
    noma_id BINARY(16) NOT NULL,
    credential_id VARBINARY(1024) NOT NULL,
    user_handle VARBINARY(64) NOT NULL,
    public_key_cose BLOB NOT NULL,
    sign_count BIGINT UNSIGNED NOT NULL DEFAULT 0,
    backup_eligible BOOLEAN NOT NULL,
    backup_state BOOLEAN NOT NULL,
    created_at DATETIME(3) NOT NULL,
    revoked_at DATETIME(3) NULL,
    PRIMARY KEY (passkey_id),
    UNIQUE KEY uq_passkey_credential (credential_id),
    CONSTRAINT fk_passkey_noma FOREIGN KEY (noma_id) REFERENCES nomas(noma_id),
    INDEX ix_passkey_noma (noma_id, revoked_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

CREATE TABLE recovery_codes (
    recovery_id BINARY(16) NOT NULL,
    noma_id BINARY(16) NOT NULL,
    code_hash BINARY(32) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    consumed_at DATETIME(3) NULL,
    active_noma_id BINARY(16) GENERATED ALWAYS AS (IF(consumed_at IS NULL, noma_id, NULL)) STORED,
    PRIMARY KEY (recovery_id),
    UNIQUE KEY uq_recovery_hash (code_hash),
    UNIQUE KEY uq_recovery_active (active_noma_id),
    CONSTRAINT fk_recovery_noma FOREIGN KEY (noma_id) REFERENCES nomas(noma_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

CREATE TABLE management_sessions (
    session_hash BINARY(32) NOT NULL,
    noma_id BINARY(16) NOT NULL,
    scope ENUM('manage', 'recovery') NOT NULL,
    recovery_id BINARY(16) NULL,
    created_at DATETIME(3) NOT NULL,
    authenticated_at DATETIME(3) NOT NULL,
    last_seen_at DATETIME(3) NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    revoked_at DATETIME(3) NULL,
    PRIMARY KEY (session_hash),
    CONSTRAINT fk_session_noma FOREIGN KEY (noma_id) REFERENCES nomas(noma_id),
    CONSTRAINT fk_session_recovery FOREIGN KEY (recovery_id) REFERENCES recovery_codes(recovery_id),
    CONSTRAINT ck_session_recovery CHECK ((scope = 'recovery' AND recovery_id IS NOT NULL) OR (scope = 'manage' AND recovery_id IS NULL)),
    INDEX ix_session_noma (noma_id, revoked_at),
    INDEX ix_session_expiry (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

CREATE TABLE auth_challenges (
    challenge_id BINARY(16) NOT NULL,
    challenge_hash BINARY(32) NOT NULL,
    purpose ENUM('passkey_register', 'passkey_authenticate', 'holder_register', 'credential_issue') NOT NULL,
    noma_id BINARY(16) NULL,
    intent_id BINARY(16) NULL,
    session_hash BINARY(32) NULL,
    created_at DATETIME(3) NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    consumed_at DATETIME(3) NULL,
    PRIMARY KEY (challenge_id),
    UNIQUE KEY uq_auth_challenge (challenge_hash),
    CONSTRAINT fk_challenge_noma FOREIGN KEY (noma_id) REFERENCES nomas(noma_id),
    CONSTRAINT fk_challenge_intent FOREIGN KEY (intent_id) REFERENCES issuance_intents(intent_id) ON DELETE CASCADE,
    CONSTRAINT fk_challenge_session FOREIGN KEY (session_hash) REFERENCES management_sessions(session_hash) ON DELETE CASCADE,
    INDEX ix_challenge_expiry (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

CREATE TABLE holder_keys (
    holder_key_id BINARY(16) NOT NULL,
    noma_id BINARY(16) NOT NULL,
    ec_x BINARY(32) NOT NULL,
    ec_y BINARY(32) NOT NULL,
    jwk_thumbprint BINARY(32) NOT NULL,
    state ENUM('active', 'revoked') NOT NULL,
    created_at DATETIME(3) NOT NULL,
    revoked_at DATETIME(3) NULL,
    active_noma_id BINARY(16) GENERATED ALWAYS AS (IF(state = 'active', noma_id, NULL)) STORED,
    PRIMARY KEY (holder_key_id),
    UNIQUE KEY uq_holder_active (active_noma_id),
    UNIQUE KEY uq_holder_thumbprint (jwk_thumbprint),
    CONSTRAINT fk_holder_noma FOREIGN KEY (noma_id) REFERENCES nomas(noma_id),
    CONSTRAINT ck_holder_state CHECK ((state = 'active' AND revoked_at IS NULL) OR (state = 'revoked' AND revoked_at IS NOT NULL)),
    INDEX ix_holder_noma (noma_id, state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

CREATE TABLE issuer_keys (
    kid VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    ec_x BINARY(32) NOT NULL,
    ec_y BINARY(32) NOT NULL,
    state ENUM('prepublished', 'signing', 'verify_only', 'distrusted') NOT NULL,
    published_at DATETIME(3) NOT NULL,
    signing_from DATETIME(3) NOT NULL,
    signing_until DATETIME(3) NOT NULL,
    verify_until DATETIME(3) NOT NULL,
    distrusted_at DATETIME(3) NULL,
    PRIMARY KEY (kid),
    CONSTRAINT ck_issuer_times CHECK (signing_until > signing_from AND verify_until > signing_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

CREATE TABLE status_lists (
    list_id BINARY(16) NOT NULL,
    slot_count INT UNSIGNED NOT NULL DEFAULT 131072,
    version BIGINT UNSIGNED NOT NULL DEFAULT 1,
    published_version BIGINT UNSIGNED NOT NULL DEFAULT 0,
    published_at DATETIME(3) NULL,
    token_expires_at DATETIME(3) NULL,
    signed_token MEDIUMBLOB NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY (list_id),
    CONSTRAINT ck_status_slots CHECK (slot_count = 131072),
    CONSTRAINT ck_status_version CHECK (published_version <= version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

CREATE TABLE credentials (
    credential_id BINARY(16) NOT NULL,
    noma_id BINARY(16) NOT NULL,
    profile_revision BIGINT UNSIGNED NOT NULL,
    holder_key_id BINARY(16) NOT NULL,
    issuer_kid VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    list_id BINARY(16) NOT NULL,
    slot_index INT UNSIGNED NOT NULL,
    required_status_version BIGINT UNSIGNED NOT NULL,
    state ENUM('active', 'revoked', 'expired') NOT NULL,
    issued_at DATETIME(3) NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    revoked_at DATETIME(3) NULL,
    serialized_sd_jwt MEDIUMBLOB NULL,
    token_sha256 BINARY(32) NOT NULL,
    active_noma_id BINARY(16) GENERATED ALWAYS AS (IF(state = 'active', noma_id, NULL)) STORED,
    PRIMARY KEY (credential_id),
    UNIQUE KEY uq_credential_active (active_noma_id),
    UNIQUE KEY uq_credential_slot (list_id, slot_index),
    CONSTRAINT fk_credential_noma FOREIGN KEY (noma_id) REFERENCES nomas(noma_id),
    CONSTRAINT fk_credential_holder FOREIGN KEY (holder_key_id) REFERENCES holder_keys(holder_key_id),
    CONSTRAINT fk_credential_issuer FOREIGN KEY (issuer_kid) REFERENCES issuer_keys(kid),
    CONSTRAINT fk_credential_list FOREIGN KEY (list_id) REFERENCES status_lists(list_id),
    CONSTRAINT ck_credential_slot CHECK (slot_index < 131072),
    CONSTRAINT ck_credential_times CHECK (expires_at > issued_at),
    INDEX ix_credential_cleanup (expires_at, state),
    INDEX ix_credential_noma (noma_id, state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

CREATE TABLE status_publication_outbox (
    event_id BINARY(16) NOT NULL,
    list_id BINARY(16) NOT NULL,
    target_version BIGINT UNSIGNED NOT NULL,
    state ENUM('pending', 'processing', 'completed') NOT NULL DEFAULT 'pending',
    attempts INT UNSIGNED NOT NULL DEFAULT 0,
    created_at DATETIME(3) NOT NULL,
    available_at DATETIME(3) NOT NULL,
    lease_until DATETIME(3) NULL,
    completed_at DATETIME(3) NULL,
    PRIMARY KEY (event_id),
    UNIQUE KEY uq_publication_version (list_id, target_version),
    CONSTRAINT fk_outbox_list FOREIGN KEY (list_id) REFERENCES status_lists(list_id),
    INDEX ix_outbox_worker (state, available_at, lease_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

CREATE TABLE management_audit (
    event_id BINARY(16) NOT NULL,
    noma_id BINARY(16) NOT NULL,
    action ENUM('issued', 'profile_updated', 'credential_issued', 'holder_rotated', 'passkey_added', 'passkey_removed', 'recovered', 'revoked') NOT NULL,
    profile_revision BIGINT UNSIGNED NOT NULL,
    occurred_at DATETIME(3) NOT NULL,
    PRIMARY KEY (event_id),
    CONSTRAINT fk_audit_noma FOREIGN KEY (noma_id) REFERENCES nomas(noma_id),
    INDEX ix_audit_noma (noma_id, occurred_at),
    INDEX ix_audit_cleanup (occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

-- Receipt grants never contain token plaintext or holder private keys.
-- One challenge per grant; replacing it invalidates the preceding challenge.
CREATE TABLE credential_receipt_grants (
    grant_id BINARY(16) NOT NULL,
    noma_id BINARY(16) NOT NULL,
    credential_id BINARY(16) NOT NULL,
    holder_key_id BINARY(16) NOT NULL,
    token_hash BINARY(32) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    challenge_hash BINARY(32) NULL,
    challenge_expires_at DATETIME(3) NULL,
    consumed_at DATETIME(3) NULL,
    invalidated_at DATETIME(3) NULL,
    PRIMARY KEY (grant_id),
    UNIQUE KEY uq_receipt_token (token_hash),
    UNIQUE KEY uq_receipt_challenge (challenge_hash),
    CONSTRAINT fk_receipt_noma FOREIGN KEY (noma_id) REFERENCES nomas(noma_id),
    CONSTRAINT fk_receipt_credential FOREIGN KEY (credential_id) REFERENCES credentials(credential_id) ON DELETE CASCADE,
    CONSTRAINT fk_receipt_holder FOREIGN KEY (holder_key_id) REFERENCES holder_keys(holder_key_id),
    CONSTRAINT ck_receipt_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_receipt_challenge CHECK (
        (challenge_hash IS NULL AND challenge_expires_at IS NULL) OR
        (challenge_hash IS NOT NULL AND challenge_expires_at IS NOT NULL)
    ),
    INDEX ix_receipt_expiry (expires_at),
    INDEX ix_receipt_noma (noma_id, consumed_at, invalidated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

-- Local transactional queue only. Independent encrypted immutable storage
-- and its verified checkpoint are required by V1-DECISIONS.md section 9.1.
-- The single worker assigns record_sequence from the external checkpoint;
-- AUTO_INCREMENT is intentionally avoided because rollbacks can leave gaps.
CREATE TABLE security_invalidation_outbox (
    event_id BINARY(16) NOT NULL,
    noma_id BINARY(16) NULL,
    operation ENUM('profile_updated', 'credential_replaced', 'holder_rotated', 'passkey_removed', 'recovered', 'noma_revoked', 'issuer_distrusted') NOT NULL,
    idempotency_hash BINARY(32) NOT NULL,
    request_hash BINARY(32) NOT NULL,
    operation_token_hash BINARY(32) NULL,
    record_sequence BIGINT UNSIGNED NULL,
    record_sha256 BINARY(32) NULL,
    state ENUM('pending', 'processing', 'recorded', 'completed') NOT NULL DEFAULT 'pending',
    created_at DATETIME(3) NOT NULL,
    available_at DATETIME(3) NOT NULL,
    lease_until DATETIME(3) NULL,
    attempts INT UNSIGNED NOT NULL DEFAULT 0,
    recorded_at DATETIME(3) NULL,
    completed_at DATETIME(3) NULL,
    PRIMARY KEY (event_id),
    UNIQUE KEY uq_invalidation_idempotency (idempotency_hash),
    UNIQUE KEY uq_invalidation_token (operation_token_hash),
    UNIQUE KEY uq_invalidation_sequence (record_sequence),
    CONSTRAINT fk_invalidation_noma FOREIGN KEY (noma_id) REFERENCES nomas(noma_id),
    CONSTRAINT ck_invalidation_record CHECK (
        state IN ('pending', 'processing') OR
        (record_sequence IS NOT NULL AND record_sha256 IS NOT NULL AND recorded_at IS NOT NULL)
    ),
    CONSTRAINT ck_invalidation_complete CHECK (state <> 'completed' OR completed_at IS NOT NULL),
    INDEX ix_invalidation_worker (state, available_at, lease_until),
    INDEX ix_invalidation_noma (noma_id, state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

-- Typed minimum replay data, without profiles, token bytes or secret hashes.
-- No FK to revoked targets: cleanup must not erase pending replay data.
-- Required fields for each target_kind are validated by the application.
CREATE TABLE security_invalidation_targets (
    event_id BINARY(16) NOT NULL,
    target_index INT UNSIGNED NOT NULL,
    target_kind ENUM('noma', 'credential', 'holder_key', 'passkey', 'recovery_code', 'issuer_key') NOT NULL,
    target_id BINARY(16) NULL,
    noma_id BINARY(16) NULL,
    issuer_kid VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NULL,
    list_id BINARY(16) NULL,
    slot_index INT UNSIGNED NULL,
    original_expires_at DATETIME(3) NULL,
    profile_revision BIGINT UNSIGNED NULL,
    noma_issued_at DATETIME(3) NULL,
    noma_updated_at DATETIME(3) NULL,
    invalidated_at DATETIME(3) NOT NULL,
    retain_until DATETIME(3) NULL,
    PRIMARY KEY (event_id, target_index),
    CONSTRAINT fk_invalidation_target_event FOREIGN KEY (event_id) REFERENCES security_invalidation_outbox(event_id) ON DELETE CASCADE,
    CONSTRAINT ck_invalidation_target_id CHECK (
        (target_kind = 'issuer_key' AND issuer_kid IS NOT NULL AND target_id IS NULL) OR
        (target_kind <> 'issuer_key' AND target_id IS NOT NULL AND issuer_kid IS NULL)
    ),
    CONSTRAINT ck_invalidation_slot CHECK (slot_index IS NULL OR slot_index < 131072)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;

-- Application invariants (must be verified in service transactions):
-- * UTF-8 NFC normalization, exact codepoint limits, allowed control characters.
-- * A referenced photo is active and owned by the same NOMA.
-- * Holder key on a credential belongs to the same active NOMA.
-- * Issuer signing key is authorized and within its signing interval.
-- * At most five live management passkeys per NOMA.
-- * Retiring current credentials and inserting a replacement is atomic.
-- * Recovery commits atomically and revokes every prior session and credential.
-- * Credentials are not returned before required_status_version is published.
-- * Cleanup clears credential token bytes before removing referenced key data.
-- * Status slots cannot be recycled while previous credentials remain unexpired.
-- * Receipt grant, credential and active holder key belong to the same NOMA.
-- * Grant/challenge consumption is atomic; retries require a new grant.
-- * Recovery scope only permits replacement setup and completion, not downloads.
-- * Recovery completion atomically consumes the unused recovery code once.
-- * Every security invalidation commits with its outbox and typed targets.
-- * Record/checkpoint confirmation gates success, delivery and publication.
-- * Restore replays the external journal and invalidates all prior credentials,
--   sessions, challenges, intents and receipt grants before opening service.
-- * Local outbox cleanup cannot delete the independent replay records.
-- * restore_locked_at is internal, absent from public claims; a non-null value
--   blocks management, recovery and credential issuance/delivery.
