"""Route an input file to the video or PDF pipeline based on its extension."""

from __future__ import annotations

from pathlib import Path

from .errors import UnsupportedInputError

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".mov", ".webm", ".avi"}
PDF_EXTENSIONS = {".pdf"}


def route(input_path: str | Path) -> str:
    """Classify an input path as "video" or "pdf".

    Raises UnsupportedInputError for anything else. Existence checks are the
    caller's job — this only inspects the extension.
    """
    path = Path(input_path)
    ext = path.suffix.lower()
    if ext in VIDEO_EXTENSIONS:
        return "video"
    if ext in PDF_EXTENSIONS:
        return "pdf"
    supported = ", ".join(sorted(VIDEO_EXTENSIONS | PDF_EXTENSIONS))
    shown = ext if ext else "(no extension)"
    raise UnsupportedInputError(
        f"Unsupported input type {shown} for '{path.name}'. Supported extensions: {supported}."
    )
