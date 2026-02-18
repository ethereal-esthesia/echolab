#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage: ./backup_non_git.sh [--dest DIR] [--whole-project] [--zip-overwrite] [--config FILE] [--dry-run] [--list-only]

Creates a timestamped .tar.gz backup of non-git project assets.
Backups exclude all git-tracked files and require a clean git working tree.

Options:
  --dest DIR          Backup destination directory.
                      Default: "default_backup_dir" from config,
                      else "./.backups/<backup_folder_name>".
  --whole-project     Backup the whole project folder (excludes .git and target).
  --zip-overwrite     Write/replace "<dest>/echolab_latest.zip" each run.
  --config FILE       Dropbox config file path (default: ./dropbox.toml).
  --dry-run           Show what would be backed up without creating archive.
  --list-only         Print files that would be backed up, then exit.
  -h, --help          Show help.
EOF
}

dest_root=""
whole_project=0
zip_overwrite=0
config_file="$SCRIPT_DIR/dropbox.toml"
dry_run=0
list_only=0
exclude_patterns=()
git_excludes=()
backup_folder_name="echolab_backups"
git_projects=()
nested_git_roots=()
queue_file="$SCRIPT_DIR/.backup_state/nested_git_repos.queue"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || { echo "error: --dest requires a path" >&2; exit 2; }
      dest_root="$2"
      shift 2
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
    echo "error: backup_non_git.sh must run inside a git repository." >&2
    exit 1
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: git working tree is not clean. Commit/stash changes before backup." >&2
    exit 1
  fi
}

discover_git_projects() {
  while IFS= read -r repo_root; do
    [[ -n "$repo_root" ]] && git_projects+=("$repo_root")
  done < <(
    find . -type d -name .git -prune \
      | awk '
          {
            d=$0
            if (d=="./.git") {
              print "."
            } else {
              sub(/^.\//, "", d)
              sub(/\/.git$/, "", d)
              print d
            }
          }
        ' \
      | awk '{ print length, $0 }' \
      | sort -n -k1,1 -k2,2 \
      | awk '{ $1=""; sub(/^ /,""); print }'
  )
}

load_git_tracked_excludes() {
  for repo_root in "${git_projects[@]}"; do
    while IFS= read -r tracked; do
      [[ -n "$tracked" ]] || continue
      if [[ "$repo_root" == "." ]]; then
        git_excludes+=("$tracked")
      else
        git_excludes+=("$repo_root/$tracked")
      fi
    done < <(git -C "$repo_root" ls-files 2>/dev/null || true)
  done
}

build_nested_git_roots() {
  nested_git_roots=()
  for repo_root in "${git_projects[@]}"; do
    if [[ "$repo_root" != "." ]]; then
      nested_git_roots+=("$repo_root")
    fi
  done
}

queue_nested_git_repos() {
  mkdir -p "$(dirname "$queue_file")"
  : > "$queue_file"
  for repo_root in "${nested_git_roots[@]}"; do
    printf "%s\n" "$repo_root" >> "$queue_file"
  done
}

path_is_under() {
  local child="$1"
  local parent="$2"
  if [[ "$parent" == "." ]]; then
    return 0
  fi
  [[ "$child" == "$parent" || "$child" == "$parent/"* ]]
}

collect_project_scan_roots() {
  local repo_root="$1"
  local roots=()
  local candidate

  if [[ "$whole_project" -eq 1 ]]; then
    roots+=("$repo_root")
  else
    for candidate in "${existing[@]}"; do
      if path_is_under "$candidate" "$repo_root"; then
        roots+=("$candidate")
      elif path_is_under "$repo_root" "$candidate"; then
        roots+=("$repo_root")
      fi
    done
  fi

  if [[ "${#roots[@]}" -eq 0 ]]; then
    return
  fi
  printf "%s\n" "${roots[@]}" | awk 'NF' | sort -u
}

collect_project_files() {
  local repo_root="$1"
  local scan_root
  local other_repo
  local prune_expr=()
  local first=1

  for other_repo in "${git_projects[@]}"; do
    [[ "$other_repo" == "$repo_root" ]] && continue
    if path_is_under "$other_repo" "$repo_root"; then
      if [[ "$first" -eq 0 ]]; then
        prune_expr+=(-o)
      fi
      prune_expr+=(-path "$other_repo")
      first=0
    fi
  done

  while IFS= read -r scan_root; do
    [[ -n "$scan_root" ]] || continue
    if [[ -f "$scan_root" ]]; then
      printf "%s\n" "$scan_root"
      continue
    fi
    if [[ ! -d "$scan_root" ]]; then
      continue
    fi

    if [[ "${#prune_expr[@]}" -gt 0 ]]; then
      find "$scan_root" \
        \( -name .git -o "${prune_expr[0]}" "${prune_expr[@]:1}" \) -prune -o \
        -type f -print
    else
      find "$scan_root" \
        \( -name .git \) -prune -o \
        -type f -print
    fi
  done < <(collect_project_scan_roots "$repo_root")

  return 0
}

run_project_list_only() {
  local repo_root="$1"
  local rel
  echo "Project run: $repo_root"

  while IFS= read -r f; do
    rel="${f#./}"
    should_exclude_file "$rel" && continue
    print_scheduled_file "$rel"
  done < <(collect_project_files "$repo_root" | sort -u)

  return 0
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

file_size_bytes() {
  local path="$1"
  if stat -f %z "$path" >/dev/null 2>&1; then
    stat -f %z "$path"
  else
    stat -c %s "$path"
  fi
}

human_size() {
  local bytes="$1"
  local units=("B" "KB" "MB" "GB" "TB")
  local idx=0
  local value="$bytes"
  while (( value >= 1024 && idx < ${#units[@]} - 1 )); do
    value=$((value / 1024))
    idx=$((idx + 1))
  done
  printf "%s %s" "$value" "${units[$idx]}"
}

print_scheduled_file() {
  local rel="$1"
  local abs="$SCRIPT_DIR/$rel"
  if [[ ! -f "$abs" ]]; then
    return
  fi
  local bytes
  bytes="$(file_size_bytes "$abs")"
  local human
  human="$(human_size "$bytes")"
  printf "  [%10s] %s\n" "$human" "$rel"
}

ensure_clean_git
discover_git_projects
load_git_tracked_excludes
build_nested_git_roots

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
  dest_root="$SCRIPT_DIR/.backups/$backup_folder_name"
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
    "archive"
  )

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
  for repo_root in "${git_projects[@]}"; do
    run_project_list_only "$repo_root"
  done
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
  out_file="$dest_root/echolab_non_git_${timestamp}.tar.gz"
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
