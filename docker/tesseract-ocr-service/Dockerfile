FROM python:3.12-slim

ARG TESSDATA_REPO=tessdata_best
ARG TESSDATA_BASE_URL=https://github.com/tesseract-ocr/${TESSDATA_REPO}/raw/main

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata
ENV TESSERACT_LANG=por+eng
ENV TESSERACT_OEM=1
ENV TESSERACT_PSM=6

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      poppler-utils \
      tesseract-ocr \
      wget \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir -p "$TESSDATA_PREFIX"; \
    wget -O "$TESSDATA_PREFIX/por.traineddata" "$TESSDATA_BASE_URL/por.traineddata"; \
    wget -O "$TESSDATA_PREFIX/eng.traineddata" "$TESSDATA_BASE_URL/eng.traineddata"

COPY docker/tesseract-ocr-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY docker/tesseract-ocr-service/app.py .

EXPOSE 8081

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8081"]
