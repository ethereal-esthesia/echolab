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


def render_bitmap(rom: bytes, bank: int, scale: int) -> tuple[bytes, int, int]:
    bank_off = bank * 2048
    base_w = COLS * GLYPH_W
    base_h = ROWS * GLYPH_H
    w = base_w * scale
    h = base_h * scale

    pix = bytearray(w * h * 3)

    for code in range(COUNT):
        glyph_off = bank_off + code * GLYPH_H
        gx = (code % COLS) * GLYPH_W
        gy = (code // COLS) * GLYPH_H

        for y in range(GLYPH_H):
            row = rom[glyph_off + y] & 0x7F
            for x in range(GLYPH_W):
                on = ((row >> x) & 0x01) != 0
                c = 255 if on else 0
                for sy in range(scale):
                    for sx in range(scale):
                        px = (gx + x) * scale + sx
                        py = (gy + y) * scale + sy
                        i = (py * w + px) * 3
                        pix[i:i+3] = bytes((c, c, c))

    return bytes(pix), w, h


def write_ppm(path: pathlib.Path, pix: bytes, w: int, h: int) -> None:
    with path.open("wb") as f:
        f.write(f"P6\n{w} {h}\n255\n".encode("ascii"))
        f.write(pix)


def write_bmp_24(path: pathlib.Path, pix: bytes, w: int, h: int) -> None:
    row_stride = ((w * 3 + 3) // 4) * 4
    img_size = row_stride * h
    file_size = 14 + 40 + img_size

    with path.open("wb") as f:
        f.write(b"BM")
        f.write(struct.pack("<IHHI", file_size, 0, 0, 54))
        f.write(struct.pack("<IIIHHIIIIII", 40, w, h, 1, 24, 0, img_size, 2835, 2835, 0, 0))

        pad = b"\x00" * (row_stride - w * 3)
        for y in range(h - 1, -1, -1):
            row = bytearray()
            for x in range(w):
                i = (y * w + x) * 3
                r = pix[i]
                g = pix[i + 1]
                b = pix[i + 2]
                row.extend((b, g, r))
            f.write(row)
            f.write(pad)


def main() -> int:
    ap = argparse.ArgumentParser(description="Export Apple IIe text glyph ROM slice to editable BMP/PNG")
    ap.add_argument("--rom", required=True, help="Input ROM binary (e.g. retro_7x8_mono.bin)")
    ap.add_argument("--out", required=True, help="Output image path (.bmp, .png, or .ppm)")
    ap.add_argument("--bank", type=int, default=0, choices=[0, 1, 2], help="ROM bank (0=normal,1=flash,2=mouse)")
    ap.add_argument("--scale", type=int, default=1, help="Pixel scale factor for editing (1 = 1:1)")
    args = ap.parse_args()

    rom_path = pathlib.Path(args.rom)
    out_path = pathlib.Path(args.out)
    rom = rom_path.read_bytes()

    if len(rom) < 6144:
        raise SystemExit(f"ROM too small ({len(rom)} bytes), expected at least 6144")
    if args.scale < 1:
        raise SystemExit("scale must be >= 1")

    pix, w, h = render_bitmap(rom, args.bank, args.scale)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.suffix.lower() == ".bmp":
        write_bmp_24(out_path, pix, w, h)
        print(out_path)
        return 0

    if out_path.suffix.lower() == ".ppm":
        write_ppm(out_path, pix, w, h)
        print(out_path)
        return 0

    if out_path.suffix.lower() != ".png":
        raise SystemExit("output extension must be .bmp, .png, or .ppm")

    with tempfile.TemporaryDirectory() as td:
        ppm = pathlib.Path(td) / "tmp.ppm"
        write_ppm(ppm, pix, w, h)
        subprocess.run(["sips", "-s", "format", "png", str(ppm), "--out", str(out_path)], check=True)

    print(out_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
