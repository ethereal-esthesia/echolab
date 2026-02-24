#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage: ./pull.sh [options]

Pulls both:
1) git updates from remote
2) Dropbox asset files via ./sync_to_dropbox.sh --pull

Options:
  --git-only            Run only git pull.
  --dropbox-only        Run only Dropbox pull.
  --git-remote NAME     Git remote (default: origin).
  --git-branch NAME     Git branch (default: current branch).
  --rebase              Use git pull --rebase (default is --ff-only).
  --dropbox-path PATH   Dropbox root path for asset pull.
  --dropbox-dest DIR    Local destination root for Dropbox pull.
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
git_rebase=0
dropbox_src=""
dropbox_dest=""
state_file=""
config_file=""
assume_yes=0
dry_run=0

load_project_dropbox_env() {
  local env_file="$SCRIPT_DIR/.secrets/dropbox.env"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
}

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

resolve_dropbox_auth_envs() {
  local cfg="$1"
  dropbox_token_env_name="DROPBOX_ACCESS_TOKEN"
  dropbox_refresh_env_name="DROPBOX_REFRESH_TOKEN"
  dropbox_app_key_env_name="DROPBOX_APP_KEY"
  dropbox_app_secret_env_name="DROPBOX_APP_SECRET"
  if [[ -f "$cfg" ]]; then
    token_env_cfg="$(parse_toml_string "token_env" "$cfg" || true)"
    [[ -n "${token_env_cfg:-}" ]] && dropbox_token_env_name="$token_env_cfg"
    refresh_env_cfg="$(parse_toml_string "refresh_token_env" "$cfg" || true)"
    [[ -n "${refresh_env_cfg:-}" ]] && dropbox_refresh_env_name="$refresh_env_cfg"
    app_key_env_cfg="$(parse_toml_string "app_key_env" "$cfg" || true)"
    [[ -n "${app_key_env_cfg:-}" ]] && dropbox_app_key_env_name="$app_key_env_cfg"
    app_secret_env_cfg="$(parse_toml_string "app_secret_env" "$cfg" || true)"
    [[ -n "${app_secret_env_cfg:-}" ]] && dropbox_app_secret_env_name="$app_secret_env_cfg"
  fi
}

has_dropbox_auth() {
  local token_val refresh_val app_key_val app_secret_val
  token_val="${!dropbox_token_env_name:-}"
  if [[ -n "$token_val" ]]; then
    return 0
  fi
  refresh_val="${!dropbox_refresh_env_name:-}"
  app_key_val="${!dropbox_app_key_env_name:-}"
  app_secret_val="${!dropbox_app_secret_env_name:-}"
  [[ -n "$refresh_val" && -n "$app_key_val" && -n "$app_secret_val" ]]
}

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
    --rebase)
      git_rebase=1
      shift
      ;;
    --dropbox-path)
      [[ $# -ge 2 ]] || { echo "error: $1 requires a value" >&2; exit 2; }
      dropbox_src="$2"
      shift 2
      ;;
    --dropbox-dest)
      [[ $# -ge 2 ]] || { echo "error: --dropbox-dest requires a value" >&2; exit 2; }
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

load_project_dropbox_env

if [[ "$run_dropbox" -eq 1 ]]; then
  cfg_path="$SCRIPT_DIR/dropbox.toml"
  [[ -n "$config_file" ]] && cfg_path="$config_file"
  resolve_dropbox_auth_envs "$cfg_path"
  if ! has_dropbox_auth; then
    echo "warning: Dropbox credentials are not configured." >&2
    echo "warning: Expected $dropbox_token_env_name or ($dropbox_refresh_env_name + $dropbox_app_key_env_name + $dropbox_app_secret_env_name)." >&2
    echo "warning: Skipping Dropbox pull step. See README section 'Dropbox API Setup' for instructions." >&2
    run_dropbox=0
  fi
fi

if [[ "$run_git" -eq 1 ]]; then
  if [[ -z "$git_branch" ]]; then
    git_branch="$(git rev-parse --abbrev-ref HEAD)"
  fi
  if [[ "$git_rebase" -eq 1 ]]; then
    echo "[git] pull --rebase $git_remote $git_branch"
    if [[ "$dry_run" -eq 0 ]]; then
      git pull --rebase "$git_remote" "$git_branch"
    fi
  else
    echo "[git] pull --ff-only $git_remote $git_branch"
    if [[ "$dry_run" -eq 0 ]]; then
      git pull --ff-only "$git_remote" "$git_branch"
    fi
  fi
fi

if [[ "$run_dropbox" -eq 1 ]]; then
  dropbox_args=(--pull)
  [[ -n "$dropbox_src" ]] && dropbox_args+=(--src "$dropbox_src")
  [[ -n "$dropbox_dest" ]] && dropbox_args+=(--dest "$dropbox_dest")
  [[ -n "$state_file" ]] && dropbox_args+=(--state-file "$state_file")
  [[ -n "$config_file" ]] && dropbox_args+=(--config "$config_file")
  preview_args=(--pull --dry-run)
  [[ -n "$dropbox_src" ]] && preview_args+=(--src "$dropbox_src")
  [[ -n "$dropbox_dest" ]] && preview_args+=(--dest "$dropbox_dest")
  [[ -n "$state_file" ]] && preview_args+=(--state-file "$state_file")
  [[ -n "$config_file" ]] && preview_args+=(--config "$config_file")
  echo "[dropbox] preview: ./sync_to_dropbox.sh ${preview_args[*]}"
  preview_output="$(./sync_to_dropbox.sh "${preview_args[@]}")"
  printf "%s\n" "$preview_output" | sed -n '/^download: /p'
  changed_count="$(printf "%s\n" "$preview_output" | grep -c '^download: ' || true)"
  if [[ "$changed_count" -eq 0 ]]; then
    echo "[dropbox] no file changes to pull."
    exit 0
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    exit 0
  fi

  if [[ "$assume_yes" -eq 0 ]]; then
    if [[ -t 0 ]]; then
      printf "Run Dropbox pull for %s file(s)? [y/N] " "$changed_count" >&2
      read -r reply || true
      case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *)
          echo "Skipped Dropbox pull." >&2
          exit 0
          ;;
      esac
    else
      echo "error: Dropbox pull confirmation required (non-interactive shell). Use --yes." >&2
      exit 2
    fi
  fi

  echo "[dropbox] run: ./sync_to_dropbox.sh ${dropbox_args[*]}"
  ./sync_to_dropbox.sh "${dropbox_args[@]}"
fi
