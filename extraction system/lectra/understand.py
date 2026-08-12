"""Understanding layer on the local 7B thinking model — decomposed into
MULTIPLE small calls, because a 7B model cannot digest a whole lecture in one
giant structured request:

  1. one summary call per section            (plain text)
  2. document info: one-liner + language     (schema-constrained JSON)
  3. chapter markers                         (schema-constrained JSON)
  4. key concepts with first-seen locations  (schema-constrained JSON)
  5. global summary                          (plain text)

Structured calls constrain generation with a JSON schema (Ollama `format`),
validate with pydantic, retry once with the error message, then fail loudly —
per the contract. When the local LLM is unavailable, build_fallback_summary
produces a valid (if modest) Summary locally instead of crashing.
"""

from __future__ import annotations

import re
from typing import Sequence

from pydantic import BaseModel, ValidationError

from . import local_llm
from .errors import UnderstandingError
from .progress import log, warn
from .schema import (
    Chapter,
    KeyConcept,
    PointLocation,
    Section,
    SectionSummaryItem,
    Summary,
    UnderstandingResponse,
)

MAX_VISUAL_CHARS = 3500  # per-call caps keep every request 7B-sized
MAX_SPOKEN_CHARS = 3500
MAX_OVERVIEW_CHARS = 16000

_LATEX_RULE = (
    "Preserve ALL notation exactly: mathematics stays LaTeX ($...$ / $$...$$), code stays in "
    "backticks or fenced blocks, and symbols/subscripts/superscripts are never rewritten as "
    "plain words."
)


# ---------------------------------------------------------------------------
# Flat, small-model-friendly wire schemas (internal to this module)
# ---------------------------------------------------------------------------


class _VideoChapter(BaseModel):
    title: str
    start_seconds: float


class _VideoChapterList(BaseModel):
    chapters: list[_VideoChapter]


class _PdfChapter(BaseModel):
    title: str
    page: int


class _PdfChapterList(BaseModel):
    chapters: list[_PdfChapter]


class _VideoConcept(BaseModel):
    concept: str
    explanation: str
    first_seen_seconds: float


class _VideoConceptList(BaseModel):
    key_concepts: list[_VideoConcept]


class _PdfConcept(BaseModel):
    concept: str
    explanation: str
    first_seen_page: int


class _PdfConceptList(BaseModel):
    key_concepts: list[_PdfConcept]


class _DocumentInfo(BaseModel):
    one_liner: str
    language: str


class _InvalidStructuredOutput(Exception):
    """Internal: the model responded but the JSON did not validate."""


# ---------------------------------------------------------------------------
# Input rendering
# ---------------------------------------------------------------------------


def _clip(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    return text[:limit] + "\n[...truncated...]"


def _describe_location(section: Section) -> str:
    location = section.location
    if location.timestamp_ranges:
        ranges = ", ".join(f"{start:.1f}s-{end:.1f}s" for start, end in location.timestamp_ranges)
        return f"appears at {ranges}"
    if location.pages:
        return "page " + ", ".join(str(p) for p in location.pages)
    return "location unknown"


def _section_content(section: Section) -> str:
    parts = [f"SECTION {section.id}: {section.title} ({_describe_location(section)})"]
    visual = section.visual_content_markdown or section.raw_ocr_text
    if visual:
        parts.append("VISUAL CONTENT:\n" + _clip(visual, MAX_VISUAL_CHARS))
    if section.spoken_content:
        spoken = " ".join(segment.text for segment in section.spoken_content)
        parts.append("SPOKEN (aligned transcript):\n" + _clip(spoken, MAX_SPOKEN_CHARS))
    return "\n\n".join(parts)


def _build_overview(
    sections: Sequence[Section], summaries: Sequence[SectionSummaryItem]
) -> str:
    by_id = {item.id: item.summary for item in summaries}
    lines = []
    for section in sections:
        lines.append(
            f"- {section.id} | {section.title} | {_describe_location(section)}\n"
            f"  {by_id.get(section.id, '')}"
        )
    text = "\n".join(lines)
    if len(text) > MAX_OVERVIEW_CHARS:
        text = text[:MAX_OVERVIEW_CHARS] + "\n[...truncated...]"
    return "SECTIONS:\n" + text


# ---------------------------------------------------------------------------
# Call helpers: retry once with the error, then fail loudly
# ---------------------------------------------------------------------------


def _text_call(prompt: str, *, what: str, num_predict: int = 4096) -> str:
    result = local_llm.chat(prompt, num_predict=num_predict).strip()
    if result:
        return result
    warn(f"{what}: the model returned an empty response, retrying once")
    retry_prompt = prompt + "\n\nYour previous response was empty. Respond with the requested text only."
    result = local_llm.chat(retry_prompt, num_predict=num_predict).strip()
    if result:
        return result
    raise UnderstandingError(f"The local LLM returned an empty {what} twice; giving up.")


def _extract_json(raw: str) -> str:
    text = raw.strip()
    fence = re.match(r"^```[a-zA-Z]*\s*\n(.*)\n```$", text, re.DOTALL)
    if fence:
        text = fence.group(1).strip()
    start, end = text.find("{"), text.rfind("}")
    if start != -1 and end > start:
        return text[start : end + 1]
    return text


def _structured_call(prompt: str, response_model: type[BaseModel], *, what: str):
    schema = response_model.model_json_schema()

    def attempt(current_prompt: str):
        raw = local_llm.chat(current_prompt, schema=schema)
        try:
            return response_model.model_validate_json(_extract_json(raw))
        except ValidationError as exc:
            raise _InvalidStructuredOutput(str(exc)) from exc

    try:
        return attempt(prompt)
    except _InvalidStructuredOutput as first_error:
        warn(f"{what}: invalid JSON from the model, retrying once ({str(first_error)[:160]})")
        retry_prompt = (
            f"{prompt}\n\nYour previous response was invalid: {str(first_error)[:400]}\n"
            "Respond again with ONLY valid JSON matching the schema."
        )
        try:
            return attempt(retry_prompt)
        except _InvalidStructuredOutput as second_error:
            raise UnderstandingError(
                f"The local LLM returned malformed {what} twice; giving up. "
                f"Last error: {str(second_error)[:400]}"
            ) from second_error


# ---------------------------------------------------------------------------
# The multi-call understanding flow
# ---------------------------------------------------------------------------


def run_understanding(sections: Sequence[Section], source_type: str) -> UnderstandingResponse:
    if not sections:
        return UnderstandingResponse(
            global_summary="The document contained no extractable sections.",
            one_liner="Empty document.",
        )

    source_desc = "video lecture" if source_type == "video" else "PDF document"

    # Calls 1..N: one small summary call per section.
    section_summaries: list[SectionSummaryItem] = []
    for index, section in enumerate(sections, start=1):
        prompt = (
            f"Summarize this section of a {source_desc} in 1-3 sentences. {_LATEX_RULE} "
            "Reply with ONLY the summary text — no preamble, no headings.\n\n"
            + _section_content(section)
        )
        summary = _text_call(prompt, what=f"summary for {section.id}")
        section_summaries.append(SectionSummaryItem(id=section.id, summary=summary))
        log(f"  section summaries: {index}/{len(sections)}")

    overview = _build_overview(sections, section_summaries)

    # Call N+1: one-liner + language.
    info = _structured_call(
        f"You are given per-section summaries of a {source_desc}.\n\n{overview}\n\n"
        'Return JSON with "one_liner" (a single sentence describing what this content is) '
        'and "language" (the ISO 639-1 code of the content\'s primary language, e.g. "en").',
        _DocumentInfo,
        what="document info",
    )
    log("  document info done")

    # Call N+2: chapter markers.
    if source_type == "video":
        chapter_list = _structured_call(
            f"You are given per-section summaries of a {source_desc}, with the time ranges "
            f"where each section appears on screen.\n\n{overview}\n\n"
            "Produce chapter markers like YouTube chapters: 3 to 12 entries in chronological "
            "order (fewer only if the content is very short). Return JSON with \"chapters\": a "
            'list of {"title", "start_seconds"}. Each start_seconds must be the start of the '
            "section where that chapter begins, taken from the ranges above.",
            _VideoChapterList,
            what="chapters",
        )
        chapters = [
            Chapter(
                title=item.title,
                start=PointLocation(timestamp=round(float(item.start_seconds), 2)),
            )
            for item in chapter_list.chapters
        ]
    else:
        chapter_list = _structured_call(
            f"You are given per-section summaries of a {source_desc}, with the page number of "
            f"each section.\n\n{overview}\n\n"
            "Produce chapter markers like a table of contents: 3 to 12 entries in order (fewer "
            'only if the content is very short). Return JSON with "chapters": a list of '
            '{"title", "page"}. Each page must be the 1-based page number of the section where '
            "that chapter begins, taken from the list above.",
            _PdfChapterList,
            what="chapters",
        )
        chapters = [
            Chapter(title=item.title, start=PointLocation(page=int(item.page)))
            for item in chapter_list.chapters
        ]
    log("  chapters done")

    # Call N+3: key concepts with first-seen locations.
    if source_type == "video":
        concept_list = _structured_call(
            f"You are given per-section summaries of a {source_desc}, with the time ranges "
            f"where each section appears.\n\n{overview}\n\n"
            f"Identify the 5 to 15 most important concepts (fewer only if the content is very "
            f"short). {_LATEX_RULE} Return JSON with \"key_concepts\": a list of "
            '{"concept", "explanation", "first_seen_seconds"}. explanation is 2-3 sentences; '
            "first_seen_seconds is the start of the section where the concept is first "
            "explained, taken from the ranges above.",
            _VideoConceptList,
            what="key concepts",
        )
        concepts = [
            KeyConcept(
                concept=item.concept,
                explanation=item.explanation,
                first_seen=PointLocation(timestamp=round(float(item.first_seen_seconds), 2)),
            )
            for item in concept_list.key_concepts
        ]
    else:
        concept_list = _structured_call(
            f"You are given per-section summaries of a {source_desc}, with the page number of "
            f"each section.\n\n{overview}\n\n"
            f"Identify the 5 to 15 most important concepts (fewer only if the content is very "
            f"short). {_LATEX_RULE} Return JSON with \"key_concepts\": a list of "
            '{"concept", "explanation", "first_seen_page"}. explanation is 2-3 sentences; '
            "first_seen_page is the 1-based page where the concept is first explained, taken "
            "from the list above.",
            _PdfConceptList,
            what="key concepts",
        )
        concepts = [
            KeyConcept(
                concept=item.concept,
                explanation=item.explanation,
                first_seen=PointLocation(page=int(item.first_seen_page)),
            )
            for item in concept_list.key_concepts
        ]
    log("  key concepts done")

    # Call N+4: global summary.
    global_summary = _text_call(
        f"Write a global summary of this {source_desc} in three to six paragraphs, based on "
        f"the per-section summaries below. {_LATEX_RULE} "
        "Reply with ONLY the summary paragraphs — no preamble, no headings.\n\n" + overview,
        what="global summary",
        num_predict=8192,
    )
    log("  global summary done")

    return UnderstandingResponse(
        global_summary=global_summary,
        one_liner=info.one_liner,
        language=info.language or None,
        key_concepts=concepts,
        chapters=chapters,
        section_summaries=section_summaries,
    )


def apply_understanding(sections: Sequence[Section], response: UnderstandingResponse) -> Summary:
    """Write per-section summaries onto the sections and build the Summary."""
    summaries = {item.id: item.summary for item in response.section_summaries}
    missing = [section.id for section in sections if section.id not in summaries]
    if missing:
        warn(f"Understanding pass missed section summaries for: {', '.join(missing)}")
    for section in sections:
        section.section_summary = summaries.get(section.id, section.section_summary or "")
    return Summary(
        global_=response.global_summary,
        one_liner=response.one_liner,
        key_concepts=response.key_concepts,
        chapters=response.chapters,
    )


# ---------------------------------------------------------------------------
# Offline fallback (local LLM unavailable): never crash, emit a valid Summary
# ---------------------------------------------------------------------------


def build_fallback_summary(
    sections: Sequence[Section], source_type: str, source_name: str
) -> Summary:
    chapters: list[Chapter] = []
    for section in sections:
        point = PointLocation()
        if section.location.timestamp_ranges:
            point = PointLocation(timestamp=section.location.timestamp_ranges[0][0])
        elif section.location.pages:
            point = PointLocation(page=section.location.pages[0])
        chapters.append(Chapter(title=section.title, start=point))

    titles = "; ".join(section.title for section in sections[:15])
    global_text = (
        f"Automatically extracted structure of {source_name} "
        f"({len(sections)} sections, source type: {source_type}). "
        "No LLM summarization was performed because the local LLM was unavailable; "
        f"start Ollama (`ollama serve`), pull the model (`ollama pull {local_llm.model_name()}`), "
        "and re-run for full summaries, key concepts, and chapters. "
        f"Extracted sections include: {titles}."
    )
    return Summary(
        global_=global_text,
        one_liner=f"Extracted content of {source_name} ({len(sections)} sections; no LLM summary).",
        key_concepts=[],
        chapters=chapters,
    )
