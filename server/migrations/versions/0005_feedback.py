"""Private player feedback with screenshot attachments."""

from alembic import op

revision = "0005_feedback"
down_revision = "0004_direct_signup"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        CREATE TABLE IF NOT EXISTS player_feedback (
            feedback_id CHAR(36) PRIMARY KEY,
            user_id CHAR(36) NOT NULL,
            submission_id CHAR(36) NOT NULL,
            payload_hash CHAR(64) NOT NULL,
            category VARCHAR(16) NOT NULL,
            title VARCHAR(100) NOT NULL,
            description TEXT NOT NULL,
            build_version VARCHAR(80) NOT NULL,
            created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
            UNIQUE (user_id, submission_id),
            INDEX (created_at, feedback_id),
            INDEX (category, created_at, feedback_id),
            FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """)
    op.execute("""
        CREATE TABLE IF NOT EXISTS feedback_screenshots (
            feedback_id CHAR(36) NOT NULL,
            position TINYINT UNSIGNED NOT NULL,
            width SMALLINT UNSIGNED NOT NULL,
            height SMALLINT UNSIGNED NOT NULL,
            image MEDIUMBLOB NOT NULL,
            PRIMARY KEY (feedback_id, position),
            FOREIGN KEY (feedback_id) REFERENCES player_feedback(feedback_id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """)


def downgrade():
    op.drop_table("feedback_screenshots")
    op.drop_table("player_feedback")
