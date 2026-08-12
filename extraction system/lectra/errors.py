"""Shared exception hierarchy. The CLI catches LectraError and exits cleanly."""


class LectraError(RuntimeError):
    """Base class for all errors lectra raises on purpose."""


class UnsupportedInputError(LectraError):
    """The input file extension maps to no pipeline."""


class PipelineError(LectraError):
    """A video/PDF pipeline stage failed (missing dependency, unreadable media, ...)."""


class OCRUnavailableError(LectraError):
    """PaddleOCR is not installed or could not be initialised."""


class LocalLLMError(LectraError):
    """The local LLM (Ollama) could not be reached or returned an error."""


class VisionError(LectraError):
    """A Claude vision call failed or was refused."""


class UnderstandingError(LectraError):
    """The understanding layer failed (API error, or unusable output after retry)."""
