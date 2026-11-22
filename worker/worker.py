"""Queue worker (the consumer of Lab 07): takes job ids from a Redis list, does the work, reports the status.

Reliable-queue pattern (what SQS does with its visibility timeout):
  1. BLMOVE queue:jobs -> queue:processing : the id is MOVED, not removed, so a crash cannot lose it.
  2. do the work, update the status in the hash job:<id>
  3. LREM queue:processing                  : the "acknowledge": the job is finished for good.
An id left in queue:processing means a worker died mid-job; at start-up it is put back in the queue.
No local state: everything lives in Redis, and the settings come from the environment.
"""
import logging
import os
import signal
import socket
import time
from datetime import datetime, timezone

import redis

REDIS_URL = os.environ["REDIS_URL"]
WORK_SECONDS = float(os.environ.get("WORK_SECONDS", "2"))  # how long the stub work lasts
QUEUE_KEY = "queue:jobs"  # same names as in api/main.py
PROCESSING_KEY = "queue:processing"
POLL_SECONDS = 2  # one blocking wait lasts this long: also the longest a stop request waits

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


def process(r: redis.Redis, job_id: str) -> None:
    key = f"job:{job_id}"
    if not r.exists(key):  # the record expired while the id waited
        log.warning("job %s has no record any more: dropped", job_id)
        return
    r.hset(key, mapping={"status": "processing", "started_at": now()})
    log.info("picked up job %s (%s)", job_id, r.hget(key, "type"))
    try:
        time.sleep(WORK_SECONDS)  # the stub work: step 24 replaces it with a real task
    except Exception as exc:
        r.hset(key, mapping={"status": "failed", "error": str(exc)[:200], "finished_at": now()})
        log.error("job %s failed: %s", job_id, exc)
        return
    r.hset(key, mapping={"status": "done", "finished_at": now()})
    log.info("job %s done", job_id)


def main() -> None:
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    # The socket timeout must be longer than the blocking wait of BLMOVE.
    r = redis.Redis.from_url(
        REDIS_URL, decode_responses=True, socket_connect_timeout=2, socket_timeout=POLL_SECONDS + 5
    )
    log.info("worker started (work takes %s s per job)", WORK_SECONDS)
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
