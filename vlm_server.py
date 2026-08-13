import base64
import io
import json
import os
import socket
import threading
import time
import urllib.request

import torch
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger
from PIL import Image
from pydantic import BaseModel
from transformers import AutoProcessor, AutoModelForVision2Seq

# ---------------------------------------------------------------------------
# Auto-discovery: announce this server's current LAN address to Supabase so
# the app never needs a hardcoded IP. If the wifi hands out a new IP, the
# next heartbeat updates it and every client picks it up automatically.
# ---------------------------------------------------------------------------
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://zxudswchxzfmfydulrvi.supabase.co")
SUPABASE_ANON_KEY = os.environ.get(
    "SUPABASE_ANON_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp4dWRzd2NoeHpmbWZ5ZHVscnZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1MzI5ODIsImV4cCI6MjEwMjEwODk4Mn0.i6qbTyW2fnNkdF4enIIIJzCnTVY1pRHntVIFqyOisDU",
)
PORT = int(os.environ.get("PORT", "5000"))
HEARTBEAT_SECONDS = 20


def lan_ip() -> str:
    """Local network IP of this machine (no traffic is actually sent)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def announce_forever():
    while True:
        url = f"http://{lan_ip()}:{PORT}"
        body = json.dumps({"id": "default", "url": url}).encode()
        req = urllib.request.Request(
            f"{SUPABASE_URL}/rest/v1/ai_servers",
            data=body,
            method="POST",
            headers={
                "apikey": SUPABASE_ANON_KEY,
                "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                "Content-Type": "application/json",
                "Prefer": "resolution=merge-duplicates",
            },
        )
        try:
            urllib.request.urlopen(req, timeout=10).read()
            logger.info(f"Announced AI server at {url}")
        except Exception as e:  # noqa: BLE001 — keep the heartbeat alive
            logger.warning(f"Could not announce server address: {e}")
        time.sleep(HEARTBEAT_SECONDS)


logger.info("Initializing SmolVLM-500M-Instruct. This may take a moment to download the first time...")
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
logger.info(f"Using device: {DEVICE}")

# Initialize model and processor globally
processor = AutoProcessor.from_pretrained("HuggingFaceTB/SmolVLM-500M-Instruct")
model = AutoModelForVision2Seq.from_pretrained(
    "HuggingFaceTB/SmolVLM-500M-Instruct",
    torch_dtype=torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16,
).to(DEVICE)
logger.success("Model loaded successfully!")

app = FastAPI()

# The Flutter web build calls this server from the browser — without CORS
# headers every request would be blocked before it reaches us.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

threading.Thread(target=announce_forever, daemon=True).start()

class GenerateRequest(BaseModel):
    prompt: str
    image_b64: str = None


def run_vlm(prompt: str, image: Image.Image | None = None, max_new_tokens: int = 512) -> str:
    """One SmolVLM generation — shared by /generate and the notes pipeline."""
    messages = [{"role": "user", "content": []}]
    if image is not None:
        messages[0]["content"].append({"type": "image"})
    messages[0]["content"].append({"type": "text", "text": prompt})

    prompt_text = processor.apply_chat_template(messages, add_generation_prompt=True)
    if image is not None:
        inputs = processor(text=prompt_text, images=[image], return_tensors="pt")
    else:
        inputs = processor(text=prompt_text, return_tensors="pt")
    inputs = inputs.to(DEVICE)

    # Greedy decoding + repetition penalty keeps the small model from
    # inventing objects ("a plant on the desk"…) that are not on the board.
    generated_ids = model.generate(
        **inputs,
        max_new_tokens=max_new_tokens,
        do_sample=False,
        repetition_penalty=1.3,
    )
    output = processor.batch_decode(generated_ids, skip_special_tokens=True)[0]
    if "Assistant:" in output:
        output = output.split("Assistant:")[-1].strip()
    return output


@app.post("/generate")
def generate(req: GenerateRequest):
    logger.info(f"Received request with prompt: {req.prompt[:80]}")
    image = None
    if req.image_b64:
        image = Image.open(io.BytesIO(base64.b64decode(req.image_b64))).convert("RGB")
    output = run_vlm(req.prompt, image)
    logger.success(f"Generated response: {output[:100]}...")
    return {"text": output}


# ===========================================================================
# Class notes — "End class" pipeline
#   slides (+ optional lecture audio with slide timestamps) -> whisper
#   transcript -> SmolVLM slide reading -> structured notes JSON.
#   Progress is written to Supabase so the app's progress bar fills live.
# ===========================================================================

import tempfile

from notes_pipeline import align_segments, compose_notes, gemini_enhance, wiki_enrich

WHISPER_MODEL_SIZE = os.environ.get("WHISPER_MODEL", "base")  # tiny/base = fast
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
_whisper_model = None
_whisper_lock = threading.Lock()


def get_whisper():
    """Lazy-load faster-whisper so the server starts fast without it."""
    global _whisper_model
    with _whisper_lock:
        if _whisper_model is None:
            from faster_whisper import WhisperModel

            logger.info(f"Loading faster-whisper '{WHISPER_MODEL_SIZE}' (int8)…")
            _whisper_model = WhisperModel(
                WHISPER_MODEL_SIZE, device="auto", compute_type="int8"
            )
            logger.success("Whisper ready.")
    return _whisper_model


def supabase_update_note(note_id: str, fields: dict):
    body = json.dumps(fields).encode()
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/class_notes?id=eq.{note_id}",
        data=body,
        method="PATCH",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
        },
    )
    try:
        urllib.request.urlopen(req, timeout=10).read()
    except Exception as e:  # noqa: BLE001
        logger.warning(f"Could not update note {note_id}: {e}")


class EndClassRequest(BaseModel):
    note_id: str
    language: str = "en"
    title: str = "Class notes"
    slides: list[str] = []          # base64 PNGs, in order
    stroke_counts: list[int] = []   # strokes per slide — sparse slides skip the VLM
    slide_marks: list[dict] = []    # [{"index": int, "at": seconds}]
    session_id: str | None = None   # live captions become the transcript
    audio_b64: str | None = None
    audio_url: str | None = None           # public URL (preferred for big files)
    audio_ext: str = "webm"


# Sparse doodles make the 500M model hallucinate scenery. Below this many
# strokes we don't ask it anything.
MIN_STROKES_FOR_VLM = 3

SLIDE_PROMPT = (
    "This image is a digital whiteboard from a class: handwriting and line "
    "drawings on a plain white background. There are no photos, objects, "
    "plants or people in it. Transcribe the text that is actually written "
    "and briefly describe any diagram, in 2-3 sentences of class notes. "
    "If the strokes are too unclear to read, reply exactly: Unclear sketch."
)


def _transcribe(req: EndClassRequest):
    """faster-whisper transcription (from the `transcription` branch)."""
    audio_bytes = None
    if req.audio_b64:
        audio_bytes = base64.b64decode(req.audio_b64)
    elif req.audio_url:
        with urllib.request.urlopen(req.audio_url, timeout=60) as resp:
            audio_bytes = resp.read()
    if not audio_bytes:
        return []
    with tempfile.NamedTemporaryFile(suffix=f".{req.audio_ext}", delete=False) as f:
        f.write(audio_bytes)
        path = f.name
    segments, info = get_whisper().transcribe(path, vad_filter=True)
    out = [
        {"start": float(s.start), "end": float(s.end), "text": s.text}
        for s in segments
    ]
    logger.info(f"Transcribed {len(out)} segments ({info.language}, {info.duration:.0f}s)")
    return out


def _generate_notes(note_id, title, language, slides, stroke_counts, slide_marks, segments):
    """Slides + transcript segments -> finished notes row. Shared by the
    end-class flow and the lecture-video flow."""
    note = lambda p, s: supabase_update_note(note_id, {"progress": p, "stage": s})  # noqa: E731

    # Read every slide with SmolVLM (the model is already in memory).
    # Slides with almost no ink are skipped — asking a small VLM about
    # three stray lines is where the hallucinations came from.
    slide_summaries = []
    total = max(len(slides), 1)
    for i, b64 in enumerate(slides):
        note(20 + int(55 * i / total), f"Reading slide {i + 1} of {total}…")
        strokes = stroke_counts[i] if i < len(stroke_counts) else None
        if strokes is not None and strokes < MIN_STROKES_FOR_VLM:
            slide_summaries.append("")
            continue
        try:
            image = Image.open(io.BytesIO(base64.b64decode(b64))).convert("RGB")
            text = run_vlm(SLIDE_PROMPT, image, max_new_tokens=180)
            if "unclear sketch" in text.lower():
                text = ""
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Slide {i} failed: {e}")
            text = ""
        slide_summaries.append(text)

    # Align transcript to slides + compose the notes JSON.
    note(80, "Writing the notes…")
    per_slide, unassigned = align_segments(segments, slide_marks, len(slides))
    notes = compose_notes(title, slide_summaries, per_slide, unassigned, language)

    # Optional Gemini polish (Content_Generation's schema), time-boxed.
    if GEMINI_API_KEY:
        note(88, "Polishing with Gemini…")
        notes = gemini_enhance(notes, GEMINI_API_KEY)

    # Free Wikipedia illustrations for the key concepts.
    note(94, "Adding illustrations…")
    notes = wiki_enrich(notes)

    supabase_update_note(
        note_id,
        {"status": "ready", "progress": 100, "stage": "Ready", "notes": notes},
    )
    logger.success(f"Notes ready for {note_id}")


def _process_class_notes(req: EndClassRequest):
    note = lambda p, s: supabase_update_note(req.note_id, {"progress": p, "stage": s})  # noqa: E731
    try:
        # Get the transcript: live captions (already transcribed during
        # class) beat re-transcribing; else fall back to the audio file.
        note(5, "Collecting the lecture transcript…")
        segments = []
        if req.session_id:
            try:
                segments = _fetch_session_captions(req.session_id)
                logger.info(f"Using {len(segments)} live captions as transcript")
            except Exception as e:  # noqa: BLE001
                logger.warning(f"Could not fetch live captions: {e}")
        if not segments:
            note(8, "Transcribing the lecture…")
            try:
                segments = _transcribe(req)
            except Exception as e:  # noqa: BLE001 — notes still work without audio
                logger.warning(f"Transcription failed, continuing with slides only: {e}")

        _generate_notes(
            req.note_id, req.title, req.language, req.slides,
            req.stroke_counts, req.slide_marks, segments,
        )
    except Exception as e:  # noqa: BLE001
        logger.exception("Class notes pipeline failed")
        supabase_update_note(
            req.note_id, {"status": "failed", "stage": "Failed", "error": str(e)[:500]}
        )


# ---------------------------------------------------------------------------
# Live transcription: the board posts ~15s audio chunks during the lecture;
# each is whisper-transcribed and written to live_captions so students see
# captions almost live (and end_class reuses them as the transcript).
# ---------------------------------------------------------------------------

class LiveChunkRequest(BaseModel):
    session_id: str
    classroom_id: str
    slide_index: int = 0
    chunk_index: int = 0
    offset_s: float = 0.0          # seconds from lecture start
    audio_b64: str
    audio_ext: str = "webm"


def _insert_captions(rows: list[dict]):
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/live_captions",
        data=json.dumps(rows).encode(),
        method="POST",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
        },
    )
    urllib.request.urlopen(req, timeout=10).read()


def _process_live_chunk(req: LiveChunkRequest):
    try:
        audio = base64.b64decode(req.audio_b64)
        with tempfile.NamedTemporaryFile(suffix=f".{req.audio_ext}", delete=False) as f:
            f.write(audio)
            path = f.name
        segments, _info = get_whisper().transcribe(path, vad_filter=True)
        rows = []
        for s in segments:
            text = s.text.strip()
            if not text:
                continue
            rows.append(
                {
                    "session_id": req.session_id,
                    "classroom_id": req.classroom_id,
                    "slide_index": req.slide_index,
                    "chunk_index": req.chunk_index,
                    "start_s": req.offset_s + float(s.start),
                    "end_s": req.offset_s + float(s.end),
                    "text": text,
                }
            )
        if rows:
            _insert_captions(rows)
            logger.info(f"Live chunk {req.chunk_index}: {len(rows)} captions")
    except Exception as e:  # noqa: BLE001 — a bad chunk must not kill the class
        logger.warning(f"Live chunk failed: {e}")


@app.post("/live_chunk")
def live_chunk(req: LiveChunkRequest):
    threading.Thread(target=_process_live_chunk, args=(req,), daemon=True).start()
    return {"ok": True}


def _fetch_session_captions(session_id: str):
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/live_captions"
        f"?session_id=eq.{session_id}&order=start_s.asc&select=start_s,end_s,text",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
        },
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        rows = json.load(resp)
    return [
        {"start": r["start_s"], "end": r["end_s"], "text": r["text"]} for r in rows
    ]


# ---------------------------------------------------------------------------
# Lecture video flow: the teacher uploads the class recording AFTER class.
# Its audio is the canonical source — transcribed ONCE into media_captions
# (player subtitles, translated per-student in the app) and then combined
# with the session slides to synthesise the class notes.
# ---------------------------------------------------------------------------

class LectureMediaRequest(BaseModel):
    media_id: str
    note_id: str | None = None
    language: str = "en"
    title: str = "Class notes"
    audio_b64: str                  # the raw (unencrypted) video/audio bytes
    audio_ext: str = "mp4"
    slides: list[str] = []
    stroke_counts: list[int] = []
    slide_marks: list[dict] = []


def _set_media_status(media_id: str, status: str):
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/class_media?id=eq.{media_id}",
        data=json.dumps({"transcript_status": status}).encode(),
        method="PATCH",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
        },
    )
    try:
        urllib.request.urlopen(req, timeout=10).read()
    except Exception as e:  # noqa: BLE001
        logger.warning(f"Could not update media status: {e}")


def _insert_media_captions(media_id: str, segments: list[dict]):
    rows = [
        {
            "media_id": media_id,
            "start_s": s["start"],
            "end_s": s["end"],
            "text": s["text"],
        }
        for s in segments
        if s.get("text", "").strip()
    ]
    if not rows:
        return
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/media_captions",
        data=json.dumps(rows).encode(),
        method="POST",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
        },
    )
    urllib.request.urlopen(req, timeout=15).read()


def _process_lecture_media(req: LectureMediaRequest):
    try:
        _set_media_status(req.media_id, "processing")
        if req.note_id:
            supabase_update_note(
                req.note_id,
                {"progress": 5, "stage": "Transcribing the lecture video…"},
            )
        # faster-whisper reads the audio track straight out of mp4/webm.
        audio = base64.b64decode(req.audio_b64)
        with tempfile.NamedTemporaryFile(suffix=f".{req.audio_ext}", delete=False) as f:
            f.write(audio)
            path = f.name
        raw, info = get_whisper().transcribe(path, vad_filter=True)
        segments = [
            {"start": float(s.start), "end": float(s.end), "text": s.text.strip()}
            for s in raw
        ]
        logger.info(
            f"Lecture video: {len(segments)} segments ({info.duration:.0f}s)")
        _insert_media_captions(req.media_id, segments)
        _set_media_status(req.media_id, "ready")

        # Synthesise the class notes from this transcript + the slides.
        if req.note_id:
            _generate_notes(
                req.note_id, req.title, req.language, req.slides,
                req.stroke_counts, req.slide_marks, segments,
            )
    except Exception as e:  # noqa: BLE001
        logger.exception("Lecture media pipeline failed")
        _set_media_status(req.media_id, "failed")
        if req.note_id:
            supabase_update_note(
                req.note_id,
                {"status": "failed", "stage": "Failed", "error": str(e)[:500]},
            )


@app.post("/lecture_media")
def lecture_media(req: LectureMediaRequest):
    logger.info(
        f"Lecture media: media={req.media_id} note={req.note_id} "
        f"slides={len(req.slides)} bytes~{len(req.audio_b64) * 3 // 4}")
    threading.Thread(target=_process_lecture_media, args=(req,), daemon=True).start()
    return {"ok": True}


@app.post("/end_class")
def end_class(req: EndClassRequest):
    logger.info(
        f"End class: note={req.note_id} slides={len(req.slides)} "
        f"marks={len(req.slide_marks)} audio={'yes' if (req.audio_b64 or req.audio_url) else 'no'}"
    )
    threading.Thread(target=_process_class_notes, args=(req,), daemon=True).start()
    return {"ok": True, "note_id": req.note_id}

@app.get("/health")
def health():
    return {"ok": True}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
