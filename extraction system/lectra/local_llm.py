"""Client for a local LLM served by Ollama — no cloud API involved.

The default model is qwen3:8b, a small local reasoning model, and every call
requests thinking mode (Ollama's `think` flag separates the reasoning tokens
from the answer). Models that don't support thinking are detected on first
use and the flag is dropped automatically.

Transport is stdlib urllib, so there is no SDK dependency. Structured calls
pass a JSON schema through Ollama's `format` parameter, which constrains
generation to schema-valid JSON.
"""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from typing import Any

from .errors import LocalLLMError
from .progress import warn

DEFAULT_MODEL = "qwen3:8b"  # local Qwen reasoning model, thinking mode supported
DEFAULT_URL = "http://localhost:11434"
DEFAULT_NUM_CTX = 8192
DEFAULT_TIMEOUT = 600.0  # seconds; a 7B model on CPU can be slow per call
CONNECT_TIMEOUT = 3.0

_THINK_TAG_RE = re.compile(r"<think>.*?</think>", re.DOTALL)

_tags_cache: dict[str, list[str]] = {}
_think_support: dict[str, bool] = {}
_warned_no_think: set[str] = set()


def backend() -> str:
    """'gemini' when GEMINI_API_KEY is set (cloud), else 'ollama' (local)."""
    return "gemini" if os.environ.get("GEMINI_API_KEY") else "ollama"


def base_url() -> str:
    return os.environ.get("LECTRA_OLLAMA_URL", DEFAULT_URL).rstrip("/")


def model_name() -> str:
    if backend() == "gemini":
        from . import gemini_llm

        return gemini_llm.model_name()
    return os.environ.get("LECTRA_MODEL", DEFAULT_MODEL)


def vision_model_name() -> str:
    """Optional local vision model (e.g. qwen2.5vl:7b). Empty = disabled."""
    return os.environ.get("LECTRA_VISION_MODEL", "")


def num_ctx() -> int:
    try:
        return int(os.environ.get("LECTRA_NUM_CTX", DEFAULT_NUM_CTX))
    except ValueError:
        return DEFAULT_NUM_CTX


def strip_think_tags(text: str) -> str:
    """Remove <think>...</think> blocks a model may leak into its content."""
    return _THINK_TAG_RE.sub("", text or "").strip()


# ---------------------------------------------------------------------------
# HTTP plumbing
# ---------------------------------------------------------------------------


def _http_json(method: str, path: str, payload=None, timeout: float = DEFAULT_TIMEOUT) -> dict:
    url = f"{base_url()}{path}"
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}, method=method
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        try:
            detail = exc.read().decode("utf-8", "replace")
        except Exception:
            detail = ""
        raise LocalLLMError(
            f"Ollama request to {path} failed (HTTP {exc.code}): {detail[:300]}"
        ) from exc
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        raise LocalLLMError(
            f"Could not reach the Ollama server at {base_url()} ({exc}). "
            "Is `ollama serve` running?"
        ) from exc
    except json.JSONDecodeError as exc:
        raise LocalLLMError(f"Ollama returned invalid JSON from {path}: {exc}") from exc


# ---------------------------------------------------------------------------
# Server / model discovery
# ---------------------------------------------------------------------------


def installed_models(refresh: bool = False) -> list[str]:
    url = base_url()
    if not refresh and url in _tags_cache:
        return _tags_cache[url]
    data = _http_json("GET", "/api/tags", timeout=CONNECT_TIMEOUT)
    names = [entry.get("name", "") for entry in data.get("models", [])]
    _tags_cache[url] = names
    return names


def _model_matches(installed: str, wanted: str) -> bool:
    if installed == wanted:
        return True
    # "deepseek-r1" matches "deepseek-r1:7b" when no tag was requested
    if ":" not in wanted and installed.split(":", 1)[0] == wanted:
        return True
    return False


def model_installed(name: str) -> bool:
    try:
        return any(_model_matches(m, name) for m in installed_models())
    except LocalLLMError:
        return False


def readiness() -> tuple[bool, str]:
    """(ready, reason): the server answers AND the text model is installed."""
    if backend() == "gemini":
        from . import gemini_llm

        return gemini_llm.readiness()
    try:
        models = installed_models()
    except LocalLLMError:
        return False, (
            f"Ollama server not reachable at {base_url()} — "
            "install Ollama (https://ollama.com) and run `ollama serve`"
        )
    if not any(_model_matches(m, model_name()) for m in models):
        return False, (
            f"model '{model_name()}' is not installed — run: ollama pull {model_name()}"
        )
    return True, ""


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
    """One non-streaming chat call; returns the assistant content.

    Thinking mode is requested by default (reasoning lands in the response's
    separate `thinking` field and is discarded here). If the model rejects the
    `think` flag, we warn once and retry the same call without it. Any
    <think> tags leaked into the content are stripped defensively.

    When GEMINI_API_KEY is set, the call is routed to the Gemini API instead.
    """
    if backend() == "gemini":
        from . import gemini_llm

        return gemini_llm.chat(
            prompt,
            system=system,
            images=images,
            schema=schema,
            model=model,
            num_predict=num_predict,
            timeout=timeout,
        )
    model = model or model_name()
    if timeout is None:
        try:
            timeout = float(os.environ.get("LECTRA_LLM_TIMEOUT", DEFAULT_TIMEOUT))
        except ValueError:
            timeout = DEFAULT_TIMEOUT

    messages: list[dict[str, Any]] = []
    if system:
        messages.append({"role": "system", "content": system})
    user_message: dict[str, Any] = {"role": "user", "content": prompt}
    if images:
        user_message["images"] = images
    messages.append(user_message)

    think = _think_support.get(model, True)
    while True:
        payload: dict[str, Any] = {
            "model": model,
            "messages": messages,
            "stream": False,
            "options": {"num_ctx": num_ctx(), "num_predict": num_predict},
        }
        if think:
            payload["think"] = True
        if schema is not None:
            payload["format"] = schema
        try:
            data = _http_json("POST", "/api/chat", payload, timeout=timeout)
        except LocalLLMError as exc:
            if think and "think" in str(exc).lower():
                _think_support[model] = False
                think = False
                if model not in _warned_no_think:
                    warn(f"model '{model}' does not support thinking mode — continuing without it.")
                    _warned_no_think.add(model)
                continue
            raise
        _think_support.setdefault(model, think)
        content = (data.get("message") or {}).get("content", "")
        return strip_think_tags(content)
