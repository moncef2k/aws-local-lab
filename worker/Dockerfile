FROM python:3.12.16-slim-trixie

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Dependencies, pinned: redis and boto3 at the same versions as the API, Pillow (images) for the thumbnails.
RUN pip install --no-cache-dir redis==8.1.0 boto3==1.44.6 Pillow==13.0.0

COPY worker.py .

# Never run as root inside the container.
RUN useradd --system --uid 10001 --no-create-home app
USER app

# Exec form: Python is process 1 and receives SIGTERM from "docker stop" directly.
CMD ["python", "worker.py"]
