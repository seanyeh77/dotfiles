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

-- Space f y / f Y / f l: copy the current file's full path, its path relative to the working
-- directory, or the full path with the line number (path:42). Over SSH the copy reaches your own
-- computer's clipboard (OSC 52, see options.lua).
local function copy_path(fmt, with_line)
  return function()
    local path = vim.fn.expand(fmt)
    if path == "" then
      vim.notify("This buffer has no file", vim.log.levels.WARN)
      return
    end
    if with_line then
      path = path .. ":" .. vim.fn.line(".")
    end
    vim.fn.setreg("+", path)
    vim.notify("Copied " .. path)
  end
end
vim.keymap.set("n", "<leader>fy", copy_path("%:p"), { desc = "Copy file path" })
vim.keymap.set("n", "<leader>fY", copy_path("%:."), { desc = "Copy relative file path" })
vim.keymap.set("n", "<leader>fl", copy_path("%:p", true), { desc = "Copy file path:line" })

-- Space f o: open the current file in the system's default app, e.g. a PDF in Preview to read every
-- page (nvim's image preview shows only the first). Over SSH there is no app to open it with, so it
-- tells you how to download the file instead.
vim.keymap.set("n", "<leader>fo", function()
  local path = vim.fn.expand("%:p")
  if path == "" then
    vim.notify("This buffer has no file", vim.log.levels.WARN)
    return
  end
  if vim.env.SSH_CONNECTION then
    vim.notify("Over SSH: run `tsz " .. vim.fn.expand("%:.") .. "` in the shell to download it", vim.log.levels.WARN)
    return
  end
  local _, err = vim.ui.open(path)
  if err then
    vim.notify(err, vim.log.levels.ERROR)
  end
end, { desc = "Open file in system app" })

-- Space c i / c I: the class under the cursor's parent classes / the classes that inherit from it,
-- in a list to jump through. Needs a language server with type hierarchy (clangd, jdtls; not pyright).
local function type_hierarchy(kind)
  return function()
    if #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/prepareTypeHierarchy" }) == 0 then
      vim.notify("This file's language server cannot show class inheritance", vim.log.levels.WARN)
      return
    end
    vim.lsp.buf.typehierarchy(kind)
  end
end
vim.keymap.set("n", "<leader>ci", type_hierarchy("supertypes"), { desc = "Parent classes" })
vim.keymap.set("n", "<leader>cI", type_hierarchy("subtypes"), { desc = "Child classes" })
