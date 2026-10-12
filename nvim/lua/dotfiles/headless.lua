-- Headless install and inspection helpers, used by install.sh and ci/verify.lua.
--
--   nvim --headless -c "lua require('dotfiles.headless').install()"   install everything, then quit
--
-- The lists come from LazyVim itself (its core plus the extras in config/lazy.lua), so this file
-- never repeats which languages are configured.
local M = {}

local function out(s)
  io.stdout:write(s .. "\n")
  io.stdout:flush()
end
M.out = out

local collected
--- Load LazyVim's language plugins and return what they want installed:
---   { mason = { package names }, ts = { parser names }, servers = { lspconfig names } }
function M.collect()
  if collected then
    return collected
  end
  local lazy = require("lazy")
  -- LazyVim decides which servers go through Mason from Mason's registry. On a fresh machine the
  -- registry is not downloaded yet, so refresh it first; otherwise no server would be installed.
  lazy.load({ plugins = { "mason.nvim" } })
  local refreshed = false
  require("mason-registry").refresh(function()
    refreshed = true
  end)
  if not vim.wait(120000, function()
    return refreshed
  end, 200) then
    out("!! Mason registry refresh timed out (network?)")
  end
  -- Record the servers LazyVim passes to mason-lspconfig (exactly what it would install)
  lazy.load({ plugins = { "mason-lspconfig.nvim" } })
  local mlsp = require("mason-lspconfig")
  local servers = {}
  local setup = mlsp.setup
  mlsp.setup = function(o)
    o = o or {}
    servers = vim.deepcopy(o.ensure_installed or {})
    if vim.env.DOTFILES_HEADLESS_INSTALL == "1" then
      o.ensure_installed = {} -- install them ourselves, so only one installer runs
    end
    return setup(o)
  end
  lazy.load({ plugins = { "mason.nvim", "nvim-lspconfig", "nvim-treesitter" } })
  mlsp.setup = setup

  local map = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
  local seen, mason = {}, {}
  local function add(name)
    if name and not seen[name] then
      seen[name] = true
      table.insert(mason, name)
    end
  end
  LazyVim.opts("mason.nvim") -- resolves opts, which records the full list (plugins/dotfiles.lua)
  for _, tool in ipairs(_G.DOTFILES.mason_tools or {}) do
    add(tool)
  end
  for _, server in ipairs(servers) do
    add(map[server] or server)
  end
  table.sort(mason)

  LazyVim.opts("nvim-treesitter") -- resolves opts, which records the full list (plugins/dotfiles.lua)
  local ts = vim.fn.uniq(vim.fn.sort(vim.deepcopy(_G.DOTFILES.ts_langs or {})))

  collected = { mason = mason, ts = ts, servers = servers }
  return collected
end

--- Install every Mason package, waiting until each one succeeded or failed.
---@return string[] failed
local function install_mason(names, timeout_ms)
  local mr = require("mason-registry") -- already refreshed by M.collect()
  local pending, failed = {}, {}
  for _, name in ipairs(names) do
    local ok, pkg = pcall(mr.get_package, name)
    if not ok then
      table.insert(failed, name .. " (not in registry)")
    elseif not pkg:is_installed() then
      pending[name] = pkg
    end
  end
  M._on_failed = function(pkg)
    if pending[pkg.name] then
      pending[pkg.name] = nil
      table.insert(failed, pkg.name)
    end
  end
  if not M._listening then
    M._listening = true
    mr:on("package:install:failed", function(pkg)
      M._on_failed(pkg)
    end)
  end
  for name, pkg in pairs(pending) do
    if not pkg:is_installing() then -- LazyVim may already have started it
      out("  mason: installing " .. name)
      pkg:install()
    end
  end
  vim.wait(timeout_ms, function()
    for name, pkg in pairs(pending) do
      if pkg:is_installed() then
        pending[name] = nil
      end
    end
    return next(pending) == nil
  end, 500)
  for name in pairs(pending) do
    table.insert(failed, name .. " (timed out)")
  end
  table.sort(failed)
  return failed
end

--- Compile every treesitter parser (two rounds: parallel builds occasionally fail).
---@return string[] missing
local function install_ts(langs, timeout_ms)
  local TS = require("nvim-treesitter")
  local lock = (vim.env.XDG_CACHE_HOME or (vim.env.HOME .. "/.cache")) .. "/tree-sitter/lock"
  local function missing()
    local have = {}
    for _, l in ipairs(TS.get_installed()) do
      have[l] = true
    end
    return vim.tbl_filter(function(l)
      return not have[l]
    end, langs)
  end
  for round = 1, 2 do
    local todo = missing()
    if #todo == 0 then
      break
    end
    out(("  treesitter round %d: %s"):format(round, table.concat(todo, " ")))
    for _, f in ipairs(vim.fn.glob(lock .. "/*.lock", false, true)) do
      os.remove(f) -- stale locks left by an interrupted build
    end
    pcall(function()
      TS.install(todo):wait(timeout_ms)
    end)
  end
  return missing()
end

--- Install Mason packages and treesitter parsers, report, then quit nvim (exit 1 on failures).
function M.install()
  M.failed = 0
  local ok, err = pcall(function()
    local want = M.collect()
    if #want.servers == 0 then
      out("!! LazyVim selected no Mason language servers (registry unavailable?)")
      M.failed = M.failed + 1
    end
    out("Mason packages: " .. table.concat(want.mason, " "))
    local failed = install_mason(want.mason, 15 * 60 * 1000)
    if #failed > 0 then -- one retry for transient download errors
      local retry = vim.tbl_map(function(f)
        return (f:gsub(" %(.*%)$", ""))
      end, failed)
      out("  mason: retrying " .. table.concat(retry, " "))
      failed = install_mason(retry, 10 * 60 * 1000)
    end
    out("Treesitter parsers: " .. table.concat(want.ts, " "))
    local missing = install_ts(want.ts, 5 * 60 * 1000)
    if #failed > 0 then
      out("!! Mason packages not installed: " .. table.concat(failed, ", "))
    end
    if #missing > 0 then
      out("!! treesitter parsers not installed: " .. table.concat(missing, ", "))
    end
    M.failed = M.failed + #failed + #missing
  end)
  if not ok then
    out("!! headless install error: " .. tostring(err))
    M.failed = 1
  end
  vim.cmd(M.failed == 0 and "qa!" or "cquit 1")
end

return M
