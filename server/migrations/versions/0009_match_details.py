from alembic import op

revision = "0009_match_details"
down_revision = "0008_player_directory"


def upgrade():
    op.execute("ALTER TABLE match_players ADD COLUMN detail JSON NULL")


def downgrade():
    op.execute("ALTER TABLE match_players DROP COLUMN detail")
