"""Gemini client: model selection, readiness gating, and the pydantic-to-
responseSchema conversion. No network calls are made here."""

from typing import Optional

from pydantic import BaseModel

from lectra import gemini_llm


def test_default_model_and_env_override(monkeypatch):
    monkeypatch.delenv("LECTRA_GEMINI_MODEL", raising=False)
    assert gemini_llm.model_name() == "gemini-flash-latest"
    monkeypatch.setenv("LECTRA_GEMINI_MODEL", "gemini-3.5-flash")
    assert gemini_llm.model_name() == "gemini-3.5-flash"


def test_readiness_false_without_api_key(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    ready, reason = gemini_llm.readiness()
    assert ready is False
    assert "GEMINI_API_KEY" in reason


def test_schema_conversion_inlines_refs():
    class Item(BaseModel):
        title: str
        start_seconds: float

    class ItemList(BaseModel):
        chapters: list[Item]

    converted = gemini_llm.to_gemini_schema(ItemList.model_json_schema())
    assert "$defs" not in str(converted)
    assert "$ref" not in str(converted)
    assert converted["type"] == "object"
    items = converted["properties"]["chapters"]["items"]
    assert items["type"] == "object"
    assert set(items["properties"]) == {"title", "start_seconds"}
    assert items["required"] == ["title", "start_seconds"]


def test_schema_conversion_optional_becomes_nullable():
    class Model(BaseModel):
        name: str
        note: Optional[str] = None

    converted = gemini_llm.to_gemini_schema(Model.model_json_schema())
    assert converted["properties"]["note"].get("nullable") is True
    assert converted["properties"]["name"]["type"] == "string"
