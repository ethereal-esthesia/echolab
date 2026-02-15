# Echo Lab

Echo Lab is a Rust workspace for emulator experiments.

## Current Scope

- Minimal lab model and machine registry
- One machine descriptor: Apple IIe
- Deterministic fast RNG module for emulator workloads
- Testable screen buffer with explicit frame publish counter
- Text-mode video scanout (RAM -> black/white screen buffer with every-other-scanline output)

## Run

```bash
cargo run
```

## Demo: Text Hello

```bash
cargo run --example hello_text
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
- `src/main.rs`: CLI entry and output
- `src/lab.rs`: `Lab` model and machine list
- `src/machines/`: machine descriptors
- `src/rng.rs`: deterministic `FastRng` from benchmark logic
- `src/screen_buffer.rs`: emulator display buffer (`u32` pixels + `frame_id`)
- `src/video/mod.rs`: text-only video controller that renders RAM into `ScreenBuffer`
- `tests/rng_determinism.rs`: integration tests for RNG behavior
- `tests/screen_buffer.rs`: integration tests for display buffer behavior
- `tests/text_video.rs`: integration tests for text scanout behavior
- `examples/hello_text.rs`: simple text-page hello-world render demo
- `archive/`: imported legacy projects kept for reference

## Near-Term Plan

1. Add CPU state and step execution scaffolding.
2. Introduce memory bus abstraction.
3. Add deterministic trace-based tests.
