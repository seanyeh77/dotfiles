-- markdownlint (LazyVim's markdown extra) with ~/.config/nvim/.markdownlint-cli2.yaml, which turns
-- off the rules that only add noise in notes and reports (line length, table pipe alignment)
return {
  "mfussenegger/nvim-lint",
  optional = true,
  opts = {
    linters = {
      ["markdownlint-cli2"] = {
        prepend_args = { "--config", vim.fn.stdpath("config") .. "/.markdownlint-cli2.yaml" },
      },
    },
  },
}
