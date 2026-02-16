# Echo Lab

Echo Lab is a Rust workspace for emulator experiments.

## Current Scope

- Minimal lab model and machine registry
- One machine descriptor: Apple IIe
- Deterministic fast RNG module for emulator workloads
- Testable screen buffer with explicit frame publish counter
- Text-mode video scanout (RAM -> phosphor-green-on-black buffer with every-other-scanline output, using rounded Apple IIe glyph ROM data for codes 0-127)

## Run

```bash
cargo run
```

## Demo: Text Hello

```bash
cargo run --example hello_text
```

## Demo: SDL3 Text 40x24

```bash
cargo run --example sdl3_text40x24 --features sdl3
```

Requires SDL3 development libraries installed on your system.

Capture the last rendered frame before exit:

```bash
cargo run --example sdl3_text40x24 --features sdl3 -- --screenshot
```

Screenshots are always named `screenshot_<timestamp>.ppm`.
Default output directory comes from `echolab.toml`:

```bash
default_screenshot_dir = "screenshots"
```

Override output directory per run:

```bash
cargo run --example sdl3_text40x24 --features sdl3 -- --screenshot /tmp/echolab_shots
```

Configuration lives in:

```bash
./echolab.toml
```

You can override config path:

```bash
cargo run --example sdl3_text40x24 --features sdl3 -- --config /path/to/echolab.toml --screenshot
```

## Edit Text ROM Glyphs

Export the active glyph set (codes 0-127) to an editable PNG:

```bash
python3 tools/charrom_to_png.py \
  --rom assets/roms/APPLE2E_TEXT_DISPLAY_ROUNDED.bin \
  --out assets/roms/APPLE2E_TEXT_DISPLAY_ROUNDED_EDIT.png \
  --bank 0 \
  --start-code 128 \
  --scale 8
```

After editing that PNG, import it back into the ROM:

```bash
python3 tools/png_to_charrom.py \
  --in assets/roms/APPLE2E_TEXT_DISPLAY_ROUNDED_EDIT.png \
  --rom-in assets/roms/APPLE2E_TEXT_DISPLAY_ROUNDED.bin \
  --rom-out assets/roms/APPLE2E_TEXT_DISPLAY_ROUNDED.bin \
  --bank 0 \
  --start-code 128
```

## Scripts

- `./install.sh [--force]`: install toolchain and platform dependencies.
- `./install_vscode.sh`: install VS Code + Rust extensions.
- `./build.sh [--release]`: build the project.
- `./run.sh [--release] [-- <args>]`: run the binary.
- `./test.sh [--release]`: run tests.
- `./check.sh [--no-lint]`: run format check, compile check, and clippy by default.
- `./ci_local.sh [--release]`: run local CI sequence (fmt, clippy, test, build).
- `./clean.sh`: remove build artifacts.

## Project Layout

- `src/lib.rs`: library modules exported for app + tests
- `src/capture.rs`: reusable screenshot CLI/capture flow for emulator frontends
- `src/config.rs`: typed config loader for `echolab.toml`
- `src/main.rs`: CLI entry and output
- `src/lab.rs`: `Lab` model and machine list
- `src/machines/`: machine descriptors
- `src/rng.rs`: deterministic `FastRng` from benchmark logic
- `src/screen_buffer.rs`: emulator display buffer (`u32` pixels + `frame_id`) + PPM screenshot export
- `src/video/mod.rs`: text-only video controller that renders RAM into `ScreenBuffer`
- `tests/capture.rs`: reusable capture option/capture behavior tests
- `tests/config.rs`: parser tests for config behavior
- `tests/rng_determinism.rs`: integration tests for RNG behavior
- `tests/screen_buffer.rs`: integration tests for display buffer behavior
- `tests/text_video.rs`: integration tests for text scanout behavior
- `examples/hello_text.rs`: simple text-page hello-world render demo
- `examples/sdl3_text40x24.rs`: SDL3 windowed 40x24 text display demo
- `echolab.toml`: default app config values (screenshot directory, auto-exit)
- `tools/charrom_to_png.py`: export ROM glyphs to editable PNG
- `tools/png_to_charrom.py`: import edited PNG back into ROM bytes
- `archive/`: imported legacy projects kept for reference

## Near-Term Plan

1. Add CPU state and step execution scaffolding.
2. Introduce memory bus abstraction.
3. Add deterministic trace-based tests.
