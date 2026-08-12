"""Command-line interface: lectra process <input> [--output out.json] [--mode fast|deep]."""

from __future__ import annotations

import argparse
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from . import __version__, gemini_llm, pdf_pipeline, understand, video
from .errors import LectraError
from .progress import log, stage, warn
from .router import route
from .schema import LectraDocument, Meta


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="lectra",
        description=(
            "Extract the full content, structure, and summary of a lecture video or a PDF "
            "into one unified JSON file."
        ),
    )
    parser.add_argument("--version", action="version", version=f"lectra {__version__}")
    subparsers = parser.add_subparsers(dest="command", required=True)

    process = subparsers.add_parser(
        "process",
        help="Process a video (.mp4/.mkv/.mov/.webm/.avi) or a .pdf into structured JSON.",
    )
    process.add_argument("input", help="Path to the input video or PDF file")
    process.add_argument(
        "--output",
        "-o",
        help="Output JSON path (default: <input>.lectra.json next to the input)",
    )
    process.add_argument(
        "--mode",
        choices=("fast", "deep"),
        default="deep",
        help="deep = Gemini vision for slides/scanned pages (default); fast = OCR only",
    )
    process.add_argument(
        "--assets-dir",
        help="Directory for extracted images (default: <output basename>.assets/)",
    )
    process.add_argument(
        "--hash-threshold",
        type=int,
        default=video.DEFAULT_HASH_THRESHOLD,
        help="phash distance that counts as a slide change / revisit (video only, default 10)",
    )
    process.add_argument(
        "--sample-interval",
        type=float,
        default=video.DEFAULT_SAMPLE_INTERVAL,
        help="Seconds between sampled frames (video only, default 2.0)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return _process(args)
    except LectraError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        return 130


def _process(args: argparse.Namespace) -> int:
    started = time.perf_counter()

    input_path = Path(args.input).expanduser()
    if not input_path.is_file():
        print(f"error: input file not found: {input_path}", file=sys.stderr)
        return 2
    kind = route(input_path)

    llm_ready, llm_reason = gemini_llm.readiness()
    mode = args.mode
    if mode == "deep" and not llm_ready:
        warn(f"{llm_reason} — falling back to --mode fast (OCR only, no LLM).")
        mode = "fast"

    output = Path(args.output).expanduser() if args.output else input_path.with_suffix(".lectra.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    stem = output.name[: -len(".json")] if output.name.endswith(".json") else output.name
    assets_dir = (
        Path(args.assets_dir).expanduser() if args.assets_dir else output.parent / f"{stem}.assets"
    )
    log(
        f"Input: {input_path} ({kind}), mode={mode}, "
        f"llm={gemini_llm.model_name()} (Gemini API)"
    )

    transcript = []
    duration = None
    page_count = None
    language = "unknown"
    if kind == "video":
        sections, transcript, duration, language = video.process_video(
            input_path,
            mode=mode,
            assets_dir=assets_dir,
            hash_threshold=args.hash_threshold,
            sample_interval=args.sample_interval,
        )
    else:
        sections, page_count = pdf_pipeline.process_pdf(input_path, mode=mode, assets_dir=assets_dir)

    if llm_ready:
        with stage(
            f"Understanding layer (Gemini '{gemini_llm.model_name()}', multiple calls)"
        ):
            response = understand.run_understanding(sections, source_type=kind)
        summary = understand.apply_understanding(sections, response)
        if language == "unknown" and response.language:
            language = response.language
    else:
        warn(
            f"Skipping the LLM understanding layer ({llm_reason}) — "
            "writing a locally generated fallback summary."
        )
        summary = understand.build_fallback_summary(
            sections, source_type=kind, source_name=input_path.name
        )

    # Asset paths are stored relative to the output JSON's directory.
    output_dir = output.parent.resolve()
    for section in sections:
        if section.asset_path:
            relative = os.path.relpath(Path(section.asset_path).resolve(), output_dir)
            section.asset_path = Path(relative).as_posix()

    meta = Meta(
        source_file=input_path.name,
        source_type=kind,
        duration_seconds=duration,
        page_count=page_count,
        language=language,
        mode=mode,
        processed_at=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        tool_version=__version__,
    )

    with stage("Schema validation + write"):
        document = LectraDocument(
            meta=meta, summary=summary, sections=sections, transcript=transcript
        )
        output.write_text(document.to_json() + "\n", encoding="utf-8")

    log(
        f"Done in {time.perf_counter() - started:.1f}s — "
        f"{len(sections)} sections, {len(transcript)} transcript segments."
    )
    log(f"Wrote {output}")
    print(str(output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
