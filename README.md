# dotfiles

[![test](https://github.com/seanyeh77/dotfiles/actions/workflows/test.yml/badge.svg)](https://github.com/seanyeh77/dotfiles/actions/workflows/test.yml)

A Neovim + tmux development environment, installed with one command:

- **Neovim**: [LazyVim](https://www.lazyvim.org) with language support for Python, C/C++, TypeScript/JavaScript, Rust, Go (when Go is installed), Bash, Lua, JSON, YAML, TOML, Docker, Markdown and CMake, in the [Catppuccin](https://catppuccin.com) theme
- **tmux**: [Oh my tmux!](https://github.com/gpakosz/.tmux) with a Catppuccin status line
- **Claude Code** (optional), with plugins

The status line separators and file icons need a [Nerd Font](https://www.nerdfonts.com) in the terminal you connect from (the font lives on your local machine, not on the server).

| OS | Package manager | Notes |
| --- | --- | --- |
| macOS | Homebrew | Homebrew is installed if missing |
| Debian / Ubuntu | apt | |
| Fedora / RHEL / Rocky / Alma | dnf / yum | ripgrep and fd need EPEL on RHEL; skipped if unavailable |
| Arch | pacman | |
| openSUSE | zypper | |
| Alpine | apk | musl: some Mason tools cannot run (best effort) |
| Windows | WSL | Run inside WSL, which counts as Linux; native Windows is not supported |

Both amd64 and arm64 are supported. glibc Linux always uses the official Neovim release; macOS and Alpine use the package manager's Neovim. LazyVim needs Neovim 0.11.2 or later.

## Install / update

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
```

Without curl:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
```

Re-running the same command updates everything (pulls the latest config, syncs plugins and LSP servers). Existing `~/.config/nvim`, `~/.tmux.conf` and `~/.tmux.conf.local` are backed up as `.bak.<timestamp>` before being replaced.

## Claude Code (optional)

At the start, the installer asks whether to install [Claude Code](https://code.claude.com/docs/en/overview) and which plugins to add from Anthropic's official marketplace:

| Plugin | Purpose |
| --- | --- |
| `commit-commands` | Commit, push and open pull requests |
| `code-review` | Review your changes before committing |
| `feature-dev` | Guided feature development workflow |
| `security-guidance` | Warn about security issues while Claude edits |

Language-server plugins (`pyright-lsp`, `clangd-lsp`, `typescript-lsp`, `rust-analyzer-lsp`, `lua-lsp`, and `gopls-lsp` when Go is installed) are added automatically. They give Claude live diagnostics and go-to-definition, reusing the servers Mason installed for Neovim: `shell/env.sh` puts Mason's `bin` folder and `~/.local/bin` on your `PATH`.

In tmux, `prefix + A` opens `claude` in a split next to the current pane. Log in the first time you start it.

To skip the questions, preset the answers:

```bash
INSTALL_CLAUDE=1 CLAUDE_PLUGINS="commit-commands code-review" bash <(curl -fsSL https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
```

`INSTALL_CLAUDE=0` skips Claude Code. Without a terminal (CI, cron) and nothing preset, it is skipped.

## Contents

| File | Purpose |
| --- | --- |
| `install.sh` | Installs system packages, Neovim, Node.js and the tree-sitter CLI, links the config, installs plugins headless |
| `nvim/lua/config/lazy.lua` | LazyVim and the enabled language extras |
| `nvim/lua/config/options.lua` | Options on top of LazyVim's defaults |
| `nvim/lua/plugins/dotfiles.lua` | Overrides: Catppuccin, bash, system clangd / Alpine handling, extra Mason packages |
| `nvim/lua/dotfiles/headless.lua` | Installs every Mason package and parser LazyVim wants and waits for them (used by `install.sh` and CI) |
| `tmux/tmux.conf.local` | Oh my tmux! settings: Catppuccin colours, prefix `C-a`, `prefix + A` for Claude |
| `shell/env.sh` | Adds `~/.local/bin` and Mason's `bin` to `PATH`; sourced from `~/.bashrc` / `~/.zshrc` |
| `ci/verify.lua` | Checks that plugins, LSP servers, parsers and formatting actually work |
| `ci/verify-tmux.sh` | Checks that tmux loads the config with the expected prefix, colours and keys |
| `ci/verify-claude.sh` | Checks that Claude Code and its plugins are installed |
| `.github/workflows/test.yml` | Runs the installer and verification on every supported OS and architecture |

## Adding a language

LazyVim has a ready-made "extra" for most languages, which sets up the LSP server, formatter, linter and Treesitter parser together. Browse them inside Neovim with `:LazyExtras`, then add the import to `nvim/lua/config/lazy.lua` so every machine gets it, for example:

```lua
{ import = "lazyvim.plugins.extras.lang.java" },
```

Re-run the installer (or restart Neovim) to install the new tools.

## Key bindings

Neovim's leader key is `Space`. Press it and wait: a menu lists every binding.

| Neovim | Action |
| --- | --- |
| `Space Space` / `Space /` | Find files / search text in the project |
| `Space e` | File explorer |
| `Space ,` | Switch between open files |
| `Shift-h` / `Shift-l` | Previous / next file (tab bar) |
| `gd` / `gr` / `K` | Go to definition / references / hover docs |
| `Space ca` / `Space cr` / `Space cf` | Code action / rename / format |
| `]d` / `[d` | Next / previous diagnostic |
| `Ctrl-h/j/k/l` | Move between splits |
| `Space l` / `Space cm` | Plugin manager (Lazy) / Mason |

The tmux prefix is `Ctrl-a`.

| tmux | Action |
| --- | --- |
| `C-a \|` or `C-a _` / `C-a -` | Split side by side / top and bottom |
| `C-a h/j/k/l` | Move between panes |
| `C-a +` | Maximize the current pane (again to restore) |
| `C-a c` / `C-a n` / `C-a p` | New window / next / previous |
| `C-a A` | Open Claude Code in a split |
| `C-a e` / `C-a r` | Edit / reload `~/.tmux.conf.local` |

## Environment variables

| Variable | Default |
| --- | --- |
| `DOTFILES_REPO` | `https://github.com/seanyeh77/dotfiles` |
| `DOTFILES_DIR` | `~/dotfiles` |
| `NODE_MAJOR` | `22` |
| `INSTALL_CLAUDE` | ask (`1` install, `0` skip) |
| `CLAUDE_PLUGINS` | ask (space-separated plugin names) |

## Troubleshooting

- **Old glibc (Debian 12, RHEL 9).** The prebuilt tree-sitter CLI needs glibc 2.39, so the installer builds it from source with cargo. The first install takes a few extra minutes.
- **Slow parser builds with gcc 12.2.** tree-sitter compiles parsers with `-Wall` by default, which makes gcc 12.2 take minutes on large generated parsers such as `gitcommit`. Both `install.sh` and `nvim/lua/config/options.lua` set `CFLAGS=-O2` to avoid it.
- **Icons show as boxes or question marks.** Install a Nerd Font on the machine you connect from and select it in that terminal.
- **Checking the result.** Run `:checkhealth`, `:Mason` and `:LazyHealth` inside Neovim.
