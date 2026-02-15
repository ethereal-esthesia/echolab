#!/bin/bash
set -euo pipefail

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      echo "Usage: ./clean.sh"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: ./clean.sh"
      exit 1
      ;;
  esac
done

cargo clean
