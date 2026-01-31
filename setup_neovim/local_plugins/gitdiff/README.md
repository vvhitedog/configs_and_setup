# GitDiff

Two-pane git diff browser for Neovim. Top pane shows changed files, bottom pane
shows git log with source/target markers. Press Enter on a file to open a
split diff in a new tab (source left, target right).

## Install

With vim-plug:

```
Plug '~/software/gitdiff'
```

## Setup

```
lua << EOF
require("gitdiffiles").setup({
  log_max = 200,
  log_view = "oneline",
  ui = {
    open_in_tab = true,
    file_height = nil,
    log_height = nil,
  },
  keys = {
    open = "<CR>",
    refresh = "r",
    quit = "q",
    set_source = "s",
    set_target = "t",
    toggle_log = "L",
  },
})
EOF
```

## Usage

```
:GitDiff
:GitDiff HEAD
:GitDiff origin/HEAD
:GitDiff HEAD~3 HEAD
```

## Keys

File list pane:

- `<CR>` open diff for selected file (new tab)
- `r` refresh
- `q` close

Log pane:

- `s` set source commit (commit lines only)
- `t` set target commit (commit or WORKDIR line)
- `L` toggle log view (one-line vs full)
- `r` refresh
- `q` close

The first log line is always a WORKDIR pseudo-entry (uncommitted changes).
Target defaults to WORKDIR; source defaults to the top commit in the log.
Both panes use winbars to show the current source/target selection.
