# dotfiles

[![test](https://github.com/seanyeh77/dotfiles/actions/workflows/test.yml/badge.svg)](https://github.com/seanyeh77/dotfiles/actions/workflows/test.yml)

Neovim ([LazyVim](https://www.lazyvim.org)) and tmux ([Oh my tmux!](https://github.com/gpakosz/.tmux)) in the Catppuccin theme, terminal setup for iTerm2 and Ghostty, plus optional [Claude Code](https://code.claude.com/docs/en/overview).

## Install

```bash
curl -fsSL seanyeh77.github.io/dotfiles | bash
```

It first shows a plan with versions and asks once. Run it again to update.

- **System** (sudo, every user): only missing OS packages such as git, tmux, compilers and ripgrep; installed ones are never upgraded. Without sudo rights this step is skipped.
- **Only you** (`~`, no sudo): Neovim, Node.js LTS, tree-sitter, [uv](https://docs.astral.sh/uv/), Python, lazygit, nvim plugins, LSP servers and Claude Code, kept at the latest release.
- **OS**: macOS, Debian, Ubuntu, Fedora, RHEL, Arch, openSUSE, Alpine, WSL and Termux, on amd64 or arm64.

## Terminal

- **iTerm2** (macOS): a profile with Catppuccin Mocha, JetBrainsMono Nerd Font and Option as Alt, made the default, and the Minimal theme (title bar in the terminal's colour, if you never picked a theme); restart iTerm2.
- **Ghostty**: `ghostty/config` with the same theme. Unlike iTerm2 it shows images inside nvim, also over SSH and in tmux.
- On macOS both are set up when installed; Ghostty is installed only when you run the installer in it.
- **Font**: JetBrainsMono Nerd Font is installed on macOS and on a Linux desktop. Servers you ssh into need none: your own terminal draws the text. Elsewhere, pick a [Nerd Font](https://www.nerdfonts.com) in your terminal, or icons show as boxes.
- **Over SSH**: copying in nvim and tmux reaches your local clipboard (OSC 52), and Ghostty presents itself as `xterm-256color`, so servers need no setup.

## Claude Code

The installer asks whether to install it and which plugins to add (Enter for all), and remembers the answers.

- Workflow: commit-commands, code-review, feature-dev, security-guidance, code-simplifier, claude-md-management, superpowers, context7
- Frontend: frontend-design, playwright, design, vercel-react-best-practices
- Language-server plugins for the languages nvim supports
- Claude is never added as a co-author: Claude Code is set not to add `Co-Authored-By` or session links, and a global git `commit-msg` hook removes those lines from any commit (each repository's own hooks still run).
- At the end the installer lists the MCP servers that still need a sign-in (run `/mcp` in Claude).

## Options

Set them before `bash`, e.g. `curl -fsSL seanyeh77.github.io/dotfiles | DOTFILES_ASK=1 bash`.

| Variable | Effect |
| --- | --- |
| `DOTFILES_ASK=1` | Ask the Claude Code questions again |
| `INSTALL_CLAUDE=1\|0`, `CLAUDE_PLUGINS="a b"` | Answer them up front |
| `ASSUME_YES=1` | Do not ask before installing |
| `NO_SUDO=1` / `USE_SUDO=1` | Never use sudo / ask for the sudo password even if you are not in an admin group |
| `PYTHON_VERSION=3.13` | Pin Python instead of the latest |
| `DOTFILES_TERMINAL=iterm2\|ghostty\|none` | Set up only that terminal (`ghostty` installs it if missing) |
| `NO_ITERM=1` / `NO_GHOSTTY=1` | Skip one terminal |
| `DOTFILES_FONT=1\|0` | Install the Nerd Font or not |
| `DOTFILES_DIR` | Where the repo goes (default `~/dotfiles`) |

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
| `Space ac` / `Space as` | Open Claude / send the selection to Claude |
| `Space aa` / `Space ad` | Accept / reject Claude's diff |
| `Space gc` | Compare the file with a commit you pick (again to close) |
| `Space gg` | lazygit: stage, commit, push, browse history |
| `:qa` | Quit |

Supported languages are Python, C/C++, TypeScript, Rust, Go, Bash, Lua, JSON, YAML, TOML, Docker, Markdown and CMake. To add one, run `:LazyExtras`, or add an import line to `nvim/lua/config/lazy.lua`.

With Claude Code installed, Claude sees the file and selection you have open in nvim and shows its edits as diffs there. In a Claude that was already running, type `/ide` and pick Neovim.

For C/C++, clangd needs a `compile_commands.json` in the project root. Generate it with `cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON` or `bear -- make`.

## tmux

The prefix is `Ctrl-a`.

| Keys | Action |
| --- | --- |
| `C-a \|` / `C-a -` | Split side by side / top and bottom |
| `C-a h/j/k/l` | Move between panes |
| `C-a +` | Maximize the pane |
| `C-a c` / `C-a n` | New / next window |
| `C-a [` | Copy mode: `v` to select, `y` to copy |
| `C-a A` | Open Claude Code, connected to the nvim in the same folder |

## Shell

`shell/env.sh` is loaded from `~/.bashrc` and `~/.zshrc`. It puts `~/.local/bin` and Mason's tools on `PATH`, loads Ghostty's shell integration, and adds:

| Command | Action |
| --- | --- |
| `sshk host` | ssh, but first copy your SSH key to the host if needed, so later logins need no password |
