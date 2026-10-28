# The SideProof backend. It serves the Flutter web build too when one is copied to /srv/web.
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /srv
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN mkdir models && curl -fsSL -o models/face_landmarker.task \
    https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task
COPY backend/sideproof sideproof
COPY backend/demo demo
ENV SIDEPROOF_DB=/data/sideproof.db \
    SIDEPROOF_FACE_MODEL=/srv/models/face_landmarker.task \
    SIDEPROOF_WEB_DIR=/srv/web
VOLUME /data
EXPOSE 8000
CMD ["uvicorn", "sideproof.api:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
