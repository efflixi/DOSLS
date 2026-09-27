#!/usr/bin/env python3
"""Wrap the NASM flat 16-bit load module in a DOS MZ executable header."""

from pathlib import Path
import struct
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: build_mz.py input.bin output.exe", file=sys.stderr)
        return 2

    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    image = source.read_bytes()
    if not image or len(image) >= 0x10000:
        print("Load module must be between 1 and 65535 bytes.", file=sys.stderr)
        return 1

    header_size = 32
    file_size = header_size + len(image)
    pages, last_page = divmod(file_size, 512)
    if last_page:
        pages += 1

    # IMAGE is deliberately a single segment with its initial stack at EOF.
    words = (
        0x5A4D,                  # e_magic: MZ
        last_page,               # e_cblp
        pages,                   # e_cp
        0,                       # e_crlc: no relocations
        header_size // 16,       # e_cparhdr
        0,                       # e_minalloc
        0xFFFF,                  # e_maxalloc
        0,                       # e_ss
        len(image),              # e_sp
        0,                       # e_csum
        0,                       # e_ip
        0,                       # e_cs
        0x1C,                    # e_lfarlc
        0,                       # e_ovno
    )
    header = struct.pack("<14H", *words) + bytes(header_size - 28)
    destination.write_bytes(header + image)
    print(f"Wrote {destination} ({file_size} bytes; load module {len(image)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
