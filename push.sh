#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage: ./push.sh [options]

Pushes both:
1) git changes to remote
2) non-code files to Dropbox via ./sync_to_dropbox.sh

Options:
  --git-only            Run only git push.
  --dropbox-only        Run only Dropbox push.
  --git-remote NAME     Git remote (default: origin).
  --git-branch NAME     Git branch (default: current branch).
  --dropbox-path PATH   Dropbox root path for non-code push.
  --state-file FILE     Shared local sync timestamp file.
  --config FILE         Dropbox config file path.
  --yes                 Skip Dropbox y/N confirmation prompt.
  --dry-run             Print actions; Dropbox side runs in --dry-run mode.
  -h, --help            Show help.
EOF
}

run_git=1
run_dropbox=1
git_remote="origin"
git_branch=""
dropbox_dest=""
state_file=""
config_file=""
assume_yes=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --git-only)
      run_git=1
      run_dropbox=0
      shift
      ;;
    --dropbox-only)
      run_git=0
      run_dropbox=1
      shift
      ;;
    --git-remote)
      [[ $# -ge 2 ]] || { echo "error: --git-remote requires a value" >&2; exit 2; }
      git_remote="$2"
      shift 2
      ;;
    --git-branch)
      [[ $# -ge 2 ]] || { echo "error: --git-branch requires a value" >&2; exit 2; }
      git_branch="$2"
      shift 2
      ;;
    --dropbox-path)
      [[ $# -ge 2 ]] || { echo "error: $1 requires a value" >&2; exit 2; }
      dropbox_dest="$2"
      shift 2
      ;;
    --state-file)
      [[ $# -ge 2 ]] || { echo "error: --state-file requires a value" >&2; exit 2; }
      state_file="$2"
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || { echo "error: --config requires a value" >&2; exit 2; }
      config_file="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --yes)
      assume_yes=1
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

if [[ "$run_dropbox" -eq 1 ]]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: Dropbox push flow requires running inside a git repository." >&2
    exit 1
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: git working tree is not clean. Commit/stash changes before Dropbox push." >&2
    exit 1
  fi
fi

if [[ "$run_git" -eq 1 ]]; then
  if [[ -z "$git_branch" ]]; then
    git_branch="$(git rev-parse --abbrev-ref HEAD)"
  fi
  echo "[git] push $git_remote $git_branch"
  if [[ "$dry_run" -eq 0 ]]; then
    git push "$git_remote" "$git_branch"
  fi
fi

if [[ "$run_dropbox" -eq 1 ]]; then
  dropbox_cmd=(./sync_to_dropbox.sh)
  [[ -n "$dropbox_dest" ]] && dropbox_cmd+=(--dest "$dropbox_dest")
  [[ -n "$state_file" ]] && dropbox_cmd+=(--state-file "$state_file")
  [[ -n "$config_file" ]] && dropbox_cmd+=(--config "$config_file")

  preview_cmd=(./sync_to_dropbox.sh --dry-run)
  [[ -n "$dropbox_dest" ]] && preview_cmd+=(--dest "$dropbox_dest")
  [[ -n "$state_file" ]] && preview_cmd+=(--state-file "$state_file")
  [[ -n "$config_file" ]] && preview_cmd+=(--config "$config_file")
  echo "[dropbox] preview: ${preview_cmd[*]}"
  preview_output="$("${preview_cmd[@]}")"
  printf "%s\n" "$preview_output" | sed -n '/^upload: /p'
  changed_count="$(printf "%s\n" "$preview_output" | grep -c '^upload: ' || true)"
  if [[ "$changed_count" -eq 0 ]]; then
    echo "[dropbox] no file changes to push."
    exit 0
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    exit 0
  fi

  if [[ "$assume_yes" -eq 0 ]]; then
    if [[ -t 0 ]]; then
      printf "Run Dropbox push for %s file(s)? [y/N] " "$changed_count" >&2
      read -r reply || true
      case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *)
          echo "Skipped Dropbox push." >&2
          exit 0
          ;;
      esac
    else
      echo "error: Dropbox push confirmation required (non-interactive shell). Use --yes." >&2
      exit 2
    fi
  fi

  echo "[dropbox] run: ${dropbox_cmd[*]}"
  "${dropbox_cmd[@]}"
fi
