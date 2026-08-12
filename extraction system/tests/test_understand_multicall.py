"""The multi-call understanding flow, with the local LLM mocked out.

Verifies that one summary call is made per section plus one call each for
document info, chapters, key concepts, and the global summary — and that
structured calls retry exactly once on malformed JSON before failing loudly.
"""

import json

import pytest

from lectra import understand
from lectra.errors import UnderstandingError
from lectra.schema import Section, SectionLocation


def _video_sections():
    return [
        Section(
            id="sec_001",
            kind="slide",
            title="Intro",
            location=SectionLocation(timestamp_ranges=[(0.0, 60.0)], pages=None),
            visual_content_markdown="## Intro",
            raw_ocr_text="Intro",
        ),
        Section(
            id="sec_002",
            kind="slide",
            title="Loss Functions",
            location=SectionLocation(timestamp_ranges=[(60.0, 120.0)], pages=None),
            visual_content_markdown="## Loss\n$L = \\sum e_i^2$",
            raw_ocr_text="Loss",
        ),
    ]


def _pdf_sections():
    return [
        Section(
            id="sec_001",
            kind="page",
            title="Abstract",
            location=SectionLocation(timestamp_ranges=None, pages=[1]),
            visual_content_markdown="# Abstract",
            raw_ocr_text="Abstract",
        ),
        Section(
            id="sec_002",
            kind="page",
            title="Methods",
            location=SectionLocation(timestamp_ranges=None, pages=[2]),
            visual_content_markdown="# Methods",
            raw_ocr_text="Methods",
        ),
    ]


class FakeChat:
    """Stands in for local_llm.chat; dispatches on the schema's model title."""

    def __init__(self, video=True, chapters_responses=None):
        self.video = video
        self.chapters_responses = list(chapters_responses or [])
        self.calls = []

    def __call__(self, prompt, *, system=None, images=None, schema=None, model=None,
                 num_predict=4096, timeout=None):
        self.calls.append({"prompt": prompt, "schema": schema})
        if schema is None:
            if prompt.startswith("Summarize this section"):
                return "A short section summary with $x^2$ preserved."
            return "Paragraph one.\n\nParagraph two.\n\nParagraph three."
        title = schema.get("title", "")
        if title == "_DocumentInfo":
            return json.dumps({"one_liner": "A lecture on optimization.", "language": "en"})
        if title.endswith("ChapterList"):
            if self.chapters_responses:
                return self.chapters_responses.pop(0)
            if self.video:
                return json.dumps({"chapters": [{"title": "Intro", "start_seconds": 0.0}]})
            return json.dumps({"chapters": [{"title": "Abstract", "page": 1}]})
        if title.endswith("ConceptList"):
            if self.video:
                return json.dumps(
                    {"key_concepts": [
                        {"concept": "Loss", "explanation": "How error is measured.",
                         "first_seen_seconds": 60.0}
                    ]}
                )
            return json.dumps(
                {"key_concepts": [
                    {"concept": "Methods", "explanation": "The approach.", "first_seen_page": 2}
                ]}
            )
        raise AssertionError(f"unexpected schema: {title}")


def test_multicall_assembly_video(monkeypatch):
    fake = FakeChat(video=True)
    monkeypatch.setattr(understand.local_llm, "chat", fake)

    response = understand.run_understanding(_video_sections(), source_type="video")

    assert [s.id for s in response.section_summaries] == ["sec_001", "sec_002"]
    assert response.one_liner == "A lecture on optimization."
    assert response.language == "en"
    assert response.chapters[0].start.timestamp == 0.0
    assert response.chapters[0].start.page is None
    assert response.key_concepts[0].first_seen.timestamp == 60.0
    assert response.global_summary.startswith("Paragraph one.")
    # multiple calls for one thing: 2 section summaries + info + chapters
    # + concepts + global = 6 calls
    assert len(fake.calls) == 6


def test_multicall_pdf_locations_use_pages(monkeypatch):
    fake = FakeChat(video=False)
    monkeypatch.setattr(understand.local_llm, "chat", fake)

    response = understand.run_understanding(_pdf_sections(), source_type="pdf")

    assert response.chapters[0].start.page == 1
    assert response.chapters[0].start.timestamp is None
    assert response.key_concepts[0].first_seen.page == 2
    assert response.key_concepts[0].first_seen.timestamp is None


def test_structured_call_retries_once_then_succeeds(monkeypatch):
    fake = FakeChat(
        video=True,
        chapters_responses=[
            "THIS IS NOT JSON",
            json.dumps({"chapters": [{"title": "Recovered", "start_seconds": 5.0}]}),
        ],
    )
    monkeypatch.setattr(understand.local_llm, "chat", fake)

    response = understand.run_understanding(_video_sections(), source_type="video")
    assert response.chapters[0].title == "Recovered"
    assert len(fake.calls) == 7  # exactly one extra call for the retry

    retry_prompt = fake.calls[4]["prompt"]  # the retried chapters call
    assert "Your previous response was invalid" in retry_prompt


def test_structured_call_fails_loudly_after_second_bad_response(monkeypatch):
    fake = FakeChat(video=True, chapters_responses=["bad", "still bad"])
    monkeypatch.setattr(understand.local_llm, "chat", fake)

    with pytest.raises(UnderstandingError, match="malformed chapters twice"):
        understand.run_understanding(_video_sections(), source_type="video")


def test_empty_sections_short_circuits(monkeypatch):
    def explode(*args, **kwargs):
        raise AssertionError("no LLM call expected for empty input")

    monkeypatch.setattr(understand.local_llm, "chat", explode)
    response = understand.run_understanding([], source_type="pdf")
    assert response.one_liner == "Empty document."
    assert response.section_summaries == []
