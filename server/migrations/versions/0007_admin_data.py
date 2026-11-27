"""Keep reversible, audited display-name changes separate from account credentials."""
from alembic import op

revision = "0007_admin_data"
down_revision = "0006_admin_workspace"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        CREATE TABLE IF NOT EXISTS admin_nickname_changes (
            change_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            user_id CHAR(36) NOT NULL,
            old_nickname VARCHAR(40) NOT NULL,
            new_nickname VARCHAR(40) NOT NULL,
            reason VARCHAR(500) NOT NULL,
            changed_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
            INDEX (user_id, change_id),
            FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """)


def downgrade():
    op.drop_table("admin_nickname_changes")
