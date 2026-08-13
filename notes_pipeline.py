"""Pure logic for the class-notes pipeline — no ML imports, fully unit-testable.

Integrates the two teammate branches into one flow:
  * `transcription` branch  -> faster-whisper segments [{start, end, text}]
  * `Content_Generation`    -> structured notes JSON (same field names as the
    React app's schema so its UI could render our output unchanged)

The heavy lifting (whisper, SmolVLM, HTTP) lives in vlm_server.py; everything
here is deterministic string/list work so it runs in milliseconds.
"""

from __future__ import annotations

import json
import re
import urllib.request
from collections import Counter

STOPWORDS = set(
    """a an and are as at be by for from has have i in is it its of on or that
    the this to was we will with you your so if then than they them there here
    what which who whom these those our us not no do does did done can could
    should would may might must about into over under again very just also"""
    .split()
)


# ---------------------------------------------------------------------------
# Transcript <-> slide alignment
# ---------------------------------------------------------------------------

def align_segments(segments, slide_marks, slide_count):
    """Assign transcript segments to slides using slide-change timestamps.

    segments:    [{"start": float, "end": float, "text": str}]
    slide_marks: [{"index": int, "at": float}] — seconds (relative to audio
                 start) when each slide became visible, sorted by `at`.
    Returns (per_slide, unassigned):
      per_slide  dict slide_index -> [text, ...]
      unassigned [text, ...] (used when there are no usable marks)
    """
    per_slide: dict[int, list[str]] = {}
    unassigned: list[str] = []
    marks = sorted(
        (m for m in (slide_marks or []) if 0 <= int(m.get("index", -1)) < slide_count),
        key=lambda m: float(m.get("at", 0)),
    )
    if not marks:
        unassigned = [s["text"].strip() for s in segments if s.get("text", "").strip()]
        return per_slide, unassigned

    for seg in segments:
        text = (seg.get("text") or "").strip()
        if not text:
            continue
        start = float(seg.get("start", 0))
        current = marks[0]["index"]
        for mark in marks:
            if float(mark["at"]) <= start:
                current = int(mark["index"])
            else:
                break
        per_slide.setdefault(current, []).append(text)
    return per_slide, unassigned


# ---------------------------------------------------------------------------
# Tiny offline "NLP"
# ---------------------------------------------------------------------------

def split_sentences(text):
    parts = re.split(r"(?<=[.!?])\s+", (text or "").strip())
    return [p.strip() for p in parts if p.strip()]


def first_sentences(text, n):
    return " ".join(split_sentences(text)[:n])


def extract_key_terms(text, limit=6):
    """Most frequent capitalised / long words with the sentence that
    introduces them — a fast offline stand-in for LLM concept extraction."""
    sentences = split_sentences(text)
    words = re.findall(r"[A-Za-z][A-Za-z\-]{3,}", text or "")
    counts = Counter(w.lower() for w in words if w.lower() not in STOPWORDS)
    terms = []
    for word, _ in counts.most_common(limit * 3):
        context = next((s for s in sentences if word in s.lower()), "")
        if not context:
            continue
        terms.append({"term": word.capitalize(), "definition": first_sentences(context, 1)})
        if len(terms) >= limit:
            break
    return terms


# ---------------------------------------------------------------------------
# Notes composition (Content_Generation schema)
# ---------------------------------------------------------------------------

def compose_notes(title, slide_summaries, per_slide_transcript, unassigned, language="en"):
    """Build the structured notes JSON offline.

    slide_summaries:      [str] — SmolVLM's reading of each slide, by index.
    per_slide_transcript: dict index -> [str]
    unassigned:           [str] — transcript with no slide timestamps.
    """
    all_transcript = []
    for i in range(len(slide_summaries)):
        all_transcript.extend(per_slide_transcript.get(i, []))
    all_transcript.extend(unassigned)
    transcript_text = " ".join(all_transcript)

    source_text = transcript_text or " ".join(s for s in slide_summaries if s)
    overview = first_sentences(source_text, 3) or "Notes generated from the class board."
    simplified = first_sentences(source_text, 1) or overview

    per_slide = []
    for i, summary in enumerate(slide_summaries):
        spoken = " ".join(per_slide_transcript.get(i, []))
        per_slide.append(
            {
                "index": i,
                "title": f"Slide {i + 1}",
                "summary": (summary or "").strip() or "No readable content on this slide.",
                "transcript": spoken,
            }
        )

    return {
        "language": language,
        "title": title,
        "lecture_overview": overview,
        "simplified_summary": simplified,
        "key_concepts": extract_key_terms(source_text, limit=5),
        "technical_terms": extract_key_terms(" ".join(s for s in slide_summaries if s), limit=5),
        "per_slide": per_slide,
        "transcript": transcript_text,
    }


# ---------------------------------------------------------------------------
# Retrieval for the lecture chatbot: rank material chunks by relevance to
# the question so the small chat model sees the RIGHT context, not a wall
# of text it will ignore.
# ---------------------------------------------------------------------------

def _tokens(text):
    return {w for w in re.findall(r"[a-z0-9]+", (text or "").lower())
            if w not in STOPWORDS and len(w) > 2}


def chunk_material(text, max_len=300):
    """Sentence-grouped chunks of roughly max_len chars."""
    chunks, buf = [], ""
    for sentence in split_sentences(text):
        if len(buf) + len(sentence) + 1 > max_len and buf:
            chunks.append(buf)
            buf = sentence
        else:
            buf = f"{buf} {sentence}".strip()
    if buf:
        chunks.append(buf)
    return chunks


def retrieve_context(question, material_texts, top_k=6, chunk_len=260):
    """Most question-relevant chunks across all material, original order
    preserved. Falls back to the first chunks when nothing overlaps."""
    q = _tokens(question)
    chunks = []
    for text in material_texts:
        chunks.extend(chunk_material(text, max_len=chunk_len))
    if not chunks:
        return []
    scored = []
    for i, chunk in enumerate(chunks):
        overlap = len(q & _tokens(chunk))
        scored.append((overlap, i, chunk))
    scored.sort(key=lambda t: (-t[0], t[1]))
    picked = [t for t in scored[:top_k] if t[0] > 0]
    if not picked:  # nothing matched — give the opening of the lecture
        picked = scored[:top_k]
    picked.sort(key=lambda t: t[1])  # restore narrative order
    return [chunk for _, _, chunk in picked]


# ---------------------------------------------------------------------------
# Free imagery: attach a Wikipedia thumbnail + a one-line extract to the key
# concepts so the notes get real illustrations (no API key needed).
# ---------------------------------------------------------------------------

def wiki_enrich(notes, limit=4, timeout=6, fetch=None):
    """Best-effort illustration lookup. `fetch` is injectable for tests."""
    import urllib.parse

    def default_fetch(term):
        url = ("https://en.wikipedia.org/api/rest_v1/page/summary/"
               + urllib.parse.quote(term))
        req = urllib.request.Request(url, headers={"User-Agent": "kaksha-notes/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.load(resp)

    fetch = fetch or default_fetch
    enriched = []
    for concept in notes.get("key_concepts", [])[:limit]:
        term = concept.get("term") or concept.get("concept") or ""
        item = dict(concept)
        try:
            data = fetch(term)
            if data.get("type") == "standard":
                thumb = (data.get("thumbnail") or {}).get("source")
                if thumb:
                    item["image"] = thumb
                extract = data.get("extract")
                if extract:
                    item["wiki"] = first_sentences(extract, 2)
        except Exception:  # noqa: BLE001 — imagery is a bonus, never a blocker
            pass
        enriched.append(item)
    out = dict(notes)
    out["key_concepts"] = enriched + list(notes.get("key_concepts", []))[limit:]
    return out


# ---------------------------------------------------------------------------
# Optional Gemini polish — ported from Content_Generation/server/aiServer.mjs.
# Same schema; strictly time-boxed so a slow network never blocks the notes.
# ---------------------------------------------------------------------------

GEMINI_MODEL = "gemini-flash-latest"

_NOTES_SCHEMA = {
    "type": "object",
    "properties": {
        "lecture_overview": {"type": "string"},
        "simplified_summary": {"type": "string"},
        "key_concepts": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"concept": {"type": "string"}, "explanation": {"type": "string"}},
                "required": ["concept", "explanation"],
            },
        },
        "technical_terms": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"term": {"type": "string"}, "definition": {"type": "string"}},
                "required": ["term", "definition"],
            },
        },
        "slide_summaries": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["lecture_overview", "simplified_summary", "key_concepts", "technical_terms"],
}


def gemini_enhance(notes, api_key, timeout=30):
    """Rewrite the offline notes with Gemini (Content_Generation's approach).
    Returns improved notes, or the input unchanged on any failure."""
    if not api_key:
        return notes
    material = {
        "slides": [p["summary"] for p in notes["per_slide"]],
        "transcript": notes.get("transcript", "")[:12000],
    }
    body = json.dumps(
        {
            "contents": [
                {
                    "parts": [
                        {
                            "text": "You are preparing class notes for students from a "
                            "lecture. Board slides (in order) and the spoken transcript "
                            "follow as JSON. Write a clear lecture_overview, a one-line "
                            "simplified_summary, key_concepts, technical_terms, and one "
                            "improved summary per slide (same order, same count).\n\n"
                            + json.dumps(material)
                        }
                    ]
                }
            ],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": _NOTES_SCHEMA,
                "maxOutputTokens": 4096,
            },
        }
    ).encode()
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent?key={api_key}",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.load(resp)
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        improved = json.loads(text)
        notes = dict(notes)
        for key in ("lecture_overview", "simplified_summary", "key_concepts", "technical_terms"):
            if improved.get(key):
                notes[key] = improved[key]
        summaries = improved.get("slide_summaries") or []
        if len(summaries) == len(notes["per_slide"]):
            notes["per_slide"] = [
                {**p, "summary": s or p["summary"]}
                for p, s in zip(notes["per_slide"], summaries)
            ]
        return notes
    except Exception:  # noqa: BLE001 — enhancement is best-effort
        return notes
