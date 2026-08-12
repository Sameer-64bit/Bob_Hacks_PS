"""Progress reporting to stderr: which stage is running and how long it took."""

from __future__ import annotations

import sys
import time
from contextlib import contextmanager


def log(message: str) -> None:
    print(f"[lectra] {message}", file=sys.stderr, flush=True)


def warn(message: str) -> None:
    print(f"[lectra] WARNING: {message}", file=sys.stderr, flush=True)


@contextmanager
def stage(name: str):
    """Wrap a pipeline stage: announces start, then elapsed time on exit."""
    log(f"{name} ...")
    start = time.perf_counter()
    try:
        yield
    except Exception:
        log(f"{name} FAILED after {time.perf_counter() - start:.1f}s")
        raise
    log(f"{name} done in {time.perf_counter() - start:.1f}s")
