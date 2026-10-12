# dotfiles

[![test](https://github.com/seanyeh77/dotfiles/actions/workflows/test.yml/badge.svg)](https://github.com/seanyeh77/dotfiles/actions/workflows/test.yml)

A Neovim + tmux development environment, installed with one command.

| OS | Package manager | Notes |
| --- | --- | --- |
| macOS | Homebrew | Homebrew is installed if missing |
| Debian / Ubuntu | apt | |
| Fedora / RHEL / Rocky / Alma | dnf / yum | ripgrep and fd need EPEL on RHEL; skipped if unavailable |
| Arch | pacman | |
| openSUSE | zypper | |
| Alpine | apk | musl: some Mason tools cannot run (best effort) |
| Windows | WSL | Run inside WSL, which counts as Linux; native Windows is not supported |

Both amd64 and arm64 are supported. glibc Linux always uses the official Neovim release; macOS and Alpine use the package manager's Neovim. The config needs Neovim 0.11 or later.

## Install / update

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
```

Without curl:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
```

Re-running the same command updates everything (pulls the latest config, syncs plugins and LSP servers). Existing `~/.config/nvim` and `~/.tmux.conf` are backed up as `.bak.<timestamp>` before being replaced.

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
| `nvim/init.lua` | lazy.nvim, Treesitter, Mason + LSP, blink.cmp completion, conform formatting, telescope |
| `tmux.conf` | Prefix `C-a`, mouse, vim-style pane navigation, `prefix + A` for Claude, tpm plugins |
| `shell/env.sh` | Adds `~/.local/bin` and Mason's `bin` to `PATH`; sourced from `~/.bashrc` / `~/.zshrc` |
| `ci/verify.lua` | Checks that plugins, LSP servers, parsers and formatting actually work |
| `ci/verify-claude.sh` | Checks that Claude Code and its plugins are installed |
| `.github/workflows/test.yml` | Runs the installer and verification on every supported OS and architecture |

## Adding a language

Edit the lists near the top of `nvim/init.lua`:

- `servers`: LSP servers (lspconfig names)
- `mason_tools`: formatters (Mason package names)
- `TS_LANGS`: Treesitter parsers

## Key bindings

| Keys | Action |
| --- | --- |
| `gd` / `K` | Go to definition / hover docs |
| `grn` / `gra` / `grr` | Rename / code action / references |
| `<Space>f` | Format buffer |
| `<Space>e` | Show diagnostic |
| `<Space>sf` / `<Space>sg` / `<Space>sb` | Find files / grep / buffers |
| tmux `C-a \|` / `C-a -` | Split left-right / top-bottom |
| tmux `C-a h/j/k/l` | Move between panes |
| tmux `C-a A` | Open Claude Code in a split |

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
- **Slow parser builds with gcc 12.2.** tree-sitter compiles parsers with `-Wall` by default, which makes gcc 12.2 take minutes on large generated parsers such as `gitcommit`. Both `install.sh` and `init.lua` set `CFLAGS=-O2` to avoid it.
- **Checking the result.** Run `:checkhealth` and `:Mason` inside Neovim.
