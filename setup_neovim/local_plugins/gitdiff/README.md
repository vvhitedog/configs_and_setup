# GitDiff

Two-pane git diff browser for Neovim. Top pane shows changed files, bottom pane
shows a colorized `git log --graph` with source/target markers. Press Enter on
a file to open a split diff in a new tab (source left, target right).

## Install

This repo installs GitDiff as a local Neovim pack plugin:

```
~/.config/nvim/pack/local/start/gitdiff
```

## Setup

```
lua << EOF
require("gitdiffiles").setup({
  log_max = 0,
  log_view = "oneline",
  diff_mode = "pr",
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
    toggle_mode = "m",
  },
})
EOF
```

## Usage

```
:GitDiff
:GitDiff HEAD
:GitDiff origin/HEAD
:GitDiff origin/main
:GitDiff HEAD~3 HEAD
```

`log_max = 0` means "show the full log" instead of truncating after a fixed count.
Both one-line and full log views use `git log --graph`.

## Keys

File list pane:

- `<CR>` open diff for selected file (new tab)
- `r` refresh
- `q` close

Log pane:

- `s` set source commit (commit lines only)
- `t` set target commit (commit or WORKDIR line)
- `L` toggle log view (one-line graph vs full graph)
- `m` toggle diff mode (`PR` merge-base mode vs `ALL` branch-base mode)
- `r` refresh
- `q` close

The first log line is always a WORKDIR pseudo-entry (uncommitted changes).
Target defaults to WORKDIR. Source defaults to the first available ref from
`origin/HEAD`, `origin/main`, `origin/master`, `main`, `master`, then falls back
to the top commit in the log if none of those resolve.
Both panes show the active diff mode and the toggle key in the winbar.

## Diff Modes

- `PR` mode diffs from the merge-base of the selected source and target, which hides changes that only came from merging the upstream branch back into your working branch.
- `ALL` mode diffs from the branch base along the target's first-parent history, so merged upstream changes stay visible.
- The log marks the computed merge-base with a highlighted `[MERGE-BASE]` tag.
