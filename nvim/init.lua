-- ~/.config/nvim/init.lua
-- Neovim >= 0.11；macOS / Linux / WSL，amd64 / arm64 皆可用

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ========== 基本設定 ==========
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

-- ========== 語言清單（要加語言改這裡） ==========
local uname = vim.uv.os_uname()
local is_linux_arm64 = uname.sysname == "Linux" and (uname.machine == "aarch64" or uname.machine == "arm64")
local is_musl = vim.fn.filereadable("/etc/alpine-release") == 1
-- 系統已有 clangd（apt/dnf/apk 裝的）就用系統的；否則由 Mason 安裝
local system_clangd = vim.fn.executable("clangd") == 1

-- LSP servers（lspconfig 名稱），由 Mason 安裝
local mason_servers = {
  "pyright",       -- Python
  "bashls",        -- Bash / sh
  "lua_ls",        -- Lua
  "rust_analyzer", -- Rust
  "ts_ls",         -- JavaScript / TypeScript
  "jsonls",        -- JSON
  "yamlls",        -- YAML
  "dockerls",      -- Dockerfile
  "marksman",      -- Markdown
}
-- Mason 的 clangd 沒有 linux arm64 / musl 版本，這些平台只能用系統的
if not system_clangd and not is_linux_arm64 and not is_musl then
  table.insert(mason_servers, "clangd")
end
-- gopls 需要 go 才能安裝
if vim.fn.executable("go") == 1 then table.insert(mason_servers, "gopls") end

-- Formatter（Mason 套件名稱）
local mason_tools = { "stylua", "ruff", "shfmt", "prettier", "clang-format" }

-- Treesitter parser（語法高亮）
_G.TS_LANGS = {
  "c", "cpp", "cuda", "python", "bash", "lua", "rust", "go",
  "javascript", "typescript", "tsx", "json", "yaml", "toml",
  "dockerfile", "make", "cmake", "markdown", "markdown_inline",
  "html", "css", "sql", "vim", "vimdoc", "diff", "gitcommit",
}

-- ========== lazy.nvim ==========
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  -- 主題
  { "folke/tokyonight.nvim", priority = 1000,
    config = function() vim.cmd.colorscheme("tokyonight") end },

  -- 語法高亮
  { "nvim-treesitter/nvim-treesitter", branch = "main", lazy = false, build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").install(_G.TS_LANGS)
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          if pcall(vim.treesitter.start, args.buf) then
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end },

  -- LSP：Mason 負責安裝，lspconfig 提供設定，mason-lspconfig 自動 enable
  { "mason-org/mason.nvim", opts = {} },
  { "neovim/nvim-lspconfig" },
  { "mason-org/mason-lspconfig.nvim",
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
    opts = { automatic_enable = true } },
  { "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason-lspconfig.nvim" },
    opts = { ensure_installed = vim.list_extend(vim.deepcopy(mason_servers), mason_tools) } },

  -- 自動補全
  { "saghen/blink.cmp", version = "1.*",
    opts = {
      keymap = { preset = "default" }, -- <C-y> 確認, <C-n>/<C-p> 選擇
      completion = { documentation = { auto_show = true } },
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
      fuzzy = { implementation = "prefer_rust_with_warning" },
    } },

  -- 格式化
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

  -- 實用小工具
  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
  { "lewis6991/gitsigns.nvim", opts = {} },
  { "folke/which-key.nvim", event = "VeryLazy", opts = {} },
}, { checker = { enabled = false } })

-- ========== LSP 個別設定 ==========
vim.lsp.config("lua_ls", {
  settings = { Lua = { diagnostics = { globals = { "vim" } } } },
})
-- 系統 clangd 不經 Mason，要手動 enable
if system_clangd then
  vim.lsp.enable("clangd")
end

vim.diagnostic.config({ virtual_text = true, severity_sort = true })

-- ========== 快捷鍵 ==========
-- Neovim 0.11 內建：K 文件, grn 改名, gra code action, grr 參考, gri 實作
local map = vim.keymap.set
map("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
map("n", "<leader>f", function() require("conform").format({ lsp_format = "fallback" }) end,
  { desc = "Format buffer" })
map("n", "<leader>e", vim.diagnostic.open_float, { desc = "Show diagnostic" })
map("n", "<leader>sf", function() require("telescope.builtin").find_files() end, { desc = "Find files" })
map("n", "<leader>sg", function() require("telescope.builtin").live_grep() end, { desc = "Grep" })
map("n", "<leader>sb", function() require("telescope.builtin").buffers() end, { desc = "Buffers" })
