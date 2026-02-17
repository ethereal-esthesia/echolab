#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage: ./sync_to_dropbox.sh --source FILE [--dest DIR] [--name FILENAME] [--state FILE] [--config FILE] [--dry-run]

Copies FILE to Dropbox only when FILE is newer than the last recorded check.

Options:
  --source FILE   Source file to sync (required).
  --dest DIR      Destination directory.
                  Default: auto-detect Dropbox:
                    1) ~/Library/CloudStorage/Dropbox
                    2) ~/Dropbox
                  Then uses "<dropbox>/<sync_folder_name>" from config.
  --name NAME     Output filename in destination (default: basename of source).
  --state FILE    State file path for last-check timestamp.
                  Default: .backup_state/dropbox_sync_<hash>.state
  --config FILE   Dropbox config file path.
                  Default: ./dropbox.toml
  --dry-run       Show what would happen without copying.
  -h, --help      Show help.
EOF
}

source_file=""
dest_root=""
out_name=""
state_file=""
config_file="$SCRIPT_DIR/dropbox.toml"
token_env_name=""
sync_folder_name="echolab_sync"
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo "error: --source requires a path" >&2; exit 2; }
      source_file="$2"
      shift 2
      ;;
    --dest)
      [[ $# -ge 2 ]] || { echo "error: --dest requires a path" >&2; exit 2; }
      dest_root="$2"
      shift 2
      ;;
    --name)
      [[ $# -ge 2 ]] || { echo "error: --name requires a value" >&2; exit 2; }
      out_name="$2"
      shift 2
      ;;
    --state)
      [[ $# -ge 2 ]] || { echo "error: --state requires a path" >&2; exit 2; }
      state_file="$2"
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || { echo "error: --config requires a path" >&2; exit 2; }
      config_file="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
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

[[ -n "$source_file" ]] || { echo "error: --source is required" >&2; usage; exit 2; }
[[ -f "$source_file" ]] || { echo "error: source file not found: $source_file" >&2; exit 1; }

parse_toml_string() {
  local key="$1"
  local path="$2"
  awk -F '=' -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      val = $2
      sub(/^[[:space:]]*/, "", val)
      sub(/[[:space:]]*#.*/, "", val)
      gsub(/^"/, "", val)
      gsub(/"$/, "", val)
      print val
      exit
    }
  ' "$path"
}

if [[ -f "$config_file" ]]; then
  if [[ -z "$dest_root" ]]; then
    configured_dest="$(parse_toml_string "default_sync_dir" "$config_file" || true)"
    if [[ -n "${configured_dest:-}" ]]; then
      dest_root="$configured_dest"
    fi
  fi
  token_env_name="$(parse_toml_string "token_env" "$config_file" || true)"
  configured_folder="$(parse_toml_string "sync_folder_name" "$config_file" || true)"
  if [[ -n "${configured_folder:-}" ]]; then
    sync_folder_name="$configured_folder"
  fi
fi

if [[ -z "$dest_root" ]]; then
  if [[ -d "$HOME/Library/CloudStorage/Dropbox" ]]; then
    dest_root="$HOME/Library/CloudStorage/Dropbox/$sync_folder_name"
  elif [[ -d "$HOME/Dropbox" ]]; then
    dest_root="$HOME/Dropbox/$sync_folder_name"
  else
    echo "error: Dropbox folder not found. Provide --dest DIR." >&2
    exit 1
  fi
fi

if [[ -z "$out_name" ]]; then
  out_name="$(basename "$source_file")"
fi

source_abs="$(cd "$(dirname "$source_file")" && pwd)/$(basename "$source_file")"
source_key="$(printf "%s" "$source_abs" | shasum -a 1 | awk '{print $1}')"
if [[ -z "$state_file" ]]; then
  state_file="$SCRIPT_DIR/.backup_state/dropbox_sync_${source_key}.state"
fi

if stat -f %m "$source_file" >/dev/null 2>&1; then
  source_mtime="$(stat -f %m "$source_file")"
else
  source_mtime="$(stat -c %Y "$source_file")"
fi

last_checked=0
if [[ -f "$state_file" ]]; then
  read -r last_checked < "$state_file" || true
  [[ "$last_checked" =~ ^[0-9]+$ ]] || last_checked=0
fi

dest_file="$dest_root/$out_name"

echo "Source: $source_abs"
echo "Destination: $dest_file"
echo "State file: $state_file"
if [[ -n "$token_env_name" ]]; then
  echo "Token env key (from config): $token_env_name"
fi
echo "Source mtime: $source_mtime"
echo "Last checked mtime: $last_checked"

if (( source_mtime <= last_checked )); then
  echo "No sync needed (source is not newer than last check)."
  exit 0
fi

if [[ "$dry_run" -eq 1 ]]; then
  echo "Dry run: would copy source to destination and update state."
  exit 0
fi

mkdir -p "$dest_root"
mkdir -p "$(dirname "$state_file")"
cp -f "$source_file" "$dest_file"
printf "%s\n" "$source_mtime" > "$state_file"

echo "Synced: $dest_file"
