# lectra

`lectra` turns a **lecture video** or a **PDF** into one structured JSON file containing the full content, structure, and summary of the input — with mathematical notation preserved as LaTeX and code kept in fenced blocks.

**All AI runs locally.** There is no cloud API: lectra talks to a local model served by [Ollama](https://ollama.com) — by default **`qwen3:8b`**, a small local reasoning model, with **thinking mode** enabled on every call. Because a model this size can't digest a whole lecture in one giant request, the understanding layer is decomposed into **multiple small calls**: one summary call per section, then separate calls for chapters, key concepts, document info, and the global summary.

```
lectra process <input_file> [--output out.json] [--mode fast|deep]
```

Both pipelines emit the **same unified JSON schema** (validated with pydantic before writing), so downstream code never needs to know whether the source was a video or a PDF.

## How it works

**Video** (`.mp4` `.mkv` `.mov` `.webm` `.avi`):

1. ffmpeg extracts 16 kHz mono audio.
2. faster-whisper (`small`, int8, VAD) produces a timestamped transcript.
3. OpenCV samples a frame every 2 s; perceptual hashes (phash) detect slide changes; revisited slides are deduplicated — each unique slide keeps *all* of its appearance time ranges and is saved as `slide_001.png`, … in an assets folder.
4. Slide content: **fast** mode stores raw PaddleOCR lines; **deep** mode (default) makes one local-LLM call per slide to produce structured markdown (title, bullet hierarchy, equations in LaTeX, code in fenced blocks, figure descriptions). If `LECTRA_VISION_MODEL` names a local vision model (e.g. `qwen2.5vl:7b`) the slide image is read directly; otherwise the 7B thinking model reconstructs the content from the OCR lines. Raw OCR text is always kept as a fallback.
5. Transcript segments are aligned to the slide on screen when they were spoken.
6. The understanding layer runs its multi-call pass (see below): global summary, key concepts with first-seen timestamps, chapter markers, per-section summaries.

**PDF**:

1. PyMuPDF opens the file; a page with fewer than 20 characters of text *and* at least one image is classified as **scanned**.
2. Digital pages: font-size information turns large spans into markdown headings; text becomes clean per-page markdown.
3. Scanned pages: rendered to PNG at 200 dpi, then OCR (fast) or a local-LLM structuring call (deep) — same backends and LaTeX-preservation rules as video slides.
4. Understanding layer as above, with page numbers instead of timestamps.

**The understanding layer — multiple calls for one thing.** Instead of a single oversized request, lectra makes N + 4 small calls, each sized for a 7B model:

| Call | Output |
|---|---|
| 1…N — one per section | 1–3 sentence section summary (plain text) |
| N+1 | one-liner + language (schema-constrained JSON) |
| N+2 | chapter markers (schema-constrained JSON) |
| N+3 | key concepts + first-seen locations (schema-constrained JSON) |
| N+4 | 3–6 paragraph global summary (plain text) |

Structured calls pass a JSON schema through Ollama's `format` parameter, are validated with pydantic, retried **once** with the error message on malformed output, and then fail loudly. Thinking output (`<think>…</think>` / Ollama's `thinking` field) is kept out of the results.

## Install

Python **3.11+** is required. Either `uv` or plain `venv`+`pip` works — dependencies live in `pyproject.toml` with a mirrored `requirements.txt`. The LLM client is stdlib-only (no SDK).

**1. Ollama + the thinking model:**

```bash
brew install ollama          # macOS (or download from https://ollama.com)
ollama serve                 # if the Ollama app isn't already running
ollama pull qwen3:8b         # ~5.2 GB, the default model
```

Optional — a local vision model so deep mode reads slide images directly instead of structuring OCR text:

```bash
ollama pull qwen2.5vl:7b
export LECTRA_VISION_MODEL=qwen2.5vl:7b
```

**2. ffmpeg** (needed for video inputs):

```bash
brew install ffmpeg        # macOS
sudo apt install ffmpeg    # Debian/Ubuntu
```

**3. The package** — with `uv`:

```bash
cd "extraction system"
uv venv && source .venv/bin/activate
uv pip install -e ".[dev]"
```

or with plain pip:

```bash
cd "extraction system"
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
pip install -e ".[dev]"        # installs the `lectra` command + pytest
```

**4. OCR (recommended)** — PaddleOCR powers `--mode fast`, the always-kept `raw_ocr_text`, and (when no vision model is configured) the text that deep mode structures. Its wheels are platform-sensitive, so it ships as an extra:

```bash
pip install -e ".[ocr]"        # paddleocr + paddlepaddle
```

If the Ollama server is down or the model isn't pulled, lectra **does not crash**: it warns, drops to fast mode, and writes a locally generated fallback summary.

First-run downloads: faster-whisper fetches the `small` model (~460 MB) and PaddleOCR fetches its recognition models.

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
| `LECTRA_MODEL` | `qwen3:8b` | The local text model (thinking-capable) |
| `LECTRA_VISION_MODEL` | *(unset)* | Optional local vision model for deep mode (e.g. `qwen2.5vl:7b`) |
| `LECTRA_OLLAMA_URL` | `http://localhost:11434` | Where the Ollama server listens |
| `LECTRA_NUM_CTX` | `8192` | Context window requested per call |
| `LECTRA_LLM_TIMEOUT` | `600` | Per-call timeout in seconds (CPU inference is slow) |

Thinking mode is requested on every call; if a configured model doesn't support it, lectra warns once and continues without it.

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
| Ollama server unreachable | Warn → fall back to fast mode + local fallback summary |
| `qwen3:8b` not pulled | Same, with the exact `ollama pull` command in the warning |
| `--mode fast`, LLM available | OCR content, but the understanding layer still runs (text-only calls) |
| Deep mode, no vision model configured | Slides/scanned pages are structured from their OCR lines by the text model |
| `LECTRA_VISION_MODEL` set but not pulled | Warn once; fall back to OCR-line structuring |
| PaddleOCR not installed | Warn once; `raw_ocr_text` empty; pipeline continues |
| ffmpeg missing (video input) | Clear fatal error with install instructions |
| Video has no audio stream | Warn; empty transcript; slides still processed |
| One slide's LLM call fails | Warn; that slide falls back to raw OCR text |
| Model emits malformed JSON | Retry once with the error message, then fail loudly |

## Project layout

```
lectra/
├── cli.py           # argparse entry point (`lectra process ...`)
├── router.py        # extension → video | pdf
├── video.py         # ffmpeg → whisper → phash slides → dedup → align
├── pdf_pipeline.py  # page routing, heading-aware markdown, 200dpi renders
├── vision.py        # shared OCR + local-LLM markdown structuring (BOTH pipelines)
├── local_llm.py     # Ollama client: thinking mode, JSON-schema outputs, readiness
├── understand.py    # multi-call understanding layer + retry + offline fallback
├── schema.py        # the pydantic contract
├── errors.py        # exception hierarchy
└── progress.py      # stderr stage logging with timings
tests/               # router, slide dedup (synthetic hashes), scanned-page detector,
                     # schema validation, local-LLM client, multi-call understanding
                     # (mocked), and an end-to-end PDF smoke test
```

## Tests

```bash
pytest
```

The unit tests run without any heavy dependencies or a running Ollama (LLM calls are mocked or pointed at a closed port). The PDF smoke test generates a small digital PDF with PyMuPDF and runs the real CLI end to end; it skips itself if PyMuPDF is absent.
