#!/usr/bin/env python3
"""Build the fixed HyFS v2 volume used by the Hylang reader test."""

import hashlib
from pathlib import Path
import sys
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from hyfs2 import Hyfs2Image  # noqa: E402


FIXTURE_SHA256 = "cfee952ab0d7603c63e6ff66e0210c72cb24931520567d8cc5cbd0269dbed1ca"


def main() -> None:
    path = Path(sys.argv[1])
    path.unlink(missing_ok=True)
    with patch("hyfs2.time.time", return_value=1735689600):
        image = Hyfs2Image.create(path, 1024 * 1024)
        image.mkdir("/System")
        image.mkdir("/System/Core")
        image.put("/System/Core/System.exec", b"AUEX")
        image.mkdir("/Users")
        image.put("/Users/note+1.txt", b"hello")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != FIXTURE_SHA256:
        raise AssertionError(f"HyFS v2 fixture changed: {digest}")


if __name__ == "__main__":
    main()
