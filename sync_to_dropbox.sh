#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage:
  ./sync_to_dropbox.sh [--dest PATH] [--state-dir DIR] [--remote-compare] [--config FILE] [--dry-run]
  ./sync_to_dropbox.sh --pull [--src PATH] [--dest DIR] [--state-dir DIR] [--config FILE] [--dry-run]

Non-code sync wrapper.
Push mode delegates to ./sync_noncode_to_dropbox.sh.
Pull mode delegates to ./pull_noncode_from_dropbox.sh.

Options:
  --pull            Run pull mode (Dropbox -> local).
  --src PATH        Dropbox source root path for pull mode.
  --dest PATH       Dropbox destination root path.
                    In pull mode, this is local destination directory.
  --state-dir DIR   Per-file state directory.
  --remote-compare  Compare against Dropbox timestamps.
                    Push mode only.
  --config FILE     Dropbox config file path.
  --dry-run         Show what would upload without sending data.
  -h, --help        Show help.
EOF
}

delegated_args=()
mode="push"
remote_compare=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pull)
      mode="pull"
      shift
      ;;
    --src)
      [[ $# -ge 2 ]] || { echo "error: $1 requires a value" >&2; exit 2; }
      delegated_args+=("$1" "$2")
      shift 2
      ;;
    --dest|--state-dir|--config)
      [[ $# -ge 2 ]] || { echo "error: $1 requires a value" >&2; exit 2; }
      delegated_args+=("$1" "$2")
      shift 2
      ;;
    --remote-compare|--dry-run)
      [[ "$1" == "--remote-compare" ]] && remote_compare=1
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

if [[ "$mode" == "pull" ]]; then
  if [[ "$remote_compare" -eq 1 ]]; then
    echo "error: --remote-compare is supported only in push mode." >&2
    usage
    exit 2
  fi
  if [[ -n "${delegated_args[*]-}" ]]; then
    exec "$SCRIPT_DIR/pull_noncode_from_dropbox.sh" "${delegated_args[@]}"
  fi
  exec "$SCRIPT_DIR/pull_noncode_from_dropbox.sh"
fi
if [[ -n "${delegated_args[*]-}" ]]; then
  exec "$SCRIPT_DIR/sync_noncode_to_dropbox.sh" "${delegated_args[@]}"
fi
exec "$SCRIPT_DIR/sync_noncode_to_dropbox.sh"
