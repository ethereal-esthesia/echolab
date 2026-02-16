#!/bin/bash
set -euo pipefail

MODE="debug"
RUN_ARGS=()
OS="$(uname -s)"

ensure_sdl3_link_path_macos() {
  if [[ "$OS" != "Darwin" ]]; then
    return 0
  fi

  local sdl3_prefix=""
  local sdl3_lib=""
  local sdl3_inc=""

  if command -v brew >/dev/null 2>&1; then
    sdl3_prefix="$(brew --prefix sdl3 2>/dev/null || true)"
  fi

  if [[ -n "$sdl3_prefix" ]]; then
    sdl3_lib="$sdl3_prefix/lib"
    sdl3_inc="$sdl3_prefix/include"
  elif [[ -d "/opt/homebrew/opt/sdl3/lib" ]]; then
    sdl3_lib="/opt/homebrew/opt/sdl3/lib"
    sdl3_inc="/opt/homebrew/opt/sdl3/include"
  elif [[ -d "/usr/local/opt/sdl3/lib" ]]; then
    sdl3_lib="/usr/local/opt/sdl3/lib"
    sdl3_inc="/usr/local/opt/sdl3/include"
  fi

  if [[ -n "$sdl3_lib" && -d "$sdl3_lib" ]]; then
    export LIBRARY_PATH="${sdl3_lib}:${LIBRARY_PATH:-}"
    export DYLD_FALLBACK_LIBRARY_PATH="${sdl3_lib}:${DYLD_FALLBACK_LIBRARY_PATH:-}"
  fi

  if [[ -n "$sdl3_inc" && -d "$sdl3_inc" ]]; then
    export CPATH="${sdl3_inc}:${CPATH:-}"
  fi
}

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

ensure_sdl3_link_path_macos

if [[ "$MODE" == "release" ]]; then
  if [[ ${#RUN_ARGS[@]} -gt 0 ]]; then
    cargo run --release "${RUN_ARGS[@]}"
  else
    cargo run --release
  fi
else
  if [[ ${#RUN_ARGS[@]} -gt 0 ]]; then
    cargo run "${RUN_ARGS[@]}"
  else
    cargo run
  fi
fi
