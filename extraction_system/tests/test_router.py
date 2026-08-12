import pytest

from lectra.errors import UnsupportedInputError
from lectra.router import route


@pytest.mark.parametrize(
    "name",
    ["lecture.mp4", "talk.mkv", "seminar.mov", "demo.webm", "old.avi"],
)
def test_video_extensions(name):
    assert route(name) == "video"


@pytest.mark.parametrize("name", ["LECTURE.MP4", "Talk.MkV", "notes.PDF"])
def test_extensions_are_case_insensitive(name):
    assert route(name) in {"video", "pdf"}


def test_pdf_extension():
    assert route("paper.pdf") == "pdf"


def test_paths_with_directories():
    assert route("/some/dir/deep learning.mp4") == "video"
    assert route("/some/dir/notes.pdf") == "pdf"


@pytest.mark.parametrize("name", ["notes.txt", "audio.mp3", "deck.pptx", "archive.tar.gz"])
def test_unsupported_extensions_error(name):
    with pytest.raises(UnsupportedInputError, match="Unsupported input type"):
        route(name)


def test_no_extension_errors_cleanly():
    with pytest.raises(UnsupportedInputError, match=r"\(no extension\)"):
        route("README")
