#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

MODE="interview"
OVERWRITE=0
ENABLE_SYSTEMD=1
TERMINAL_MODE="terminator"
SKIP_NEOVIM=0
SKIP_TMUX=0
SKIP_TMUX_COMPOSE=0
SKIP_ATUIN=0
SKIP_BLESH=0
SKIP_TERMINATOR=0
SKIP_GHOSTTY=1
SKIP_BASE=0
SKIP_FONTS=0

APT_UPDATED=0
MIN_NVIM_VERSION="0.9.5"
MIN_NODE_VERSION="16.18.0"
MIN_NPM_VERSION="8.0.0"
MIN_YARN_VERSION="1.22.0"
NPM_PREFIX="$HOME/.local"

export PATH="$HOME/.local/bin:$HOME/.atuin/bin:$HOME/.cargo/bin:$HOME/.npm-global/bin:$PATH"

usage() {
  cat <<'EOF'
Usage: setup_ubuntu.sh [options]

Options:
  --interview            Ask about installs and overwrites (default)
  --yolo, --yes          Install selected components and overwrite without asking
  --overwrite, --force   Overwrite existing configs without prompts, but keep install prompts
  --terminal MODE        Terminal target: terminator (default), ghostty, both, none
  --skip-neovim          Skip installing or upgrading neovim
  --skip-tmux            Skip installing or upgrading tmux
  --skip-tmux-compose    Skip tmux-compose helpers and user services
  --skip-atuin           Skip installing or upgrading atuin
  --skip-blesh           Skip installing or syncing ble.sh and .blerc
  --skip-terminator      Skip installing or syncing terminator
  --skip-ghostty         Skip installing or syncing ghostty
  --skip-base            Skip installing base packages
  --skip-fonts           Skip installing Sauce Code Pro fonts
  --no-systemd           Copy tmux-compose helpers, but do not enable user services
  -h, --help             Show this help
EOF
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local choice
  local options

  if [[ "$MODE" == "yolo" ]]; then
    return 0
  fi

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

apt_install_optional() {
  local pkg
  for pkg in "$@"; do
    if apt_has_pkg "$pkg"; then
      apt_install "$pkg"
    else
      echo "Optional apt package not found, skipping: $pkg"
    fi
  done
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

clean_version() {
  echo "$1" | sed -E 's/^[^0-9]*//; s/^[0-9]+://; s/[^0-9.].*$//'
}

version_ge() {
  local a="$1"
  local b="$2"
  if [[ -z "$a" || -z "$b" ]]; then
    return 1
  fi
  [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)" == "$b" ]]
}

ensure_dir() {
  local dir="$1"
  if [[ -n "$dir" ]]; then
    mkdir -p "$dir"
  fi
}

get_installed_nvim_version() {
  if ! command -v nvim >/dev/null 2>&1; then
    return 0
  fi
  nvim --version 2>/dev/null | head -n1 | sed -E 's/^NVIM v?//; s/[^0-9.].*$//'
}

get_apt_nvim_version() {
  local cand
  cand="$(apt-cache policy neovim 2>/dev/null | awk -F': ' '/Candidate:/ {print $2}')"
  if [[ -z "$cand" || "$cand" == "(none)" ]]; then
    return 0
  fi
  clean_version "$cand"
}

get_snap_nvim_version() {
  if ! command -v snap >/dev/null 2>&1; then
    return 0
  fi
  local ver
  ver="$(snap info nvim 2>/dev/null | awk '/latest\/stable:/ {print $2; exit} /stable:/ {print $2; exit}')"
  clean_version "$ver"
}

get_node_version() {
  if ! command -v node >/dev/null 2>&1; then
    return 0
  fi
  node --version 2>/dev/null | sed -E 's/^v//; s/[^0-9.].*$//'
}

get_npm_version() {
  if ! command -v npm >/dev/null 2>&1; then
    return 0
  fi
  npm --version 2>/dev/null | sed -E 's/[^0-9.].*$//'
}

get_yarn_version() {
  if ! command -v yarn >/dev/null 2>&1; then
    return 0
  fi
  yarn --version 2>/dev/null | sed -E 's/[^0-9.].*$//'
}

copy_file_unprompted() {
  local src="$1"
  local dest="$2"

  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
}

copy_file() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if [[ ! -f "$src" ]]; then
    echo "Missing source file: $src"
    return 1
  fi

  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    echo "$label is already up to date: $dest"
    return 0
  fi

  if [[ "$MODE" != "yolo" && "$OVERWRITE" -ne 1 ]]; then
    if [[ -e "$dest" ]]; then
      if ! prompt_yes_no "Overwrite $label at $dest?" "y"; then
        return 0
      fi
    else
      if ! prompt_yes_no "Install $label to $dest?" "y"; then
        return 0
      fi
    fi
  fi

  copy_file_unprompted "$src" "$dest"
}

copy_dir() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if [[ ! -d "$src" ]]; then
    echo "Missing source directory: $src"
    return 1
  fi

  if [[ -d "$dest" ]] && command -v diff >/dev/null 2>&1 && diff -qr "$src" "$dest" >/dev/null 2>&1; then
    echo "$label is already up to date: $dest"
    return 0
  fi

  if [[ "$MODE" != "yolo" && "$OVERWRITE" -ne 1 ]]; then
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
  else
    if [[ -e "$dest" ]]; then
      rm -rf "$dest"
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
  local installed_ver="" apt_ver="" snap_ver="" recommended_source="" recommended_ver=""
  installed_ver="$(get_installed_nvim_version)"
  apt_ver="$(get_apt_nvim_version)"
  snap_ver="$(get_snap_nvim_version)"

  echo "Neovim versions: installed=${installed_ver:-none}, apt=${apt_ver:-none}, snap=${snap_ver:-none} (need >= ${MIN_NVIM_VERSION})"

  if [[ -n "$apt_ver" ]] && version_ge "$apt_ver" "$MIN_NVIM_VERSION"; then
    recommended_source="apt"
    recommended_ver="$apt_ver"
  fi
  if [[ -n "$snap_ver" ]] && version_ge "$snap_ver" "$MIN_NVIM_VERSION"; then
    if [[ -z "$recommended_ver" ]] || version_ge "$snap_ver" "$recommended_ver"; then
      recommended_source="snap"
      recommended_ver="$snap_ver"
    fi
  fi

  if [[ -z "$recommended_source" ]]; then
    echo "WARNING: No apt or snap Neovim version meets ${MIN_NVIM_VERSION}."
    echo "Available: apt=${apt_ver:-none}, snap=${snap_ver:-none}"
    if ! prompt_yes_no "Install the newest available Neovim anyway?" "y"; then
      return 0
    fi
    if [[ -n "$snap_ver" ]] && { [[ -z "$apt_ver" ]] || version_ge "$snap_ver" "$apt_ver"; }; then
      recommended_source="snap"
      recommended_ver="$snap_ver"
    elif [[ -n "$apt_ver" ]]; then
      recommended_source="apt"
      recommended_ver="$apt_ver"
    else
      echo "No Neovim package found in apt or snap."
      return 0
    fi
  else
    if ! prompt_yes_no "Install/upgrade Neovim via ${recommended_source} (v${recommended_ver})?" "y"; then
      return 0
    fi
  fi

  if [[ "$recommended_source" == "snap" ]]; then
    ensure_command snap snapd || return 0
    sudo snap install nvim --classic
  else
    apt_install neovim
  fi
}

install_tmux() {
  if command -v tmux >/dev/null 2>&1; then
    if ! prompt_yes_no "Tmux already installed. Reinstall/upgrade?" "y"; then
      return 0
    fi
  else
    if ! prompt_yes_no "Install tmux?" "y"; then
      return 0
    fi
  fi
  apt_install tmux
}

install_blesh() {
  local ble_path="$HOME/.local/share/blesh/ble.sh"
  local tmp=""

  if [[ -f "$ble_path" ]]; then
    if ! prompt_yes_no "ble.sh already installed. Reinstall/update from source?" "n"; then
      return 0
    fi
  else
    if ! prompt_yes_no "Install ble.sh from source?" "y"; then
      return 0
    fi
  fi

  ensure_command git git || return 0
  ensure_command make make || return 0
  ensure_command gawk gawk || return 0

  tmp="$(mktemp -d)"
  if git clone --recursive --depth 1 --shallow-submodules \
      https://github.com/akinomyoga/ble.sh.git "$tmp/ble.sh" && \
      make -C "$tmp/ble.sh" install PREFIX="$HOME/.local"; then
    rm -rf "$tmp"
  else
    local rc=$?
    rm -rf "$tmp"
    echo "WARNING: ble.sh install failed."
    return "$rc"
  fi
}

install_atuin() {
  if command -v atuin >/dev/null 2>&1; then
    if ! prompt_yes_no "Atuin already installed. Reinstall/upgrade?" "y"; then
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
  ensure_command tar tar || return 0

  local tmp=""
  tmp="$(mktemp -d)"
  echo "Installing atuin via the release binary installer (no shell config mutation)."
  if curl -fsSL --retry 3 -o "$tmp/atuin-installer.sh" \
      https://github.com/atuinsh/atuin/releases/latest/download/atuin-installer.sh && \
      ATUIN_NO_MODIFY_PATH=1 ATUIN_DISABLE_UPDATE=1 \
        sh "$tmp/atuin-installer.sh" --quiet --no-modify-path; then
    rm -rf "$tmp"
  else
    local rc=$?
    rm -rf "$tmp"
    echo "WARNING: atuin install failed."
    return "$rc"
  fi
}

install_ghostty() {
  if command -v ghostty >/dev/null 2>&1; then
    if ! prompt_yes_no "Ghostty already installed. Reinstall/upgrade?" "y"; then
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

  echo "Ghostty package not found in apt. Trying snap."
  ensure_command snap snapd || return 0
  sudo snap install ghostty --classic
}

install_terminator() {
  if command -v terminator >/dev/null 2>&1; then
    if ! prompt_yes_no "Terminator already installed. Reinstall/upgrade?" "y"; then
      return 0
    fi
  else
    if ! prompt_yes_no "Install terminator?" "y"; then
      return 0
    fi
  fi
  apt_install terminator
}

install_base() {
  if ! prompt_yes_no "Install base packages (curl git ripgrep fzf xsel unzip fontconfig python3)?" "y"; then
    return 0
  fi
  apt_install curl git ripgrep fzf xsel unzip fontconfig python3
  apt_install_optional btop xclip wl-clipboard
}

install_vim_plug() {
  local plug_path="$HOME/.local/share/nvim/site/autoload/plug.vim"
  if [[ -f "$plug_path" ]]; then
    if ! prompt_yes_no "vim-plug already installed. Reinstall?" "y"; then
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

npm_global_install() {
  local pkg="$1"
  local log=""
  ensure_dir "$NPM_PREFIX"
  log="$(mktemp)"
  if npm install -g "$pkg" --prefix "$NPM_PREFIX" >"$log" 2>&1; then
    rm -f "$log"
    return 0
  fi
  echo "npm install -g $pkg failed under ${NPM_PREFIX}. See $log"
  if prompt_yes_no "Retry npm install -g $pkg with sudo?" "n"; then
    local sudo_log
    sudo_log="$(mktemp)"
    if sudo npm install -g "$pkg" >"$sudo_log" 2>&1; then
      rm -f "$sudo_log"
    else
      echo "sudo npm install -g $pkg failed. See $sudo_log"
    fi
  fi
}

run_plug_install() {
  local plug_path="$HOME/.local/share/nvim/site/autoload/plug.vim"
  if [[ ! -f "$plug_path" ]]; then
    return 0
  fi
  if ! command -v nvim >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$MODE" != "yolo" ]]; then
    if ! prompt_yes_no "Run :PlugInstall now to fetch Neovim plugins?" "y"; then
      return 0
    fi
  fi
  nvim --headless +PlugInstall +qall || true
}

install_node_tooling() {
  local node_ver npm_ver yarn_ver
  node_ver="$(get_node_version)"
  npm_ver="$(get_npm_version)"
  yarn_ver="$(get_yarn_version)"

  echo "Node tooling: node=${node_ver:-none} (>=${MIN_NODE_VERSION}), npm=${npm_ver:-none} (>=${MIN_NPM_VERSION}), yarn=${yarn_ver:-none} (>=${MIN_YARN_VERSION})"

  if [[ -z "$node_ver" ]] || ! version_ge "$node_ver" "$MIN_NODE_VERSION"; then
    echo "CoC requires Node.js >= ${MIN_NODE_VERSION}."
    if prompt_yes_no "Install Node.js LTS via NodeSource (adds apt repo)?" "y"; then
      ensure_command curl curl || return 0
      curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
      apt_install nodejs
      node_ver="$(get_node_version)"
      npm_ver="$(get_npm_version)"
    else
      echo "Skipping Node.js install; CoC may not work."
      return 0
    fi
  fi

  if [[ -z "$npm_ver" ]] || ! version_ge "$npm_ver" "$MIN_NPM_VERSION"; then
    if prompt_yes_no "Update npm to the latest (global)?" "y"; then
      npm_global_install "npm@latest"
      npm_ver="$(get_npm_version)"
    fi
  fi

  yarn_ver="$(get_yarn_version)"
  if [[ -z "$yarn_ver" ]] || ! version_ge "$yarn_ver" "$MIN_YARN_VERSION"; then
    if command -v corepack >/dev/null 2>&1; then
      if prompt_yes_no "Enable corepack and install Yarn (stable)?" "y"; then
        local cp_log
        cp_log="$(mktemp)"
        if ! corepack enable >"$cp_log" 2>&1; then
          echo "corepack enable failed. See $cp_log"
        else
          rm -f "$cp_log"
        fi
        cp_log="$(mktemp)"
        if ! corepack prepare yarn@stable --activate >"$cp_log" 2>&1; then
          echo "corepack prepare failed. See $cp_log"
        else
          rm -f "$cp_log"
        fi
      fi
    else
      if prompt_yes_no "Install yarn via npm (global)?" "y"; then
        npm_global_install "yarn"
      fi
    fi
  fi
}

install_fonts() {
  local zip_path="$SCRIPT_DIR/setup_terminator/sauce_code_fonts.zip"
  local dest_dir="$HOME/.local/share/fonts/sauce_code_pro"

  if [[ ! -f "$zip_path" ]]; then
    echo "Font archive not found: $zip_path"
    return 0
  fi

  if [[ "$MODE" != "yolo" ]]; then
    if ! prompt_yes_no "Install Sauce Code Pro fonts from $zip_path?" "y"; then
      return 0
    fi
  fi

  ensure_command unzip unzip || return 0
  mkdir -p "$dest_dir"
  unzip -o "$zip_path" -d "$dest_dir" >/dev/null
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$dest_dir" || true
  fi
}

sync_ghostty() {
  copy_file "$SCRIPT_DIR/setup_ghostty/config" "$HOME/.config/ghostty/config" "Ghostty config"
}

sync_terminator() {
  copy_file "$SCRIPT_DIR/setup_terminator/config" "$HOME/.config/terminator/config" "Terminator config"
}

sync_tmux() {
  copy_file "$SCRIPT_DIR/setup_tmux/tmux.conf" "$HOME/.tmux.conf" "tmux config"
}

reload_tmux_config() {
  if [[ -z "${TMUX:-}" ]]; then
    return 0
  fi
  if ! command -v tmux >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$MODE" != "yolo" && "$OVERWRITE" -ne 1 ]]; then
    if ! prompt_yes_no "Reload the running tmux server config now?" "y"; then
      return 0
    fi
  fi
  if ! tmux source-file "$HOME/.tmux.conf"; then
    echo "WARNING: failed to reload tmux config. New tmux sessions will still use ~/.tmux.conf."
  fi
}

sync_tmux_compose() {
  local bin_src_dir="$SCRIPT_DIR/setup_tmux/bin"
  local unit_src_dir="$SCRIPT_DIR/setup_tmux/systemd/user"
  local src dest unit

  if [[ ! -d "$bin_src_dir" ]]; then
    echo "tmux-compose helper directory not found: $bin_src_dir"
    return 0
  fi

  if [[ "$MODE" != "yolo" && "$OVERWRITE" -ne 1 ]]; then
    if ! prompt_yes_no "Install/update tmux-compose helper scripts?" "y"; then
      return 0
    fi
  fi

  ensure_dir "$HOME/.local/bin"
  for src in "$bin_src_dir"/*; do
    [[ -f "$src" ]] || continue
    dest="$HOME/.local/bin/$(basename "$src")"
    copy_file_unprompted "$src" "$dest"
    chmod +x "$dest" || true
  done

  if [[ -d "$unit_src_dir" ]]; then
    ensure_dir "$HOME/.config/systemd/user"
    for unit in "$unit_src_dir"/*; do
      [[ -f "$unit" ]] || continue
      copy_file_unprompted "$unit" "$HOME/.config/systemd/user/$(basename "$unit")"
    done
  fi

  if [[ "$ENABLE_SYSTEMD" -ne 1 ]]; then
    return 0
  fi
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl not found; copied tmux-compose units but did not enable them."
    return 0
  fi
  if [[ "$MODE" != "yolo" && "$OVERWRITE" -ne 1 ]]; then
    if ! prompt_yes_no "Enable/start tmux-compose user services and snapshot timer?" "y"; then
      return 0
    fi
  fi

  if ! systemctl --user daemon-reload; then
    echo "WARNING: systemctl --user daemon-reload failed; user services were not enabled."
    return 0
  fi
  if ! systemctl --user enable --now tmux-pane-history.service tmux-window-usage.service tmux-compose-snapshot.timer; then
    echo "WARNING: failed to enable/start one or more tmux-compose user units."
  fi
}

sync_atuin() {
  copy_file "$SCRIPT_DIR/setup_atuin/config.toml" "$HOME/.config/atuin/config.toml" "atuin config"
}

sync_blesh() {
  copy_file "$SCRIPT_DIR/setup_bash/blerc" "$HOME/.blerc" "ble.sh config"
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
  local plugin_dir plugin_name
  for plugin_dir in "$SCRIPT_DIR/setup_neovim/local_plugins"/*; do
    [[ -d "$plugin_dir" ]] || continue
    plugin_name="$(basename "$plugin_dir")"
    copy_dir "$plugin_dir" "$HOME/.config/nvim/pack/local/start/$plugin_name" \
      "neovim local plugin $plugin_name"
  done

  copy_file "$SCRIPT_DIR/setup_neovim/git-diff3-view.py" "$HOME/.local/bin/git-diff3-view.py" "git-diff3-view.py"
  copy_file "$SCRIPT_DIR/setup_neovim/clang-rename.py" "$HOME/.local/bin/clang-rename.py" "clang-rename.py"
  copy_file "$SCRIPT_DIR/setup_neovim/ccls-docker" "$HOME/.local/bin/ccls-docker" "ccls-docker wrapper"

  local helper
  local helpers=(
    "$HOME/.local/bin/git-diff3-view.py"
    "$HOME/.local/bin/clang-rename.py"
    "$HOME/.local/bin/ccls-docker"
  )
  for helper in "${helpers[@]}"; do
    if [[ -e "$helper" ]]; then
      chmod +x "$helper"
    fi
  done
}

atuin_import_bash() {
  if ! command -v atuin >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$MODE" == "yolo" ]] || prompt_yes_no "Import default bash history into atuin now?" "y"; then
    atuin import bash || true
  fi
}

selected_terminals() {
  local terms=()
  [[ "$SKIP_TERMINATOR" -ne 1 ]] && terms+=("terminator")
  [[ "$SKIP_GHOSTTY" -ne 1 ]] && terms+=("ghostty")
  if [[ "${#terms[@]}" -eq 0 ]]; then
    echo "none"
  else
    local IFS=,
    echo "${terms[*]}"
  fi
}

print_summary() {
  echo "configs_and_setup install"
  echo "  mode: $MODE"
  echo "  overwrite configs: $([[ "$MODE" == "yolo" || "$OVERWRITE" -eq 1 ]] && echo yes || echo prompt)"
  echo "  terminals: $(selected_terminals)"
  echo "  ble.sh: $([[ "$SKIP_BLESH" -ne 1 ]] && echo enabled || echo skipped)"
  echo "  tmux-compose services: $([[ "$ENABLE_SYSTEMD" -eq 1 && "$SKIP_TMUX_COMPOSE" -ne 1 ]] && echo enabled || echo disabled)"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interview)
      MODE="interview"
      ;;
    --yolo|--yes)
      MODE="yolo"
      OVERWRITE=1
      ;;
    --overwrite|--force)
      OVERWRITE=1
      ;;
    --terminal)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--terminal requires one of: terminator, ghostty, both, none"
        exit 1
      fi
      TERMINAL_MODE="$1"
      case "$TERMINAL_MODE" in
        terminator)
          SKIP_TERMINATOR=0
          SKIP_GHOSTTY=1
          ;;
        ghostty)
          SKIP_TERMINATOR=1
          SKIP_GHOSTTY=0
          ;;
        both)
          SKIP_TERMINATOR=0
          SKIP_GHOSTTY=0
          ;;
        none)
          SKIP_TERMINATOR=1
          SKIP_GHOSTTY=1
          ;;
        *)
          echo "Unknown terminal mode: $TERMINAL_MODE"
          echo "Expected one of: terminator, ghostty, both, none"
          exit 1
          ;;
      esac
      ;;
    --skip-neovim) SKIP_NEOVIM=1 ;;
    --skip-tmux) SKIP_TMUX=1 ;;
    --skip-tmux-compose) SKIP_TMUX_COMPOSE=1 ;;
    --skip-atuin) SKIP_ATUIN=1 ;;
    --skip-blesh) SKIP_BLESH=1 ;;
    --skip-terminator) SKIP_TERMINATOR=1 ;;
    --skip-ghostty) SKIP_GHOSTTY=1 ;;
    --skip-base) SKIP_BASE=1 ;;
    --skip-fonts) SKIP_FONTS=1 ;;
    --no-systemd) ENABLE_SYSTEMD=0 ;;
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

print_summary

if [[ "$SKIP_BASE" -ne 1 ]]; then
  install_base
fi
if [[ "$SKIP_NEOVIM" -ne 1 ]]; then
  install_neovim
  install_node_tooling
fi
if [[ "$SKIP_TMUX" -ne 1 ]]; then
  install_tmux
fi
if [[ "$SKIP_ATUIN" -ne 1 ]]; then
  install_atuin
fi
if [[ "$SKIP_BLESH" -ne 1 ]]; then
  install_blesh
fi
if [[ "$SKIP_TERMINATOR" -ne 1 ]]; then
  install_terminator
fi
if [[ "$SKIP_GHOSTTY" -ne 1 ]]; then
  install_ghostty
fi
if [[ "$SKIP_FONTS" -ne 1 ]]; then
  install_fonts
fi

if [[ "$SKIP_TERMINATOR" -ne 1 ]]; then
  sync_terminator
fi
if [[ "$SKIP_GHOSTTY" -ne 1 ]]; then
  sync_ghostty
fi
sync_neovim
install_vim_plug
sync_atuin
if [[ "$SKIP_BLESH" -ne 1 ]]; then
  sync_blesh
fi
sync_tmux
if [[ "$SKIP_TMUX_COMPOSE" -ne 1 ]]; then
  sync_tmux_compose
fi
reload_tmux_config
sync_bash
atuin_import_bash
run_plug_install

echo "Done."
