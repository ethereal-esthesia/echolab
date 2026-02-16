# Echo Lab

EchoLab is a repository for retro machines emulation and experimentation.

## Current Scope

- Minimal lab model and machine registry
- One machine descriptor: Apple IIe
- Deterministic fast RNG module for emulator workloads
- Testable screen buffer with explicit frame publish counter
- Text-mode video scanout (RAM -> phosphor-green-on-black buffer with every-other-scanline output, using rounded Apple IIe glyph ROM data with unique codes 0-255)

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
Default text color is green; add `-- --white` to render white-on-black.
For frame-flip stress testing, add `-- --flip-test` to randomize all 40x24 chars to codes `0..15` each frame.
For black/white flip testing, add `-- --bw-flip-test` (full-frame toggle every frame, through persistence blend).
Add `-- --fullscreen` to start the SDL window in fullscreen.
Default sync is crossover timing: host display refresh (autodetected from SDL mode; measured from VSync presents if unavailable) with Apple IIe NTSC guest pacing (`59.92Hz`).
Default presentation also applies phosphor persistence using normalized blending (`current + previous = 100%` each frame).
Add `-- --crossover-vsync-off` to keep crossover timing but disable renderer VSync (`--crossfade-vsync-off` is kept as an alias).
Add `-- --vsync-off` for raw uncoupled timing.

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

Export the full glyph set (codes 0-255) to an editable 1:1 BMP:

```bash
python3 tools/charrom_export.py \
  --rom assets/roms/retro_7x8_mono.bin \
  --out assets/roms/retro_7x8_mono_edit.bmp \
  --bank 0
```

After editing that BMP, import it back into the ROM:

```bash
python3 tools/charrom_import.py \
  --in assets/roms/retro_7x8_mono_edit.bmp \
  --rom-in assets/roms/retro_7x8_mono.bin \
  --rom-out assets/roms/retro_7x8_mono.bin \
  --bank 0
```

Import is strict black/white by default and fails if any pixel is not pure `#000000` or `#FFFFFF`.
Use `--no-strict-bw` only when you intentionally want thresholded conversion.

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
- `src/sdl_display_core.rs`: reusable SDL display loop core (timing, persistence, capture, text scanout integration)
- `src/timing.rs`: reusable crossover timing and frame pacing helpers
- `src/postfx.rs`: reusable post-processing (frame persistence blend)
- `src/video/mod.rs`: text-only video controller that renders RAM into `ScreenBuffer`
- `tests/capture.rs`: reusable capture option/capture behavior tests
- `tests/config.rs`: parser tests for config behavior
- `tests/postfx.rs`: persistence blend behavior and weighted-mix property tests
- `tests/rng_determinism.rs`: integration tests for RNG behavior
- `tests/screen_buffer.rs`: integration tests for display buffer behavior
- `tests/timing.rs`: long-horizon crossover cadence/timing tests
- `tests/text_video.rs`: integration tests for text scanout behavior
- `examples/hello_text.rs`: simple text-page hello-world render demo
- `examples/sdl3_text40x24.rs`: SDL3 windowed 40x24 text display demo
- `echolab.toml`: default app config values (screenshot directory, auto-exit)
- `tools/charrom_export.py`: export ROM glyphs to editable BMP/PNG
- `tools/charrom_import.py`: import edited BMP/PNG back into ROM bytes
- `archive/`: imported legacy projects kept for reference

## Near-Term Plan

1. Add CPU state and step execution scaffolding.
2. Introduce memory bus abstraction.
3. Add deterministic trace-based tests.

## License

This project is licensed under the MIT License. See `LICENSE`.

## Memory Map Target

### Address Space

| Range | Purpose |
|---|---|
| `0x0000-0x00FF` | ZERO PAGE RAM |
| `0x0100-0x01FF` | CPU STACK RAM |
| `0x0200-0xBFFF` | RAM |
| `0xC000-0xDFFF` | ROM |
| `0xE000-0xE0FF` | MMIO |
| `0xE100-0xFFFF` | monitor/firmware ROM + vectors (or flip MMIO/ROM order) |

### MMIO Registers (`0xE000-0xE0FF`)

| Offset | Name | Notes |
|---|---|---|
| `+0x00/+0x01` | `FRM_BASE_LO/HI` | `HI = 0x00` turns off display |
| `+0x02/+0x03` | `VPT_BASE_LO/HI` | `HI = 0x00` turns off viewport |
| `+0x04` | `VPT_COLS` | viewport width |
| `+0x05` | `VPT_ROWS` | viewport height |
| `+0x06` | `VPT_COL_OFFSET_CHAR` | viewport scroll column offset |
| `+0x07` | `VPT_ROW_OFFSET_CHAR` | viewport row offset (256-byte boundary) |
| `+0x08` | `VPT_X_OFFSET_PX` | `0x00-0x06` |
| `+0x09` | `VPT_Y_OFFSET_PX` | `0x00-0x07` |
| `+0x0A` | `VBL_SYNC` | write: apply frame/viewport settings at blanking period; read: bit0=`in_vblank`, bit1=`write_pending` |
| `+0x0B` | `SWITCH_80_COL` | write: bit0 turns 80-col mode on, bit1 turns it off; read: bit0=`1` when 80-col mode is on, `0` when off |

### MMIO I/O Block Plan

| Range | Block | Initial Purpose |
|---|---|---|
| `0xE000-0xE01F` | `VIDEO` | frame/viewport control, VBlank sync/status, 80-col switch |
| `0xE020-0xE02F` | `INPUT` | keyboard data/status and basic input flags |
| `0xE030-0xE03F` | `AUDIO` | simple tone/noise frequency, volume, gate/control |
| `0xE040-0xE05F` | `TIMER_IRQ` | free-running timer, compare registers, IRQ enable/status/ack |
| `0xE060-0xE07F` | `SERIAL_DEBUG` | TX/RX data/status and optional debug output port |
| `0xE080-0xE09F` | `STORAGE` | virtual storage command/status/data stub for future expansion |

Guidelines:
- Keep read side effects and write side effects explicit per register.
- Separate status registers (read-heavy) from command registers (write-heavy).
- Use predictable reset values and document them.
- Use one IRQ status + one IRQ acknowledge path per block.
