"""Queue worker (the consumer of Lab 07): takes job ids from a Redis list, does the work, reports the status.

Reliable-queue pattern (what SQS does with its visibility timeout):
  1. BLMOVE queue:jobs -> queue:processing : the id is MOVED, not removed, so a crash cannot lose it.
  2. do the work, update the status in the hash job:<id>
  3. LREM queue:processing                  : the "acknowledge": the job is finished for good.
An id left in queue:processing means a worker died mid-job; at start-up it is put back in the queue.
Job types (the "type" field of the job): "thumbnail" (step 24) and "noop" (sleeps, for tests).
No local state: everything lives in Redis and in the bucket, and the settings come from the environment.
"""
import io
import json
import logging
import os
import signal
import socket
import time
from datetime import datetime, timezone

import boto3
import redis
from botocore.config import Config
from PIL import Image, ImageOps

REDIS_URL = os.environ["REDIS_URL"]
WORK_SECONDS = float(os.environ.get("WORK_SECONDS", "2"))  # how long a "noop" job lasts
QUEUE_KEY = "queue:jobs"  # same names as in api/main.py
PROCESSING_KEY = "queue:processing"
POLL_SECONDS = 2  # one blocking wait lasts this long: also the longest a stop request waits

# The object store (S3 in AWS): same settings and same client options as the API (api/main.py).
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
        connect_timeout=3,
        read_timeout=10,
        retries={"max_attempts": 2},
    ),
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(socket.gethostname())  # the container id, to tell workers apart in the logs

stopping = False


def request_stop(signum, frame):
    """SIGTERM is what "docker stop" sends: do not stop now, stop between two jobs."""
    global stopping
    stopping = True
    log.info("signal %s received: finishing the current job, then stopping", signum)


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def requeue_unfinished(r: redis.Redis) -> None:
    """Put back the ids a dead worker left in the processing list, at the tail of the queue (taken next).

    Ids enter the processing list at its head, so the oldest is at the tail. Taking from the head and
    pushing on the queue's tail puts the oldest last, which is the first one a worker takes."""
    count = 0
    while r.lmove(PROCESSING_KEY, QUEUE_KEY, "LEFT", "RIGHT") is not None:
        count += 1
    if count:
        log.warning("requeued %s unfinished job(s) left by a previous worker", count)


def make_thumbnail(payload: dict) -> dict:
    """Read the image payload["key"] from the bucket, shrink it to fit in size x size, write it back."""
    key = payload.get("key", "")
    if not key.startswith("originals/"):
        raise ValueError("payload.key must be an object under originals/")
    size = int(payload.get("size", "128"))
    if not 16 <= size <= 1024:
        raise ValueError("payload.size must be between 16 and 1024")
    data = s3.get_object(Bucket=S3_BUCKET, Key=key)["Body"].read()
    with Image.open(io.BytesIO(data)) as img:  # raises UnidentifiedImageError if it is not an image
        img = ImageOps.exif_transpose(img)  # apply the camera's rotation flag, if any
        if img.mode not in ("RGB", "RGBA", "L", "LA", "P"):
            img = img.convert("RGB")  # modes PNG cannot store (CMYK, ...)
        img.thumbnail((size, size))  # shrink in place, keeping the proportions
        width, height = img.size
        out = io.BytesIO()
        img.save(out, format="PNG")
    name = os.path.splitext(os.path.basename(key))[0]
    out_key = f"thumbnails/{name}-{size}.png"  # the size is in the name; a redo of the same job overwrites
    s3.put_object(Bucket=S3_BUCKET, Key=out_key, Body=out.getvalue(), ContentType="image/png")
    return {"result_key": out_key, "result_size": f"{width}x{height}"}


def do_noop(payload: dict) -> dict:
    time.sleep(WORK_SECONDS)  # pretend to work
    return {}


HANDLERS = {"thumbnail": make_thumbnail, "noop": do_noop}


def process(r: redis.Redis, job_id: str) -> None:
    key = f"job:{job_id}"
    if not r.exists(key):  # the record expired while the id waited
        log.warning("job %s has no record any more: dropped", job_id)
        return
    r.hset(key, mapping={"status": "processing", "started_at": now()})
    job_type = r.hget(key, "type")
    log.info("picked up job %s (%s)", job_id, job_type)
    try:  # everything that can go wrong with the job itself happens inside this block
        handler = HANDLERS.get(job_type)
        if handler is None:
            raise ValueError(f"unknown job type {job_type!r}")
        result = handler(json.loads(r.hget(key, "payload") or "{}"))
    except Exception as exc:
        message = f"{type(exc).__name__}: {exc}"[:200]
        r.hset(key, mapping={"status": "failed", "error": message, "finished_at": now()})
        log.error("job %s failed: %s", job_id, message)
        return
    r.hset(key, mapping={"status": "done", "finished_at": now(), **result})
    log.info("job %s done %s", job_id, result or "")


def main() -> None:
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    # The socket timeout must be longer than the blocking wait of BLMOVE.
    r = redis.Redis.from_url(
        REDIS_URL, decode_responses=True, socket_connect_timeout=2, socket_timeout=POLL_SECONDS + 5
    )
    log.info("worker started (job types: %s)", ", ".join(HANDLERS))
    recovered = False
    while not stopping:
        try:
            if not recovered:
                requeue_unfinished(r)
                recovered = True
            job_id = r.blmove(QUEUE_KEY, PROCESSING_KEY, POLL_SECONDS, "RIGHT", "LEFT")
            if job_id is None:  # the wait timed out: nothing to do, check the stop flag and wait again
                continue
            process(r, job_id)
            r.lrem(PROCESSING_KEY, 1, job_id)  # acknowledge
        except redis.RedisError as exc:
            log.error("redis problem: %s (retrying in 2 s)", exc)
            recovered = False  # an id may be stuck in the processing list: look again
            time.sleep(2)
    log.info("stopped")


if __name__ == "__main__":
    main()
