#!/bin/bash
set -euo pipefail

LINT=1
for arg in "$@"; do
  case "$arg" in
    --no-lint)
      LINT=0
      ;;
    -h|--help)
      echo "Usage: ./check.sh [--no-lint]"
      echo "Runs cargo fmt --check, cargo check, and optionally cargo clippy."
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: ./check.sh [--no-lint]"
      exit 1
      ;;
  esac
done

cargo fmt --all --check
cargo check

if [[ "$LINT" -eq 1 ]]; then
  cargo clippy --all-targets -- -D warnings
fi
