"""End-to-end smoke test of the PDF pipeline on a small generated digital PDF.

Runs the real CLI (fast mode, no API key) and validates the produced JSON
against the contract. Skipped automatically when PyMuPDF is not installed.
"""

import json

import pytest

fitz = pytest.importorskip("pymupdf", reason="PyMuPDF not installed")

from lectra.cli import main
from lectra.schema import LectraDocument


def _make_pdf(path):
    doc = fitz.open()
    page = doc.new_page()
    page.insert_text((72, 90), "Gradient Descent", fontsize=22)
    page.insert_text(
        (72, 140),
        "The update rule moves the parameters against the gradient of the loss function.",
        fontsize=11,
    )
    page.insert_text((72, 170), "- learning rate controls the step size", fontsize=11)

    page2 = doc.new_page()
    page2.insert_text((72, 90), "Backpropagation", fontsize=22)
    page2.insert_text(
        (72, 140),
        "Gradients flow backward through the network using the chain rule.",
        fontsize=11,
    )
    doc.save(str(path))
    doc.close()


def test_pdf_pipeline_end_to_end_fast_mode(tmp_path, monkeypatch):
    # No API key -> deterministic fallback path (no network calls)
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)

    pdf_path = tmp_path / "mini_lecture.pdf"
    _make_pdf(pdf_path)
    output_path = tmp_path / "out.json"

    exit_code = main(["process", str(pdf_path), "--output", str(output_path), "--mode", "fast"])
    assert exit_code == 0
    assert output_path.exists()

    data = json.loads(output_path.read_text(encoding="utf-8"))
    doc = LectraDocument.model_validate(data)

    assert doc.meta.source_type == "pdf"
    assert doc.meta.page_count == 2
    assert doc.meta.duration_seconds is None
    assert doc.meta.mode == "fast"
    assert doc.transcript == []

    assert [s.id for s in doc.sections] == ["sec_001", "sec_002"]
    assert all(s.kind == "page" for s in doc.sections)
    assert doc.sections[0].location.pages == [1]
    assert doc.sections[0].location.timestamp_ranges is None
    assert doc.sections[0].spoken_content == []

    # heading detection: the large-font line becomes the title and a heading
    assert doc.sections[0].title == "Gradient Descent"
    assert "# Gradient Descent" in doc.sections[0].visual_content_markdown
    assert doc.sections[1].title == "Backpropagation"

    # digital pages keep their extracted text as the raw fallback
    assert "update rule" in doc.sections[0].raw_ocr_text

    # no API key -> locally built fallback summary, one chapter per section
    assert len(doc.summary.chapters) == 2
    assert doc.summary.chapters[0].start.page == 1
    assert doc.summary.one_liner


def test_deep_mode_without_api_key_falls_back_to_fast(tmp_path, monkeypatch, capsys):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)

    pdf_path = tmp_path / "mini.pdf"
    _make_pdf(pdf_path)
    output_path = tmp_path / "out.json"

    exit_code = main(["process", str(pdf_path), "--output", str(output_path)])  # default deep
    assert exit_code == 0

    captured = capsys.readouterr()
    assert "falling back to --mode fast" in captured.err

    data = json.loads(output_path.read_text(encoding="utf-8"))
    assert data["meta"]["mode"] == "fast"


def test_missing_input_file_exits_2(tmp_path, capsys):
    exit_code = main(["process", str(tmp_path / "nope.pdf")])
    assert exit_code == 2
    assert "not found" in capsys.readouterr().err


def test_unsupported_extension_exits_1(tmp_path, capsys):
    bogus = tmp_path / "notes.txt"
    bogus.write_text("hello")
    exit_code = main(["process", str(bogus)])
    assert exit_code == 1
    assert "Unsupported input type" in capsys.readouterr().err
