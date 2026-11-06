"""跨进程 flock。fd 默认不被子进程继承，msb 起的长驻进程不会把锁一直握住。"""

from __future__ import annotations

import fcntl
import os
import time
from contextlib import contextmanager
from typing import Iterator


class LockTimeout(Exception):
    pass


@contextmanager
def flock(path: str, timeout_s: float) -> Iterator[None]:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_APPEND, 0o644)
    try:
        deadline = time.monotonic() + timeout_s
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise LockTimeout(path) from None
                time.sleep(0.1)
        yield
    finally:
        os.close(fd)
