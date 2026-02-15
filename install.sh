#!/bin/bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    -f|--force)
      FORCE=1
      ;;
    -h|--help)
      echo "Usage: ./install.sh [--force]"
      echo "  --force  Continue even if potentially conflicting toolchain managers are detected."
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: ./install.sh [--force]"
      exit 1
      ;;
  esac
done

OS="$(uname -s)"

warn_on_toolchain_conflicts() {
  local detected=()

  command -v nix >/dev/null 2>&1 && detected+=("Nix (nix)")
  command -v nix-env >/dev/null 2>&1 && detected+=("Nix (nix-env)")
  command -v conda >/dev/null 2>&1 && detected+=("Conda (conda)")
  command -v mamba >/dev/null 2>&1 && detected+=("Conda/Mamba (mamba)")
  command -v pixi >/dev/null 2>&1 && detected+=("Pixi (pixi)")

  if [[ "$OS" == "Darwin" ]]; then
    command -v port >/dev/null 2>&1 && detected+=("MacPorts (port)")
    command -v fink >/dev/null 2>&1 && detected+=("Fink (fink)")
  fi

  if [[ ${#detected[@]} -eq 0 ]]; then
    return 0
  fi

  echo "WARNING: Potentially conflicting toolchain/package manager detected:"
  printf '  - %s\n' "${detected[@]}"
  echo "These can override PATH or dependencies used by this setup."

  if [[ "$FORCE" -ne 1 ]]; then
    echo "Aborting. Re-run with --force to continue anyway."
    exit 2
  fi

  echo "Continuing because --force was provided."
}

ensure_brew_on_path() {
  if [[ -d "/opt/homebrew/bin" && ":$PATH:" != *":/opt/homebrew/bin:"* ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
  elif [[ -d "/usr/local/bin" && ":$PATH:" != *":/usr/local/bin:"* ]]; then
    export PATH="/usr/local/bin:$PATH"
  fi
}

install_build_deps_macos() {
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
  else
    echo "Xcode Command Line Tools already installed."
  fi

  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "Homebrew already installed."
  fi

  ensure_brew_on_path

  echo "Installing build dependencies with Homebrew..."
  brew update
  brew install pkg-config cmake
}

install_build_deps_linux() {
  echo "Installing build dependencies for Linux..."

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y build-essential pkg-config cmake curl ca-certificates
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y gcc gcc-c++ make pkgconf-pkg-config cmake curl ca-certificates
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y gcc gcc-c++ make pkgconfig cmake curl ca-certificates
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --needed --noconfirm base-devel pkgconf cmake curl ca-certificates
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper --non-interactive install -y gcc gcc-c++ make pkg-config cmake curl ca-certificates
  elif command -v apk >/dev/null 2>&1; then
    sudo apk add --no-cache build-base pkgconfig cmake curl ca-certificates
  else
    echo "Unsupported Linux distribution/package manager."
    echo "Install these manually: compiler toolchain, pkg-config/pkgconf, cmake, curl, ca-certificates"
    exit 1
  fi
}

install_or_update_rust() {
  local shell_profile

  if ! command -v rustup >/dev/null 2>&1; then
    echo "Installing Rust toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  fi

  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
  fi

  if [[ "$OS" == "Darwin" ]]; then
    shell_profile="$HOME/.zprofile"
  else
    shell_profile="$HOME/.profile"
  fi

  if ! grep -q 'source "$HOME/.cargo/env"' "$shell_profile" 2>/dev/null; then
    echo 'source "$HOME/.cargo/env"' >> "$shell_profile"
  fi

  if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1; then
    echo "Rust toolchain not found in PATH. Run: source $HOME/.cargo/env"
    exit 1
  fi

  echo "Updating Rust toolchain..."
  rustup update
}

add_platform_targets() {
  if [[ "$OS" == "Darwin" ]]; then
    echo "Adding macOS Rust targets..."
    rustup target add x86_64-apple-darwin aarch64-apple-darwin
  elif [[ "$OS" == "Linux" ]]; then
    echo "Linux host detected; skipping extra default Rust targets."
  fi
}

maybe_add_metal_crates() {
  if [[ "$OS" != "Darwin" ]]; then
    echo "Skipping Metal crates on non-macOS platforms."
    return 0
  fi

  if [[ -f "Cargo.toml" ]]; then
    cargo add metal objc
  fi
}

warn_on_toolchain_conflicts

case "$OS" in
  Darwin)
    install_build_deps_macos
    ;;
  Linux)
    install_build_deps_linux
    ;;
  *)
    echo "Unsupported OS: $OS"
    echo "This installer currently supports macOS and Linux."
    exit 1
    ;;
esac

install_or_update_rust
add_platform_targets
maybe_add_metal_crates

echo "Setup complete."
echo "Verify: cargo --version && rustc --version"
