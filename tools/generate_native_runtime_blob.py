#!/usr/bin/env python3
"""Assemble the small ring-3 transition shim into checked Hylang bytes."""

from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory


SYMBOLS = {
    "native_setup": "SetupOffset",
    "native_enter": "EnterOffset",
    "native_page_fault": "PageFaultOffset",
    "native_general_protection": "GeneralProtectionOffset",
    "native_invalid_opcode": "InvalidOpcodeOffset",
    "native_divide_error": "DivideErrorOffset",
    "native_timer": "TimerOffset",
    "native_int80": "Int80Offset",
    "native_boot_info": "BootInfoPointerOffset",
    "native_original_page_fault": "OriginalPageFaultOffset",
    "native_original_general_protection": "OriginalGeneralProtectionOffset",
    "native_original_invalid_opcode": "OriginalInvalidOpcodeOffset",
    "native_original_divide_error": "OriginalDivideErrorOffset",
    "native_original_timer": "OriginalTimerOffset",
    "native_original_int80": "OriginalInt80Offset",
}


def main() -> None:
    source, output = map(Path, sys.argv[1:3])
    with TemporaryDirectory(prefix="australis-native-runtime-") as directory:
        work = Path(directory)
        obj, elf, binary = (work / name for name in
                            ("runtime.o", "runtime.elf", "runtime.bin"))
        subprocess.run(["gcc", "-c", "-nostdlib", "-o", str(obj), str(source)],
                       check=True)
        subprocess.run(["ld", "-nostdlib", "-Ttext=0", "-e", "native_setup",
                        "-o", str(elf), str(obj)], check=True)
        relocations = subprocess.check_output(
            ["readelf", "-r", str(elf)], text=True)
        if "There are no relocations" not in relocations:
            raise RuntimeError("native runtime contains unresolved relocations")
        subprocess.run(["objcopy", "-O", "binary", "--only-section=.text",
                        str(elf), str(binary)], check=True)
        data = binary.read_bytes()
        if not data or len(data) > 4096:
            raise RuntimeError("native runtime must fit in one code page")
        nm = subprocess.check_output(["nm", "-n", str(elf)], text=True)
        offsets = {}
        for line in nm.splitlines():
            fields = line.split()
            if len(fields) == 3 and fields[2] in SYMBOLS:
                offsets[fields[2]] = int(fields[0], 16)
        if set(offsets) != set(SYMBOLS):
            raise RuntimeError("native runtime is missing a required entry point")
        for name in ("native_boot_info", "native_original_page_fault",
                     "native_original_general_protection",
                     "native_original_invalid_opcode",
                     "native_original_divide_error", "native_original_timer",
                     "native_original_int80"):
            if offsets[name] + 8 > len(data):
                raise RuntimeError(f"{name} is outside the runtime code page")

    lines = ["// Generated from native_runtime.S; regenerate with the Makefile.",
             "public class NativeRuntimeBlob {"]
    for name, method in SYMBOLS.items():
        lines.append(f"    public static int {method}() {{ return {offsets[name]}; }}")
    lines += ["    public static byte[] Bytes() {",
              f"        byte[] code = new byte[{len(data)}];"]
    for index, value in enumerate(data):
        lines.append(f"        code[{index}] = {value};")
    lines += ["        return code;", "    }", "}", ""]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines))


if __name__ == "__main__":
    main()
