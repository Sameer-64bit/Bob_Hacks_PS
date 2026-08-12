# lectra

`lectra` turns a **lecture video** or a **PDF** into one structured JSON file containing the full content, structure, and summary of the input — with mathematical notation preserved as LaTeX and code kept in fenced blocks.

The AI layer is powered by the **Gemini API** (multimodal — page and slide images go straight to the model). Because one giant request is fragile, the understanding layer is decomposed into **multiple small calls**: one summary call per section, then separate calls for chapters, key concepts, document info, and the global summary — each schema-constrained, validated, and retried once on malformed output.

```
lectra process <input_file> [--output out.json] [--mode fast|deep]
```

Both pipelines emit the **same unified JSON schema** (validated with pydantic before writing), so downstream code never needs to know whether the source was a video or a PDF.

## How it works

**Video** (`.mp4` `.mkv` `.mov` `.webm` `.avi`):

1. ffmpeg extracts 16 kHz mono audio.
2. faster-whisper (`small`, int8, VAD) produces a timestamped transcript.
3. OpenCV samples a frame every 2 s; perceptual hashes (phash) detect slide changes; revisited slides are deduplicated — each unique slide keeps *all* of its appearance time ranges and is saved as `slide_001.png`, … in an assets folder.
4. Slide content: **fast** mode stores raw OCR lines; **deep** mode (default) sends each slide image to Gemini for structured markdown (title, bullet hierarchy, equations in LaTeX, code in fenced blocks, one-line figure descriptions). Raw OCR text is always kept as a fallback.
5. Transcript segments are aligned to the slide on screen when they were spoken.
6. The understanding layer runs its multi-call pass: global summary, key concepts with first-seen timestamps, chapter markers, per-section summaries.

**PDF**:

1. PyMuPDF opens the file; a page with fewer than 20 characters of text *and* at least one image is classified as **scanned**.
2. Digital pages: font-size information turns large spans into markdown headings; text becomes clean per-page markdown.
3. Scanned pages: rendered to PNG at 200 dpi, then OCR (fast) or Gemini vision (deep) — same LaTeX-preservation rules as video slides.
4. Understanding layer as above, with page numbers instead of timestamps.

**The understanding layer — multiple calls for one thing:**

| Call | Output |
|---|---|
| 1…N — one per section | 1–3 sentence section summary (plain text) |
| N+1 | one-liner + language (schema-constrained JSON) |
| N+2 | chapter markers (schema-constrained JSON) |
| N+3 | key concepts + first-seen locations (schema-constrained JSON) |
| N+4 | 3–6 paragraph global summary (plain text) |

Structured calls are constrained with Gemini's `responseSchema`, validated with pydantic, retried **once** with the error message on malformed output, and then fail loudly.

## Install

Python **3.11+** is required. Either `uv` or plain `venv`+`pip` works — dependencies live in `pyproject.toml` with a mirrored `requirements.txt`. The Gemini client is stdlib-only (no SDK).

**1. A Gemini API key** (from [Google AI Studio](https://aistudio.google.com/apikey)):

```bash
export GEMINI_API_KEY=your-key-here
```

**2. ffmpeg** (needed for video inputs):

```bash
brew install ffmpeg        # macOS
sudo apt install ffmpeg    # Debian/Ubuntu
```

**3. The package:**

```bash
cd "extraction system"
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
pip install -e ".[dev]"        # installs the `lectra` command + pytest
```

**4. OCR (optional)** — populates the `raw_ocr_text` fallback and powers `--mode fast`. PaddleOCR ships as an extra because its wheels are platform-sensitive; a system `tesseract` binary is used as an automatic fallback when PaddleOCR is absent:

```bash
pip install -e ".[ocr]"        # paddleocr + paddlepaddle
# or: brew install tesseract
```

If `GEMINI_API_KEY` is missing, lectra **does not crash**: it warns, drops to fast mode, and writes a locally generated fallback summary.

First video run downloads the Whisper `small` model (~460 MB); transcription runs locally via faster-whisper.

## Usage

Video (deep mode is the default):

```bash
lectra process lecture.mp4 --output lecture.json
```

PDF, OCR-only:

```bash
lectra process paper.pdf --mode fast -o paper.json
```

Output defaults to `<input>.lectra.json` next to the input. Extracted images land in `<output basename>.assets/` (`slide_001.png` for video, `page_003.png` for scanned PDF pages); `--assets-dir` overrides this. Asset paths inside the JSON are relative to the JSON file. For video, `--hash-threshold` (default 10) and `--sample-interval` (default 2.0 s) tune slide detection.

Progress for every stage — and how long it took — is printed to **stderr**; the only thing on stdout is the output path, so the command composes in scripts.

### Environment variables

| Variable | Default | Effect |
|---|---|---|
| `GEMINI_API_KEY` | *(required for deep mode + summaries)* | Gemini API key |
| `LECTRA_GEMINI_MODEL` | `gemini-flash-latest` | Gemini model id |
| `LECTRA_GEMINI_MIN_INTERVAL` | `3.2` | Seconds between API calls (raise on strict free-tier keys) |
| `LECTRA_LLM_TIMEOUT` | `180` | Per-call timeout in seconds |

Rate limits are handled automatically: calls are paced, and 429/5xx responses are retried with backoff.

## Output schema (contract)

```jsonc
{
  "meta":    { "source_file", "source_type", "duration_seconds", "page_count",
               "language", "mode", "processed_at", "tool_version" },
  "summary": { "global", "one_liner",
               "key_concepts": [{ "concept", "explanation", "first_seen": {"timestamp", "page"} }],
               "chapters":     [{ "title", "start": {"timestamp", "page"} }] },
  "sections": [{ "id", "kind",                       // "slide" | "page" | "heading_section"
                 "title",
                 "location": { "timestamp_ranges",   // all appearances; null for pdf
                               "pages" },            // page numbers; null for video
                 "visual_content_markdown",          // LaTeX math, fenced code, figure notes
                 "raw_ocr_text",                     // always kept, even in deep mode
                 "spoken_content": [{ "start", "end", "text" }],   // [] for pdf
                 "section_summary",
                 "asset_path" }],                    // null if no image saved
  "transcript": [{ "start", "end", "text" }]         // [] for pdf
}
```

Timestamps are seconds as floats. The document is validated against the pydantic models in `lectra/schema.py` before the file is written.

## Graceful degradation

| Situation | Behavior |
|---|---|
| `GEMINI_API_KEY` not set | Warn → fall back to fast mode + local fallback summary |
| `--mode fast`, key present | OCR content, but the understanding layer still runs |
| API rate-limited (429) | Automatic pacing + backoff retries |
| PaddleOCR not installed | Fall back to system `tesseract`; if absent too, warn and continue with empty `raw_ocr_text` |
| ffmpeg missing (video input) | Clear fatal error with install instructions |
| Video has no audio stream | Warn; empty transcript; slides still processed |
| One slide's vision call fails | Warn; that slide falls back to raw OCR text |
| Model emits malformed JSON | Retry once with the error message, then fail loudly |

## Project layout

```
lectra/
├── cli.py           # argparse entry point (`lectra process ...`)
├── router.py        # extension → video | pdf
├── video.py         # ffmpeg → whisper → phash slides → dedup → align
├── pdf_pipeline.py  # page routing, heading-aware markdown, 200dpi renders
├── vision.py        # shared OCR + Gemini vision (used by BOTH pipelines)
├── gemini_llm.py    # Gemini API client: pacing, retries, responseSchema
├── understand.py    # multi-call understanding layer + retry + offline fallback
├── schema.py        # the pydantic contract
├── errors.py        # exception hierarchy
└── progress.py      # stderr stage logging with timings
tests/               # router, slide dedup (synthetic hashes), scanned-page detector,
                     # schema validation, Gemini client (no network), multi-call
                     # understanding (mocked), and an end-to-end PDF smoke test
```

## Tests

```bash
pytest
```

The tests run without any heavy dependencies, a network connection, or an API key (LLM calls are mocked; the no-key fallback path is exercised for real). The PDF smoke test generates a small digital PDF with PyMuPDF and runs the real CLI end to end; it skips itself if PyMuPDF is absent.
