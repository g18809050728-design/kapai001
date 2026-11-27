"""Store the last successful login and reasons for administrator grants."""

from alembic import op
from sqlalchemy import inspect

revision = "0008_player_directory"
down_revision = "0007_admin_data"
branch_labels = None
depends_on = None


def upgrade():
    inspector = inspect(op.get_bind())
    if "last_login_at" not in {c["name"] for c in inspector.get_columns("users")}:
        op.execute("""
            ALTER TABLE users ADD COLUMN last_login_at DATETIME(6),
                ADD INDEX users_created_at (created_at, user_id),
                ADD INDEX users_last_login_at (last_login_at, user_id)
        """)
    if "reason" not in {c["name"] for c in inspector.get_columns("admin_audit_log")}:
        op.execute("""
            ALTER TABLE admin_audit_log ADD COLUMN reason VARCHAR(500),
                ADD INDEX admin_audit_by_operation (operation, audit_id),
                ADD INDEX admin_audit_by_target (object_id, operation, audit_id)
        """)
    # Sessions have always expired seven days after creation and are never extended.
    op.execute("""
        UPDATE users u JOIN (
            SELECT user_id, MAX(expires_at) - INTERVAL 7 DAY AS login_at
            FROM auth_sessions GROUP BY user_id
        ) s ON s.user_id=u.user_id
        SET u.last_login_at=s.login_at
        WHERE u.last_login_at IS NULL OR u.last_login_at<s.login_at
    """)


def downgrade():
    op.execute("ALTER TABLE admin_audit_log DROP INDEX admin_audit_by_target, DROP INDEX admin_audit_by_operation, DROP COLUMN reason")
    op.execute("ALTER TABLE users DROP INDEX users_last_login_at, DROP INDEX users_created_at, DROP COLUMN last_login_at")
