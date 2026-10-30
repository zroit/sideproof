# The SideProof backend. It also serves the web build (Next.js static export), committed as
# web-dist/, and the Android APK from downloads/.
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
COPY web-dist web
COPY downloads downloads
ENV SIDEPROOF_DB=/data/sideproof.db \
    SIDEPROOF_FACE_MODEL=/srv/models/face_landmarker.task \
    SIDEPROOF_WEB_DIR=/srv/web \
    SIDEPROOF_DOWNLOADS_DIR=/srv/downloads
VOLUME /data
EXPOSE 8000
CMD ["uvicorn", "sideproof.api:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
