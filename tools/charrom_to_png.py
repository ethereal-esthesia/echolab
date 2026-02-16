#!/usr/bin/env python3
import argparse
import pathlib
import subprocess
import tempfile

GLYPH_W = 7
GLYPH_H = 8
COLS = 16
ROWS = 8
COUNT = COLS * ROWS  # 128


def render_bitmap(rom: bytes, bank: int, start_code: int, scale: int) -> tuple[bytes, int, int]:
    bank_off = bank * 2048
    base_w = COLS * GLYPH_W
    base_h = ROWS * GLYPH_H
    w = base_w * scale
    h = base_h * scale

    pix = bytearray(w * h * 3)

    for code in range(COUNT):
        src_code = start_code + code
        glyph_off = bank_off + src_code * GLYPH_H
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


def main() -> int:
    ap = argparse.ArgumentParser(description="Export Apple IIe text glyph ROM slice to editable PNG")
    ap.add_argument("--rom", required=True, help="Input ROM binary (e.g. APPLE2E_TEXT_DISPLAY_ROUNDED.bin)")
    ap.add_argument("--out", required=True, help="Output image path (.png or .ppm)")
    ap.add_argument("--bank", type=int, default=0, choices=[0, 1, 2], help="ROM bank (0=normal,1=flash,2=mouse)")
    ap.add_argument("--start-code", type=int, default=128, help="Starting glyph code in bank (default 128 for active 0-127 set)")
    ap.add_argument("--scale", type=int, default=8, help="Pixel scale factor for editing")
    args = ap.parse_args()

    rom_path = pathlib.Path(args.rom)
    out_path = pathlib.Path(args.out)
    rom = rom_path.read_bytes()

    if len(rom) < 6144:
        raise SystemExit(f"ROM too small ({len(rom)} bytes), expected at least 6144")
    if args.start_code < 0 or args.start_code + COUNT > 256:
        raise SystemExit("start-code must satisfy start_code..start_code+127 within 0..255")
    if args.scale < 1:
        raise SystemExit("scale must be >= 1")

    pix, w, h = render_bitmap(rom, args.bank, args.start_code, args.scale)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.suffix.lower() == ".ppm":
        write_ppm(out_path, pix, w, h)
        print(out_path)
        return 0

    if out_path.suffix.lower() != ".png":
        raise SystemExit("output extension must be .png or .ppm")

    with tempfile.TemporaryDirectory() as td:
        ppm = pathlib.Path(td) / "tmp.ppm"
        write_ppm(ppm, pix, w, h)
        subprocess.run(["sips", "-s", "format", "png", str(ppm), "--out", str(out_path)], check=True)

    print(out_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
