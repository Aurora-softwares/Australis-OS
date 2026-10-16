#!/usr/bin/env python3
"""Package the Australis root tree as a directory-capable HyFS v2 image."""

import argparse
import os
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
from hyfs2 import Hyfs2Image, Hyfs2Error  # noqa: E402

REQUIRED_SYSTEM_EXECUTABLES = (
    "/System/Core/System.exec",
    "/System/Core/CommandShell.exec",
    "/System/Core/Device.exec",
    "/System/Core/Storage.exec",
    "/System/Bin/cat.exec",
    "/System/Bin/ls.exec",
    "/System/Bin/version.exec",
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--size-mib", type=int, default=4)
    parser.add_argument("--system-apps", type=Path,
                        help="directory of executables to install under /System")
    args = parser.parse_args()
    try:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="hyfs2-build-",
                                         dir=args.output.parent) as workspace:
            staged = Path(workspace) / "root.img"
            image = Hyfs2Image.create(staged, args.size_mib * 1024 * 1024,
                                      args.root)
            for directory in ("/System", "/System/Core", "/System/Bin", "/Applications",
                              "/Users", "/Volumes", "/Temporary"):
                try:
                    image.stat(directory)
                except Hyfs2Error:
                    image.mkdir(directory, record_time=False)
            image.mkdir("/System/Config", record_time=False)
            manifest = (Path(__file__).resolve().parents[1] / "src" / "userland" /
                        "system" / "startup.manifest")
            contents = manifest.read_bytes()
            if not contents.startswith(b"AUSM1\nDevice|") or len(contents) > 256:
                raise Hyfs2Error("invalid source startup manifest")
            image.put("/System/Config/startup.manifest", contents,
                      record_time=False)
            capability_manifest = (Path(__file__).resolve().parents[1] / "src" /
                                   "userland" / "system" / "capabilities.manifest")
            capability_contents = capability_manifest.read_bytes()
            if (not capability_contents.startswith(b"AUSC1\n") or
                    len(capability_contents) > 4096):
                raise Hyfs2Error("invalid source capability manifest")
            image.put("/System/Config/capabilities.manifest", capability_contents,
                      record_time=False)
            if args.system_apps is not None:
                if not args.system_apps.is_dir() or args.system_apps.is_symlink():
                    raise Hyfs2Error("system applications source is not a real directory")
                for executable in sorted(args.system_apps.rglob("*.exec")):
                    if executable.is_symlink() or not executable.is_file():
                        raise Hyfs2Error(f"invalid system executable: {executable}")
                    relative = executable.relative_to(args.system_apps)
                    if any(part.startswith(".") for part in relative.parts):
                        raise Hyfs2Error(f"invalid system executable path: {executable}")
                    parent = relative.parent
                    current = "/System"
                    for part in parent.parts:
                        current += "/" + part
                        try:
                            image.stat(current)
                        except Hyfs2Error:
                            image.mkdir(current, record_time=False)
                    image.put("/System/" + relative.as_posix(),
                              executable.read_bytes(), record_time=False)
            for executable in sorted(args.root.glob("*.exec")):
                image.put("/System/Bin/" + executable.name, executable.read_bytes(),
                          record_time=False)
            if args.system_apps is not None:
                for path in REQUIRED_SYSTEM_EXECUTABLES:
                    try:
                        contents = image.read_file(path)
                    except Hyfs2Error as error:
                        raise Hyfs2Error(f"required system executable missing: {path}") from error
                    if len(contents) < 32 or contents[:4] != b"AUEX":
                        raise Hyfs2Error(f"invalid packaged system executable: {path}")
            os.replace(staged, args.output)
    except (Hyfs2Error, OSError) as error:
        parser.exit(1, f"make_hyfs2_image: {error}\n")


if __name__ == "__main__":
    main()
