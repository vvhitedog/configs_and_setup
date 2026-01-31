# keymap-cheatsheet.nvim

Popup cheatsheet of keymaps defined in your Neovim config (filtered using `:verbose map` “Last set from …”).

Descriptions come from the mapping’s `desc` when available (e.g. `vim.keymap.set(..., { desc = "..." })`).

If you use Vimscript mappings (or you don’t want to touch existing mappings), you can add descriptions without rewriting anything:

```vim
let g:keymap_cheatsheet_desc = {
\ 'n': { '<leader>ff': 'Find files', '<leader>fg': 'Live grep' },
\ 'i': { 'jj': 'Exit insert mode' },
\ }
```

## Usage

- `:CheatSheet`

Optional mapping (Vimscript):

```vim
nnoremap <silent> <leader>? :CheatSheet<CR>
```

Optional mapping (Lua):

```lua
vim.keymap.set("n", "<leader>?", "<cmd>CheatSheet<cr>", { silent = true })
```

