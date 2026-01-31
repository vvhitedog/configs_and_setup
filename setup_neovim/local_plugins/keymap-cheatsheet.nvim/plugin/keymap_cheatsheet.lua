-- Defines :CheatSheet on startup (no setup required).
vim.api.nvim_create_user_command("CheatSheet", function()
  require("keymap_cheatsheet").open()
end, {})

