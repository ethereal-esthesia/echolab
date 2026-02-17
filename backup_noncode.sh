#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage: ./backup_noncode.sh [--dest DIR] [--include-archive] [--whole-project] [--zip-overwrite] [--dry-run]

Creates a timestamped .tar.gz backup of non-code project assets.

Options:
  --dest DIR          Backup destination directory.
                      Default: auto-detect Dropbox:
                        1) ~/Library/CloudStorage/Dropbox
                        2) ~/Dropbox
                      Then uses "<dropbox>/echolab_backups".
  --include-archive   Include ./archive in backup (off by default).
  --whole-project     Backup the whole project folder (excludes .git and target).
  --zip-overwrite     Write/replace "<dest>/echolab_latest.zip" each run.
  --dry-run           Show what would be backed up without creating archive.
  -h, --help          Show help.
EOF
}

dest_root=""
include_archive=0
whole_project=0
zip_overwrite=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || { echo "error: --dest requires a path" >&2; exit 2; }
      dest_root="$2"
      shift 2
      ;;
    --include-archive)
      include_archive=1
      shift
      ;;
    --whole-project)
      whole_project=1
      shift
      ;;
    --zip-overwrite)
      zip_overwrite=1
      shift
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

if [[ -z "$dest_root" ]]; then
  if [[ -d "$HOME/Library/CloudStorage/Dropbox" ]]; then
    dest_root="$HOME/Library/CloudStorage/Dropbox/echolab_backups"
  elif [[ -d "$HOME/Dropbox" ]]; then
    dest_root="$HOME/Dropbox/echolab_backups"
  else
    echo "error: Dropbox folder not found. Provide --dest DIR." >&2
    exit 1
  fi
fi

echo "Backup source: $SCRIPT_DIR"
echo "Backup target dir: $dest_root"
if [[ "$whole_project" -eq 1 ]]; then
  echo "Included paths:"
  echo "  - . (whole project)"
  echo "Excluded paths:"
  echo "  - .git/"
  echo "  - target/"
else
  items=(
    "assets/roms"
    "screenshots"
    "echolab.toml"
  )

  if [[ "$include_archive" -eq 1 ]]; then
    items+=("archive")
  fi

  existing=()
  for item in "${items[@]}"; do
    if [[ -e "$item" ]]; then
      existing+=("$item")
    fi
  done

  if [[ "${#existing[@]}" -eq 0 ]]; then
    echo "error: no backup targets found." >&2
    exit 1
  fi

  printf 'Included paths:\n'
  for item in "${existing[@]}"; do
    echo "  - $item"
  done
fi

if [[ "$dry_run" -eq 1 ]]; then
  echo "Dry run complete."
  exit 0
fi

mkdir -p "$dest_root"
timestamp="$(date '+%Y%m%d_%H%M%S')"

if [[ "$zip_overwrite" -eq 1 ]]; then
  if ! command -v zip >/dev/null 2>&1; then
    echo "error: zip command not found." >&2
    exit 1
  fi
  out_file="$dest_root/echolab_latest.zip"
  rm -f "$out_file"
  if [[ "$whole_project" -eq 1 ]]; then
    zip -qry "$out_file" . -x ".git/*" "target/*"
  else
    zip -qry "$out_file" "${existing[@]}"
  fi
else
  out_file="$dest_root/echolab_noncode_${timestamp}.tar.gz"
  if [[ "$whole_project" -eq 1 ]]; then
    tar -czf "$out_file" --exclude=.git --exclude=target .
  else
    tar -czf "$out_file" "${existing[@]}"
  fi
fi

echo "Backup created: $out_file"
