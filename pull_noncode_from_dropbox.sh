#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'USAGE'
Usage: ./pull_noncode_from_dropbox.sh [--src PATH] [--dest DIR] [--config FILE] [--state-dir DIR] [--dry-run]

Pulls files recursively from Dropbox API into a local destination directory,
preserving relative paths under --src.

Incremental behavior uses per-file Dropbox revision state + timestamps:
- If local file exists and rev matches last pulled rev, file is skipped.
- If rev state is missing/mismatched but local mtime >= Dropbox server_modified,
  file is treated as up-to-date and skipped.
- Otherwise file is downloaded and state is updated.

Options:
  --src PATH        Dropbox source root path (default: /<sync_folder_name>/noncode).
  --dest DIR        Local destination root directory (default: repo root).
  --config FILE     Config file path (default: ./dropbox.toml).
  --state-dir DIR   Pull state directory (default: .backup_state/dropbox_pull_noncode).
                    Also updates push state files in .backup_state/dropbox_sync_noncode
                    so unchanged pulled files are not re-uploaded.
  --dry-run         Show what would download without writing files.
  -h, --help        Show help.
USAGE
}

src_root=""
dest_root="$SCRIPT_DIR"
config_file="$SCRIPT_DIR/dropbox.toml"
state_dir="$SCRIPT_DIR/.backup_state/dropbox_pull_noncode"
sync_state_dir="$SCRIPT_DIR/.backup_state/dropbox_sync_noncode"
dry_run=0
sync_folder_name="echolab_sync"
token_env_name="DROPBOX_ACCESS_TOKEN"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src)
      [[ $# -ge 2 ]] || { echo "error: --src requires a path" >&2; exit 2; }
      src_root="$2"
      shift 2
      ;;
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

file_sha1() {
  local path="$1"
  shasum -a 1 "$path" | awk '{print $1}'
}

write_push_state_from_local() {
  local rel="$1"
  local local_abs="$2"
  [[ -f "$local_abs" ]] || return 0

  local mtime size hash key out
  if stat -f %m "$local_abs" >/dev/null 2>&1; then
    mtime="$(stat -f %m "$local_abs")"
  else
    mtime="$(stat -c %Y "$local_abs")"
  fi
  if stat -f %z "$local_abs" >/dev/null 2>&1; then
    size="$(stat -f %z "$local_abs")"
  else
    size="$(stat -c %s "$local_abs")"
  fi
  hash="$(file_sha1 "$local_abs")"
  key="$(printf "%s" "$rel" | shasum -a 1 | awk '{print $1}')"
  out="$sync_state_dir/${key}.state"
  printf "%s\t%s\t%s\n" "$mtime" "$size" "$hash" > "$out"
}

if [[ -f "$config_file" ]]; then
  token_env_name_cfg="$(parse_toml_string "token_env" "$config_file" || true)"
  [[ -n "${token_env_name_cfg:-}" ]] && token_env_name="$token_env_name_cfg"
  sync_folder_name_cfg="$(parse_toml_string "sync_folder_name" "$config_file" || true)"
  [[ -n "${sync_folder_name_cfg:-}" ]] && sync_folder_name="$sync_folder_name_cfg"
fi

if [[ -z "$src_root" ]]; then
  src_root="/$sync_folder_name/noncode"
fi
[[ "$src_root" == /* ]] || src_root="/$src_root"

dropbox_token="${!token_env_name:-}"
if [[ -z "$dropbox_token" ]]; then
  echo "error: Dropbox token env var is empty: $token_env_name" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl is required for Dropbox API calls." >&2
  exit 1
fi
if ! command -v shasum >/dev/null 2>&1; then
  echo "error: shasum is required." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required for JSON parsing." >&2
  exit 1
fi

mkdir -p "$state_dir"
mkdir -p "$sync_state_dir"
mkdir -p "$dest_root"

list_tmp="$(mktemp)"
trap 'rm -f "$list_tmp"' EXIT

list_dropbox_files() {
  local path="$1"
  local cursor=""
  local has_more=1

  while [[ "$has_more" -eq 1 ]]; do
    local resp
    if [[ -z "$cursor" ]]; then
      local body
      body=$(printf '{"path":"%s","recursive":true,"include_deleted":false,"include_non_downloadable_files":false}' "$path")
      resp="$(curl -sS -f -X POST "https://api.dropboxapi.com/2/files/list_folder" \
        --header "Authorization: Bearer $dropbox_token" \
        --header "Content-Type: application/json" \
        --data "$body")"
    else
      local body
      body=$(printf '{"cursor":"%s"}' "$cursor")
      resp="$(curl -sS -f -X POST "https://api.dropboxapi.com/2/files/list_folder/continue" \
        --header "Authorization: Bearer $dropbox_token" \
        --header "Content-Type: application/json" \
        --data "$body")"
    fi

    if printf "%s" "$resp" | grep -q '"error_summary"'; then
      echo "error: Dropbox list_folder failed: $resp" >&2
      return 1
    fi

    printf "%s" "$resp" | python3 -c '
import json,sys
obj=json.load(sys.stdin)
for e in obj.get("entries",[]):
    if e.get(".tag")!="file":
        continue
    p=e.get("path_display","")
    r=e.get("rev","")
    m=e.get("server_modified","")
    if p:
        print(f"{p}\t{r}\t{m}")
' >> "$list_tmp"

    has_more_val="$(printf "%s" "$resp" | python3 -c 'import json,sys; print(1 if json.load(sys.stdin).get("has_more") else 0)')"
    has_more="$has_more_val"
    if [[ "$has_more" -eq 1 ]]; then
      cursor="$(printf "%s" "$resp" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cursor",""))')"
      if [[ -z "$cursor" ]]; then
        echo "error: Dropbox pagination cursor missing." >&2
        return 1
      fi
    fi
  done
}

list_dropbox_files "$src_root"

if [[ ! -s "$list_tmp" ]]; then
  echo "No files found under Dropbox path: $src_root"
  exit 0
fi

echo "Dropbox source root: $src_root"
echo "Local destination root: $dest_root"
echo "Token env key: $token_env_name"
echo "State dir: $state_dir"
echo "Candidate remote files: $(wc -l < "$list_tmp" | tr -d ' ')"

downloaded=0
skipped=0
failed=0

while IFS=$'\t' read -r path_display rev server_modified; do
  [[ -n "$path_display" ]] || continue
  rel="${path_display#${src_root%/}/}"
  if [[ "$rel" == "$path_display" ]]; then
    # If root path itself maps directly, strip leading slash.
    rel="${path_display#/}"
  fi

  local_abs="$dest_root/$rel"
  state_key="$(printf "%s" "$path_display" | shasum -a 1 | awk '{print $1}')"
  state_file="$state_dir/${state_key}.state"

  last_rev=""
  last_remote_epoch=0
  if [[ -f "$state_file" ]]; then
    read -r last_rev last_remote_epoch < "$state_file" || true
    [[ "$last_remote_epoch" =~ ^[0-9]+$ ]] || last_remote_epoch=0
  fi
  remote_epoch="$(iso_to_epoch "$server_modified")"

  if [[ -f "$local_abs" && -n "$last_rev" && "$last_rev" == "$rev" ]]; then
    printf "%s %s\n" "$rev" "$remote_epoch" > "$state_file"
    if [[ "$dry_run" -eq 0 ]]; then
      write_push_state_from_local "$rel" "$local_abs"
    fi
    skipped=$((skipped + 1))
    continue
  fi

  if [[ -f "$local_abs" ]]; then
    if stat -f %m "$local_abs" >/dev/null 2>&1; then
      local_mtime="$(stat -f %m "$local_abs")"
    else
      local_mtime="$(stat -c %Y "$local_abs")"
    fi
    if (( remote_epoch > 0 && local_mtime >= remote_epoch )); then
      printf "%s %s\n" "$rev" "$remote_epoch" > "$state_file"
      if [[ "$dry_run" -eq 0 ]]; then
        write_push_state_from_local "$rel" "$local_abs"
      fi
      skipped=$((skipped + 1))
      continue
    fi
  fi

  echo "download: $path_display -> $local_abs"

  if [[ "$dry_run" -eq 1 ]]; then
    downloaded=$((downloaded + 1))
    continue
  fi

  mkdir -p "$(dirname "$local_abs")"
  api_arg=$(printf '{"path":"%s"}' "$path_display")
  if curl -sS -f -X POST "https://content.dropboxapi.com/2/files/download" \
    --header "Authorization: Bearer $dropbox_token" \
    --header "Dropbox-API-Arg: $api_arg" \
    -o "$local_abs"; then
    printf "%s %s\n" "$rev" "$remote_epoch" > "$state_file"
    write_push_state_from_local "$rel" "$local_abs"
    downloaded=$((downloaded + 1))
  else
    echo "error: download failed for $path_display" >&2
    failed=$((failed + 1))
  fi

done < "$list_tmp"

echo "Summary: downloaded=$downloaded skipped=$skipped failed=$failed"

if (( failed > 0 )); then
  exit 1
fi
