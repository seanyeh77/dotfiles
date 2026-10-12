-- ~/.config/nvim/init.lua
-- Neovim >= 0.11; macOS / Linux / WSL, amd64 / arm64

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ========== Options ==========
local o = vim.opt
o.number = true
o.relativenumber = true
o.mouse = "a"
o.clipboard = "unnamedplus"
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.smartindent = true
o.ignorecase = true
o.smartcase = true
o.signcolumn = "yes"
o.termguicolors = true
o.updatetime = 250
o.undofile = true
o.splitright = true
o.splitbelow = true
o.scrolloff = 8

-- ========== Languages (edit these lists to add a language) ==========
local uname = vim.uv.os_uname()
local is_linux_arm64 = uname.sysname == "Linux" and (uname.machine == "aarch64" or uname.machine == "arm64")
local is_musl = vim.fn.filereadable("/etc/alpine-release") == 1

-- LSP servers (lspconfig names), installed by Mason by default
local servers = {
  "pyright",       -- Python
  "bashls",        -- Bash / sh
  "lua_ls",        -- Lua
  "rust_analyzer", -- Rust
  "ts_ls",         -- JavaScript / TypeScript
  "jsonls",        -- JSON
  "yamlls",        -- YAML
  "dockerls",      -- Dockerfile
  "marksman",      -- Markdown
  "clangd",        -- C / C++ / CUDA
}
-- gopls needs go to install
if vim.fn.executable("go") == 1 then table.insert(servers, "gopls") end

-- Servers that use the system package when present (server -> executable), bypassing Mason
--   clangd: Mason has no linux arm64 / musl build, and distro clangd is reliable
--   lua_ls: Mason ships a glibc binary that cannot run on musl (Alpine)
local prefer_system = { clangd = "clangd" }
if is_musl then prefer_system.lua_ls = "lua-language-server" end

-- Platforms where Mason has no binary at all: only the system package can provide it
local mason_unavailable = {}
if is_linux_arm64 or is_musl then mason_unavailable.clangd = true end

local mason_servers, system_servers = {}, {}
for _, s in ipairs(servers) do
  local exe = prefer_system[s]
  if exe and vim.fn.executable(exe) == 1 then
    table.insert(system_servers, s)
  elseif not mason_unavailable[s] then
    table.insert(mason_servers, s)
  end
end

-- Formatters (Mason package names)
local mason_tools = { "stylua", "ruff", "shfmt", "prettier", "clang-format" }

-- Exported for CI (ci/verify.lua reads these lists)
_G.DOTFILES = { mason_servers = mason_servers, mason_tools = mason_tools, system_servers = system_servers }

-- Treesitter parsers (syntax highlighting)
_G.TS_LANGS = {
  "c", "cpp", "cuda", "python", "bash", "lua", "rust", "go",
  "javascript", "typescript", "tsx", "json", "yaml", "toml",
  "dockerfile", "make", "cmake", "markdown", "markdown_inline",
  "html", "css", "sql", "vim", "vimdoc", "diff", "gitcommit",
}

-- Setting CFLAGS replaces tree-sitter's default compiler flags, which include -Wall.
-- gcc 12.2 (Debian 12) spends minutes on -Wall for large generated parsers (e.g. gitcommit).
-- install.sh sets the same default for headless installs.
if not vim.env.CFLAGS or vim.env.CFLAGS == "" then vim.env.CFLAGS = "-O2" end

-- ========== lazy.nvim ==========
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  -- Colorscheme
  { "folke/tokyonight.nvim", priority = 1000,
    config = function() vim.cmd.colorscheme("tokyonight") end },

  -- Syntax highlighting
  { "nvim-treesitter/nvim-treesitter", branch = "main", lazy = false, build = ":TSUpdate",
    config = function()
      -- Only install missing parsers in interactive sessions. Headless runs (install.sh, CI)
      -- are handled by install.sh, so several nvim processes never compile at once or get
      -- killed mid-build and leave stale locks behind.
      if #vim.api.nvim_list_uis() > 0 then
        local ts = require("nvim-treesitter")
        local installed = ts.get_installed()
        local missing = vim.tbl_filter(function(l) return not vim.list_contains(installed, l) end, _G.TS_LANGS)
        if #missing > 0 then ts.install(missing) end
      end
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          if pcall(vim.treesitter.start, args.buf) then
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end },

  -- LSP: Mason installs, lspconfig configures, mason-lspconfig enables automatically
  { "mason-org/mason.nvim", opts = {} },
  { "neovim/nvim-lspconfig" },
  { "mason-org/mason-lspconfig.nvim",
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
    opts = { automatic_enable = true } },
  { "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason-lspconfig.nvim" },
    opts = { ensure_installed = vim.list_extend(vim.deepcopy(mason_servers), mason_tools) } },

  -- Completion
  { "saghen/blink.cmp", version = "1.*",
    opts = {
      keymap = { preset = "default" }, -- <C-y> accept, <C-n>/<C-p> select
      completion = { documentation = { auto_show = true } },
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
      fuzzy = { implementation = "prefer_rust_with_warning" },
    } },

  -- Formatting
  { "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_format" },
        sh = { "shfmt" }, bash = { "shfmt" },
        c = { "clang-format" }, cpp = { "clang-format" }, cuda = { "clang-format" },
        rust = { "rustfmt", lsp_format = "fallback" },
        go = { "gofmt" },
        javascript = { "prettier" }, typescript = { "prettier" },
        json = { "prettier" }, yaml = { "prettier" }, markdown = { "prettier" },
      },
    } },

  -- Utilities
  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
  { "lewis6991/gitsigns.nvim", opts = {} },
  { "folke/which-key.nvim", event = "VeryLazy", opts = {} },
}, { checker = { enabled = false } })

-- ========== Per-server LSP settings ==========
vim.lsp.config("lua_ls", {
  settings = { Lua = { diagnostics = { globals = { "vim" } } } },
})
-- Servers from system packages are not managed by Mason, so enable them explicitly
for _, s in ipairs(system_servers) do vim.lsp.enable(s) end

vim.diagnostic.config({ virtual_text = true, severity_sort = true })

-- ========== Keymaps ==========
-- Built into Neovim 0.11: K hover, grn rename, gra code action, grr references, gri implementation
local map = vim.keymap.set
map("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
map("n", "<leader>f", function() require("conform").format({ lsp_format = "fallback" }) end,
  { desc = "Format buffer" })
map("n", "<leader>e", vim.diagnostic.open_float, { desc = "Show diagnostic" })
map("n", "<leader>sf", function() require("telescope.builtin").find_files() end, { desc = "Find files" })
map("n", "<leader>sg", function() require("telescope.builtin").live_grep() end, { desc = "Grep" })
map("n", "<leader>sb", function() require("telescope.builtin").buffers() end, { desc = "Buffers" })
