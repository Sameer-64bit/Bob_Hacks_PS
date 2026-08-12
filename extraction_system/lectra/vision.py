"""Shared content-extraction backends used by BOTH pipelines.

Two backends live here:
  * OCR (PaddleOCR, with a system-tesseract fallback) — "fast" mode text
    extraction, and the raw_ocr_text fallback that is always captured, even
    in deep mode.
  * Gemini vision (lectra.gemini_llm) — "deep" mode structured markdown:
    each slide/page image goes straight to the multimodal Gemini API, one
    call per image.

Heavy imports (paddleocr, PIL) are deferred to call time so the rest of the
package imports without them installed.
"""

from __future__ import annotations

import base64
import io
import re
import shutil
import subprocess
from pathlib import Path

from . import gemini_llm
from .errors import LLMError, OCRUnavailableError, VisionError
from .progress import warn

MAX_IMAGE_DIM = 1568  # px — larger slides are downscaled before the LLM call

_ocr_engine = None
_tesseract_fallback_warned = False


# ---------------------------------------------------------------------------
# OCR (PaddleOCR, tesseract fallback)
# ---------------------------------------------------------------------------


def _get_ocr_engine():
    global _ocr_engine
    if _ocr_engine is not None:
        return _ocr_engine
    try:
        from paddleocr import PaddleOCR
    except ImportError as exc:
        raise OCRUnavailableError(
            "PaddleOCR is not installed. Install the OCR extra: pip install 'lectra[ocr]' "
            "(or: pip install 'paddleocr>=2.7,<3' paddlepaddle)."
        ) from exc
    try:
        _ocr_engine = PaddleOCR(lang="en", use_angle_cls=True, show_log=False)
    except TypeError:
        # newer paddleocr releases dropped these constructor kwargs
        _ocr_engine = PaddleOCR(lang="en")
    except Exception as exc:
        raise OCRUnavailableError(f"PaddleOCR failed to initialise: {exc}") from exc
    return _ocr_engine


def _ocr_with_tesseract(path: str) -> list[str]:
    """OCR one image with the system tesseract binary (no Python deps)."""
    try:
        proc = subprocess.run(
            ["tesseract", path, "stdout"],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except Exception as exc:
        warn(f"OCR failed on {path}: {exc}")
        return []
    if proc.returncode != 0:
        warn(f"OCR failed on {path}: {proc.stderr.strip()}")
        return []
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def ocr_image(image_path: Path | str) -> list[str]:
    """Run OCR on an image and return the recognised text lines.

    PaddleOCR is the primary backend; when it is not installed, the system
    tesseract binary is used instead (warned once). Raises OCRUnavailableError
    when neither backend is available; other OCR failures degrade to an empty
    result with a warning (a bad frame should not kill a long run).
    """
    global _tesseract_fallback_warned
    path = str(image_path)
    try:
        engine = _get_ocr_engine()
    except OCRUnavailableError:
        if shutil.which("tesseract") is None:
            raise
        if not _tesseract_fallback_warned:
            warn("PaddleOCR is not installed — falling back to the system tesseract binary.")
            _tesseract_fallback_warned = True
        return _ocr_with_tesseract(path)
    try:
        try:
            result = engine.ocr(path, cls=True)
        except TypeError:
            result = engine.ocr(path)
    except Exception as exc:
        warn(f"OCR failed on {path}: {exc}")
        return []
    return _parse_ocr_result(result)


def _parse_ocr_result(result) -> list[str]:
    """Normalise both the classic (<3.0) and new (>=3.0) PaddleOCR shapes."""
    lines: list[str] = []
    if not result:
        return lines
    for page in result:
        if page is None:
            continue
        texts = None
        if hasattr(page, "get"):  # paddleocr >= 3 returns dict-like OCRResult
            texts = page.get("rec_texts")
        if texts is not None:
            lines.extend(t.strip() for t in texts if t and t.strip())
            continue
        for item in page:  # classic: [box, (text, confidence)]
            try:
                text = item[1][0]
            except (TypeError, IndexError, KeyError):
                continue
            if text and str(text).strip():
                lines.append(str(text).strip())
    return lines


# ---------------------------------------------------------------------------
# Deep-mode structured markdown via Gemini vision
# ---------------------------------------------------------------------------


def _encode_image(image_path: Path | str) -> str:
    """Base64-encode an image for the API, downscaling oversized frames."""
    try:
        from PIL import Image
    except ImportError as exc:
        raise VisionError("Pillow is required for vision calls (pip install Pillow).") from exc

    with Image.open(image_path) as img:
        img = img.convert("RGB")
        if max(img.size) > MAX_IMAGE_DIM:
            img.thumbnail((MAX_IMAGE_DIM, MAX_IMAGE_DIM), Image.LANCZOS)
        buffer = io.BytesIO()
        img.save(buffer, format="PNG")
        data = buffer.getvalue()
    return base64.standard_b64encode(data).decode("ascii")


_SLIDE_PROMPT = """\
Transcribe this {kind} into structured Markdown. Return ONLY the Markdown for its content — no preamble, no commentary, no code fence around the whole answer.

Rules:
- Start with the title as a '## ' heading. If no title is visible, write a short descriptive one.
- Reproduce bullet points as Markdown lists, preserving the nesting hierarchy exactly.
- Write ALL mathematical notation as LaTeX: $...$ inline, $$...$$ for display equations. Preserve subscripts, superscripts, Greek letters, and symbols exactly. Never approximate math with plain words.
- Put any code in fenced code blocks with a language tag when identifiable.
- For every diagram, chart, table, or figure, add a line: 'Figure: <one or two sentence description>'.
- Transcribe faithfully; do not invent content that is not visible."""


def describe_image_markdown(image_path: Path | str, kind: str = "lecture slide") -> str:
    """Produce structured markdown for one slide/page image via Gemini vision."""
    image_b64 = _encode_image(image_path)
    try:
        content = gemini_llm.chat(_SLIDE_PROMPT.format(kind=kind), images=[image_b64])
    except LLMError as exc:
        raise VisionError(f"Gemini vision call failed for {image_path}: {exc}") from exc
    if not content:
        raise VisionError(f"Gemini returned empty output for {image_path}.")
    return _strip_outer_fence(content)


def _strip_outer_fence(text: str) -> str:
    match = re.match(r"^```[a-zA-Z]*\s*\n(.*)\n```$", text, re.DOTALL)
    return match.group(1).strip() if match else text


# ---------------------------------------------------------------------------
# Title helpers shared by both pipelines
# ---------------------------------------------------------------------------

_HEADING_RE = re.compile(r"^#{1,6}\s+(.+)$", re.MULTILINE)


def title_from_markdown(markdown: str) -> str | None:
    match = _HEADING_RE.search(markdown or "")
    return match.group(1).strip() if match else None


def title_from_lines(lines: list[str]) -> str | None:
    for line in lines:
        line = line.strip()
        if line:
            return line[:80]
    return None
