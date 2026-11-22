FROM python:3.12.16-slim-trixie

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# The only dependency, pinned (same version as the API). Step 24 adds Pillow and boto3.
RUN pip install --no-cache-dir redis==8.1.0

COPY worker.py .

# Never run as root inside the container.
RUN useradd --system --uid 10001 --no-create-home app
USER app

# Exec form: Python is process 1 and receives SIGTERM from "docker stop" directly.
CMD ["python", "worker.py"]
