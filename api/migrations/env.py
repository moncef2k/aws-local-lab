"""Alembic environment: how migrations connect to the database."""
from logging.config import fileConfig

from alembic import context

from db import Base, engine

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Used by "alembic revision --autogenerate" to compare the models with the real database.
target_metadata = Base.metadata


def run_migrations_online():
    # Same engine as the API, so the same DATABASE_URL: one place to configure.
    with engine.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


# Only "online" mode (a live database) is used in this lab.
run_migrations_online()
