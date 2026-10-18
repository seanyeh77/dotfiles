-- Compare the project with a commit: in the commit list (Space g l / Space g L), Enter opens every
-- file that differs between that commit and what is on disk now. The right side is your real file,
-- so gd, K, editing and saving all work there; the left side is the commit's version. q closes it.
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

return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
    opts = {
      enhanced_diff_hl = true,
      keymaps = { view = { close }, file_panel = { close }, file_history_panel = { close } },
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
