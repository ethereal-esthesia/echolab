#!/usr/bin/env python3
import argparse
import pathlib
import subprocess
import tempfile
import struct

GLYPH_W = 7
GLYPH_H = 8
COLS = 16
ROWS = 16
COUNT = COLS * ROWS  # 256


def read_bmp_24(path: pathlib.Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if data[:2] != b"BM":
        raise ValueError("Expected BMP file")
    if len(data) < 54:
        raise ValueError("BMP header too short")

    pixel_off = struct.unpack_from("<I", data, 10)[0]
    dib_size = struct.unpack_from("<I", data, 14)[0]
    if dib_size < 40:
        raise ValueError("Unsupported BMP DIB header")

    width = struct.unpack_from("<i", data, 18)[0]
    height = struct.unpack_from("<i", data, 22)[0]
    planes = struct.unpack_from("<H", data, 26)[0]
    bpp = struct.unpack_from("<H", data, 28)[0]
    compression = struct.unpack_from("<I", data, 30)[0]

    if planes != 1 or bpp != 24 or compression != 0:
        raise ValueError("Only uncompressed 24bpp BMP is supported")
    if width <= 0 or height == 0:
        raise ValueError("Invalid BMP dimensions")

    w = width
    h = abs(height)
    row_stride = ((w * 3 + 3) // 4) * 4
    needed = pixel_off + row_stride * h
    if len(data) < needed:
        raise ValueError("BMP pixel data truncated")

    out = bytearray(w * h * 3)
    bottom_up = height > 0
    for y in range(h):
        src_y = (h - 1 - y) if bottom_up else y
        src_row = pixel_off + src_y * row_stride
        for x in range(w):
            b = data[src_row + x * 3 + 0]
            g = data[src_row + x * 3 + 1]
            r = data[src_row + x * 3 + 2]
            i = (y * w + x) * 3
            out[i : i + 3] = bytes((r, g, b))

    return w, h, bytes(out)


def pixel_on(pix: bytes, w: int, x: int, y: int) -> bool:
    i = (y * w + x) * 3
    return pix[i] >= 128 or pix[i + 1] >= 128 or pix[i + 2] >= 128


def validate_strict_bw(pix: bytes, w: int, h: int) -> None:
    invalid = 0
    first = None
    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 3
            rgb = (pix[i], pix[i + 1], pix[i + 2])
            if rgb != (0, 0, 0) and rgb != (255, 255, 255):
                invalid += 1
                if first is None:
                    first = (x, y, rgb)

    if invalid:
        x, y, rgb = first
        raise SystemExit(
            "strict-bw check failed: image contains non-binary pixels "
            f"(found {invalid}; first at x={x}, y={y}, rgb={rgb}). "
            "Use pure black/white pixels or pass --no-strict-bw."
        )


def main() -> int:
    ap = argparse.ArgumentParser(description="Import edited BMP/PNG/PPM glyph sheet into Apple IIe text ROM slice")
    ap.add_argument("--in", dest="in_image", required=True, help="Input edited image (.bmp, .png, or .ppm)")
    ap.add_argument("--rom-in", required=True, help="Source ROM file to patch")
    ap.add_argument("--rom-out", required=True, help="Destination ROM file")
    ap.add_argument("--bank", type=int, default=0, choices=[0, 1, 2], help="ROM bank (0=normal,1=flash,2=mouse)")
    ap.add_argument(
        "--no-strict-bw",
        action="store_true",
        help="Allow non-binary input pixels (default is strict black/white validation)",
    )
    args = ap.parse_args()

    in_image = pathlib.Path(args.in_image)
    rom_in = pathlib.Path(args.rom_in)
    rom_out = pathlib.Path(args.rom_out)

    with tempfile.TemporaryDirectory() as td:
        bmp_path = pathlib.Path(td) / "sheet.bmp"
        if in_image.suffix.lower() == ".bmp":
            bmp_path.write_bytes(in_image.read_bytes())
        else:
            subprocess.run(
                ["sips", "-s", "format", "bmp", str(in_image), "--out", str(bmp_path)],
                check=True,
            )

        w, h, pix = read_bmp_24(bmp_path)

    base_w = COLS * GLYPH_W
    base_h = ROWS * GLYPH_H
    if w % base_w != 0 or h % base_h != 0:
        raise SystemExit(f"Image size {w}x{h} is not an integer scale of {base_w}x{base_h}")
    sx = w // base_w
    sy = h // base_h
    if sx != sy:
        raise SystemExit("Non-uniform scale is not supported")
    scale = sx

    if not args.no_strict_bw:
        validate_strict_bw(pix, w, h)

    rom = bytearray(rom_in.read_bytes())
    if len(rom) < 6144:
        raise SystemExit(f"ROM too small ({len(rom)} bytes), expected at least 6144")

    bank_off = args.bank * 2048

    for code in range(COUNT):
        glyph_off = bank_off + code * GLYPH_H
        gx = (code % COLS) * GLYPH_W
        gy = (code // COLS) * GLYPH_H

        for y in range(GLYPH_H):
            row = 0
            for x in range(GLYPH_W):
                cx = (gx + x) * scale + scale // 2
                cy = (gy + y) * scale + scale // 2
                if pixel_on(pix, w, cx, cy):
                    row |= 1 << x
            rom[glyph_off + y] = row

    rom_out.parent.mkdir(parents=True, exist_ok=True)
    rom_out.write_bytes(rom)
    print(rom_out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
