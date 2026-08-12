"""Local LLM client: think-tag stripping, model matching, and clean failures
when the Ollama server is unreachable (no network calls succeed here — the
tests point at a closed port, so connection refusal is immediate)."""

import pytest

from lectra import local_llm
from lectra.errors import LocalLLMError

UNREACHABLE = "http://127.0.0.1:9"


def test_strip_think_tags_removes_reasoning():
    text = "<think>step by step reasoning...</think>The answer is 4."
    assert local_llm.strip_think_tags(text) == "The answer is 4."


def test_strip_think_tags_handles_multiline_and_multiple_blocks():
    text = "<think>a\nb\nc</think>First. <think>more</think>Second."
    assert local_llm.strip_think_tags(text) == "First. Second."


def test_strip_think_tags_leaves_plain_text_alone():
    assert local_llm.strip_think_tags("  no tags here  ") == "no tags here"
    assert local_llm.strip_think_tags("") == ""


def test_model_matching():
    assert local_llm._model_matches("deepseek-r1:7b", "deepseek-r1:7b")
    assert local_llm._model_matches("deepseek-r1:7b", "deepseek-r1")  # untagged request
    assert not local_llm._model_matches("deepseek-r1:7b", "deepseek-r1:8b")
    assert not local_llm._model_matches("llama3:8b", "deepseek-r1")


def test_default_is_the_qwen_thinking_model(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.delenv("LECTRA_MODEL", raising=False)
    assert local_llm.model_name() == "qwen3:8b"


def test_chat_raises_cleanly_when_server_unreachable(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.setenv("LECTRA_OLLAMA_URL", UNREACHABLE)
    with pytest.raises(LocalLLMError, match="Could not reach the Ollama server"):
        local_llm.chat("hello")


def test_readiness_reports_unreachable_server(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.setenv("LECTRA_OLLAMA_URL", UNREACHABLE)
    ready, reason = local_llm.readiness()
    assert ready is False
    assert "not reachable" in reason


def test_model_installed_false_when_server_unreachable(monkeypatch):
    monkeypatch.setenv("LECTRA_OLLAMA_URL", UNREACHABLE)
    assert local_llm.model_installed("deepseek-r1:7b") is False


def test_backend_selection(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    assert local_llm.backend() == "ollama"
    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    assert local_llm.backend() == "gemini"
    assert local_llm.model_name().startswith("gemini")


def test_gemini_schema_conversion_inlines_refs():
    from pydantic import BaseModel

    from lectra import gemini_llm

    class Item(BaseModel):
        title: str
        start_seconds: float

    class ItemList(BaseModel):
        chapters: list[Item]

    converted = gemini_llm.to_gemini_schema(ItemList.model_json_schema())
    assert "$defs" not in json_dumps(converted)
    assert converted["type"] == "object"
    items = converted["properties"]["chapters"]["items"]
    assert items["type"] == "object"
    assert set(items["properties"]) == {"title", "start_seconds"}
    assert items["required"] == ["title", "start_seconds"]


def json_dumps(obj):
    import json

    return json.dumps(obj)
