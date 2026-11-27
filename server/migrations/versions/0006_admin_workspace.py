"""Add feedback triage and a reversible statistics layer; leave original records intact."""

from alembic import op

revision = "0006_admin_workspace"
down_revision = "0005_feedback"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        CREATE TABLE IF NOT EXISTS feedback_triage (
            feedback_id CHAR(36) PRIMARY KEY,
            status VARCHAR(16) NOT NULL,
            note VARCHAR(1600) NOT NULL,
            updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
            FOREIGN KEY (feedback_id) REFERENCES player_feedback(feedback_id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """)
    op.execute("""
        CREATE TABLE IF NOT EXISTS stats_adjustments (
            record_id CHAR(36) PRIMARY KEY,
            match_id CHAR(36) UNIQUE,
            started_at DATETIME(6),
            game_version VARCHAR(80),
            character_id VARCHAR(80),
            difficulty VARCHAR(20),
            first_battle TINYINT UNSIGNED,
            finished TINYINT UNSIGNED,
            excluded TINYINT UNSIGNED NOT NULL DEFAULT 0,
            reason VARCHAR(500) NOT NULL,
            revision INT UNSIGNED NOT NULL DEFAULT 1,
            INDEX (started_at),
            FOREIGN KEY (match_id) REFERENCES matches(match_id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """)


def downgrade():
    op.drop_table("stats_adjustments")
    op.drop_table("feedback_triage")
