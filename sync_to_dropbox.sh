#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage:
  ./sync_to_dropbox.sh --source FILE [--dest PATH] [--name FILENAME] [--state FILE] [--allow-tracked] [--config FILE] [--dry-run]
  ./sync_to_dropbox.sh --noncode [--dest PATH] [--state-dir DIR] [--remote-compare] [--config FILE] [--dry-run]

Uploads FILE to Dropbox API only when FILE is newer than the last recorded check.

Options:
  --noncode       Run incremental non-code multi-file sync mode (delegates to
                  ./sync_noncode_to_dropbox.sh).
  --source FILE   Source file to sync (required).
  --dest PATH     Dropbox destination folder path (example: /echolab_sync).
                  Defaults to "default_sync_dir" from config, else "/<sync_folder_name>".
  --name NAME     Output filename in destination (default: basename of source).
  --state FILE    State file path for last-check timestamp.
                  Default: .backup_state/dropbox_sync_<hash>.state
  --state-dir DIR Per-file state dir for --noncode mode.
  --remote-compare
                  For --noncode mode: compare against Dropbox timestamps.
  --allow-tracked Allow uploading a git-tracked source file in single-file mode.
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
noncode_mode=0
state_dir=""
remote_compare=0
allow_tracked=0
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
    --noncode)
      noncode_mode=1
      shift
      ;;
    --dest)
      [[ $# -ge 2 ]] || { echo "error: --dest requires a path" >&2; exit 2; }
      dest_root="$2"
      shift 2
      ;;
    --state-dir)
      [[ $# -ge 2 ]] || { echo "error: --state-dir requires a path" >&2; exit 2; }
      state_dir="$2"
      shift 2
      ;;
    --remote-compare)
      remote_compare=1
      shift
      ;;
    --allow-tracked)
      allow_tracked=1
      shift
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

if [[ "$noncode_mode" -eq 1 ]]; then
  delegated_args=()
  [[ -n "$dest_root" ]] && delegated_args+=(--dest "$dest_root")
  [[ -n "$state_dir" ]] && delegated_args+=(--state-dir "$state_dir")
  [[ "$remote_compare" -eq 1 ]] && delegated_args+=(--remote-compare)
  [[ -n "$config_file" ]] && delegated_args+=(--config "$config_file")
  [[ "$dry_run" -eq 1 ]] && delegated_args+=(--dry-run)
  exec "$SCRIPT_DIR/sync_noncode_to_dropbox.sh" "${delegated_args[@]}"
fi

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
  dest_root="/$sync_folder_name"
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

token_env_name="${token_env_name:-DROPBOX_ACCESS_TOKEN}"
dropbox_token="${!token_env_name:-}"

[[ "$dest_root" == /* ]] || dest_root="/$dest_root"
dropbox_path="${dest_root%/}/$out_name"

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl is required for Dropbox API upload." >&2
  exit 1
fi

if [[ -z "$dropbox_token" ]]; then
  echo "error: Dropbox token env var is empty: $token_env_name" >&2
  exit 1
fi

if [[ "$allow_tracked" -eq 0 ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  source_rel="$source_file"
  if [[ "$source_rel" == "$SCRIPT_DIR/"* ]]; then
    source_rel="${source_rel#"$SCRIPT_DIR/"}"
  fi
  if git ls-files --error-unmatch -- "$source_rel" >/dev/null 2>&1; then
    echo "warning: source file is git-tracked: $source_rel" >&2
    if [[ -t 0 ]]; then
      printf "Remove it from git control now with 'git rm --cached %s'? [y/N] " "$source_rel" >&2
      read -r reply || true
      case "$reply" in
        [yY]|[yY][eE][sS])
          git rm --cached -- "$source_rel" >/dev/null
          echo "Removed from git index (file kept locally): $source_rel" >&2
          ;;
        *)
          echo "error: refusing to sync tracked file. Use --allow-tracked to override." >&2
          exit 1
          ;;
      esac
    else
      echo "error: refusing to sync tracked file. Use --allow-tracked to override." >&2
      echo "hint: git rm --cached -- \"$source_rel\"" >&2
      exit 1
    fi
  fi
fi

echo "Source: $source_abs"
echo "Dropbox destination: $dropbox_path"
echo "State file: $state_file"
echo "Token env key: $token_env_name"
echo "Source mtime: $source_mtime"
echo "Last checked mtime: $last_checked"

if (( source_mtime <= last_checked )); then
  echo "No sync needed (source is not newer than last check)."
  exit 0
fi

if [[ "$dry_run" -eq 1 ]]; then
  echo "Dry run: would upload source to Dropbox API and update state."
  exit 0
fi

mkdir -p "$(dirname "$state_file")"
api_arg=$(printf '{"path":"%s","mode":"overwrite","autorename":false,"mute":true,"strict_conflict":false}' "$dropbox_path")
upload_resp="$(curl -sS -f -X POST "https://content.dropboxapi.com/2/files/upload" \
  --header "Authorization: Bearer $dropbox_token" \
  --header "Dropbox-API-Arg: $api_arg" \
  --header "Content-Type: application/octet-stream" \
  --data-binary @"$source_file")" || {
  echo "error: Dropbox upload failed for $dropbox_path" >&2
  exit 1
}
if printf "%s" "$upload_resp" | grep -q '"error_summary"'; then
  echo "error: Dropbox upload returned API error: $upload_resp" >&2
  exit 1
fi
printf "%s\n" "$source_mtime" > "$state_file"

echo "Uploaded: $dropbox_path"
