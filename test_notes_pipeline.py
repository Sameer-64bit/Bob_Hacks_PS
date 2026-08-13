"""Unit tests for notes_pipeline (pure logic — no ML deps needed).

Run with:  python3 test_notes_pipeline.py   (or pytest)
"""

from notes_pipeline import align_segments, compose_notes, extract_key_terms


def test_alignment_with_marks():
    segs = [
        {"start": 1, "end": 4, "text": "Welcome to class."},
        {"start": 12, "end": 20, "text": "A linked list is a chain of nodes."},
        {"start": 40, "end": 50, "text": "Now recursion."},
    ]
    marks = [{"index": 0, "at": 0}, {"index": 1, "at": 10}, {"index": 2, "at": 35}]
    per_slide, unassigned = align_segments(segs, marks, 3)
    assert per_slide == {
        0: ["Welcome to class."],
        1: ["A linked list is a chain of nodes."],
        2: ["Now recursion."],
    }
    assert unassigned == []


def test_alignment_without_marks_returns_unassigned():
    segs = [{"start": 0, "end": 2, "text": "Hello."}]
    per_slide, unassigned = align_segments(segs, [], 2)
    assert per_slide == {}
    assert unassigned == ["Hello."]


def test_out_of_range_marks_are_ignored():
    segs = [{"start": 0, "end": 2, "text": "Hello."}]
    per_slide, unassigned = align_segments(segs, [{"index": 9, "at": 0}], 3)
    assert per_slide == {} and unassigned == ["Hello."]


def test_compose_notes_structure():
    notes = compose_notes(
        "DSA Class",
        ["Slide about linked lists", "Recursion tree drawing"],
        {0: ["A linked list is a chain of nodes."]},
        ["Recap tomorrow."],
        "en",
    )
    assert notes["title"] == "DSA Class"
    assert len(notes["per_slide"]) == 2
    assert notes["per_slide"][0]["transcript"].startswith("A linked list")
    assert notes["lecture_overview"]
    assert isinstance(notes["key_concepts"], list)
    assert isinstance(notes["technical_terms"], list)


def test_compose_notes_empty_slide():
    notes = compose_notes("X", [""], {}, [], "hi")
    assert notes["per_slide"][0]["summary"] == "No readable content on this slide."
    assert notes["language"] == "hi"


def test_key_terms_skip_stopwords():
    text = "Recursion means a function calling itself. Recursion needs a base case."
    terms = extract_key_terms(text)
    assert any(t["term"].lower() == "recursion" for t in terms)
    assert all(t["definition"] for t in terms)





def test_wiki_enrich_with_injected_fetch():
    from notes_pipeline import wiki_enrich

    notes = {"key_concepts": [{"term": "Recursion", "definition": "x"}]}

    def fake(term):
        return {
            "type": "standard",
            "thumbnail": {"source": "https://img/r.png"},
            "extract": "Recursion is self-reference.",
        }

    out = wiki_enrich(notes, fetch=fake)
    assert out["key_concepts"][0]["image"] == "https://img/r.png"
    assert out["key_concepts"][0]["wiki"]


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"{name}: ok")
    print("All notes_pipeline tests passed.")
