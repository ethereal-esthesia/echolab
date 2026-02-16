#!/usr/bin/env python3
import argparse
import pathlib
import re


def extract_text_display_bytes(java_source: str) -> bytearray:
    m = re.search(
        r"private\s+static\s+final\s+byte\[\]\s+TEXT_DISPLAY\s*=\s*\{(.*?)\};",
        java_source,
        flags=re.S,
    )
    if not m:
        raise ValueError("TEXT_DISPLAY byte array not found")

    body = m.group(1)
    hex_values = re.findall(r"0x([0-9a-fA-F]{1,2})", body)
    if not hex_values:
        raise ValueError("No hex bytes found in TEXT_DISPLAY")

    return bytearray(int(v, 16) for v in hex_values)


def to_ink_grid(rows, inverted):
    grid = [[0] * 7 for _ in range(8)]
    for y in range(8):
        b = rows[y] & 0x7F
        for x in range(7):
            bit = (b >> (6 - x)) & 1
            ink = (1 - bit) if inverted else bit
            grid[y][x] = ink
    return grid


def from_ink_grid(grid, inverted):
    rows = [0] * 8
    for y in range(8):
        b = 0
        for x in range(7):
            ink = grid[y][x]
            bit = (1 - ink) if inverted else ink
            b |= (bit & 1) << (6 - x)
        rows[y] = b
    return rows


def round_convex_corners(grid):
    out = [row[:] for row in grid]

    for y in range(8):
        for x in range(7):
            if grid[y][x] == 0:
                continue

            up = grid[y - 1][x] if y > 0 else 0
            down = grid[y + 1][x] if y < 7 else 0
            left = grid[y][x - 1] if x > 0 else 0
            right = grid[y][x + 1] if x < 6 else 0

            # Trim hard convex corners to a rounded shape.
            convex = (
                (right and down and not left and not up)
                or (left and down and not right and not up)
                or (right and up and not left and not down)
                or (left and up and not right and not down)
            )
            if convex:
                out[y][x] = 0

    return out


def round_glyph(rows8):
    rows = list(rows8)

    # Determine polarity per glyph: inverse glyphs are mostly 1 bits.
    bit_count = sum(((r & 0x7F).bit_count()) for r in rows)
    inverted = bit_count > (8 * 7 // 2)

    ink = to_ink_grid(rows, inverted)
    rounded = round_convex_corners(ink)
    out_rows = from_ink_grid(rounded, inverted)

    # Preserve high bit if any row uses it.
    for i, r in enumerate(rows):
        if r & 0x80:
            out_rows[i] |= 0x80

    return out_rows


def transform_all_glyphs(data: bytearray) -> bytearray:
    if len(data) % 8 != 0:
        raise ValueError(f"Expected glyph rows in groups of 8 bytes, got {len(data)} bytes")

    out = bytearray(data)
    for base in range(0, len(data), 8):
        glyph = data[base : base + 8]
        rounded = round_glyph(glyph)
        out[base : base + 8] = bytes(rounded)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract DisplayIIe TEXT_DISPLAY data and generate rounded-edge variant"
    )
    parser.add_argument("--input-java", required=True, help="Path to DisplayIIe.java")
    parser.add_argument("--out-original", required=True, help="Output path for extracted original bytes")
    parser.add_argument("--out-rounded", required=True, help="Output path for rounded bytes")
    args = parser.parse_args()

    in_path = pathlib.Path(args.input_java)
    out_original = pathlib.Path(args.out_original)
    out_rounded = pathlib.Path(args.out_rounded)

    src = in_path.read_text(encoding="utf-8")
    data = extract_text_display_bytes(src)
    rounded = transform_all_glyphs(data)

    out_original.parent.mkdir(parents=True, exist_ok=True)
    out_rounded.parent.mkdir(parents=True, exist_ok=True)
    out_original.write_bytes(data)
    out_rounded.write_bytes(rounded)

    print(f"extracted bytes: {len(data)}")
    print(f"original: {out_original}")
    print(f"rounded:  {out_rounded}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
