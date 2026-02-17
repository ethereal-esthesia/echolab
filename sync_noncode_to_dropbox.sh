#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'USAGE'
Usage: ./sync_noncode_to_dropbox.sh [--dest PATH] [--config FILE] [--state-dir DIR] [--remote-compare] [--dry-run]

Uploads scheduled non-code files individually to Dropbox API, preserving relative paths.
Only uploads files that changed since last sync (timestamp + content-aware fallback).

Options:
  --dest PATH       Dropbox destination root (default: /<sync_folder_name>).
  --config FILE     Config file path (default: ./dropbox.toml).
  --state-dir DIR   Per-file sync state directory.
                    Default: .backup_state/dropbox_sync_noncode
  --remote-compare  Ignore local state timing and compare source mtime against
                    Dropbox file timestamps (server_modified) for each file.
  --dry-run         Show what would upload without sending data.
  -h, --help        Show help.
USAGE
}

dest_root=""
config_file="$SCRIPT_DIR/dropbox.toml"
state_dir="$SCRIPT_DIR/.backup_state/dropbox_sync_noncode"
dry_run=0
remote_compare=0
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
    --remote-compare)
      remote_compare=1
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

iso_to_epoch() {
  local iso="$1"
  if [[ -z "$iso" ]]; then
    echo 0
    return 0
  fi
  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s >/dev/null 2>&1; then
    date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s
    return 0
  fi
  if date -u -d "$iso" +%s >/dev/null 2>&1; then
    date -u -d "$iso" +%s
    return 0
  fi
  echo 0
}

dropbox_remote_mtime_epoch() {
  local dropbox_path="$1"
  local resp
  local api_arg
  api_arg=$(printf '{"path":"%s","include_media_info":false,"include_deleted":false,"include_has_explicit_shared_members":false}' "$dropbox_path")
  resp="$(curl -sS -X POST "https://api.dropboxapi.com/2/files/get_metadata" \
    --header "Authorization: Bearer $dropbox_token" \
    --header "Content-Type: application/json" \
    --data "$api_arg")"

  if printf "%s" "$resp" | grep -q '"error_summary"[[:space:]]*:[[:space:]]*"path/not_found/'; then
    echo 0
    return 0
  fi

  if printf "%s" "$resp" | grep -q '"error_summary"'; then
    echo "error: metadata lookup failed for $dropbox_path: $resp" >&2
    return 1
  fi

  local server_modified
  server_modified="$(printf "%s" "$resp" | sed -n 's/.*"server_modified"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  iso_to_epoch "$server_modified"
}

file_sha1() {
  local path="$1"
  shasum -a 1 "$path" | awk '{print $1}'
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
if [[ "$remote_compare" -eq 1 ]]; then
  echo "Compare mode: Dropbox timestamps (server_modified)"
else
  echo "Compare mode: local state mtimes"
fi
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
  dropbox_path="${dest_root%/}/$rel"

  if [[ "$remote_compare" -eq 1 ]]; then
    remote_mtime=0
    if ! remote_mtime="$(dropbox_remote_mtime_epoch "$dropbox_path")"; then
      failed=$((failed + 1))
      continue
    fi
    if (( remote_mtime > 0 && source_mtime <= remote_mtime )); then
      skipped=$((skipped + 1))
      continue
    fi
  else
    last_checked=0
    last_size=0
    last_hash=""
    state_has_extended=0
    if [[ -f "$state_file" ]]; then
      state_raw="$(cat "$state_file" || true)"
      if [[ "$state_raw" == *$'\t'* ]]; then
        IFS=$'\t' read -r last_checked last_size last_hash <<< "$state_raw"
        state_has_extended=1
      else
        last_checked="$state_raw"
      fi
      [[ "$last_checked" =~ ^[0-9]+$ ]] || last_checked=0
      [[ "$last_size" =~ ^[0-9]+$ ]] || last_size=0
    fi

    if stat -f %z "$abs" >/dev/null 2>&1; then
      source_size="$(stat -f %z "$abs")"
    else
      source_size="$(stat -c %s "$abs")"
    fi

    if (( source_mtime <= last_checked )); then
      if [[ "$state_has_extended" -eq 0 ]]; then
        skipped=$((skipped + 1))
        continue
      fi
      if (( source_size == last_size )); then
        skipped=$((skipped + 1))
        continue
      fi
    fi

    # If mtimes changed externally, avoid re-upload by comparing stored content hash.
    if [[ -n "$last_hash" ]]; then
      source_hash="$(file_sha1 "$abs")"
      if [[ "$source_hash" == "$last_hash" ]]; then
        printf "%s\t%s\t%s\n" "$source_mtime" "$source_size" "$source_hash" > "$state_file"
        skipped=$((skipped + 1))
        continue
      fi
    fi
  fi

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
    if stat -f %z "$abs" >/dev/null 2>&1; then
      source_size="$(stat -f %z "$abs")"
    else
      source_size="$(stat -c %s "$abs")"
    fi
    source_hash="$(file_sha1 "$abs")"
    printf "%s\t%s\t%s\n" "$source_mtime" "$source_size" "$source_hash" > "$state_file"
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
