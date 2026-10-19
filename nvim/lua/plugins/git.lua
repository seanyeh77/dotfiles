-- Compare the project with a commit: in the commit list (Space g l / Space g L), Enter opens every
-- file that differs between that commit and what is on disk now. The right side is your real file,
-- so gd, K, editing and saving all work there; the left side is the commit's version. q closes it,
-- gm shows the commit's message and the commits after it (the changes this comparison includes).
-- (Snacks' default Enter checks the commit out instead; lazygit does that on purpose.)

local function compare(picker, item)
  picker:close()
  if item and item.commit then
    vim.schedule(function()
      vim.cmd("DiffviewOpen " .. item.commit)
    end)
  end
end

local close = { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close the comparison" } }

local function show_message()
  local view = require("diffview.lib").get_current_view()
  local rev = view and view.left
  if not (rev and rev.commit) then
    vim.notify("This comparison is not against a commit", vim.log.levels.WARN)
    return
  end
  local function git(...)
    local r = vim.system({ "git", ... }, { cwd = view.adapter.ctx.toplevel, text = true }):wait()
    return vim.split(vim.trim(r.stdout or ""), "\n")
  end
  local lines = git("show", "-s", "--format=commit %H%nAuthor: %an <%ae>%nDate:   %ad%n%n%B", rev.commit)
  local later = git("log", "--format=%h %s (%an, %ar)", rev.commit .. "..HEAD")
  if later[1] ~= "" then
    vim.list_extend(lines, { "", "Commits after it, included in this comparison (" .. #later .. "):", "" })
    vim.list_extend(lines, later)
  end
  Snacks.win({
    text = lines,
    ft = "git",
    width = 0.7,
    height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8)),
    border = "rounded",
    title = " " .. rev:abbrev() .. " ",
    wo = { wrap = true, cursorline = false },
    keys = { q = "close" },
  })
end
local message = { "n", "gm", show_message, { desc = "Commit message" } }

return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
    opts = {
      enhanced_diff_hl = true,
      keymaps = { view = { close, message }, file_panel = { close, message }, file_history_panel = { close } },
    },
  },
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          git_log = { title = "Compare with commit (Enter)", confirm = compare },
        },
      },
    },
  },
}
