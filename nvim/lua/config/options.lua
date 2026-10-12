-- Options are loaded before lazy.nvim startup. LazyVim's defaults:
-- https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

-- Setting CFLAGS replaces tree-sitter's default compiler flags, which include -Wall.
-- gcc 12.2 (Debian 12) spends minutes on -Wall for large generated parsers such as
-- gitcommit; with CFLAGS set the same parser builds in seconds.
if not vim.env.CFLAGS or vim.env.CFLAGS == "" then
  vim.env.CFLAGS = "-O2"
end
