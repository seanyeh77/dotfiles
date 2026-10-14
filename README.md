# dotfiles

[![test](https://github.com/seanyeh77/dotfiles/actions/workflows/test.yml/badge.svg)](https://github.com/seanyeh77/dotfiles/actions/workflows/test.yml)

Neovim ([LazyVim](https://www.lazyvim.org)) and tmux ([Oh my tmux!](https://github.com/gpakosz/.tmux)) in the Catppuccin theme, plus optional [Claude Code](https://code.claude.com/docs/en/overview).

## Install

```bash
curl -fsSL seanyeh77.github.io/dotfiles | bash
```

Before changing anything it shows a plan with versions and asks once: system changes (OS packages, needs sudo, affects every user) are only made for missing packages, while your own tools in `~` (Neovim, Node.js LTS, tree-sitter, uv, Python, nvim plugins, LSP servers, Claude Code) are installed or updated to the latest release. Claude Code is set not to add itself as a co-author of commits and PRs. Run it again to update.

- **OS**: macOS, Debian, Ubuntu, Fedora, RHEL, Arch, openSUSE, Alpine and WSL, on amd64 or arm64
- **Per user**: Neovim, Node.js, tree-sitter, [uv](https://docs.astral.sh/uv/) and Python go in `~/.local`; sudo is only asked for missing OS packages (git, tmux, compilers, ripgrep)
- **Font**: use a [Nerd Font](https://www.nerdfonts.com) in your local terminal, or icons show as boxes
- **Claude Code**: the installer asks whether to install it and which plugins to add (press Enter for all):
  - Workflow: commit-commands, code-review, feature-dev, security-guidance, code-simplifier, claude-md-management, superpowers, context7
  - Frontend: frontend-design, playwright, design, vercel-react-best-practices

## Neovim

The leader key is `Space`. Press it and wait to see every binding.

| Keys | Action |
| --- | --- |
| `Space Space` / `Space /` | Find file / search text |
| `Space e` | File explorer |
| `Shift-h` / `Shift-l` | Previous / next file |
| `Ctrl-h/j/k/l` | Move between windows |
| `gd` / `gr` / `K` | Definition / references / docs |
| `Space cr` / `Space cf` | Rename / format |
| `Ctrl-/` | Terminal |
| `:qa` | Quit |

Supported languages are Python, C/C++, TypeScript, Rust, Go, Bash, Lua, JSON, YAML, TOML, Docker, Markdown and CMake. To add one, run `:LazyExtras`, or add an import line to `nvim/lua/config/lazy.lua`.

For C/C++, clangd needs a `compile_commands.json` in the project root. Generate it with `cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON` or `bear -- make`.

## tmux

The prefix is `Ctrl-a`.

| Keys | Action |
| --- | --- |
| `C-a \|` / `C-a -` | Split side by side / top and bottom |
| `C-a h/j/k/l` | Move between panes |
| `C-a +` | Maximize the pane |
| `C-a c` / `C-a n` | New / next window |
| `C-a A` | Open Claude Code |
