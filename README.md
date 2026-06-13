# configs_and_setup
Configurations and setup scripts to sync my current environment.

## Primary synced configs
- Terminator: `setup_terminator/config` -> `~/.config/terminator/config` (palette matched to tmux/ble.sh)
- Ghostty: `setup_ghostty/config` -> `~/.config/ghostty/config`
- Neovim: `setup_neovim/init.vim`, `setup_neovim/coc-settings.json`
- Neovim local plugins: everything under `setup_neovim/local_plugins/*` -> `~/.config/nvim/pack/local/start/`
  - `gitdiff`: two-pane git diff browser with PR/all modes
  - `keymap-cheatsheet.nvim`: keymap cheat sheet
  - `project-tags.nvim`: archived local project-tags runtime
  - `tagls.nvim`: Neovim runtime for local `tagls` binary when available
- Neovim helper scripts: `setup_neovim/git-diff3-view.py`, `setup_neovim/clang-rename.py`, `setup_neovim/ccls-docker` -> `~/.local/bin`
- Tmux: `setup_tmux/tmux.conf` -> `~/.tmux.conf`
- Tmux-compose toolkit: `setup_tmux/bin/*` -> `~/.local/bin`, user units in `setup_tmux/systemd/user/*` -> `~/.config/systemd/user`
- Bash: `setup_bash/bashrc` -> sourced from `~/.bashrc`
- ble.sh: `setup_bash/blerc` -> `~/.blerc`, `ble.sh` installed to `~/.local/share/blesh`
- Atuin: `setup_atuin/config.toml` -> `~/.config/atuin/config.toml`
- Fonts: `setup_terminator/sauce_code_fonts.zip` -> `~/.local/share/fonts/sauce_code_pro`

## Setup script (Ubuntu)
`setup_ubuntu.sh` is opt-out and idempotent enough to run over an older install.
It skips copies that are already identical, prompts before overwriting in interview mode, and supports explicit hands-off overwrite.

Modes:
- interview mode (default): asks about installs and overwrites
- yolo mode: installs selected components and overwrites without prompts
- overwrite mode: use `--overwrite` or `--force` to overwrite configs without prompts while keeping install prompts

Terminals:
- default: Terminator only
- `--terminal terminator`: install/sync Terminator
- `--terminal ghostty`: install/sync Ghostty
- `--terminal both`: install/sync both terminal configs
- `--terminal none`: skip terminal install/sync

Tmux-compose installs `tmux-compose`, `tmux-mru`, `tmux-window-usage`, `tmux-pane-history`, and related helpers. By default it copies and enables the user services/timer for pane history, window usage, and recovery snapshots. Use `--no-systemd` to copy helpers without enabling services, or `--skip-tmux-compose` to skip the toolkit. The installer reloads the running tmux config when it is run from inside tmux; both `prefix+c` and `prefix+C` create a cwd-inheriting window through tmux-compose.

ble.sh is installed from `https://github.com/akinomyoga/ble.sh.git` when missing or when reinstall/update is accepted. It loads before Atuin from the synced bash custom file. Use `--skip-blesh` to skip ble.sh install and `.blerc` sync.

Neovim prefers version >= 0.9.5. The script installs vim-plug, can run `:PlugInstall`, and copies local pack plugins. CoC requires Node.js >= 16.18.0; the script can install Node.js LTS, update npm, and install Yarn if needed. Optional local binary integrations such as `tagls` and `tsxref` are guarded so Neovim starts cleanly when those binaries are not installed.

Examples:
- `./setup_ubuntu.sh`
- `./setup_ubuntu.sh --yolo`
- `./setup_ubuntu.sh --yolo --terminal both`
- `./setup_ubuntu.sh --overwrite --terminal ghostty`
- `./setup_ubuntu.sh --skip-neovim --skip-tmux-compose`
- `./setup_ubuntu.sh --terminal terminator --no-systemd`

## Atuin history import
The setup script can run the default bash history import:
- `atuin import bash`
