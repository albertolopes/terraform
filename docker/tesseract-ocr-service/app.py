import io
import os
import re
from typing import Annotated

from fastapi import FastAPI, File, HTTPException, Query, Request, UploadFile
from fastapi.responses import JSONResponse
from pdf2image import convert_from_bytes
from PIL import Image, UnidentifiedImageError
import pytesseract


app = FastAPI(title="Tesseract OCR")

MAX_BODY_BYTES = int(os.getenv("MAX_BODY_BYTES", "12582912"))
DEFAULT_LANG = os.getenv("TESSERACT_LANG", "por+eng")
DEFAULT_OEM = int(os.getenv("TESSERACT_OEM", "1"))
DEFAULT_PSM = int(os.getenv("TESSERACT_PSM", "6"))
TESSDATA_PREFIX = os.getenv("TESSDATA_PREFIX", "/usr/share/tesseract-ocr/5/tessdata")
SAFE_WHITELIST = re.compile(r"^[^\s]+$")


@app.middleware("http")
async def limit_body_size(request: Request, call_next):
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > MAX_BODY_BYTES:
        return JSONResponse(
            status_code=413,
            content={"detail": "Request body too large"},
        )

    return await call_next(request)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/ocr")
async def ocr(
    request: Request,
    file: Annotated[UploadFile | None, File()] = None,
    lang: str = DEFAULT_LANG,
    oem: int = Query(DEFAULT_OEM, ge=0, le=3),
    psm: int = Query(DEFAULT_PSM, ge=0, le=13),
    whitelist: str | None = Query(None),
):
    if file is not None:
        payload = await file.read()
        content_type = file.content_type or ""
    else:
        payload = await request.body()
        content_type = request.headers.get("content-type", "")

    if not payload:
        raise HTTPException(status_code=400, detail="Empty OCR payload")

    if len(payload) > MAX_BODY_BYTES:
        raise HTTPException(status_code=413, detail="Request body too large")

    try:
        text = _extract_text(payload, content_type, lang, oem, psm, whitelist)
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"OCR failed: {exc}") from exc

    return {"text": text}


def _extract_text(
    payload: bytes,
    content_type: str,
    lang: str,
    oem: int,
    psm: int,
    whitelist: str | None,
) -> str:
    config = _build_tesseract_config(oem, psm, whitelist)

    if content_type == "application/pdf" or payload.startswith(b"%PDF"):
        pages = convert_from_bytes(payload)
        return "\n\n".join(
            pytesseract.image_to_string(page, lang=lang, config=config) for page in pages
        )

    try:
        image = Image.open(io.BytesIO(payload))
    except UnidentifiedImageError as exc:
        raise ValueError("Unsupported file format") from exc

    return pytesseract.image_to_string(image, lang=lang, config=config)


def _build_tesseract_config(oem: int, psm: int, whitelist: str | None) -> str:
    config = [
        "--tessdata-dir",
        TESSDATA_PREFIX,
        "--oem",
        str(oem),
        "--psm",
        str(psm),
    ]

    if whitelist:
        if not SAFE_WHITELIST.fullmatch(whitelist):
            raise ValueError("whitelist must not contain whitespace")
        config.extend(["-c", f"tessedit_char_whitelist={whitelist}"])

    return " ".join(config)
