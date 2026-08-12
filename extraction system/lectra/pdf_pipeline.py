"""PDF pipeline: PyMuPDF per-page routing.

Digital pages keep their extracted text, with font-size-based heading
detection producing clean markdown. Scanned pages (fewer than 20 characters
of text AND at least one image) are rendered to PNG at 200 dpi and go through
the shared OCR / Claude-vision backends in lectra.vision.
"""

from __future__ import annotations

from collections import Counter
from pathlib import Path
from typing import Sequence

from . import vision
from .errors import OCRUnavailableError, PipelineError, VisionError
from .progress import log, stage, warn
from .schema import Section, SectionLocation

SCANNED_TEXT_THRESHOLD = 20  # chars of extracted text below which a page may be scanned
RENDER_DPI = 200
HEADING_SIZE_RATIO = 1.15  # font size must exceed body * ratio to count as a heading
MAX_HEADING_CHARS = 120

_BULLET_CHARS = "•●▪◦‣–*-"


def _import_fitz():
    try:
        import pymupdf  # PyMuPDF's current import name

        return pymupdf
    except ImportError:
        try:
            import fitz  # legacy PyMuPDF import name

            return fitz
        except ImportError as exc:
            raise PipelineError("PyMuPDF is not installed (pip install PyMuPDF).") from exc


# ---------------------------------------------------------------------------
# Pure helpers (unit-tested)
# ---------------------------------------------------------------------------


def is_scanned_page(text: str, image_count: int) -> bool:
    """A page is 'scanned' when it has fewer than 20 characters of extracted
    text AND contains at least one image."""
    return len(text.strip()) < SCANNED_TEXT_THRESHOLD and image_count > 0


def page_to_markdown(page_dict: dict) -> tuple[str, str | None]:
    """Turn a page.get_text('dict') structure into markdown.

    Large-font spans become headings (levels by descending size, capped at
    ###). Returns (markdown, first_heading_or_None).
    """
    size_weight: Counter = Counter()
    for block in page_dict.get("blocks", []):
        if block.get("type", 0) != 0:  # text blocks only
            continue
        for line in block.get("lines", []):
            for span in line.get("spans", []):
                text = span.get("text", "")
                if text.strip():
                    size_weight[round(span.get("size", 0))] += len(text)
    if not size_weight:
        return "", None

    body_size = size_weight.most_common(1)[0][0]
    heading_sizes = sorted(
        {size for size in size_weight if size > body_size * HEADING_SIZE_RATIO}, reverse=True
    )
    level_for = {size: min(rank + 1, 3) for rank, size in enumerate(heading_sizes)}

    markdown_lines: list[str] = []
    paragraph: list[str] = []
    first_heading: str | None = None

    def flush_paragraph() -> None:
        if paragraph:
            markdown_lines.append(" ".join(paragraph))
            markdown_lines.append("")
            paragraph.clear()

    for block in page_dict.get("blocks", []):
        if block.get("type", 0) != 0:
            continue
        for line in block.get("lines", []):
            spans = line.get("spans", [])
            text = "".join(span.get("text", "") for span in spans).strip()
            if not text:
                continue
            max_size = round(max(span.get("size", 0) for span in spans))
            if max_size in level_for and len(text) <= MAX_HEADING_CHARS:
                flush_paragraph()
                level = level_for[max_size]
                markdown_lines.append("#" * level + " " + text)
                markdown_lines.append("")
                if first_heading is None:
                    first_heading = text
            elif text[0] in _BULLET_CHARS and len(text) > 1:
                flush_paragraph()
                markdown_lines.append("- " + text.lstrip(_BULLET_CHARS + " ").strip())
            else:
                paragraph.append(text)
        flush_paragraph()  # paragraph break at block boundaries
    flush_paragraph()

    return "\n".join(markdown_lines).strip(), first_heading


# ---------------------------------------------------------------------------
# Pipeline
# ---------------------------------------------------------------------------


def process_pdf(pdf_path: Path, mode: str, assets_dir: Path) -> tuple[list[Section], int]:
    """Run the full PDF pipeline. Returns (sections, page_count)."""
    fitz = _import_fitz()
    try:
        document = fitz.open(str(pdf_path))
    except Exception as exc:
        raise PipelineError(f"PyMuPDF could not open the PDF: {exc}") from exc

    sections: list[Section] = []
    ocr_warned = False
    try:
        page_count = document.page_count
        backend = "local LLM + OCR" if mode == "deep" else "PaddleOCR"
        with stage(f"PDF extraction ({page_count} pages; scanned pages via {backend})"):
            for page_index in range(page_count):
                page = document[page_index]
                page_number = page_index + 1
                text = page.get_text()
                image_count = len(page.get_images(full=True))

                if is_scanned_page(text, image_count):
                    section, ocr_warned = _scanned_page_section(
                        page, page_number, mode, assets_dir, ocr_warned
                    )
                else:
                    section = _digital_page_section(page, page_number, text)
                sections.append(section)
    finally:
        document.close()

    return sections, page_count


def _digital_page_section(page, page_number: int, plain_text: str) -> Section:
    markdown, first_heading = page_to_markdown(page.get_text("dict"))
    raw_text = plain_text.strip()
    return Section(
        id=f"sec_{page_number:03d}",
        kind="page",
        title=first_heading or f"Page {page_number}",
        location=SectionLocation(timestamp_ranges=None, pages=[page_number]),
        visual_content_markdown=markdown or raw_text,
        raw_ocr_text=raw_text,
        spoken_content=[],
        section_summary="",
        asset_path=None,
    )


def _scanned_page_section(
    page, page_number: int, mode: str, assets_dir: Path, ocr_warned: bool
) -> tuple[Section, bool]:
    assets_dir.mkdir(parents=True, exist_ok=True)
    image_path = assets_dir / f"page_{page_number:03d}.png"
    pixmap = page.get_pixmap(dpi=RENDER_DPI)
    pixmap.save(str(image_path))

    raw_lines: list[str] = []
    try:
        raw_lines = vision.ocr_image(image_path)
    except OCRUnavailableError as exc:
        if not ocr_warned:
            warn(f"{exc} raw_ocr_text will be empty for scanned pages.")
            ocr_warned = True
    raw_text = "\n".join(raw_lines)

    visual_markdown = ""
    title = None
    if mode == "deep":
        try:
            visual_markdown = vision.describe_image_markdown(
                image_path, kind="scanned document page", ocr_lines=raw_lines
            )
            title = vision.title_from_markdown(visual_markdown)
            log(f"  page {page_number} (scanned) structured by the local LLM")
        except VisionError as exc:
            warn(f"page {page_number}: {exc} Falling back to raw OCR text for this page.")
    if not visual_markdown:
        visual_markdown = raw_text
    if not title:
        title = vision.title_from_lines(raw_lines) or f"Page {page_number}"

    section = Section(
        id=f"sec_{page_number:03d}",
        kind="page",
        title=title,
        location=SectionLocation(timestamp_ranges=None, pages=[page_number]),
        visual_content_markdown=visual_markdown,
        raw_ocr_text=raw_text,
        spoken_content=[],
        section_summary="",
        asset_path=str(image_path),
    )
    return section, ocr_warned
