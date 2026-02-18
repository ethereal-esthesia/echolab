#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage:
  ./sync_to_dropbox.sh [--dest PATH] [--state-file FILE] [--config FILE] [--dry-run]
  ./sync_to_dropbox.sh --pull [--src PATH] [--dest DIR] [--state-file FILE] [--config FILE] [--dry-run]

Dropbox sync wrapper.
Push mode delegates to ./sync_dropbox_push.sh.
Pull mode delegates to ./sync_dropbox_pull.sh.

Options:
  --pull            Run pull mode (Dropbox -> local).
  --src PATH        Dropbox source root path for pull mode.
  --dest PATH       Dropbox destination root path.
                    In pull mode, this is local destination directory.
  --state-file FILE Shared local sync timestamp file.
  --config FILE     Dropbox config file path.
  --dry-run         Show what would upload without sending data.
  -h, --help        Show help.
EOF
}

delegated_args=()
mode="push"

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
    --dest|--state-file|--config)
      [[ $# -ge 2 ]] || { echo "error: $1 requires a value" >&2; exit 2; }
      delegated_args+=("$1" "$2")
      shift 2
      ;;
    --dry-run)
      delegated_args+=("$1")
      shift
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
  if [[ -n "${delegated_args[*]-}" ]]; then
    exec "$SCRIPT_DIR/sync_dropbox_pull.sh" "${delegated_args[@]}"
  fi
  exec "$SCRIPT_DIR/sync_dropbox_pull.sh"
fi
if [[ -n "${delegated_args[*]-}" ]]; then
  exec "$SCRIPT_DIR/sync_dropbox_push.sh" "${delegated_args[@]}"
fi
exec "$SCRIPT_DIR/sync_dropbox_push.sh"
