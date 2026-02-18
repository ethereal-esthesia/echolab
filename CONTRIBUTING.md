# Contributing to EchoLab

Thanks for your interest in improving EchoLab.

## Development Setup

1. Install dependencies:
   - `./install.sh`
2. Build and test:
   - `./ci_local.sh`
3. Run examples:
   - `./run.sh --example hello_text`

## Coding Guidelines

- Keep changes focused and small.
- Prefer reusable modules over emulator-specific logic.
- Add or update tests with behavior changes.
- Keep docs and script help text in sync with code changes.

## Pull Requests

- Use clear commit messages.
- Describe what changed and why.
- Include test evidence (`./ci_local.sh` output summary).
- If behavior changes, update `README.md` and related docs.

## Before Opening a PR

- `./ci_local.sh` passes locally.
- `cargo fmt --check` passes.
- `cargo clippy --all-targets --all-features -D warnings` passes.
- `cargo test --all-targets --all-features` passes.
