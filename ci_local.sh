#!/bin/bash
set -euo pipefail

MODE="debug"
for arg in "$@"; do
  case "$arg" in
    -r|--release)
      MODE="release"
      ;;
    -h|--help)
      echo "Usage: ./ci_local.sh [--release]"
      echo "Runs local CI checks: fmt, clippy, test, build."
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: ./ci_local.sh [--release]"
      exit 1
      ;;
  esac
done

echo "==> Formatting check"
cargo fmt --all --check

echo "==> Lint"
cargo clippy --all-targets -- -D warnings

echo "==> Test"
if [[ "$MODE" == "release" ]]; then
  cargo test --release
else
  cargo test
fi

echo "==> Build"
if [[ "$MODE" == "release" ]]; then
  cargo build --release
else
  cargo build
fi

echo "Local CI passed."
