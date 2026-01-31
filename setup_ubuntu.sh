#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

INSTALL_NEOVIM=0
INSTALL_TMUX=0
INSTALL_ATUIN=0
INSTALL_GHOSTTY=0
INSTALL_BASE=0

APT_UPDATED=0

usage() {
  cat <<'EOF'
Usage: setup_ubuntu.sh [options]

Options:
  --install-all          Install neovim, tmux, atuin, ghostty, and base packages
  --install-neovim       Install or upgrade neovim
  --install-tmux         Install or upgrade tmux
  --install-atuin        Install or upgrade atuin
  --install-ghostty      Install or upgrade ghostty (if available via apt)
  --install-base         Install base packages (curl, git, ripgrep, fzf, xsel)
  -h, --help             Show this help
EOF
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local choice
  local options

  if [[ "$default" == "y" ]]; then
    options="[Y/n]"
  else
    options="[y/N]"
  fi

  while true; do
    read -r -p "$prompt $options " choice || true
    if [[ -z "$choice" ]]; then
      choice="$default"
    fi
    case "$choice" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
    esac
  done
}

maybe_apt_update() {
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    sudo apt-get update
    APT_UPDATED=1
  fi
}

apt_install() {
  maybe_apt_update
  sudo apt-get install -y "$@"
}

apt_has_pkg() {
  local pkg="$1"
  apt-cache show "$pkg" >/dev/null 2>&1
}

ensure_command() {
  local cmd="$1"
  local pkg="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  if prompt_yes_no "Install $pkg to provide $cmd?" "y"; then
    apt_install "$pkg"
  else
    return 1
  fi
}

copy_file() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if [[ ! -f "$src" ]]; then
    echo "Missing source file: $src"
    return 1
  fi

  if [[ -e "$dest" ]]; then
    if ! prompt_yes_no "Overwrite $label at $dest?" "y"; then
      return 0
    fi
  else
    if ! prompt_yes_no "Install $label to $dest?" "y"; then
      return 0
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
}

copy_dir() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if [[ ! -d "$src" ]]; then
    echo "Missing source directory: $src"
    return 1
  fi

  if [[ -e "$dest" ]]; then
    if ! prompt_yes_no "Overwrite $label at $dest?" "y"; then
      return 0
    fi
    rm -rf "$dest"
  else
    if ! prompt_yes_no "Install $label to $dest?" "y"; then
      return 0
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
}

diff_line_count() {
  local a="$1"
  local b="$2"

  if ! command -v diff >/dev/null 2>&1; then
    echo 0
    return 0
  fi

  if diff -q "$a" "$b" >/dev/null 2>&1; then
    echo 0
    return 0
  fi

  diff -U0 "$a" "$b" 2>/dev/null \
    | grep -E '^[+-]' \
    | grep -v '^[+-]{3} ' \
    | wc -l \
    | tr -d ' '
}

warn_large_diff() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if [[ ! -f "$src" || ! -f "$dest" ]]; then
    return 0
  fi

  local changed src_lines dest_lines max_lines ratio
  changed="$(diff_line_count "$dest" "$src")"
  src_lines="$(wc -l < "$src" | tr -d ' ')"
  dest_lines="$(wc -l < "$dest" | tr -d ' ')"
  max_lines=$(( src_lines > dest_lines ? src_lines : dest_lines ))
  if [[ "$max_lines" -eq 0 ]]; then
    max_lines=1
  fi
  ratio=$(( changed * 100 / max_lines ))

  if [[ "$changed" -ge 30 || "$ratio" -ge 40 ]]; then
    echo "WARNING: $label differs substantially from the current version at $dest."
    echo "Consider manually merging changes instead of overwriting."
  fi
}

ensure_bashrc_block() {
  local bashrc="$HOME/.bashrc"
  local block_start="# >>> configs_and_setup bash >>>"
  local block_end="# <<< configs_and_setup bash <<<"

  if [[ -f "$bashrc" ]] && grep -q "$block_start" "$bashrc"; then
    return 0
  fi

  if ! prompt_yes_no "Add configs_and_setup sourcing block to ~/.bashrc?" "y"; then
    return 0
  fi

  {
    echo ""
    echo "$block_start"
    echo 'if [ -f "$HOME/.config/bash/custom.sh" ]; then'
    echo '  . "$HOME/.config/bash/custom.sh"'
    echo "fi"
    echo "$block_end"
  } >> "$bashrc"
}

install_neovim() {
  if command -v nvim >/dev/null 2>&1; then
    if ! prompt_yes_no "Neovim already installed. Reinstall/upgrade?" "n"; then
      return 0
    fi
  else
    if ! prompt_yes_no "Install neovim?" "y"; then
      return 0
    fi
  fi
  apt_install neovim
}

install_tmux() {
  if command -v tmux >/dev/null 2>&1; then
    if ! prompt_yes_no "Tmux already installed. Reinstall/upgrade?" "n"; then
      return 0
    fi
  else
    if ! prompt_yes_no "Install tmux?" "y"; then
      return 0
    fi
  fi
  apt_install tmux
}

install_atuin() {
  if command -v atuin >/dev/null 2>&1; then
    if ! prompt_yes_no "Atuin already installed. Reinstall/upgrade?" "n"; then
      return 0
    fi
  else
    if ! prompt_yes_no "Install atuin?" "y"; then
      return 0
    fi
  fi

  if apt_has_pkg atuin; then
    apt_install atuin
    return 0
  fi

  if ! ensure_command curl curl; then
    echo "Skipping atuin install (curl not available)."
    return 0
  fi

  echo "Installing atuin via upstream install script."
  curl -fsSL https://raw.githubusercontent.com/atuinsh/atuin/main/install.sh | bash
}

install_ghostty() {
  if command -v ghostty >/dev/null 2>&1; then
    if ! prompt_yes_no "Ghostty already installed. Reinstall/upgrade?" "n"; then
      return 0
    fi
  else
    if ! prompt_yes_no "Install ghostty?" "y"; then
      return 0
    fi
  fi

  if apt_has_pkg ghostty; then
    apt_install ghostty
    return 0
  fi

  echo "Ghostty package not found in apt."
  echo "Install manually from https://ghostty.org/ and rerun this script for config sync."
}

install_base() {
  if ! prompt_yes_no "Install base packages (curl git ripgrep fzf xsel)?" "y"; then
    return 0
  fi
  apt_install curl git ripgrep fzf xsel
}

install_vim_plug() {
  local plug_path="$HOME/.local/share/nvim/site/autoload/plug.vim"
  if [[ -f "$plug_path" ]]; then
    if ! prompt_yes_no "vim-plug already installed. Reinstall?" "n"; then
      return 0
    fi
  else
    if ! prompt_yes_no "Install vim-plug for neovim?" "y"; then
      return 0
    fi
  fi

  if ! ensure_command curl curl; then
    echo "Skipping vim-plug install (curl not available)."
    return 0
  fi

  bash "$SCRIPT_DIR/setup_neovim/install_vim_plug"
}

sync_ghostty() {
  copy_file "$SCRIPT_DIR/setup_ghostty/config" "$HOME/.config/ghostty/config" "Ghostty config"
}

sync_tmux() {
  copy_file "$SCRIPT_DIR/setup_tmux/tmux.conf" "$HOME/.tmux.conf" "tmux config"
}

sync_atuin() {
  copy_file "$SCRIPT_DIR/setup_atuin/config.toml" "$HOME/.config/atuin/config.toml" "atuin config"
}

sync_bash() {
  if [[ -f "$HOME/.config/bash/custom.sh" ]]; then
    warn_large_diff "$SCRIPT_DIR/setup_bash/bashrc" "$HOME/.config/bash/custom.sh" "bash custom config"
  fi
  copy_file "$SCRIPT_DIR/setup_bash/bashrc" "$HOME/.config/bash/custom.sh" "bash custom config"
  ensure_bashrc_block
}

sync_neovim() {
  copy_file "$SCRIPT_DIR/setup_neovim/init.vim" "$HOME/.config/nvim/init.vim" "neovim init.vim"
  copy_file "$SCRIPT_DIR/setup_neovim/coc-settings.json" "$HOME/.config/nvim/coc-settings.json" "neovim coc-settings.json"
  copy_dir "$SCRIPT_DIR/setup_neovim/local_plugins/keymap-cheatsheet.nvim" \
    "$HOME/.config/nvim/pack/local/start/keymap-cheatsheet.nvim" \
    "neovim keymap-cheatsheet.nvim"

  copy_dir "$SCRIPT_DIR/setup_neovim/local_plugins/gitdiff" \
    "$HOME/.config/nvim/pack/local/start/gitdiff" \
    "neovim gitdiff local plugin"

  copy_file "$SCRIPT_DIR/setup_neovim/git-diff3-view.py" "$HOME/.local/bin/git-diff3-view.py" "git-diff3-view.py"
  copy_file "$SCRIPT_DIR/setup_neovim/clang-rename.py" "$HOME/.local/bin/clang-rename.py" "clang-rename.py"
  copy_file "$SCRIPT_DIR/setup_neovim/ccls-docker" "$HOME/.local/bin/ccls-docker" "ccls-docker wrapper"

  chmod +x "$HOME/.local/bin/git-diff3-view.py" "$HOME/.local/bin/clang-rename.py" "$HOME/.local/bin/ccls-docker" || true
}

atuin_import_bash() {
  if ! command -v atuin >/dev/null 2>&1; then
    return 0
  fi
  if prompt_yes_no "Import default bash history into atuin now?" "y"; then
    atuin import bash || true
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-all)
      INSTALL_NEOVIM=1
      INSTALL_TMUX=1
      INSTALL_ATUIN=1
      INSTALL_GHOSTTY=1
      INSTALL_BASE=1
      ;;
    --install-neovim) INSTALL_NEOVIM=1 ;;
    --install-tmux) INSTALL_TMUX=1 ;;
    --install-atuin) INSTALL_ATUIN=1 ;;
    --install-ghostty) INSTALL_GHOSTTY=1 ;;
    --install-base) INSTALL_BASE=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "$INSTALL_BASE" -eq 1 ]]; then
  install_base
fi
if [[ "$INSTALL_NEOVIM" -eq 1 ]]; then
  install_neovim
fi
if [[ "$INSTALL_TMUX" -eq 1 ]]; then
  install_tmux
fi
if [[ "$INSTALL_ATUIN" -eq 1 ]]; then
  install_atuin
fi
if [[ "$INSTALL_GHOSTTY" -eq 1 ]]; then
  install_ghostty
fi

sync_ghostty
sync_neovim
install_vim_plug
sync_atuin
sync_tmux
sync_bash
atuin_import_bash

echo "Done."
