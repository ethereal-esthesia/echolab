#!/bin/bash
set -euo pipefail

MODE="debug"
for arg in "$@"; do
  case "$arg" in
    -r|--release)
      MODE="release"
      ;;
    -h|--help)
      echo "Usage: ./build.sh [--release]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: ./build.sh [--release]"
      exit 1
      ;;
  esac
done

if [[ "$MODE" == "release" ]]; then
  cargo build --release
else
  cargo build
fi
