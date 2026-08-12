"""The unified output contract, as pydantic models.

Both pipelines produce these objects and the CLI validates a full
LectraDocument before anything is written to disk. `summary.global` is a
Python keyword, so the attribute is `global_` with a serialization alias.
"""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field

from . import __version__ as TOOL_VERSION


class PointLocation(BaseModel):
    """A single position: seconds into a video, or a 1-based page number."""

    timestamp: Optional[float] = None
    page: Optional[int] = None


class Meta(BaseModel):
    source_file: str
    source_type: Literal["video", "pdf"]
    duration_seconds: Optional[float] = None
    page_count: Optional[int] = None
    language: str
    mode: Literal["fast", "deep"]
    processed_at: str
    tool_version: str = TOOL_VERSION


class KeyConcept(BaseModel):
    concept: str
    explanation: str
    first_seen: PointLocation


class Chapter(BaseModel):
    title: str
    start: PointLocation


class Summary(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    global_: str = Field(alias="global")
    one_liner: str
    key_concepts: list[KeyConcept] = []
    chapters: list[Chapter] = []


class TranscriptSegment(BaseModel):
    start: float
    end: float
    text: str


class SectionLocation(BaseModel):
    # tuple[float, float] enforces exactly-two-element ranges at validation time
    timestamp_ranges: Optional[list[tuple[float, float]]] = None
    pages: Optional[list[int]] = None


class Section(BaseModel):
    id: str
    kind: Literal["slide", "page", "heading_section"]
    title: str
    location: SectionLocation
    visual_content_markdown: str
    raw_ocr_text: str
    spoken_content: list[TranscriptSegment] = []
    section_summary: str = ""
    asset_path: Optional[str] = None


class LectraDocument(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    meta: Meta
    summary: Summary
    sections: list[Section]
    transcript: list[TranscriptSegment]

    def to_json(self) -> str:
        return self.model_dump_json(by_alias=True, indent=2)


# ---------------------------------------------------------------------------
# Understanding-layer response (internal contract with the LLM, not the file
# format). Field names avoid aliases so the structured-output schema is plain.
# ---------------------------------------------------------------------------


class SectionSummaryItem(BaseModel):
    id: str
    summary: str


class UnderstandingResponse(BaseModel):
    global_summary: str
    one_liner: str
    language: Optional[str] = None
    key_concepts: list[KeyConcept] = []
    chapters: list[Chapter] = []
    section_summaries: list[SectionSummaryItem] = []
