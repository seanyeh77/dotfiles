-- Claude Code IDE integration, on top of LazyVim's ai.claudecode extra (enabled in
-- config/lazy.lua when `claude` is installed).
--
-- nvim runs a small server that Claude Code connects to. Claude then knows which file is open
-- and what is selected, can read nvim's diagnostics, and shows its edits as diffs in nvim.
--   Space a c   open Claude (inside tmux: in a new tmux pane on the right)
--   Space a s   send the selection (visual mode) to Claude
--   Space a b   add the current file to Claude's context
--   Space a a / Space a d   accept / reject a diff Claude proposed
-- A Claude started elsewhere (e.g. tmux prefix + A, which runs `claude --ide`) connects too;
-- in an already running Claude, type /ide and pick Neovim.
if vim.fn.executable("claude") == 0 then
  return {}
end

-- Headless runs (install.sh, CI) start no server
local headless = vim.tbl_contains(vim.v.argv, "--headless")

return {
  "coder/claudecode.nvim",
  -- Load at startup, not on the first Space a key: the server must be running before Claude
  -- connects (/ide or claude --ide), otherwise Claude finds no Neovim
  lazy = headless,
  opts = function(_, opts)
    opts.auto_start = not headless
    if vim.env.TMUX then
      -- Open Claude in a tmux pane next to nvim instead of a terminal inside nvim. tmux starts
      -- the pane, so pass the connection variables (port etc.) to it explicitly.
      opts.terminal = vim.tbl_deep_extend("force", opts.terminal or {}, {
        provider = "external",
        provider_opts = {
          external_terminal_cmd = function(cmd, env)
            local args = { "tmux", "split-window", "-h", "-l", "40%", "-c", vim.fn.getcwd() }
            for k, v in pairs(env or {}) do
              vim.list_extend(args, { "-e", k .. "=" .. tostring(v) })
            end
            table.insert(args, cmd)
            return args
          end,
        },
      })
    end
  end,
}
