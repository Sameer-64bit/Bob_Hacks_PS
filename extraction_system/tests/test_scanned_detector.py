from lectra.pdf_pipeline import is_scanned_page


def test_empty_text_with_images_is_scanned():
    assert is_scanned_page("", image_count=3) is True


def test_whitespace_only_text_counts_as_empty():
    assert is_scanned_page("   \n\t  ", image_count=1) is True


def test_short_text_without_images_is_not_scanned():
    # e.g. a nearly-blank digital page: no images means nothing to OCR
    assert is_scanned_page("short", image_count=0) is False


def test_text_rich_page_with_images_is_not_scanned():
    text = "This page has plenty of real extracted text content."
    assert is_scanned_page(text, image_count=4) is False


def test_boundary_nineteen_chars_is_scanned():
    assert is_scanned_page("x" * 19, image_count=1) is True


def test_boundary_twenty_chars_is_not_scanned():
    assert is_scanned_page("x" * 20, image_count=1) is False
