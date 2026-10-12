-- CI verification: nvim --headless -c "luafile ci/verify.lua"
-- Checks startup errors, the colorscheme, every Mason package and treesitter parser that
-- LazyVim wants, that LSP servers actually attach, and that formatting works.
-- Exits with code 1 if any check fails.

local H = require("dotfiles.headless")
local results, failed = {}, 0
local function check(name, ok, detail)
  if not ok then
    failed = failed + 1
  end
  table.insert(results, string.format("%s %-40s %s", ok and "PASS" or "FAIL", name, detail or ""))
end

-- 1. Startup
local errs = {}
for _, m in ipairs(vim.split(vim.fn.execute("messages"), "\n")) do
  if m:match("E%d+:") or m:match("Error") then
    table.insert(errs, m)
  end
end
check("startup: no errors", #errs == 0, table.concat(errs, " | "))
check("LazyVim loaded", _G.LazyVim ~= nil)
check("colorscheme catppuccin", (vim.g.colors_name or ""):find("catppuccin") ~= nil, tostring(vim.g.colors_name))

-- 2. Mason packages and treesitter parsers (lists come from LazyVim's config)
local want = H.collect()
local mr = require("mason-registry")
for _, name in ipairs(want.mason) do
  check("mason: " .. name, mr.is_installed(name))
end
for _, lang in ipairs(want.ts) do
  local ok, res = pcall(vim.treesitter.language.add, lang)
  check("treesitter: " .. lang, ok and res ~= nil and res ~= false, ok and "" or tostring(res))
end

-- 3. LSP servers attach (open a file, wait for the client)
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local samples = {
  { file = "main.py", client = "pyright", text = { "def add(a: int, b: int) -> int:", "    return a + b" } },
  { file = "main.c", client = "clangd", text = { "int main(void) { return 0; }" } },
  { file = "main.lua", client = "lua_ls", text = { "local x = 1", "return x" } },
  { file = "main.sh", client = "bashls", text = { "#!/usr/bin/env bash", "echo hi" } },
  { file = "main.ts", client = "vtsls", text = { "const x: number = 1;", "export default x;" } },
  { file = "data.json", client = "jsonls", text = { '{ "a": 1 }' } },
  { file = "conf.yaml", client = "yamlls", text = { "a: 1" } },
  { file = "Dockerfile", client = "dockerls", text = { "FROM ubuntu:24.04" } },
  { file = "README.md", client = "marksman", text = { "# Title" } },
}
-- Skip servers this platform deliberately disables (e.g. clangd on linux arm64 without a system clangd)
local servers = LazyVim.opts("nvim-lspconfig").servers or {}
for _, s in ipairs(samples) do
  local sopts = servers[s.client]
  if type(sopts) == "table" and sopts.enabled == false then
    table.insert(results, string.format("SKIP %-40s %s", "lsp attach: " .. s.client, "disabled on this platform"))
  else
    local path = tmp .. "/" .. s.file
    vim.fn.writefile(s.text, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    local attached = vim.wait(60000, function()
      for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
        if c.name == s.client then
          return true
        end
      end
      return false
    end, 500)
    check("lsp attach: " .. s.client, attached, s.file)
  end
end

-- 4. Formatting actually runs (python: ruff through LazyVim's formatter)
vim.cmd("edit " .. vim.fn.fnameescape(tmp .. "/main.py"))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x=1" })
local ok_fmt = pcall(require("conform").format, { lsp_format = "fallback", timeout_ms = 20000 })
local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
check("format: python", ok_fmt and line == "x = 1", line)

-- Report
H.out("\n========== dotfiles verify ==========")
H.out(("nvim %s, %s %s"):format(tostring(vim.version()), vim.uv.os_uname().sysname, vim.uv.os_uname().machine))
for _, r in ipairs(results) do
  H.out(r)
end
H.out(("========== %d checks, %d failed =========="):format(#results, failed))
vim.cmd(failed == 0 and "qa!" or "cquit 1")
