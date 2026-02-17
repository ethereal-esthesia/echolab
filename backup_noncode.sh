#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage: ./backup_noncode.sh [--dest DIR] [--include-archive] [--whole-project] [--zip-overwrite] [--config FILE] [--dry-run] [--list-only]

Creates a timestamped .tar.gz backup of non-code project assets.
Backups exclude all git-tracked files and require a clean git working tree.

Options:
  --dest DIR          Backup destination directory.
                      Default: auto-detect Dropbox:
                        1) ~/Library/CloudStorage/Dropbox
                        2) ~/Dropbox
                      Then uses "<dropbox>/<backup_folder_name>" from config.
  --include-archive   Include ./archive in backup (off by default).
  --whole-project     Backup the whole project folder (excludes .git and target).
  --zip-overwrite     Write/replace "<dest>/echolab_latest.zip" each run.
  --config FILE       Dropbox config file path (default: ./dropbox.toml).
  --dry-run           Show what would be backed up without creating archive.
  --list-only         Print files that would be backed up, then exit.
  -h, --help          Show help.
EOF
}

dest_root=""
include_archive=0
whole_project=0
zip_overwrite=0
config_file="$SCRIPT_DIR/dropbox.toml"
dry_run=0
list_only=0
exclude_patterns=()
git_excludes=()
backup_folder_name="echolab_backups"
nested_git_roots=()
queue_file="$SCRIPT_DIR/.backup_state/nested_git_repos.queue"

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
    --config)
      [[ $# -ge 2 ]] || { echo "error: --config requires a path" >&2; exit 2; }
      config_file="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --list-only)
      list_only=1
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

parse_exclude_patterns() {
  local path="$1"
  awk '
    BEGIN { in_exclude = 0 }
    {
      line = $0
      sub(/[[:space:]]*#.*/, "", line)
      if (line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*$/) {
        in_exclude = (line ~ /^[[:space:]]*\[exclude\][[:space:]]*$/)
        next
      }
      if (in_exclude && line ~ /=/) {
        sub(/^[[:space:]]*[^=]+=[[:space:]]*/, "", line)
        gsub(/^"/, "", line)
        gsub(/"$/, "", line)
        if (length(line) > 0) {
          print line
        }
      }
    }
  ' "$path"
}

ensure_clean_git() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: backup_noncode.sh must run inside a git repository." >&2
    exit 1
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: git working tree is not clean. Commit/stash changes before backup." >&2
    exit 1
  fi
}

load_git_tracked_excludes() {
  while IFS= read -r tracked; do
    [[ -n "$tracked" ]] && git_excludes+=("$tracked")
  done < <(git ls-files)
}

detect_nested_git_repos() {
  while IFS= read -r git_dir; do
    repo_root="${git_dir%/.git}"
    repo_root="${repo_root#./}"
    if [[ -n "$repo_root" && "$repo_root" != "." ]]; then
      nested_git_roots+=("$repo_root")
    fi
  done < <(find . -type d -name .git -prune)
}

queue_nested_git_repos() {
  mkdir -p "$(dirname "$queue_file")"
  : > "$queue_file"
  for repo_root in "${nested_git_roots[@]}"; do
    printf "%s\n" "$repo_root" >> "$queue_file"
  done
}

should_exclude_file() {
  local rel="$1"

  for tracked in "${git_excludes[@]}"; do
    if [[ "$rel" == "$tracked" || "$rel" == "$tracked/"* ]]; then
      return 0
    fi
  done

  for pattern in "${exclude_patterns[@]}"; do
    if [[ "$rel" == $pattern ]]; then
      return 0
    fi
  done

  for repo_root in "${nested_git_roots[@]}"; do
    if [[ "$rel" == "$repo_root/.git" || "$rel" == "$repo_root/.git/"* ]]; then
      return 0
    fi
  done

  return 1
}

collect_candidate_files() {
  local root="$1"
  if [[ -f "$root" ]]; then
    printf "%s\n" "$root"
    return
  fi
  if [[ -d "$root" ]]; then
    find "$root" -type d -name .git -prune -o -type f -print
  fi
}

ensure_clean_git
load_git_tracked_excludes
detect_nested_git_repos

if [[ -f "$config_file" ]]; then
  if [[ -z "$dest_root" ]]; then
    configured_dest="$(parse_toml_string "default_backup_dir" "$config_file" || true)"
    if [[ -n "${configured_dest:-}" ]]; then
      dest_root="$configured_dest"
    fi
  fi
  configured_folder="$(parse_toml_string "backup_folder_name" "$config_file" || true)"
  if [[ -n "${configured_folder:-}" ]]; then
    backup_folder_name="$configured_folder"
  fi
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] && exclude_patterns+=("$pattern")
  done < <(parse_exclude_patterns "$config_file")
fi

if [[ -z "$dest_root" ]]; then
  if [[ -d "$HOME/Library/CloudStorage/Dropbox" ]]; then
    dest_root="$HOME/Library/CloudStorage/Dropbox/$backup_folder_name"
  elif [[ -d "$HOME/Dropbox" ]]; then
    dest_root="$HOME/Dropbox/$backup_folder_name"
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

if [[ "${#exclude_patterns[@]}" -gt 0 ]]; then
  echo "Config excludes:"
  for pattern in "${exclude_patterns[@]}"; do
    echo "  - $pattern"
  done
fi
echo "Git-tracked excludes: ${#git_excludes[@]} paths"
if [[ "${#nested_git_roots[@]}" -gt 0 ]]; then
  echo "Nested git repos detected (${#nested_git_roots[@]}):"
  for repo_root in "${nested_git_roots[@]}"; do
    echo "  - $repo_root"
  done
else
  echo "Nested git repos detected: 0"
fi

if [[ "$list_only" -eq 1 ]]; then
  echo "Scheduled files:"
  if [[ "$whole_project" -eq 1 ]]; then
    while IFS= read -r f; do
      rel="${f#./}"
      should_exclude_file "$rel" && continue
      echo "$rel"
    done < <(find . -type d \( -name .git -o -name target \) -prune -o -type f -print | sort)
  else
    for item in "${existing[@]}"; do
      while IFS= read -r f; do
        should_exclude_file "$f" && continue
        echo "$f"
      done < <(collect_candidate_files "$item" | sort)
    done
  fi
  exit 0
fi

if [[ "$dry_run" -eq 1 ]]; then
  if [[ "${#nested_git_roots[@]}" -gt 0 ]]; then
    echo "Dry run: would queue nested repos in $queue_file"
  fi
  echo "Dry run complete."
  exit 0
fi

mkdir -p "$dest_root"
queue_nested_git_repos
if [[ "${#nested_git_roots[@]}" -gt 0 ]]; then
  echo "Nested repo queue written: $queue_file"
fi
timestamp="$(date '+%Y%m%d_%H%M%S')"

if [[ "$zip_overwrite" -eq 1 ]]; then
  if ! command -v zip >/dev/null 2>&1; then
    echo "error: zip command not found." >&2
    exit 1
  fi
  out_file="$dest_root/echolab_latest.zip"
  rm -f "$out_file"
  if [[ "$whole_project" -eq 1 ]]; then
    zip_excludes=(".git/*" "target/*")
    for repo_root in "${nested_git_roots[@]}"; do
      zip_excludes+=("$repo_root/.git/*")
    done
    for tracked in "${git_excludes[@]}"; do
      zip_excludes+=("$tracked")
    done
    for pattern in "${exclude_patterns[@]}"; do
      zip_excludes+=("$pattern")
    done
    zip -ry "$out_file" . -x "${zip_excludes[@]}"
  else
    zip_excludes=()
    for tracked in "${git_excludes[@]}"; do
      zip_excludes+=("$tracked")
    done
    for pattern in "${exclude_patterns[@]}"; do
      zip_excludes+=("$pattern")
    done
    if [[ "${#exclude_patterns[@]}" -gt 0 ]]; then
      zip -ry "$out_file" "${existing[@]}" -x "${zip_excludes[@]}"
    else
      if [[ "${#zip_excludes[@]}" -gt 0 ]]; then
        zip -ry "$out_file" "${existing[@]}" -x "${zip_excludes[@]}"
      else
        zip -ry "$out_file" "${existing[@]}"
      fi
    fi
  fi
else
  out_file="$dest_root/echolab_noncode_${timestamp}.tar.gz"
  tar_excludes=()
  for repo_root in "${nested_git_roots[@]}"; do
    tar_excludes+=(--exclude="$repo_root/.git" --exclude="$repo_root/.git/*")
  done
  for tracked in "${git_excludes[@]}"; do
    tar_excludes+=(--exclude="$tracked")
  done
  for pattern in "${exclude_patterns[@]}"; do
    tar_excludes+=(--exclude="$pattern")
  done
  if [[ "$whole_project" -eq 1 ]]; then
    tar -czvf "$out_file" --exclude=.git --exclude=target "${tar_excludes[@]}" .
  else
    tar -czvf "$out_file" "${tar_excludes[@]}" "${existing[@]}"
  fi
fi

echo "Backup created: $out_file"
