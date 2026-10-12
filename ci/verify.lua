-- CI 驗證：nvim --headless -c "luafile ci/verify.lua"
-- 檢查 startup 錯誤、Mason 套件、Treesitter parser、LSP 是否真的 attach
-- 任一項失敗以 exit code 1 結束

local results, failed = {}, 0
local function check(name, ok, detail)
  if not ok then failed = failed + 1 end
  table.insert(results, string.format("%s %-40s %s", ok and "PASS" or "FAIL", name, detail or ""))
end

-- 1. startup 錯誤
local errs = {}
for _, m in ipairs(vim.split(vim.fn.execute("messages"), "\n")) do
  if m:match("E%d+:") or m:match("Error") then table.insert(errs, m) end
end
check("startup: no errors", #errs == 0, table.concat(errs, " | "))
check("colorscheme loaded", vim.g.colors_name ~= nil, tostring(vim.g.colors_name))
check("blink.cmp loaded", (pcall(require, "blink.cmp")))
check("conform loaded", (pcall(require, "conform")))

-- 2. Mason 套件
local cfg = _G.DOTFILES
check("init.lua exports DOTFILES", cfg ~= nil)
if cfg then
  local registry = require("mason-registry")
  local map = {}
  local ok_map, mappings = pcall(function() return require("mason-lspconfig").get_mappings() end)
  if ok_map and mappings and mappings.lspconfig_to_package then map = mappings.lspconfig_to_package end
  for _, server in ipairs(cfg.mason_servers) do
    local pkg = map[server] or server
    check("mason: " .. server, registry.is_installed(pkg), pkg)
  end
  for _, tool in ipairs(cfg.mason_tools) do
    check("mason: " .. tool, registry.is_installed(tool))
  end
end

-- 3. Treesitter parser
for _, lang in ipairs(_G.TS_LANGS or {}) do
  local ok, res = pcall(vim.treesitter.language.add, lang)
  check("treesitter: " .. lang, ok and res ~= nil and res ~= false, ok and "" or tostring(res))
end

-- 4. LSP 實際 attach（開檔後等 client 起來）
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local samples = {
  { file = "main.py",   client = "pyright",       text = { "def add(a: int, b: int) -> int:", "    return a + b" } },
  { file = "main.c",    client = "clangd",        text = { "int main(void) { return 0; }" } },
  { file = "main.lua",  client = "lua_ls",        text = { "local x = 1", "return x" } },
  { file = "main.sh",   client = "bashls",        text = { "#!/usr/bin/env bash", "echo hi" } },
  { file = "main.ts",   client = "ts_ls",         text = { "const x: number = 1;", "export default x;" } },
  { file = "data.json", client = "jsonls",        text = { '{ "a": 1 }' } },
  { file = "Dockerfile", client = "dockerls",     text = { "FROM ubuntu:24.04" } },
}
for _, s in ipairs(samples) do
  local path = tmp .. "/" .. s.file
  vim.fn.writefile(s.text, path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  local attached = vim.wait(60000, function()
    for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
      if c.name == s.client then return true end
    end
    return false
  end, 500)
  check("lsp attach: " .. s.client, attached, s.file)
end

-- 5. formatter 實際執行（python 用 ruff）
vim.cmd("edit " .. vim.fn.fnameescape(tmp .. "/main.py"))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x=1" })
local ok_fmt = pcall(require("conform").format, { timeout_ms = 20000 })
local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
check("format: ruff (python)", ok_fmt and line == "x = 1", line)

-- 報告（headless 下 print 不換行，直接寫 stdout）
local function out(s) io.stdout:write(s .. "\n") end
out("\n========== dotfiles verify ==========")
out(string.format("nvim %s, %s %s", tostring(vim.version()), vim.uv.os_uname().sysname, vim.uv.os_uname().machine))
for _, r in ipairs(results) do out(r) end
out(string.format("========== %d checks, %d failed ==========", #results, failed))
io.stdout:flush()
vim.cmd(failed == 0 and "qa!" or "cquit 1")
