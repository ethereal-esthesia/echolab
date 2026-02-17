# EchoLab

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
- `./backup_noncode.sh [--dest DIR] [--whole-project] [--zip-overwrite] [--config FILE] [--list-only]`: create local non-code backup archives; fails if git is not clean and excludes all git-tracked files.
- `./sync_to_dropbox.sh --source FILE [--dest PATH] [--name FILENAME] [--config FILE]`: upload one file via Dropbox API only if source is newer than last check.
- `./sync_noncode_to_dropbox.sh [--dest PATH] [--config FILE] [--remote-compare] [--dry-run]`: upload scheduled non-code files individually via Dropbox API and skip unchanged files.

## Secret Scanning

Enable local pre-commit secret scanning:

```bash
git config core.hooksPath .githooks
```

Install gitleaks locally (example on macOS):

```bash
brew install gitleaks
```

CI secret scanning also runs on push and pull requests via GitHub Actions (`.github/workflows/secret-scan.yml`).

## Backup Non-Code Assets

Create a backup archive of non-code assets locally:

```bash
./backup_noncode.sh
```

Show only the files scheduled for backup (no archive written, with per-file sizes):

```bash
./backup_noncode.sh --list-only
```

`backup_noncode.sh` safety rules:
- Requires a clean git working tree.
- Excludes every git-tracked path from backup output.
- Applies extra wildcard excludes from `[exclude]` in `dropbox.toml`.
- Prints each archived file by default.
- Detects nested git repositories, excludes their `.git/` folders, and writes a queue file at `.backup_state/nested_git_repos.queue`.
- Default candidate paths include `archive/`; control inclusion via `[exclude]` in `dropbox.toml`.
- `--list-only` is grouped by per-project runs so nested git repos are evaluated separately.

Preview included paths without writing an archive:

```bash
./backup_noncode.sh --dry-run
```

Use a custom destination:

```bash
./backup_noncode.sh --dest /path/to/backups
```

Backup the whole project folder (excluding `.git/` and `target/`):

```bash
./backup_noncode.sh --whole-project
```

Create a single zip that always overwrites the previous one:

```bash
./backup_noncode.sh --whole-project --zip-overwrite
```

Use a custom config file:

```bash
./backup_noncode.sh --whole-project --zip-overwrite --config /path/to/dropbox.toml
```

Upload one file to Dropbox only when it changed (newer mtime):

```bash
./sync_to_dropbox.sh --source /path/to/echolab_latest.zip
```

Use a custom Dropbox destination path:

```bash
./sync_to_dropbox.sh --source /path/to/echolab_latest.zip --dest /echolab_sync
```

Upload scheduled non-code files individually (incremental, path-preserving):

```bash
./sync_noncode_to_dropbox.sh --dest /echolab_sync/noncode
```

Use Dropbox metadata timestamps instead of local state files:

```bash
./sync_noncode_to_dropbox.sh --dest /echolab_sync/noncode --remote-compare
```

Configure Dropbox sync defaults and token environment key in:

```bash
./dropbox.toml
```

`default_sync_dir` is a Dropbox API folder path (example: `/echolab_sync`) and `backup_folder_name` controls the default local backup subfolder name when `default_backup_dir` is empty.

Example:

```toml
token_env = "DROPBOX_ACCESS_TOKEN"
default_sync_dir = "/echolab_sync"
sync_folder_name = "echolab_sync"
default_backup_dir = "/absolute/local/path/for/backups"
backup_folder_name = "echolab_backups"

[exclude]
env = ".env*"
pem = "*.pem"
keys = "*.key"
```

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
- `dropbox.toml`: Dropbox sync + local backup config (token env key, optional defaults, wildcard exclude list)
- `tools/charrom_export.py`: export ROM glyphs to editable BMP/PNG
- `tools/charrom_import.py`: import edited BMP/PNG back into ROM bytes
- `archive/`: imported legacy projects kept for reference

## Near-Term Plan

1. Add CPU state and step execution scaffolding.
2. Introduce memory bus abstraction.
3. Add deterministic trace-based tests.

## Hardware-Faithful Emulation Plan

Goal: base emulation behavior on documented hardware timing and signal interactions, while keeping modules testable and incremental.

Approach:
- Model observable hardware behavior first (bus transactions, scan timing, soft-switch side effects), not transistor-level internals.
- Implement each subsystem as a clocked state machine with explicit inputs/outputs per tick.
- Encode hardware contracts in tests before deep optimization.

Priority order:
1. Bus and memory arbitration timing.
2. Video scan timing and VBlank edge semantics.
3. Keyboard and input strobe/read-clear behavior.
4. Audio and timer/interrupt sequencing.
5. Storage/card timing once core timing is stable.

Validation strategy:
- Compare against ROM routines and deterministic traces.
- Add subsystem tests that assert cycle-level side effects at MMIO boundaries.
- Keep one reference timing table per subsystem in docs and update it with implementation changes.

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
