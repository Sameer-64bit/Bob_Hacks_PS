"""Slide change detection + dedup, driven by synthetic hashes.

The real pipeline uses imagehash phash objects; the logic only needs `a - b`
to yield a distance, so a fake integer-backed hash exercises it exactly.
"""

from lectra.video import SlideCandidate, dedupe_slides, detect_slide_changes


class FakeHash:
    def __init__(self, value: int):
        self.value = value

    def __sub__(self, other: "FakeHash") -> int:
        return abs(self.value - other.value)

    def __repr__(self):
        return f"FakeHash({self.value})"


def H(value: int) -> FakeHash:
    return FakeHash(value)


def test_first_frame_is_always_kept():
    candidates = detect_slide_changes([(0.0, H(5))], threshold=10)
    assert [c.time for c in candidates] == [0.0]


def test_change_detected_when_distance_exceeds_threshold():
    samples = [(0.0, H(0)), (2.0, H(2)), (4.0, H(40)), (6.0, H(41))]
    candidates = detect_slide_changes(samples, threshold=10)
    assert [c.time for c in candidates] == [0.0, 4.0]


def test_distance_exactly_at_threshold_is_not_a_change():
    samples = [(0.0, H(0)), (2.0, H(10))]  # distance == threshold
    candidates = detect_slide_changes(samples, threshold=10)
    assert [c.time for c in candidates] == [0.0]


def test_comparison_is_against_last_kept_frame_not_previous_sample():
    # Each step drifts by 6 (below threshold sample-to-sample), but the third
    # sample is 12 away from the last KEPT frame, so it must trigger.
    samples = [(0.0, H(0)), (2.0, H(6)), (4.0, H(12))]
    candidates = detect_slide_changes(samples, threshold=10)
    assert [c.time for c in candidates] == [0.0, 4.0]


def test_dedupe_merges_revisit_into_existing_slide():
    # Slide A (t=0), slide B (t=4), then back to something A-like (t=8).
    candidates = [
        SlideCandidate(time=0.0, hash=H(0)),
        SlideCandidate(time=4.0, hash=H(100)),
        SlideCandidate(time=8.0, hash=H(1)),
    ]
    slides = dedupe_slides(candidates, threshold=10, total_duration=10.0)
    assert len(slides) == 2
    assert slides[0].appearances == [(0.0, 4.0), (8.0, 10.0)]
    assert slides[1].appearances == [(4.0, 8.0)]


def test_dedupe_matches_any_earlier_slide_not_just_previous():
    candidates = [
        SlideCandidate(time=0.0, hash=H(0)),
        SlideCandidate(time=4.0, hash=H(100)),
        SlideCandidate(time=8.0, hash=H(200)),
        SlideCandidate(time=12.0, hash=H(3)),  # revisits the FIRST slide
    ]
    slides = dedupe_slides(candidates, threshold=10, total_duration=16.0)
    assert len(slides) == 3
    assert slides[0].appearances == [(0.0, 4.0), (12.0, 16.0)]


def test_dedupe_keeps_distinct_slides_distinct():
    candidates = [
        SlideCandidate(time=0.0, hash=H(0)),
        SlideCandidate(time=4.0, hash=H(50)),
        SlideCandidate(time=8.0, hash=H(100)),
    ]
    slides = dedupe_slides(candidates, threshold=10, total_duration=12.0)
    assert len(slides) == 3
    assert [s.appearances for s in slides] == [[(0.0, 4.0)], [(4.0, 8.0)], [(8.0, 12.0)]]


def test_dedupe_empty_input():
    assert dedupe_slides([], threshold=10, total_duration=0.0) == []


def test_end_to_end_detection_then_dedup():
    samples = [
        (0.0, H(0)),    # slide A
        (2.0, H(1)),    # still A
        (4.0, H(100)),  # slide B
        (6.0, H(101)),  # still B
        (8.0, H(2)),    # A revisited
    ]
    candidates = detect_slide_changes(samples, threshold=10)
    slides = dedupe_slides(candidates, threshold=10, total_duration=10.0)
    assert len(slides) == 2
    assert slides[0].appearances == [(0.0, 4.0), (8.0, 10.0)]
    assert slides[1].appearances == [(4.0, 8.0)]
