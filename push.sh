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
  --dropbox-dest PATH   Dropbox destination root for non-code push.
  --state-dir DIR       State dir for non-code push.
  --remote-compare      Dropbox push: compare against remote timestamps.
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
state_dir=""
config_file=""
remote_compare=0
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
    --dropbox-dest)
      [[ $# -ge 2 ]] || { echo "error: --dropbox-dest requires a value" >&2; exit 2; }
      dropbox_dest="$2"
      shift 2
      ;;
    --state-dir)
      [[ $# -ge 2 ]] || { echo "error: --state-dir requires a value" >&2; exit 2; }
      state_dir="$2"
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || { echo "error: --config requires a value" >&2; exit 2; }
      config_file="$2"
      shift 2
      ;;
    --remote-compare)
      remote_compare=1
      shift
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
  if [[ "$assume_yes" -eq 0 ]]; then
    if [[ -t 0 ]]; then
      printf "Run Dropbox push now? [y/N] " >&2
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
  dropbox_args=()
  [[ -n "$dropbox_dest" ]] && dropbox_args+=(--dest "$dropbox_dest")
  [[ -n "$state_dir" ]] && dropbox_args+=(--state-dir "$state_dir")
  [[ -n "$config_file" ]] && dropbox_args+=(--config "$config_file")
  [[ "$remote_compare" -eq 1 ]] && dropbox_args+=(--remote-compare)
  [[ "$dry_run" -eq 1 ]] && dropbox_args+=(--dry-run)
  echo "[dropbox] ./sync_to_dropbox.sh ${dropbox_args[*]}"
  ./sync_to_dropbox.sh "${dropbox_args[@]}"
fi
