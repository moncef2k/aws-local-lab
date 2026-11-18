"""Database layer: one engine (connection pool) and the table definitions.

The address of the database comes from the environment, never from the code,
like the endpoint of an RDS instance.
"""
import os
from datetime import datetime

from sqlalchemy import DateTime, String, Text, create_engine, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

DATABASE_URL = os.environ["DATABASE_URL"]

# pool_pre_ping tests a connection before using it, so a restarted database is not a problem.
engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


class Note(Base):
    __tablename__ = "notes"

    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text, server_default="")
    created_at: Mapped[datetime] =mapped_column(DateTime(timezone=True), server_default=func.now())
