#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'USAGE'
Usage: ./sync_noncode_to_dropbox.sh [--dest PATH] [--config FILE] [--state-dir DIR] [--dry-run]

Uploads scheduled non-code files individually to Dropbox API, preserving relative paths.
Only uploads files newer than each file's last recorded sync timestamp.

Options:
  --dest PATH       Dropbox destination root (default: /<sync_folder_name>).
  --config FILE     Config file path (default: ./dropbox.toml).
  --state-dir DIR   Per-file sync state directory.
                    Default: .backup_state/dropbox_sync_noncode
  --dry-run         Show what would upload without sending data.
  -h, --help        Show help.
USAGE
}

dest_root=""
config_file="$SCRIPT_DIR/dropbox.toml"
state_dir="$SCRIPT_DIR/.backup_state/dropbox_sync_noncode"
dry_run=0
sync_folder_name="echolab_sync"
token_env_name="DROPBOX_ACCESS_TOKEN"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || { echo "error: --dest requires a path" >&2; exit 2; }
      dest_root="$2"
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || { echo "error: --config requires a path" >&2; exit 2; }
      config_file="$2"
      shift 2
      ;;
    --state-dir)
      [[ $# -ge 2 ]] || { echo "error: --state-dir requires a path" >&2; exit 2; }
      state_dir="$2"
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
  token_env_name_cfg="$(parse_toml_string "token_env" "$config_file" || true)"
  [[ -n "${token_env_name_cfg:-}" ]] && token_env_name="$token_env_name_cfg"
  sync_folder_name_cfg="$(parse_toml_string "sync_folder_name" "$config_file" || true)"
  [[ -n "${sync_folder_name_cfg:-}" ]] && sync_folder_name="$sync_folder_name_cfg"
  if [[ -z "$dest_root" ]]; then
    configured_dest="$(parse_toml_string "default_sync_dir" "$config_file" || true)"
    [[ -n "${configured_dest:-}" ]] && dest_root="$configured_dest"
  fi
fi

if [[ -z "$dest_root" ]]; then
  dest_root="/$sync_folder_name"
fi
[[ "$dest_root" == /* ]] || dest_root="/$dest_root"

dropbox_token="${!token_env_name:-}"
if [[ -z "$dropbox_token" ]]; then
  echo "error: Dropbox token env var is empty: $token_env_name" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl is required for Dropbox API upload." >&2
  exit 1
fi

if ! command -v shasum >/dev/null 2>&1; then
  echo "error: shasum is required." >&2
  exit 1
fi

mkdir -p "$state_dir"

list_output="$(./backup_noncode.sh --list-only --config "$config_file" --dest /tmp/echolab_backups)"
rel_files=()
while IFS= read -r rel; do
  [[ -n "$rel" ]] && rel_files+=("$rel")
done < <(printf "%s\n" "$list_output" | sed -n 's/^  \[[^]]*\] \(.*\)$/\1/p')

if [[ "${#rel_files[@]}" -eq 0 ]]; then
  echo "No scheduled files found."
  exit 0
fi

echo "Dropbox destination root: $dest_root"
echo "Token env key: $token_env_name"
echo "State dir: $state_dir"
echo "Candidate files: ${#rel_files[@]}"

uploaded=0
skipped=0
failed=0

for rel in "${rel_files[@]}"; do
  abs="$SCRIPT_DIR/$rel"
  if [[ ! -f "$abs" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  if stat -f %m "$abs" >/dev/null 2>&1; then
    source_mtime="$(stat -f %m "$abs")"
  else
    source_mtime="$(stat -c %Y "$abs")"
  fi

  source_key="$(printf "%s" "$rel" | shasum -a 1 | awk '{print $1}')"
  state_file="$state_dir/${source_key}.state"

  last_checked=0
  if [[ -f "$state_file" ]]; then
    read -r last_checked < "$state_file" || true
    [[ "$last_checked" =~ ^[0-9]+$ ]] || last_checked=0
  fi

  if (( source_mtime <= last_checked )); then
    skipped=$((skipped + 1))
    continue
  fi

  dropbox_path="${dest_root%/}/$rel"
  echo "upload: $rel -> $dropbox_path"

  if [[ "$dry_run" -eq 1 ]]; then
    uploaded=$((uploaded + 1))
    continue
  fi

  api_arg=$(printf '{"path":"%s","mode":"overwrite","autorename":false,"mute":true,"strict_conflict":false}' "$dropbox_path")
  if curl -sS -X POST "https://content.dropboxapi.com/2/files/upload" \
    --header "Authorization: Bearer $dropbox_token" \
    --header "Dropbox-API-Arg: $api_arg" \
    --header "Content-Type: application/octet-stream" \
    --data-binary @"$abs" >/dev/null; then
    printf "%s\n" "$source_mtime" > "$state_file"
    uploaded=$((uploaded + 1))
  else
    echo "error: upload failed for $rel" >&2
    failed=$((failed + 1))
  fi
done

echo "Summary: uploaded=$uploaded skipped=$skipped failed=$failed"

if (( failed > 0 )); then
  exit 1
fi
