-- Keymaps are loaded on the VeryLazy event. LazyVim's defaults:
-- https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

-- Space g c: compare the current file with any commit. Pick the commit from this file's history
-- (the preview shows what each commit changed); the old version opens on the left. Press
-- Space g c again to close the comparison.
vim.keymap.set("n", "<leader>gc", function()
  if vim.wo.diff then
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)):match("^gitsigns://") then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    vim.cmd("diffoff!")
    return
  end
  Snacks.picker.git_log_file({
    title = "Compare with commit",
    confirm = function(picker, item)
      picker:close()
      if item and item.commit then
        vim.schedule(function()
          require("gitsigns").diffthis(item.commit)
        end)
      end
    end,
  })
end, { desc = "Compare with a commit (toggle)" })
