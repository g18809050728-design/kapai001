from alembic import context

from kapai.db import make_engine

with make_engine().connect() as connection:
    context.configure(connection=connection)
    with context.begin_transaction():
        context.run_migrations()
