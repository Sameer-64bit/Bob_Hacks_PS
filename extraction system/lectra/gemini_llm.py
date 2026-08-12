"""The Gemini API client — lectra's LLM backend.

Gemini Flash is multimodal, so page/slide images go straight to the model.
Structured calls use Gemini's responseSchema (converted from the pydantic
JSON schema) so replies are constrained to valid JSON.

The key is read from the GEMINI_API_KEY environment variable only — it is
never written to disk. Transport is stdlib urllib; 429/5xx responses are
retried with backoff (free-tier keys are rate-limited per minute).
"""

from __future__ import annotations

import json
import os
import ssl
import time
import urllib.error
import urllib.request
from typing import Any

from .errors import LLMError
from .progress import warn

API_BASE = "https://generativelanguage.googleapis.com/v1beta"
DEFAULT_GEMINI_MODEL = "gemini-flash-latest"  # rolling alias for the current Flash
DEFAULT_TIMEOUT = 180.0
RETRY_DELAYS = [5.0, 15.0, 30.0]  # for 429 (rate limit) and transient 5xx
DEFAULT_MIN_INTERVAL = 3.2  # seconds between calls — stays under free-tier ~20 RPM

_last_call_at = 0.0


def api_key() -> str:
    return os.environ.get("GEMINI_API_KEY", "")


def model_name() -> str:
    return os.environ.get("LECTRA_GEMINI_MODEL", DEFAULT_GEMINI_MODEL)


class _RetryableHTTP(Exception):
    def __init__(self, status: int, detail: str):
        super().__init__(f"HTTP {status}: {detail}")
        self.status = status


_ssl_ctx: ssl.SSLContext | None = None


def _ssl_context() -> ssl.SSLContext:
    """Use certifi's CA bundle when available (macOS Pythons often ship
    without a usable system trust store)."""
    global _ssl_ctx
    if _ssl_ctx is None:
        try:
            import certifi

            _ssl_ctx = ssl.create_default_context(cafile=certifi.where())
        except ImportError:
            _ssl_ctx = ssl.create_default_context()
    return _ssl_ctx


def _request(path: str, payload: dict | None, timeout: float) -> dict:
    url = f"{API_BASE}{path}"
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json", "x-goog-api-key": api_key()},
        method="POST" if payload is not None else "GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout, context=_ssl_context()) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        try:
            detail = exc.read().decode("utf-8", "replace")[:400]
        except Exception:
            detail = ""
        if exc.code in (429, 500, 503):
            raise _RetryableHTTP(exc.code, detail) from exc
        raise LLMError(f"Gemini API request failed (HTTP {exc.code}): {detail}") from exc
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        raise LLMError(f"Could not reach the Gemini API ({exc}).") from exc
    except json.JSONDecodeError as exc:
        raise LLMError(f"Gemini API returned invalid JSON: {exc}") from exc


def readiness() -> tuple[bool, str]:
    """(ready, reason): the key works and the model exists."""
    if not api_key():
        return False, "GEMINI_API_KEY is not set"
    try:
        _request(f"/models/{model_name()}", None, timeout=15.0)
    except _RetryableHTTP:
        return True, ""  # rate-limited but alive — the chat retry loop handles it
    except LLMError as exc:
        return False, f"Gemini API check failed for model '{model_name()}': {exc}"
    return True, ""


# ---------------------------------------------------------------------------
# JSON-schema conversion (pydantic model_json_schema -> Gemini responseSchema)
# ---------------------------------------------------------------------------

_ALLOWED_KEYS = {"type", "format", "description", "enum"}


def _convert(node: Any, defs: dict) -> Any:
    if not isinstance(node, dict):
        return node
    if "$ref" in node:
        name = node["$ref"].rsplit("/", 1)[-1]
        return _convert(defs.get(name, {}), defs)
    if "anyOf" in node:  # Optional[...] — take the non-null variant, mark nullable
        variants = [v for v in node["anyOf"] if v.get("type") != "null"]
        if variants:
            merged = _convert(variants[0], defs)
            if isinstance(merged, dict):
                merged["nullable"] = True
                if "description" in node:
                    merged["description"] = node["description"]
            return merged
    out = {k: v for k, v in node.items() if k in _ALLOWED_KEYS}
    if "properties" in node:
        out["type"] = "object"
        out["properties"] = {k: _convert(v, defs) for k, v in node["properties"].items()}
        if "required" in node:
            out["required"] = node["required"]
    if "items" in node:
        out["type"] = "array"
        out["items"] = _convert(node["items"], defs)
    return out


def to_gemini_schema(model_schema: dict) -> dict:
    """Inline $defs/$ref and drop keys Gemini's responseSchema rejects."""
    return _convert(model_schema, model_schema.get("$defs", {}))


# ---------------------------------------------------------------------------
# Chat
# ---------------------------------------------------------------------------


def chat(
    prompt: str,
    *,
    system: str | None = None,
    images: list[str] | None = None,
    schema: dict[str, Any] | None = None,
    model: str | None = None,
    num_predict: int = 4096,
    timeout: float | None = None,
) -> str:
    model = model or model_name()
    if timeout is None:
        try:
            timeout = float(os.environ.get("LECTRA_LLM_TIMEOUT", DEFAULT_TIMEOUT))
        except ValueError:
            timeout = DEFAULT_TIMEOUT

    parts: list[dict[str, Any]] = []
    for image_b64 in images or []:
        parts.append({"inlineData": {"mimeType": "image/png", "data": image_b64}})
    parts.append({"text": prompt})

    payload: dict[str, Any] = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"maxOutputTokens": num_predict},
    }
    if system:
        payload["systemInstruction"] = {"parts": [{"text": system}]}
    if schema is not None:
        payload["generationConfig"]["responseMimeType"] = "application/json"
        payload["generationConfig"]["responseSchema"] = to_gemini_schema(schema)

    try:
        min_interval = float(os.environ.get("LECTRA_GEMINI_MIN_INTERVAL", DEFAULT_MIN_INTERVAL))
    except ValueError:
        min_interval = DEFAULT_MIN_INTERVAL

    global _last_call_at
    last_error: Exception | None = None
    for attempt in range(len(RETRY_DELAYS) + 1):
        wait = _last_call_at + min_interval - time.monotonic()
        if wait > 0:
            time.sleep(wait)
        _last_call_at = time.monotonic()
        try:
            data = _request(f"/models/{model}:generateContent", payload, timeout)
            break
        except _RetryableHTTP as exc:
            last_error = exc
            if attempt < len(RETRY_DELAYS):
                warn(f"Gemini API {exc} — retrying in {RETRY_DELAYS[attempt]:.0f}s")
                time.sleep(RETRY_DELAYS[attempt])
                continue
            raise LLMError(f"Gemini API kept failing after retries: {exc}") from exc
    else:  # pragma: no cover
        raise LLMError(f"Gemini API kept failing after retries: {last_error}")

    candidates = data.get("candidates") or []
    if not candidates:
        block = (data.get("promptFeedback") or {}).get("blockReason", "unknown")
        raise LLMError(f"Gemini returned no candidates (blockReason={block}).")
    candidate = candidates[0]
    text = "".join(
        part.get("text", "")
        for part in (candidate.get("content") or {}).get("parts", [])
        if not part.get("thought")  # skip thinking parts on reasoning models
    ).strip()
    if not text:
        finish = candidate.get("finishReason", "unknown")
        raise LLMError(f"Gemini returned empty content (finishReason={finish}).")
    return text
