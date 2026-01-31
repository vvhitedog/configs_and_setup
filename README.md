# configs_and_setup
Configurations and setup scripts to sync my current environment.

## Primary synced configs
- Ghostty: `setup_ghostty/config` -> `~/.config/ghostty/config`
- Neovim: `setup_neovim/init.vim`, `setup_neovim/coc-settings.json`
- Neovim local plugins:
  - `setup_neovim/local_plugins/keymap-cheatsheet.nvim` -> `~/.config/nvim/pack/local/start/keymap-cheatsheet.nvim`
  - `setup_neovim/local_plugins/gitdiff` -> `~/.config/nvim/pack/local/start/gitdiff`
- Neovim helper scripts: `setup_neovim/git-diff3-view.py`, `setup_neovim/clang-rename.py`, `setup_neovim/ccls-docker` -> `~/.local/bin`
- Tmux: `setup_tmux/tmux.conf` -> `~/.tmux.conf`
- Bash: `setup_bash/bashrc` -> sourced from `~/.bashrc` (history handled by Atuin; no inputrc)
- Atuin: `setup_atuin/config.toml` -> `~/.config/atuin/config.toml`

## Setup script (Ubuntu)
`setup_ubuntu.sh` prompts before installs/overwrites and focuses on Ghostty, Neovim (incl. local plugins), Atuin, tmux, and bash.
It also offers to install vim-plug and import bash history into Atuin.

Examples:
- `./setup_ubuntu.sh`
- `./setup_ubuntu.sh --install-all --install-base`
- `./setup_ubuntu.sh --install-neovim --install-tmux --install-atuin --install-ghostty --install-base`

## Atuin history import
The setup script can run the default bash history import:
- `atuin import bash`
