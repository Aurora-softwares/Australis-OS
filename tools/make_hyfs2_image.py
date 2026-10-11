#!/usr/bin/env python3
"""Package the Australis root tree as a directory-capable HyFS v2 image."""

import argparse
import os
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
from hyfs2 import Hyfs2Image, Hyfs2Error  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--size-mib", type=int, default=4)
    args = parser.parse_args()
    try:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="hyfs2-build-",
                                         dir=args.output.parent) as workspace:
            staged = Path(workspace) / "root.img"
            image = Hyfs2Image.create(staged, args.size_mib * 1024 * 1024,
                                      args.root)
            for directory in ("/System", "/System/Core", "/Bin", "/Applications",
                              "/Users", "/Volumes", "/Temporary"):
                try:
                    image.stat(directory)
                except Hyfs2Error:
                    image.mkdir(directory, record_time=False)
            for executable in sorted(args.root.glob("*.exec")):
                image.put("/Bin/" + executable.name, executable.read_bytes(),
                          record_time=False)
            os.replace(staged, args.output)
    except (Hyfs2Error, OSError) as error:
        parser.exit(1, f"make_hyfs2_image: {error}\n")


if __name__ == "__main__":
    main()
