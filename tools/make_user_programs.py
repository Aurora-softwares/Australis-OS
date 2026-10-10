#!/usr/bin/env python3
"""Build the deterministic AUEX v1 programs included in the HyFS image."""

import struct
import sys
import zlib
from pathlib import Path


DATA_BASE = 0x500000


def u32(value):
    return struct.pack("<I", value)


def write(address, length):
    return b"\x02" + u32(address) + u32(length)


def read_terminal(address, capacity):
    return b"\x03" + u32(address) + u32(capacity)


def write_count(address):
    return b"\x04" + u32(address)


def open_file(address, length):
    return b"\x05" + u32(address) + u32(length)


def read_file(address, capacity):
    return b"\x06" + u32(address) + u32(capacity)


def store_byte(address, value):
    return b"\x08" + u32(address) + bytes([value])


def image(code, data, capacity):
    header = bytearray(b"AUEX\x01\x20\x00\x00")
    header += struct.pack("<IIIIII", len(code), len(data), capacity, 0,
                          zlib.crc32(code), zlib.crc32(data))
    assert len(header) == 32
    return bytes(header) + code + data


def put(data, offset, value):
    data[offset:offset + len(value)] = value
    return DATA_BASE + offset, len(value)


def demo_program():
    data = bytearray(128)
    prompt = put(data, 0, b"user> ")
    input_label = put(data, 16, b"input: ")
    newline = put(data, 32, b"\r\n")
    path = put(data, 48, b"/hello.txt")
    file_label = put(data, 80, b"file: ")
    input_buffer = DATA_BASE + 256
    file_buffer = DATA_BASE + 512
    code = b"".join([
        write(*prompt),
        read_terminal(input_buffer, 64),
        write(*input_label),
        write_count(input_buffer),
        write(*newline),
        open_file(*path),
        read_file(file_buffer, 1024),
        write(*file_label),
        write_count(file_buffer),
        b"\x07",
        b"\x01\x00",
    ])
    return image(code, data, 2048)


def fault_program():
    data = bytearray(64)
    message = put(data, 0, b"requesting protected write\r\n")
	# Attempt to write outside of the user writable range, which should trigger a fault.
    code = write(*message) + store_byte(0x1000, 0x41) + b"\x01\x00"
    return image(code, data, 256)


def main():
	## Build the user programs and write them to the output directory.
    if len(sys.argv) != 2:
        raise SystemExit("usage: make_user_programs.py OUTPUT_DIRECTORY")
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    (output / "user-demo.exec").write_bytes(demo_program())
    (output / "user-fault.exec").write_bytes(fault_program())


if __name__ == "__main__":
    main()
