-- Show images inside nvim (PNG/JPG files, images in Markdown) with snacks.image. It needs a
-- terminal with the kitty graphics protocol: Ghostty, kitty or WezTerm (not iTerm2 or
-- Terminal.app, where nothing changes). Works over SSH and inside tmux (allow-passthrough on).
return {
  "folke/snacks.nvim",
  opts = {
    image = { enabled = true },
  },
}
