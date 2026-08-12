import copy
import json

import pytest
from pydantic import ValidationError

from lectra.schema import LectraDocument, Summary

VALID_VIDEO_DOC = {
    "meta": {
        "source_file": "lecture.mp4",
        "source_type": "video",
        "duration_seconds": 3542.0,
        "page_count": None,
        "language": "en",
        "mode": "deep",
        "processed_at": "2026-08-12T14:30:00Z",
        "tool_version": "0.1.0",
    },
    "summary": {
        "global": "A lecture on optimization. Update rule: $\\theta_{t+1} = \\theta_t - \\eta \\nabla J(\\theta)$.",
        "one_liner": "An introductory lecture on gradient descent.",
        "key_concepts": [
            {
                "concept": "Gradient descent",
                "explanation": "Iterative optimization via $\\theta_{t+1} = \\theta_t - \\eta \\nabla J(\\theta)$.",
                "first_seen": {"timestamp": 754.2, "page": None},
            }
        ],
        "chapters": [
            {"title": "Introduction", "start": {"timestamp": 0.0, "page": None}},
            {"title": "Loss functions", "start": {"timestamp": 412.5, "page": None}},
        ],
    },
    "sections": [
        {
            "id": "sec_001",
            "kind": "slide",
            "title": "Loss Functions",
            "location": {
                "timestamp_ranges": [[412.5, 638.0], [1204.0, 1231.5]],
                "pages": None,
            },
            "visual_content_markdown": "## Loss Functions\n- MSE: $L = \\frac{1}{n}\\sum (y_i - \\hat{y}_i)^2$",
            "raw_ocr_text": "Loss Functions MSE",
            "spoken_content": [
                {"start": 413.1, "end": 419.8, "text": "So now let's talk about error."}
            ],
            "section_summary": "Introduces MSE.",
            "asset_path": "assets/slide_001.png",
        }
    ],
    "transcript": [{"start": 0.0, "end": 4.2, "text": "Alright, welcome everyone."}],
}


def test_valid_video_document_validates():
    doc = LectraDocument.model_validate(VALID_VIDEO_DOC)
    assert doc.meta.source_type == "video"
    assert doc.summary.global_.startswith("A lecture")
    assert doc.sections[0].location.timestamp_ranges == [(412.5, 638.0), (1204.0, 1231.5)]


def test_valid_pdf_shaped_document_validates():
    doc_dict = copy.deepcopy(VALID_VIDEO_DOC)
    doc_dict["meta"].update({"source_type": "pdf", "duration_seconds": None, "page_count": 12})
    doc_dict["summary"]["chapters"] = [
        {"title": "Introduction", "start": {"timestamp": None, "page": 1}}
    ]
    doc_dict["sections"][0].update(
        {"kind": "page", "location": {"timestamp_ranges": None, "pages": [3]}, "spoken_content": []}
    )
    doc_dict["transcript"] = []
    doc = LectraDocument.model_validate(doc_dict)
    assert doc.meta.page_count == 12
    assert doc.sections[0].location.pages == [3]
    assert doc.transcript == []


def test_global_alias_round_trips_in_json():
    doc = LectraDocument.model_validate(VALID_VIDEO_DOC)
    dumped = json.loads(doc.to_json())
    assert "global" in dumped["summary"]
    assert "global_" not in dumped["summary"]
    # and it re-validates from its own serialized form
    assert LectraDocument.model_validate(dumped).summary.global_ == doc.summary.global_


def test_summary_constructable_by_field_name():
    summary = Summary(global_="text", one_liner="one line")
    assert summary.global_ == "text"


def test_missing_required_field_fails():
    broken = copy.deepcopy(VALID_VIDEO_DOC)
    del broken["summary"]["one_liner"]
    with pytest.raises(ValidationError):
        LectraDocument.model_validate(broken)


def test_invalid_section_kind_fails():
    broken = copy.deepcopy(VALID_VIDEO_DOC)
    broken["sections"][0]["kind"] = "chapter"
    with pytest.raises(ValidationError):
        LectraDocument.model_validate(broken)


def test_invalid_source_type_fails():
    broken = copy.deepcopy(VALID_VIDEO_DOC)
    broken["meta"]["source_type"] = "audio"
    with pytest.raises(ValidationError):
        LectraDocument.model_validate(broken)


def test_timestamp_range_must_have_two_elements():
    broken = copy.deepcopy(VALID_VIDEO_DOC)
    broken["sections"][0]["location"]["timestamp_ranges"] = [[412.5]]
    with pytest.raises(ValidationError):
        LectraDocument.model_validate(broken)


def test_wrong_type_for_timestamp_fails():
    broken = copy.deepcopy(VALID_VIDEO_DOC)
    broken["transcript"][0]["start"] = "zero"
    with pytest.raises(ValidationError):
        LectraDocument.model_validate(broken)
