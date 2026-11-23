import json
import logging
import os
import re
import socket
import time
from datetime import datetime, timezone
from typing import Annotated, Iterator
from uuid import uuid4

import boto3
import redis
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import Depends, FastAPI, File, HTTPException, Path, Request, Response, UploadFile, status
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from db import Note, SessionLocal

app = FastAPI(title="aws-local-lab API")

# Uvicorn's logger: it is already set up, so our lines show in "docker compose logs api".
log = logging.getLogger("uvicorn.error")

# Metrics (CloudWatch metrics in AWS): numbers kept in memory by this process and shown as text at
# GET /metrics, for Prometheus to read (step 30). Each replica counts only its own requests.
# The "path" label is the route template (/notes/{note_id}), never the real URL: one series per route,
# not one per note id.
REQUESTS = Counter("http_requests_total", "HTTP requests handled", ["method", "path", "status"])
LATENCY = Histogram("http_request_duration_seconds", "Time to handle one request", ["method", "path"])


@app.middleware("http")
async def record_metrics(request: Request, call_next):
    if request.url.path == "/metrics":
        return await call_next(request)  # do not count the reads of the metrics themselves
    start = time.perf_counter()
    status_code = 500  # what is counted if the handler raises
    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    finally:
        route = request.scope.get("route")
        path = route.path if route else "unmatched"
        LATENCY.labels(request.method, path).observe(time.perf_counter() - start)
        REQUESTS.labels(request.method, path, str(status_code)).inc()

# The cache. Short timeouts: a slow or dead cache must not make the API slow too.
cache = redis.Redis.from_url(
    os.environ["REDIS_URL"], decode_responses=True, socket_connect_timeout=1, socket_timeout=1
)
CACHE_TTL = int(os.environ.get("CACHE_TTL_SECONDS", "60"))

# Object storage (S3 in AWS). Same boto3 code as against real AWS: only the endpoint differs.
# "path" addressing = http://s3:8333/<bucket>/<key>; real S3 uses <bucket>.s3.amazonaws.com, which a
# container name cannot imitate.
S3_BUCKET = os.environ["S3_BUCKET"]


def make_s3_client(endpoint_url: str):
    return boto3.client(
        "s3",
        endpoint_url=endpoint_url,
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


# Two addresses for the same store. The API reaches it inside the private network (http://s3:8333),
# but a browser on your machine cannot resolve "s3": the link we hand out must use the public name
# (http://s3.localhost, served by the load balancer). A presigned URL signs the host name, so it has
# to be created for the address the client will really call. Signing is local maths: no network call.
s3 = make_s3_client(os.environ["S3_ENDPOINT_URL"])
s3_public = make_s3_client(os.environ.get("S3_PUBLIC_ENDPOINT_URL", os.environ["S3_ENDPOINT_URL"]))
# The job queue (SQS in AWS). Same Redis server as the cache, but here Redis is a hard dependency:
# a job that could not be queued must never be reported as accepted (the routes answer 503).
queue = redis.Redis.from_url(
    os.environ["REDIS_URL"], decode_responses=True, socket_connect_timeout=1, socket_timeout=2
)
QUEUE_KEY = "queue:jobs"  # a Redis list: the ids of the jobs waiting for a worker
JOB_TTL = int(os.environ.get("JOB_TTL_SECONDS", "86400"))  # how long a job record is kept (24 h)
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


class JobIn(BaseModel):
    """What a client sends to ask for a job."""

    type: str = Field(min_length=1, max_length=50)  # what to do, e.g. "thumbnail" (step 24)
    payload: dict[str, str] = Field(default_factory=dict, max_length=10)  # its inputs


class JobOut(BaseModel):
    id: str
    type: str
    status: str  # queued -> processing -> done or failed (the worker moves it on)
    created_at: datetime
    payload: dict[str, str]
    error: str | None = None  # why a job failed
    result_key: str | None = None  # where the worker stored its result (a thumbnail)
    result_size: str | None = None  # e.g. "128x85"
    result_url: str | None = None  # a presigned GET link to the result, like the one of /upload


def job_key(job_id: str) -> str:
    return f"job:{job_id}"  # the Redis hash that holds one job's record


def job_out(job_id: str, record: dict[str, str]) -> dict:
    out = {
        "id": job_id,
        "type": record["type"],
        "status": record["status"],
        "created_at": record["created_at"],
        "payload": json.loads(record["payload"]),
        "error": record.get("error"),
        "result_key": record.get("result_key"),
        "result_size": record.get("result_size"),
    }
    if out["result_key"]:  # signing is local maths, no network call
        out["result_url"] = s3_public.generate_presigned_url(
            "get_object", Params={"Bucket": S3_BUCKET, "Key": out["result_key"]}, ExpiresIn=PRESIGN_SECONDS
        )
    return out


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


@app.get("/metrics", include_in_schema=False)
def metrics():
    """The metrics of THIS replica, in the text format Prometheus reads."""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


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
        url = s3_public.generate_presigned_url(
            "get_object", Params={"Bucket": S3_BUCKET, "Key": key}, ExpiresIn=PRESIGN_SECONDS
        )
    except (BotoCoreError, ClientError) as exc:
        log.error("storage error on %s: %s", key, exc)
        raise HTTPException(status_code=502, detail="object storage unavailable")
    log.info("uploaded %s (%s bytes)", key, len(data))
    return UploadOut(key=key, size=len(data), content_type=content_type, url=url, expires_in=PRESIGN_SECONDS)


@app.post("/jobs", response_model=JobOut, response_model_exclude_none=True, status_code=status.HTTP_202_ACCEPTED)
def create_job(data: JobIn):
    """Queue a job and answer at once. 202 means "accepted", not "done": a worker does the work later."""
    job_id = uuid4().hex
    record = {
        "type": data.type,
        "status": "queued",
        "payload": json.dumps(data.payload),
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    try:
        pipe = queue.pipeline(transaction=True)  # MULTI/EXEC: sent and run as one block, nothing in between
        pipe.hset(job_key(job_id), mapping=record)  # the record first ...
        pipe.expire(job_key(job_id), JOB_TTL)  # ... that disappears by itself after a day ...
        pipe.lpush(QUEUE_KEY, job_id)  # ... then the id joins the queue
        pipe.execute()
    except redis.RedisError as exc:
        log.error("could not queue job %s: %s", job_id, exc)
        raise HTTPException(status_code=503, detail="job queue unavailable")
    log.info("queued job %s (%s)", job_id, data.type)
    return job_out(job_id, record)


@app.get("/jobs/{job_id}", response_model=JobOut, response_model_exclude_none=True)
def get_job(job_id: Annotated[str, Path(pattern=r"^[0-9a-f]{32}$")]):
    """The current state of a job: poll this until the status is "done"."""
    try:
        record = queue.hgetall(job_key(job_id))
    except redis.RedisError as exc:
        log.error("could not read job %s: %s", job_id, exc)
        raise HTTPException(status_code=503, detail="job queue unavailable")
    if not record:
        raise HTTPException(status_code=404, detail="job not found")
    return job_out(job_id, record)
