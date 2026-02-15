#!/bin/bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install it first or run ./install.sh."
  exit 1
fi

if ! brew list --cask visual-studio-code >/dev/null 2>&1; then
  echo "Installing Visual Studio Code..."
  brew install --cask visual-studio-code
else
  echo "Visual Studio Code already installed."
fi

if ! command -v code >/dev/null 2>&1; then
  if ! grep -q '/Applications/Visual Studio Code.app/Contents/Resources/app/bin' "$HOME/.zprofile" 2>/dev/null; then
    {
      echo '# VS Code CLI'
      echo 'export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$PATH"'
    } >> "$HOME/.zprofile"
  fi

  # shellcheck source=/dev/null
  source "$HOME/.zprofile" || true
fi

if ! command -v code >/dev/null 2>&1; then
  echo "'code' CLI is not available yet."
  echo "In VS Code: Cmd+Shift+P -> 'Shell Command: Install code command in PATH'"
  exit 1
fi

extensions=(
  rust-lang.rust-analyzer
  vadimcn.vscode-lldb
  tamasfe.even-better-toml
  serayuzgur.crates
)

installed_exts=$(code --list-extensions 2>/dev/null || true)
for ext in "${extensions[@]}"; do
  if ! echo "$installed_exts" | grep -qx "$ext"; then
    code --install-extension "$ext"
  fi
done

echo "VS Code setup complete."
