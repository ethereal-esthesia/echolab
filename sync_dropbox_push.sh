#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'USAGE'
Usage: ./sync_dropbox_push.sh [--dest PATH] [--config FILE] [--state-file FILE] [--dry-run]

Uploads scheduled Dropbox files individually to Dropbox API, preserving relative paths.
Push decision uses one local sync timestamp file:
- Upload when local file mtime > last_sync_ts from --state-file.

Options:
  --dest PATH       Dropbox destination root (default: /<sync_folder_name>).
  --config FILE     Config file path (default: ./dropbox.toml).
  --state-file FILE Local timestamp state file (default: .backup_state/dropbox_last_sync_time).
  --dry-run         Show what would upload without sending data.
  -h, --help        Show help.
USAGE
}

dest_root=""
config_file="$SCRIPT_DIR/dropbox.toml"
state_file="$SCRIPT_DIR/.backup_state/dropbox_last_sync_time"
dry_run=0
sync_folder_name="echolab_sync"
token_env_name="DROPBOX_ACCESS_TOKEN"
refresh_token_env_name="DROPBOX_REFRESH_TOKEN"
app_key_env_name="DROPBOX_APP_KEY"
app_secret_env_name="DROPBOX_APP_SECRET"

load_project_dropbox_env() {
  local env_file="$SCRIPT_DIR/.secrets/dropbox.env"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
}

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
    --state-file)
      [[ $# -ge 2 ]] || { echo "error: --state-file requires a path" >&2; exit 2; }
      state_file="$2"
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

load_project_dropbox_env

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

if [[ -f "$config_file" ]]; then
  token_env_name_cfg="$(parse_toml_string "token_env" "$config_file" || true)"
  [[ -n "${token_env_name_cfg:-}" ]] && token_env_name="$token_env_name_cfg"
  refresh_env_cfg="$(parse_toml_string "refresh_token_env" "$config_file" || true)"
  [[ -n "${refresh_env_cfg:-}" ]] && refresh_token_env_name="$refresh_env_cfg"
  app_key_env_cfg="$(parse_toml_string "app_key_env" "$config_file" || true)"
  [[ -n "${app_key_env_cfg:-}" ]] && app_key_env_name="$app_key_env_cfg"
  app_secret_env_cfg="$(parse_toml_string "app_secret_env" "$config_file" || true)"
  [[ -n "${app_secret_env_cfg:-}" ]] && app_secret_env_name="$app_secret_env_cfg"
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

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl is required for Dropbox API upload." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required for Dropbox token parsing." >&2
  exit 1
fi

resolve_access_token() {
  local direct_token refresh_token app_key app_secret oauth_resp oauth_token
  direct_token="${!token_env_name:-}"
  if [[ -n "$direct_token" ]]; then
    dropbox_token="$direct_token"
    auth_mode="access-token"
    return 0
  fi

  refresh_token="${!refresh_token_env_name:-}"
  app_key="${!app_key_env_name:-}"
  app_secret="${!app_secret_env_name:-}"
  if [[ -z "$refresh_token" || -z "$app_key" || -z "$app_secret" ]]; then
    echo "error: Dropbox credentials missing. Set $token_env_name or ($refresh_token_env_name + $app_key_env_name + $app_secret_env_name)." >&2
    return 1
  fi

  oauth_resp="$(curl -sS -f -X POST "https://api.dropboxapi.com/oauth2/token" \
    --data-urlencode "grant_type=refresh_token" \
    --data-urlencode "refresh_token=$refresh_token" \
    --data-urlencode "client_id=$app_key" \
    --data-urlencode "client_secret=$app_secret")" || {
    echo "error: failed to exchange Dropbox refresh token for access token." >&2
    return 1
  }

  oauth_token="$(printf "%s" "$oauth_resp" | python3 -c 'import json,sys; obj=json.load(sys.stdin); print(obj.get("access_token",""))' 2>/dev/null || true)"
  if [[ -z "$oauth_token" ]]; then
    echo "error: Dropbox OAuth exchange response missing access_token." >&2
    return 1
  fi

  dropbox_token="$oauth_token"
  auth_mode="refresh-token"
  return 0
}

dropbox_token=""
auth_mode=""
resolve_access_token

last_sync_ts=0
if [[ -f "$state_file" ]]; then
  read -r last_sync_ts < "$state_file" || true
  [[ "$last_sync_ts" =~ ^[0-9]+$ ]] || last_sync_ts=0
fi

list_output="$(./backup_dropbox.sh --list-only --config "$config_file" --dest /tmp/echolab_backups)"
rel_files=()
while IFS= read -r rel; do
  [[ -n "$rel" ]] && rel_files+=("$rel")
done < <(printf "%s\n" "$list_output" | sed -n 's/^  \[[^]]*\] \(.*\)$/\1/p')

if [[ "${#rel_files[@]}" -eq 0 ]]; then
  echo "No scheduled files found."
  exit 0
fi

echo "Dropbox destination root: $dest_root"
echo "Dropbox auth mode: $auth_mode"
if [[ "$auth_mode" == "access-token" ]]; then
  echo "Token env key: $token_env_name"
else
  echo "Refresh env keys: $refresh_token_env_name, $app_key_env_name, $app_secret_env_name"
fi
echo "State file: $state_file"
echo "Last sync ts: $last_sync_ts"
echo "Candidate files: ${#rel_files[@]}"

uploaded=0
skipped=0
failed=0
new_last_sync_ts="$last_sync_ts"

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

  if (( source_mtime <= last_sync_ts )); then
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
  upload_resp=""
  if upload_resp="$(curl -sS -f -X POST "https://content.dropboxapi.com/2/files/upload" \
    --header "Authorization: Bearer $dropbox_token" \
    --header "Dropbox-API-Arg: $api_arg" \
    --header "Content-Type: application/octet-stream" \
    --data-binary @"$abs")"; then
    if printf "%s" "$upload_resp" | grep -q '"error_summary"'; then
      echo "error: API upload failed for $rel: $upload_resp" >&2
      failed=$((failed + 1))
      continue
    fi
    server_modified="$(printf "%s" "$upload_resp" | sed -n 's/.*"server_modified"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    remote_epoch="$(iso_to_epoch "$server_modified")"
    if (( remote_epoch > new_last_sync_ts )); then
      new_last_sync_ts="$remote_epoch"
    fi
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

if [[ "$dry_run" -eq 0 ]]; then
  mkdir -p "$(dirname "$state_file")"
  now_ts="$(date +%s)"
  if (( now_ts > new_last_sync_ts )); then
    new_last_sync_ts="$now_ts"
  fi
  printf "%s\n" "$new_last_sync_ts" > "$state_file"
fi
