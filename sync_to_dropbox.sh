#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage: ./sync_to_dropbox.sh [--dest PATH] [--state-dir DIR] [--remote-compare] [--config FILE] [--dry-run]

Non-code sync mode only.
Delegates to ./sync_noncode_to_dropbox.sh.

Options:
  --dest PATH       Dropbox destination root path.
  --state-dir DIR   Per-file sync state directory.
  --remote-compare  Compare against Dropbox timestamps.
  --config FILE     Dropbox config file path.
  --dry-run         Show what would upload without sending data.
  -h, --help        Show help.
EOF
}

delegated_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest|--state-dir|--config)
      [[ $# -ge 2 ]] || { echo "error: $1 requires a value" >&2; exit 2; }
      delegated_args+=("$1" "$2")
      shift 2
      ;;
    --remote-compare|--dry-run)
      delegated_args+=("$1")
      shift
      ;;
    --noncode)
      # Backward-compatible no-op.
      shift
      ;;
    --source|--name|--state|--allow-tracked)
      echo "error: $1 is no longer supported; non-code sync is mandatory." >&2
      usage
      exit 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

exec "$SCRIPT_DIR/sync_noncode_to_dropbox.sh" "${delegated_args[@]}"
