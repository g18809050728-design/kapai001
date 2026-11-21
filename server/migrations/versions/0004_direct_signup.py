"""Separate account activation from email verification."""

from alembic import op
from sqlalchemy import inspect

revision = "0004_direct_signup"
down_revision = "0003_usernames"
branch_labels = None
depends_on = None


def upgrade():
    columns = {column["name"] for column in inspect(op.get_bind()).get_columns("users")}
    if "activated_at" not in columns:
        op.execute("""
            ALTER TABLE users
                MODIFY COLUMN email VARCHAR(254) COLLATE utf8mb4_bin NULL,
                ADD COLUMN activated_at DATETIME(6)
        """)
    op.execute("UPDATE users SET activated_at=verified_at WHERE activated_at IS NULL AND verified_at IS NOT NULL")
