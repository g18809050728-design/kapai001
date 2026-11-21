"""Keep completed milestones available after event retention expires."""

from alembic import op
from sqlalchemy import inspect

revision = "0002_retention"
down_revision = "0001_accounts"
branch_labels = None
depends_on = None


def upgrade():
    schema = inspect(op.get_bind())
    if "first_battle_at" not in {column["name"] for column in schema.get_columns("matches")}:
        op.execute("ALTER TABLE matches ADD COLUMN first_battle_at DATETIME(6)")
    op.execute("""
        UPDATE matches m JOIN game_events e ON e.match_id=m.match_id
        SET m.first_battle_at=e.received_at
        WHERE e.event_type='first_battle_completed' AND m.first_battle_at IS NULL
    """)
    if "created_at" not in {column["name"] for column in schema.get_columns("save_receipts")}:
        op.execute("""
            ALTER TABLE save_receipts ADD COLUMN created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                ADD INDEX receipt_retention (created_at)
        """)
