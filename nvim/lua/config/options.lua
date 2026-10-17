-- Options are loaded before lazy.nvim startup. LazyVim's defaults:
-- https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

-- Setting CFLAGS replaces tree-sitter's default compiler flags, which include -Wall.
-- gcc 12.2 (Debian 12) spends minutes on -Wall for large generated parsers such as
-- gitcommit; with CFLAGS set the same parser builds in seconds.
if not vim.env.CFLAGS or vim.env.CFLAGS == "" then
  vim.env.CFLAGS = "-O2"
end

-- Over SSH, LazyVim leaves the system clipboard off. Copy (y, d, c) still goes to your own
-- computer's clipboard through OSC 52 (the terminal escape code; iTerm2, Ghostty, WezTerm,
-- kitty and tmux with set-clipboard on pass it through). Paste (p) uses nvim's own register,
-- because reading the clipboard over OSC 52 makes many terminals ask for permission;
-- use the terminal's paste (Cmd-V) to paste text copied elsewhere.
if vim.env.SSH_CONNECTION or vim.env.SSH_TTY then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function paste()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste, ["*"] = paste },
  }
  vim.opt.clipboard = "unnamedplus"
end

-- Remote-plugin hosts for Python, Node.js, Perl and Ruby: nothing in this config uses them,
-- and turning them off removes the :checkhealth warnings about missing "neovim" packages
vim.g.loaded_python3_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
