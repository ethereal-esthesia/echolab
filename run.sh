#!/bin/bash
set -euo pipefail

MODE="debug"
RUN_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--release)
      MODE="release"
      shift
      ;;
    -h|--help)
      echo "Usage: ./run.sh [--release] [-- <cargo-run-args>]"
      exit 0
      ;;
    *)
      RUN_ARGS=("$@")
      break
      ;;
  esac
done

if [[ "$MODE" == "release" ]]; then
  cargo run --release "${RUN_ARGS[@]}"
else
  cargo run "${RUN_ARGS[@]}"
fi
