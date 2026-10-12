-- Overrides on top of LazyVim and its language extras (loaded last, see config/lazy.lua).

local uname = vim.uv.os_uname()
local is_linux_arm64 = uname.sysname == "Linux" and (uname.machine == "aarch64" or uname.machine == "arm64")
local is_musl = vim.fn.filereadable("/etc/alpine-release") == 1

-- A server binary installed by the OS package manager (not by Mason)
local function system_bin(name)
  local path = vim.fn.exepath(name)
  return path ~= "" and not path:find("/mason/", 1, true)
end

-- Exported for install.sh and CI (lua/dotfiles/headless.lua)
_G.DOTFILES = _G.DOTFILES or {}

return {
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },

  -- Language servers
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      -- Bash is not part of LazyVim's defaults
      opts.servers.bashls = opts.servers.bashls or {}

      -- marksman is a .NET binary that needs ICU at startup, which minimal images (Fedora,
      -- RHEL, openSUSE, Alpine) lack; it does not need culture data, so run it without
      if opts.servers.marksman ~= nil and opts.servers.marksman ~= false then
        local m = opts.servers.marksman == true and {} or opts.servers.marksman
        m.cmd_env = vim.tbl_extend("force", m.cmd_env or {}, { DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1" })
        -- Mason's marksman is a glibc binary: on musl (Alpine) only a system marksman can run
        if is_musl then
          m.mason = false
          m.enabled = system_bin("marksman")
        end
        opts.servers.marksman = m
      end

      -- clangd: prefer the OS package (reliable, and Mason has no linux arm64 / musl build)
      local clangd = opts.servers.clangd
      if clangd ~= nil and clangd ~= false then
        clangd = clangd == true and {} or clangd
        if system_bin("clangd") then
          clangd.mason = false
        elseif is_linux_arm64 or is_musl then
          clangd.enabled = false -- no clangd available on this machine
        end
        opts.servers.clangd = clangd
      end

      -- lua_ls: Mason ships a glibc binary, so use Alpine's lua-language-server on musl
      if is_musl then
        local lua_ls = opts.servers.lua_ls
        lua_ls = (lua_ls == true or lua_ls == nil) and {} or lua_ls
        lua_ls.mason = false
        lua_ls.enabled = system_bin("lua-language-server")
        opts.servers.lua_ls = lua_ls
      end
    end,
  },

  -- Mason packages
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      -- codelldb is the Rust/C debugger for LazyVim's DAP extra, which is not enabled
      opts.ensure_installed = vim.tbl_filter(function(name)
        return name ~= "codelldb"
      end, opts.ensure_installed)
      -- Servers Claude Code's language-server plugins look for on PATH (shell/env.sh adds Mason's bin)
      vim.list_extend(opts.ensure_installed, { "typescript-language-server" })
      if not is_musl then
        table.insert(opts.ensure_installed, "rust-analyzer")
      end
      _G.DOTFILES.mason_tools = vim.deepcopy(opts.ensure_installed)
      -- During install.sh, headless.lua is the only installer (see the treesitter note below)
      if vim.env.DOTFILES_HEADLESS_INSTALL == "1" then
        opts.ensure_installed = {}
      end
    end,
  },

  -- Treesitter: bash and gitcommit on top of the extras
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "bash", "gitcommit", "diff" })
      _G.DOTFILES.ts_langs = vim.deepcopy(opts.ensure_installed)
      -- During `install.sh`, the installer compiles parsers itself and waits for them. Without this,
      -- LazyVim would also start background builds that get killed when headless nvim exits.
      if vim.env.DOTFILES_HEADLESS_INSTALL == "1" then
        opts.ensure_installed = {}
      end
    end,
  },
}
