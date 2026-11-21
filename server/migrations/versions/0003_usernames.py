"""Add optional login usernames without renaming existing accounts."""

from alembic import op
from sqlalchemy import inspect

revision = "0003_usernames"
down_revision = "0002_retention"
branch_labels = None
depends_on = None


def upgrade():
    schema = inspect(op.get_bind())
    if "username" not in {column["name"] for column in schema.get_columns("users")}:
        op.execute("""
            ALTER TABLE users
                ADD COLUMN username VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin,
                ADD UNIQUE INDEX users_username_unique (username)
        """)
