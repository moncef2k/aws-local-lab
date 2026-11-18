import logging
import os
import socket
from datetime import datetime
from typing import Annotated, Iterator

import redis
from fastapi import Depends, FastAPI, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from db import Note, SessionLocal

app = FastAPI(title="aws-local-lab API")

# Uvicorn's logger: it is already set up, so our lines show in "docker compose logs api".
log = logging.getLogger("uvicorn.error")

# The cache. Short timeouts: a slow or dead cache must not make the API slow too.
cache = redis.Redis.from_url(
    os.environ["REDIS_URL"], decode_responses=True, socket_connect_timeout=1, socket_timeout=1
)
CACHE_TTL = int(os.environ.get("CACHE_TTL_SECONDS", "60"))


def get_db() -> Iterator[Session]:
    """One database session per request, always closed afterwards (even after an error)."""
    with SessionLocal() as session:
        yield session


DbSession = Annotated[Session, Depends(get_db)]


class NoteIn(BaseModel):
    """What a client sends: the body is optional."""

    title: str = Field(min_length=1, max_length=200)
    body: str = ""


class NoteOut(NoteIn):
    """What the API answers: the client's fields plus what the database added."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime


def get_note_or_404(db: Session, note_id: int) -> Note:
    note = db.get(Note, note_id)
    if note is None:
        raise HTTPException(status_code=404, detail="note not found")
    return note


@app.get("/health")
def health():
    """Liveness probe: answers as long as the process is up."""
    return {"status": "ok"}


@app.get("/whoami")
def whoami():
    """Which container answered? Inside Docker the hostname is the container id."""
    return {"hostname": socket.gethostname()}


@app.post("/notes", response_model=NoteOut, status_code=status.HTTP_201_CREATED)
def create_note(data: NoteIn, db: DbSession):
    note = Note(title=data.title, body=data.body)
    db.add(note)
    db.commit()
    db.refresh(note)  # reload: the database filled in id and created_at
    return note


@app.get("/notes", response_model=list[NoteOut])
def list_notes(db: DbSession):
    return db.scalars(select(Note).order_by(Note.id)).all()


def forget(note_id: int) -> None:
    """Remove a note from the cache (the original changed). A dead cache must not break a write."""
    try:
        cache.delete(f"note:{note_id}")
    except redis.RedisError as exc:
        log.warning("cache DELETE failed for note:%s (%s)", note_id, exc)


@app.get("/notes/{note_id}", response_model=NoteOut)
def read_note(note_id: int, db: DbSession):
    """Cache-aside: look in the cache first; on a miss read the database and keep a copy."""
    key = f"note:{note_id}"
    state = "MISS"
    try:
        cached = cache.get(key)
        if cached is not None:
            log.info("cache HIT  %s", key)
            return Response(content=cached, media_type="application/json", headers={"X-Cache": "HIT"})
    except redis.RedisError as exc:
        state = "BYPASS"  # the cache is down: answer from the database, never fail because of it
        log.warning("cache unavailable (%s): reading %s from the database", exc, key)
    body = NoteOut.model_validate(get_note_or_404(db, note_id)).model_dump_json()
    if state == "MISS":
        log.info("cache MISS %s (stored for %ss)", key, CACHE_TTL)
        try:
            cache.set(key, body, ex=CACHE_TTL)
        except redis.RedisError as exc:
            log.warning("cache SET failed for %s (%s)", key, exc)
    return Response(content=body, media_type="application/json", headers={"X-Cache": state})


@app.put("/notes/{note_id}", response_model=NoteOut)
def update_note(note_id: int, data: NoteIn, db: DbSession):
    note = get_note_or_404(db, note_id)
    note.title = data.title
    note.body = data.body
    db.commit()
    forget(note_id)  # the cached copy is now wrong: drop it, the next read refills it
    return note


@app.delete("/notes/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(note_id: int, db: DbSession):
    db.delete(get_note_or_404(db, note_id))
    db.commit()
    forget(note_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
