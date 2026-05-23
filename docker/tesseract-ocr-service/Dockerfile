FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata
ENV TESSERACT_LANG=por

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      poppler-utils \
      tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*

COPY modules/tesseract/tessdata/por.traineddata /usr/share/tesseract-ocr/5/tessdata/por.traineddata

COPY docker/tesseract-ocr-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY docker/tesseract-ocr-service/app.py .

EXPOSE 8081

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8081"]
