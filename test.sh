#!/bin/bash
set -euo pipefail

MODE="debug"
for arg in "$@"; do
  case "$arg" in
    -r|--release)
      MODE="release"
      ;;
    -h|--help)
      echo "Usage: ./test.sh [--release]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: ./test.sh [--release]"
      exit 1
      ;;
  esac
done

if [[ "$MODE" == "release" ]]; then
  cargo test --release
else
  cargo test
fi
