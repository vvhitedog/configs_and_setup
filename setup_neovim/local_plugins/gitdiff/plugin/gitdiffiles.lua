if vim.g.loaded_gitdiffiles then
  return
end
vim.g.loaded_gitdiffiles = 1

vim.api.nvim_set_hl(0, "GitDiffSourceMarker", { link = "DiffDelete", default = true })
vim.api.nvim_set_hl(0, "GitDiffTargetMarker", { link = "DiffAdd", default = true })
vim.api.nvim_set_hl(0, "GitDiffSourceTarget", { link = "DiffText", default = true })

vim.api.nvim_create_user_command("GitDiff", function(opts)
  if #opts.fargs > 2 then
    vim.notify("GitDiff: expected 0-2 args", vim.log.levels.WARN)
  end
  require("gitdiffiles").open_from_cmd(opts)
end, {
  nargs = "*",
  desc = "Open GitDiff UI",
})
