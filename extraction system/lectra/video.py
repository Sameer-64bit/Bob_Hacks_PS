"""Video pipeline: ffmpeg audio -> faster-whisper transcript -> phash slide
detection + dedup -> OCR / Claude vision slide content -> transcript alignment.

The slide change-detection and dedup logic is pure (hash objects only need a
`-` operator returning a distance) so it is unit-testable with synthetic
hashes. Heavy imports (cv2, imagehash, faster_whisper) happen at call time.
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Sequence

from . import vision
from .errors import OCRUnavailableError, PipelineError, VisionError
from .progress import log, stage, warn
from .schema import Section, SectionLocation, TranscriptSegment

DEFAULT_HASH_THRESHOLD = 10
DEFAULT_SAMPLE_INTERVAL = 2.0
WHISPER_MODEL_SIZE = "small"


# ---------------------------------------------------------------------------
# Pure slide logic (unit-tested with synthetic hashes)
# ---------------------------------------------------------------------------


@dataclass
class SlideCandidate:
    """A kept frame: the first frame of a run of visually-similar samples."""

    time: float
    hash: Any
    image: Any = None  # BGR ndarray in real runs; None in tests


@dataclass
class Slide:
    """A unique slide with every time range in which it is on screen."""

    hash: Any
    appearances: list[tuple[float, float]] = field(default_factory=list)
    image: Any = None
    asset_path: Path | None = None


class ChangeDetector:
    """Keeps a frame when its hash distance from the previously *kept* frame
    exceeds the threshold (distance == threshold is NOT a change)."""

    def __init__(self, threshold: int):
        self.threshold = threshold
        self._last_kept = None

    def offer(self, frame_hash) -> bool:
        if self._last_kept is None or (frame_hash - self._last_kept) > self.threshold:
            self._last_kept = frame_hash
            return True
        return False


def detect_slide_changes(
    samples: Sequence[tuple[float, Any]], threshold: int = DEFAULT_HASH_THRESHOLD
) -> list[SlideCandidate]:
    """Pure form of the streaming change detection: (timestamp, hash) pairs in
    time order -> the kept candidates."""
    detector = ChangeDetector(threshold)
    return [SlideCandidate(time=t, hash=h) for t, h in samples if detector.offer(h)]


def dedupe_slides(
    candidates: Sequence[SlideCandidate],
    threshold: int = DEFAULT_HASH_THRESHOLD,
    total_duration: float | None = None,
) -> list[Slide]:
    """Merge revisits: a candidate within `threshold` of ANY earlier slide is
    appended to that slide's appearances instead of becoming a new slide.

    Each candidate's appearance range runs from its own timestamp to the next
    candidate's timestamp (or total_duration for the last one).
    """
    slides: list[Slide] = []
    if not candidates:
        return slides
    if total_duration is None:
        total_duration = candidates[-1].time
    for index, candidate in enumerate(candidates):
        if index + 1 < len(candidates):
            end = candidates[index + 1].time
        else:
            end = max(total_duration, candidate.time)
        appearance = (candidate.time, end)
        for slide in slides:
            if (candidate.hash - slide.hash) <= threshold:
                slide.appearances.append(appearance)
                break
        else:
            slides.append(Slide(hash=candidate.hash, appearances=[appearance], image=candidate.image))
    return slides


def align_transcript(
    slides: Sequence[Slide], transcript: Sequence[TranscriptSegment]
) -> list[list[TranscriptSegment]]:
    """Assign each transcript segment to the slide whose appearance range
    contains the segment's midpoint. Trailing segments past every range are
    clamped onto the slide that is on screen last."""
    assigned: list[list[TranscriptSegment]] = [[] for _ in slides]
    if not slides:
        return assigned
    last_slide_index = max(
        range(len(slides)), key=lambda i: max(end for _, end in slides[i].appearances)
    )
    for segment in transcript:
        midpoint = (segment.start + segment.end) / 2.0
        for index, slide in enumerate(slides):
            if any(start <= midpoint < end for start, end in slide.appearances):
                assigned[index].append(segment)
                break
        else:
            assigned[last_slide_index].append(segment)
    return assigned


# ---------------------------------------------------------------------------
# Step 1: audio extraction (ffmpeg)
# ---------------------------------------------------------------------------


def _require_ffmpeg() -> None:
    if shutil.which("ffmpeg") is None:
        raise PipelineError(
            "ffmpeg is not installed or not on PATH; it is required to extract audio from video. "
            "Install it with 'brew install ffmpeg' (macOS) or 'sudo apt install ffmpeg' (Debian/Ubuntu)."
        )


def _has_audio_stream(video_path: Path) -> bool:
    ffprobe = shutil.which("ffprobe")
    if ffprobe is None:
        return True  # assume audio; ffmpeg will tell us otherwise
    proc = subprocess.run(
        [
            ffprobe,
            "-v", "error",
            "-select_streams", "a",
            "-show_entries", "stream=codec_type",
            "-of", "csv=p=0",
            str(video_path),
        ],
        capture_output=True,
        text=True,
    )
    return bool(proc.stdout.strip())


def extract_audio(video_path: Path, wav_path: Path) -> bool:
    """Extract 16 kHz mono WAV. Returns False when the video has no audio."""
    _require_ffmpeg()
    if not _has_audio_stream(video_path):
        warn("Video has no audio stream — the transcript will be empty.")
        return False
    proc = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-nostdin", "-y",
            "-i", str(video_path),
            "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le",
            str(wav_path),
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        tail = "\n".join((proc.stderr or "").strip().splitlines()[-8:])
        raise PipelineError(f"ffmpeg failed to extract audio (exit {proc.returncode}):\n{tail}")
    return True


# ---------------------------------------------------------------------------
# Step 2: transcription (faster-whisper)
# ---------------------------------------------------------------------------


def transcribe_audio(wav_path: Path) -> tuple[list[TranscriptSegment], str]:
    try:
        from faster_whisper import WhisperModel
    except ImportError as exc:
        raise PipelineError(
            "faster-whisper is not installed (pip install faster-whisper)."
        ) from exc

    model = WhisperModel(WHISPER_MODEL_SIZE, compute_type="int8")
    segments, info = model.transcribe(str(wav_path), vad_filter=True)
    transcript: list[TranscriptSegment] = []
    for segment in segments:  # generator: transcription happens here
        text = segment.text.strip()
        if not text:
            continue
        transcript.append(
            TranscriptSegment(
                start=round(float(segment.start), 2),
                end=round(float(segment.end), 2),
                text=text,
            )
        )
        if len(transcript) % 50 == 0:
            log(f"  transcribed up to {transcript[-1].end:.0f}s ({len(transcript)} segments)")
    return transcript, (info.language or "unknown")


# ---------------------------------------------------------------------------
# Step 3: slide extraction (OpenCV frame sampling + perceptual hash)
# ---------------------------------------------------------------------------


def extract_slide_candidates(
    video_path: Path, sample_interval: float, threshold: int
) -> tuple[list[SlideCandidate], float]:
    """Sample a frame every `sample_interval` seconds, phash it, and keep the
    frames where the hash distance from the last kept frame exceeds the
    threshold. Returns (candidates, video duration in seconds)."""
    try:
        import cv2
    except ImportError as exc:
        raise PipelineError("opencv-python is not installed (pip install opencv-python).") from exc
    try:
        import imagehash
        from PIL import Image
    except ImportError as exc:
        raise PipelineError(
            "imagehash and Pillow are required (pip install imagehash Pillow)."
        ) from exc

    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise PipelineError(f"OpenCV could not open the video: {video_path}")

    fps = capture.get(cv2.CAP_PROP_FPS)
    if not fps or fps <= 0 or fps != fps:  # 0/NaN guard
        fps = 30.0
    frame_count = capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0
    duration = frame_count / fps if frame_count > 0 else 0.0
    step = max(1, round(fps * sample_interval))

    detector = ChangeDetector(threshold)
    candidates: list[SlideCandidate] = []
    index = 0
    sampled = 0
    while True:
        if not capture.grab():
            break
        if index % step == 0:
            ok, frame = capture.retrieve()
            if ok and frame is not None:
                sampled += 1
                frame_hash = imagehash.phash(
                    Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
                )
                if detector.offer(frame_hash):
                    candidates.append(
                        SlideCandidate(
                            time=round(index / fps, 2), hash=frame_hash, image=frame.copy()
                        )
                    )
        index += 1
    capture.release()

    if not candidates:
        raise PipelineError("No frames could be decoded from the video.")
    if duration <= 0:
        duration = index / fps
    log(f"  sampled {sampled} frames -> {len(candidates)} scene changes, duration {duration:.1f}s")
    return candidates, round(duration, 2)


def save_slides(slides: Sequence[Slide], assets_dir: Path) -> None:
    """Write each unique slide as assets_dir/slide_001.png etc."""
    import cv2

    assets_dir.mkdir(parents=True, exist_ok=True)
    for number, slide in enumerate(slides, start=1):
        if slide.image is None:
            continue
        path = assets_dir / f"slide_{number:03d}.png"
        if not cv2.imwrite(str(path), slide.image):
            warn(f"Failed to write slide image {path}")
            continue
        slide.asset_path = path


# ---------------------------------------------------------------------------
# Step 4: slide content extraction
# ---------------------------------------------------------------------------


def build_sections(slides: Sequence[Slide], mode: str) -> list[Section]:
    sections: list[Section] = []
    ocr_warned = False
    for number, slide in enumerate(slides, start=1):
        raw_lines: list[str] = []
        if slide.asset_path is not None:
            try:
                raw_lines = vision.ocr_image(slide.asset_path)
            except OCRUnavailableError as exc:
                if not ocr_warned:
                    warn(f"{exc} raw_ocr_text will be empty.")
                    ocr_warned = True
        raw_text = "\n".join(raw_lines)

        visual_markdown = ""
        title = None
        if mode == "deep" and slide.asset_path is not None:
            try:
                visual_markdown = vision.describe_image_markdown(
                    slide.asset_path, kind="lecture slide"
                )
                title = vision.title_from_markdown(visual_markdown)
                log(f"  slide {number}/{len(slides)} transcribed by Gemini")
            except VisionError as exc:
                warn(f"slide {number}: {exc} Falling back to raw OCR text for this slide.")
        if not visual_markdown:
            visual_markdown = raw_text
        if not title:
            title = vision.title_from_lines(raw_lines) or f"Slide {number}"

        sections.append(
            Section(
                id=f"sec_{number:03d}",
                kind="slide",
                title=title,
                location=SectionLocation(
                    timestamp_ranges=[
                        (round(start, 2), round(end, 2)) for start, end in slide.appearances
                    ],
                    pages=None,
                ),
                visual_content_markdown=visual_markdown,
                raw_ocr_text=raw_text,
                spoken_content=[],
                section_summary="",
                asset_path=str(slide.asset_path) if slide.asset_path else None,
            )
        )
    return sections


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------


def process_video(
    video_path: Path,
    mode: str,
    assets_dir: Path,
    hash_threshold: int = DEFAULT_HASH_THRESHOLD,
    sample_interval: float = DEFAULT_SAMPLE_INTERVAL,
) -> tuple[list[Section], list[TranscriptSegment], float, str]:
    """Run the full video pipeline.

    Returns (sections, transcript, duration_seconds, language).
    """
    transcript: list[TranscriptSegment] = []
    language = "unknown"

    with tempfile.TemporaryDirectory(prefix="lectra_") as tmp:
        wav_path = Path(tmp) / "audio.wav"
        with stage("Audio extraction (ffmpeg -> 16kHz mono WAV)"):
            has_audio = extract_audio(video_path, wav_path)
        if has_audio:
            with stage(f"Transcription (faster-whisper '{WHISPER_MODEL_SIZE}', int8, VAD)"):
                transcript, language = transcribe_audio(wav_path)
                log(f"  {len(transcript)} segments, language={language}")

    with stage(
        f"Slide extraction (1 frame / {sample_interval:g}s, phash threshold {hash_threshold})"
    ):
        candidates, duration = extract_slide_candidates(video_path, sample_interval, hash_threshold)
        slides = dedupe_slides(candidates, hash_threshold, duration)
        save_slides(slides, assets_dir)
        log(f"  {len(slides)} unique slides -> {assets_dir}")

    content_backend = "Gemini vision + OCR" if mode == "deep" else "OCR"
    with stage(f"Slide content extraction ({content_backend})"):
        sections = build_sections(slides, mode)

    with stage("Transcript-slide alignment"):
        assigned = align_transcript(slides, transcript)
        for section, spoken in zip(sections, assigned):
            section.spoken_content = spoken

    return sections, transcript, duration, language
