# dotfiles

[![test](https://github.com/seanyeh77/dotfiles/actions/workflows/test.yml/badge.svg)](https://github.com/seanyeh77/dotfiles/actions/workflows/test.yml)

Neovim ([LazyVim](https://www.lazyvim.org)) and tmux ([Oh my tmux!](https://github.com/gpakosz/.tmux)) in the Catppuccin theme, terminal setup for iTerm2 and Ghostty, plus optional [Claude Code](https://code.claude.com/docs/en/overview).

## Install

```bash
curl -fsSL seanyeh77.github.io/dotfiles | bash
```

1. **Choose**: a checklist of the optional parts (Claude Code and its plugins, Docker, terminal setup, Nerd Font, SSH tools). `↑↓` move, `Space` toggles, `Enter` continues. Your choices are remembered.
2. **Plan**: what will be installed or updated, with versions, split into system changes (sudo) and your own `~`. One key press to confirm.
3. **Install**: one line per step with a spinner; independent downloads (Neovim, Node.js, uv and Python, lazygit, SSH tools, fonts, Claude Code) run in parallel, as do the LSP servers (16 at a time), the treesitter parsers and Claude's plugins; on macOS, `brew update` runs while you read the plan. The commands' output goes to `~/.local/state/dotfiles/install.log`.
4. **Summary**: what changed, what failed and why, and the next steps.

Run it again to update. Without a terminal (CI, `> file`) it prints plain lines with all the output instead.

No copy of this repo stays behind: the files are copied into place (`~/.config/nvim`, `~/.tmux.conf.local`, `~/.config/ghostty/config`, and `~/.config/dotfiles` for the shell setup and git hooks), and the download is deleted. On an update, a file you edited is saved as `<name>.bak.<time>` before it is replaced, and files you added are left alone. The `~/dotfiles` folder of older versions is removed (kept if it has changes of yours).

- **System** (sudo, every user): only missing OS packages such as git, tmux, compilers and ripgrep; installed ones are never upgraded. Without sudo rights this step is skipped.
- **Docker** (optional, off by default): Docker Desktop on macOS, Docker Engine with Compose on Linux, and you are added to the `docker` group so it runs without sudo (log in again first). Only offered when you have sudo; if Docker is already there, only the group is offered.
- **Only you** (`~`, no sudo): Neovim, Node.js LTS, tree-sitter, [uv](https://docs.astral.sh/uv/), Python, lazygit, nvim plugins, LSP servers and Claude Code, kept at the latest release.
- **OS**: macOS, Debian, Ubuntu, Fedora, RHEL, Arch, openSUSE, Alpine, WSL and Termux, on amd64 or arm64.

## Terminal

- **iTerm2** (macOS): a profile with Catppuccin Mocha, JetBrainsMono Nerd Font and Option as Alt, made the default, and the Minimal theme (title bar in the terminal's colour, if you never picked a theme); restart iTerm2.
- **Ghostty**: `ghostty/config` with the same theme. Unlike iTerm2 it shows images inside nvim, also over SSH and in tmux.
- On macOS both are set up when installed; Ghostty is installed only when you run the installer in it.
- **Updates** (macOS): an older Ghostty or iTerm2 is updated to the release its own updater offers. One that is open (e.g. the one running the installer) is left alone, and the summary says to use its menu, *Check for Updates*.
- **Font**: JetBrainsMono Nerd Font is installed on macOS and on a Linux desktop. Servers you ssh into need none: your own terminal draws the text. Elsewhere, pick a [Nerd Font](https://www.nerdfonts.com) in your terminal, or icons show as boxes.
- **Over SSH**: copying in nvim and tmux reaches your local clipboard (OSC 52), and Ghostty presents itself as `xterm-256color`, so servers need no setup.

## Claude Code

Pick it and its plugins in the checklist (all on by default).

- Workflow: commit-commands, code-review, feature-dev, security-guidance, code-simplifier, claude-md-management, superpowers, context7
- Frontend: frontend-design, playwright, design, vercel-react-best-practices
- Language-server plugins for the languages nvim supports
- Phone notifications are on: the Claude app on your phone gets a push when Claude is done and when it waits for you (a permission or a question). They arrive while the session has Remote Control on (`/remote-control`); turn either off in `/config` (*Push when Claude decides*, *Push when actions required*), later runs keep your choice.
- Claude is never added as a co-author: Claude Code is set not to add `Co-Authored-By` or session links, and a global git `commit-msg` hook removes those lines from any commit (each repository's own hooks still run).
- At the end the installer lists the MCP servers that still need a sign-in (run `/mcp` in Claude).

## Options

Set them before `bash`, e.g. `curl -fsSL seanyeh77.github.io/dotfiles | DOTFILES_ASK=1 bash`.

| Variable | Effect |
| --- | --- |
| `DOTFILES_ASK=1` | Show the checklist again |
| `INSTALL_CLAUDE`, `CLAUDE_PLUGINS="a b"`, `INSTALL_DOCKER`, `SETUP_TERMINAL`, `INSTALL_FONT`, `SETUP_SSH` | Preset the choices (`1` or `0`) |
| `ASSUME_YES=1` | Do not ask before installing |
| `DOTFILES_PLAIN=1` | No spinner: every command's output on screen |
| `NO_SUDO=1` / `USE_SUDO=1` | Never use sudo / ask for the sudo password even if you are not in an admin group |
| `PYTHON_VERSION=3.13` | Pin Python instead of the latest |
| `DOTFILES_TERMINAL=iterm2\|ghostty\|none` | Set up only that terminal (`ghostty` installs it if missing) |
| `NO_ITERM=1` / `NO_GHOSTTY=1` | Skip one terminal |
| `DOTFILES_DIR=PATH` | Install from this checkout instead of downloading the repo (the checkout is kept) |

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
| `Space cs` | Outline: classes and their members (again to close) |
| `Space ci` / `Space cI` | Parent classes / classes that inherit from this one (C++) |
| `Ctrl-/` | Terminal |
| `Space ac` / `Space as` | Open Claude / send the selection to Claude |
| `Space aa` / `Space ad` | Accept / reject Claude's diff |
| `Space fy` / `Space fY` / `Space fl` | Copy the file's full path / relative path / path:line |
| `Space fo` | Open the file in the system's app, e.g. a PDF in Preview (nvim shows only its first page) |
| `Space gc` | Compare the file with a commit you pick (again to close) |
| `Space gl`, then `Enter` | Compare the whole project with that commit: every changed file, your real files on the right (`gd` works there); `gm` shows the commit message, `q` closes |
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

## SSH

With **SSH tools** ticked in the checklist (the default), every machine gets [trzsz](https://github.com/trzsz/trzsz-go) (`trz` / `tsz`), [tssh](https://github.com/trzsz/trzsz-ssh) and [tsshd](https://github.com/trzsz/tsshd). Unticked, nothing is installed and `ssh` stays OpenSSH (tools an earlier run installed are left in `~/.local/bin`). On your own computer, `ssh` runs `tssh`: it reads `~/.ssh/config` like ssh does and adds the features below. Inside an ssh session, and in scripts, `ssh` stays the plain one; `command ssh` is always the plain one.

### Move files

Logged in to a server with `ssh`, also inside tmux:

| Command | Action |
| --- | --- |
| `tsz FILE...` | Download to your computer's `~/Downloads` (set in `~/.tssh.conf`) |
| `tsz -d DIR` | Download a whole folder |
| `trz` | Upload: pick files on your computer, they land in the current folder |

The server needs `trz` / `tsz`: this installer puts them there, or run `tssh --install-trzsz HOST` from your computer.

### Pick a host

`ssh` on its own opens a menu of the hosts in `~/.ssh/config`: type to search, `Enter` to log in. In tmux, `Space` selects several hosts, then `p` logs in to each in its own pane (`w`: windows).

### Keep sessions alive (UDP mode)

For a server you run yourself, the session can survive your laptop sleeping, a Wi-Fi change or a VPN reconnect, like mosh:

1. The server needs `tsshd` (this installer puts it in `~/.local/bin`, or run `tssh --install-tsshd HOST`) and UDP ports 61001-61999 open, e.g. `sudo ufw allow 61001:61999/udp`.
2. Add `#!! UdpMode yes` to that host in `~/.ssh/config` (ssh ignores `#!!` lines):

   ```
   Host myvm
     HostName 10.1.253.116
     User seanyeh77
     #!! UdpMode yes
   ```

3. `ssh myvm` as usual. After a network break it reconnects by itself; `Ctrl-D` while it waits gives up.

Leave it off for servers whose firewall you cannot change (school or competition clusters): there `ssh` works as usual over TCP. The installer adds one `Host *` line at the end of `~/.ssh/config` so tssh finds `tsshd` in `~/.local/bin` on the server.

## Shell

`~/.config/dotfiles/env.sh` (from `shell/env.sh`) is loaded from `~/.bashrc` and `~/.zshrc`. It puts `~/.local/bin` and Mason's tools on `PATH`, loads Ghostty's shell integration, and adds:

| Command | Action |
| --- | --- |
| `sshk host` | ssh, but first copy your ed25519 key (`~/.ssh/id_ed25519`, created if missing) to the host if needed, so later logins need no password |
