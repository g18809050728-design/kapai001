"""Accounts, solo runs, telemetry, and versioned cloud saves."""

from alembic import op

revision = "0001_accounts"
down_revision = None
branch_labels = None
depends_on = None

TABLES = {
    "users": """
        user_id CHAR(36) PRIMARY KEY,
        email VARCHAR(254) COLLATE utf8mb4_bin NOT NULL UNIQUE,
        nickname VARCHAR(40) NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        role ENUM('player','admin') NOT NULL DEFAULT 'player',
        verified_at DATETIME(6),
        totp_secret VARCHAR(64),
        last_totp_step BIGINT,
        created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
    """,
    "auth_sessions": """
        token_hash CHAR(64) PRIMARY KEY,
        user_id CHAR(36) NOT NULL,
        expires_at DATETIME(6) NOT NULL,
        mfa BOOLEAN NOT NULL DEFAULT FALSE,
        INDEX (expires_at),
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
    """,
    "auth_tokens": """
        token_hash CHAR(64) PRIMARY KEY,
        user_id CHAR(36) NOT NULL,
        kind ENUM('verify','reset') NOT NULL,
        expires_at DATETIME(6) NOT NULL,
        INDEX (expires_at),
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
    """,
    "rate_limits": """
        bucket CHAR(64) NOT NULL,
        window_start BIGINT NOT NULL,
        attempts INT UNSIGNED NOT NULL,
        PRIMARY KEY (bucket, window_start),
        INDEX (window_start)
    """,
    "matches": """
        match_id CHAR(36) PRIMARY KEY,
        mode VARCHAR(20) NOT NULL DEFAULT 'solo',
        source VARCHAR(24) NOT NULL DEFAULT 'client_reported',
        status ENUM('active','finished','abandoned') NOT NULL DEFAULT 'active',
        game_version VARCHAR(80) NOT NULL,
        manifest_id VARCHAR(80) NOT NULL,
        started_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
        finished_at DATETIME(6),
        INDEX (mode, source, started_at)
    """,
    "match_players": """
        match_id CHAR(36) NOT NULL,
        user_id CHAR(36) NOT NULL,
        seat_no SMALLINT UNSIGNED NOT NULL,
        client_run_id VARCHAR(80) COLLATE utf8mb4_bin,
        character_id VARCHAR(80) NOT NULL,
        difficulty VARCHAR(20) NOT NULL,
        result JSON,
        PRIMARY KEY (match_id, seat_no),
        UNIQUE (match_id, user_id),
        UNIQUE (user_id, client_run_id),
        FOREIGN KEY (match_id) REFERENCES matches(match_id) ON DELETE CASCADE,
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
    """,
    "game_events": """
        event_id CHAR(36) PRIMARY KEY,
        event_type VARCHAR(40) NOT NULL,
        user_id CHAR(36),
        visitor_id CHAR(36),
        match_id CHAR(36),
        data JSON,
        received_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
        UNIQUE (match_id, event_type),
        INDEX (event_type, received_at),
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        FOREIGN KEY (match_id) REFERENCES matches(match_id) ON DELETE CASCADE
    """,
    "admin_audit_log": """
        audit_id BIGINT AUTO_INCREMENT PRIMARY KEY,
        actor_id CHAR(36),
        operation VARCHAR(80) NOT NULL,
        object_id CHAR(36),
        result VARCHAR(40) NOT NULL,
        request_id CHAR(36) NOT NULL,
        created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
        FOREIGN KEY (actor_id) REFERENCES users(user_id) ON DELETE SET NULL
    """,
    "save_slots": """
        user_id CHAR(36) NOT NULL,
        slot_key ENUM('current_run','profile') NOT NULL,
        cloud_revision BIGINT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (user_id, slot_key),
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
    """,
    "save_versions": """
        user_id CHAR(36) NOT NULL,
        slot_key ENUM('current_run','profile') NOT NULL,
        cloud_revision BIGINT UNSIGNED NOT NULL,
        request_id CHAR(36) NOT NULL,
        run_id VARCHAR(80),
        run_revision BIGINT UNSIGNED,
        schema_version INT UNSIGNED NOT NULL,
        content_version VARCHAR(80) NOT NULL,
        content_hash VARCHAR(80) NOT NULL,
        manifest_id VARCHAR(80) NOT NULL,
        checksum CHAR(64) NOT NULL,
        snapshot MEDIUMBLOB NOT NULL,
        saved_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
        PRIMARY KEY (user_id, slot_key, cloud_revision),
        UNIQUE (user_id, slot_key, request_id),
        FOREIGN KEY (user_id, slot_key) REFERENCES save_slots(user_id, slot_key) ON DELETE CASCADE
    """,
    "save_receipts": """
        user_id CHAR(36) NOT NULL,
        slot_key ENUM('current_run','profile') NOT NULL,
        request_id CHAR(36) NOT NULL,
        cloud_revision BIGINT UNSIGNED NOT NULL,
        checksum CHAR(64) NOT NULL,
        PRIMARY KEY (user_id, slot_key, request_id),
        FOREIGN KEY (user_id, slot_key) REFERENCES save_slots(user_id, slot_key) ON DELETE CASCADE
    """,
}


def upgrade():
    for name, columns in TABLES.items():
        op.execute(f"CREATE TABLE IF NOT EXISTS {name} ({columns}) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
