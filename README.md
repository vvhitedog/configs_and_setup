# configs_and_setup
Configurations and setup scripts to sync my current environment.

## Primary synced configs
- Terminator: `setup_terminator/config` -> `~/.config/terminator/config`
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
- Auto-approve daemons: `claude-auto-approve`, `cursor-auto-approve`, `codex-auto-approve`, plus `setup_auto_approve/*.toml` -> `~/.config/auto-approve`
- Bash: `setup_bash/bashrc` -> sourced from `~/.bashrc`
- ble.sh: `setup_bash/blerc` -> `~/.blerc`, `ble.sh` installed to `~/.local/share/blesh`
- Atuin: `setup_atuin/config.toml` -> `~/.config/atuin/config.toml`; fallback install uses Atuin release binary installer without modifying shell files
- Fonts: `setup_terminator/sauce_code_fonts.zip` -> `~/.local/share/fonts/sauce_code_pro`

## Setup script (Ubuntu)
`setup_ubuntu.sh` is opt-out and idempotent enough to run over an older install.
It skips copies that are already identical, prompts before overwriting in interview mode, and supports explicit hands-off overwrite. The script prints numbered progress steps, hides noisy installer output in per-run logs under `/tmp`, and always prints a final success/failure summary with the failed step when something exits nonzero.

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

Tmux-compose installs `tmux-compose`, `tmux-mru`, `tmux-window-usage`, `tmux-pane-history`, and related helpers. By default it copies and enables the user services/timer for pane history, window usage, recovery snapshots, and the `claude-auto-approve`, `cursor-auto-approve`, and `codex-auto-approve` daemons. Use `--no-systemd` to copy helpers/configs without enabling services, or `--skip-tmux-compose` to skip the toolkit and auto-approve daemons. The installer reloads the running tmux config when it is run from inside tmux; both `prefix+c` and `prefix+C` create a cwd-inheriting window through tmux-compose. Window-name prompting is controlled by `prompt-on-create` in the tmux-compose status screen (`prefix+S`, then `p`) and is stored in `~/.cache/tmux/compose-state/prompt_on_create`; the default is on. Tmux truecolor is enabled for any outer `$TERM`, and tmux-compose applies a fixed dark UI palette so it does not fall back to Neovim's default dark theme during bootstrap.

ble.sh is installed from `https://github.com/akinomyoga/ble.sh.git` when missing or when reinstall/update is accepted. It loads before Atuin from the synced bash custom file. Atuin is installed via apt when available, otherwise via the official release binary installer with path modification disabled; shell integration is handled only by `setup_bash/bashrc`. Use `--skip-blesh` to skip ble.sh install and `.blerc` sync.

Directory colors come from two places: `ls` uses Ubuntu `dircolors`/`LS_COLORS` (`di=01;34`, bold ANSI blue), which Terminator maps to the palette blue `#6f8fb3` in this config. ble.sh completion uses explicit faces from `setup_bash/blerc`, such as `filename_directory=fg=#6f8fb3,bold`, so completion colors match the muted terminal blue.

Neovim prefers version >= 0.9.5. The script installs vim-plug, runs `:PlugInstall --sync`, verifies the expected remote plugins and local pack plugins, and fails loudly if a required plugin such as `baleia.nvim` or `onedark.vim` is still missing. CoC requires Node.js >= 16.18.0; the script can install Node.js LTS, update npm, install Yarn, and install the synced CoC extensions (`coc-json`, `coc-pyright`, `coc-tsserver`, `coc-java`). Optional local binary integrations such as `tagls` and `tsxref` are guarded so Neovim starts cleanly when those binaries are not installed.

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
