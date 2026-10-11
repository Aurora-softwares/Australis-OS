#!/usr/bin/env python3
"""Use the portable path-byte fallback in hosted HyFS tests.

The freestanding kernel reads string bytes directly. The native hosted test
compiler does not emit that intrinsic, so only this helper body is substituted.
"""

from pathlib import Path
import sys


source = Path(sys.argv[1]).read_text()
needle = "int value = System.Kernel.String.ByteAt(path, index);"
if source.count(needle) != 1:
    raise SystemExit("expected one Hyfs.PathByteAt intrinsic")
source = source.replace(needle,
                        'int value = PathByte(path[index]);\n'
                        '            if (path[index] == "/") { value = 47; }')
output = Path(sys.argv[2])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(source)
