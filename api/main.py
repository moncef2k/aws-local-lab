import logging
import os
import re
import socket
from datetime import datetime
from typing import Annotated, Iterator
from uuid import uuid4

import boto3
import redis
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import Depends, FastAPI, File, HTTPException, Response, UploadFile, status
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

# Object storage (S3 in AWS). Same boto3 code as against real AWS: only the endpoint differs.
# "path" addressing = http://s3:8333/<bucket>/<key>; real S3 uses <bucket>.s3.amazonaws.com, which a
# container name cannot imitate.
S3_BUCKET = os.environ["S3_BUCKET"]
s3 = boto3.client(
    "s3",
    endpoint_url=os.environ["S3_ENDPOINT_URL"],
    aws_access_key_id=os.environ["S3_ACCESS_KEY"],
    aws_secret_access_key=os.environ["S3_SECRET_KEY"],
    region_name="us-east-1",
    config=Config(
        signature_version="s3v4",
        s3={"addressing_style": "path"},
        connect_timeout=2,
        read_timeout=5,
        retries={"max_attempts": 1},
    ),
)
MAX_UPLOAD_BYTES = 5 * 1024 * 1024
PRESIGN_SECONDS = int(os.environ.get("PRESIGN_SECONDS", "300"))


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


class UploadOut(BaseModel):
    key: str
    size: int
    content_type: str
    url: str  # a presigned GET link: valid for expires_in seconds, no credentials needed
    expires_in: int


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


@app.post("/upload", response_model=UploadOut, status_code=status.HTTP_201_CREATED)
def upload(file: Annotated[UploadFile, File()]):
    """Store the file in the bucket and answer with its key and a temporary download link."""
    data = file.file.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail=f"file too large (max {MAX_UPLOAD_BYTES} bytes)")
    # The client's file name is untrusted: keep letters, digits, dot, dash, underscore only.
    name = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(file.filename or "file"))[:100]
    key = f"originals/{uuid4().hex}-{name}"  # the uuid makes the key unique: no overwriting
    content_type = file.content_type or "application/octet-stream"
    try:
        s3.put_object(Bucket=S3_BUCKET, Key=key, Body=data, ContentType=content_type)
        url = s3.generate_presigned_url(
            "get_object", Params={"Bucket": S3_BUCKET, "Key": key}, ExpiresIn=PRESIGN_SECONDS
        )
    except (BotoCoreError, ClientError) as exc:
        log.error("storage error on %s: %s", key, exc)
        raise HTTPException(status_code=502, detail="object storage unavailable")
    log.info("uploaded %s (%s bytes)", key, len(data))
    return UploadOut(key=key, size=len(data), content_type=content_type, url=url, expires_in=PRESIGN_SECONDS)
