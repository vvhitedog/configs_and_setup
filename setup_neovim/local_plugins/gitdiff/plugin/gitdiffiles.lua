if vim.g.loaded_gitdiffiles then
  return
end
vim.g.loaded_gitdiffiles = 1

vim.api.nvim_set_hl(0, "GitDiffSourceMarker", { link = "DiffDelete", default = true })
vim.api.nvim_set_hl(0, "GitDiffTargetMarker", { link = "DiffAdd", default = true })
vim.api.nvim_set_hl(0, "GitDiffSourceTarget", { link = "DiffText", default = true })
vim.api.nvim_set_hl(0, "GitDiffMergeBaseMarker", { link = "Search", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiBlack", { link = "Comment", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiRed", { link = "DiffDelete", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiGreen", { link = "DiffAdd", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiYellow", { link = "WarningMsg", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiBlue", { link = "Identifier", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiMagenta", { link = "Statement", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiCyan", { link = "Type", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiWhite", { link = "Normal", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiBrightBlack", { link = "LineNr", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiBrightRed", { link = "ErrorMsg", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiBrightGreen", { link = "DiffAdd", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiBrightYellow", { link = "WarningMsg", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiBrightBlue", { link = "Function", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiBrightMagenta", { link = "Statement", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiBrightCyan", { link = "Type", default = true })
vim.api.nvim_set_hl(0, "GitDiffAnsiBrightWhite", { link = "Normal", default = true })

vim.api.nvim_create_user_command("GitDiff", function(opts)
  if #opts.fargs > 2 then
    vim.notify("GitDiff: expected 0-2 args", vim.log.levels.WARN)
  end
  require("gitdiffiles").open_from_cmd(opts)
end, {
  nargs = "*",
  desc = "Open GitDiff UI",
})
