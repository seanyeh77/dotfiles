#!/usr/bin/env bash
# One-command installer for a Neovim + tmux development environment.
#   OS:   macOS, Debian/Ubuntu, Fedora/RHEL/Rocky, Arch, openSUSE, Alpine, WSL
#   Arch: amd64 / arm64
# Usage:      bash <(curl -fsSL https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
#   no curl:  bash <(wget -qO- https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
# Safe to re-run: it updates the repo and syncs plugins / LSP servers.
set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/seanyeh77/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
NODE_MAJOR="${NODE_MAJOR:-22}"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

# Running as root (e.g. in a container) may not have sudo
if [ "$(id -u)" -eq 0 ]; then sudo() { "$@"; }; fi

# Download with curl, falling back to wget
fetch() { # fetch URL [OUTFILE]
  if has curl; then
    if [ $# -ge 2 ]; then curl -fsSL -o "$2" "$1"; else curl -fsSL "$1"; fi
  elif has wget; then
    if [ $# -ge 2 ]; then wget -qO "$2" "$1"; else wget -qO- "$1"; fi
  else die "Need curl or wget"; fi
}

# ---------- Detect OS / architecture ----------
OS="$(uname -s)"
case "$(uname -m)" in
  x86_64|amd64)  ARCH=amd64; NVIM_ARCH=x86_64; NODE_ARCH=x64 ;;
  aarch64|arm64) ARCH=arm64; NVIM_ARCH=arm64;  NODE_ARCH=arm64 ;;
  *) die "Unsupported arch: $(uname -m)" ;;
esac

PM=""
case "$OS" in
  Darwin) PM=brew ;;
  Linux)
    for p in apt-get dnf yum pacman zypper apk; do has "$p" && { PM=$p; break; }; done
    [ -n "$PM" ] || die "No supported package manager (apt/dnf/yum/pacman/zypper/apk)" ;;
  MINGW*|MSYS*|CYGWIN*) die "Windows native is not supported, please use WSL: wsl --install" ;;
  *) die "Unsupported OS: $OS" ;;
esac
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1 || IS_WSL=0
log "OS: $OS ($PM)  Arch: $ARCH  WSL: $IS_WSL"

# The official nvim / node builds need glibc: use the package manager on macOS and musl (Alpine)
USE_PM_NVIM=0; USE_PM_NODE=0
[ "$PM" = brew ] && { USE_PM_NVIM=1; USE_PM_NODE=1; }
[ "$PM" = apk ]  && { USE_PM_NVIM=1; USE_PM_NODE=1; }

# ---------- Questions (asked up front so the rest runs unattended) ----------
# INSTALL_CLAUDE=1/0 and CLAUDE_PLUGINS="a b" preset the answers; with no terminal
# (CI, cron) and nothing preset, Claude Code is skipped.
CLAUDE_WORKFLOW_PLUGINS=(
  "commit-commands|commit, push and open pull requests"
  "code-review|review your changes before committing"
  "feature-dev|guided feature development workflow"
  "security-guidance|warn about security issues while Claude edits"
)
HAS_TTY=0; ( exec </dev/tty ) 2>/dev/null && HAS_TTY=1
ask() { # ask PROMPT DEFAULT -> REPLY
  REPLY="$2"
  [ "$HAS_TTY" = 1 ] || return 0
  printf '\033[1;36m??\033[0m %s ' "$1" > /dev/tty
  read -r REPLY < /dev/tty || true
  [ -n "$REPLY" ] || REPLY="$2"
}

if [ -z "${INSTALL_CLAUDE:-}" ]; then
  INSTALL_CLAUDE=0
  if [ "$HAS_TTY" = 1 ]; then
    ask "Install Claude Code? [Y/n]" y
    case "$REPLY" in [Nn]*) INSTALL_CLAUDE=0 ;; *) INSTALL_CLAUDE=1 ;; esac
  fi
fi
if [ "$INSTALL_CLAUDE" = 1 ] && [ -z "${CLAUDE_PLUGINS+set}" ]; then
  CLAUDE_PLUGINS=""
  for e in "${CLAUDE_WORKFLOW_PLUGINS[@]}"; do CLAUDE_PLUGINS="$CLAUDE_PLUGINS ${e%%|*}"; done
  if [ "$HAS_TTY" = 1 ]; then
    {
      echo "   Claude Code plugins (Anthropic's official marketplace):"
      i=1; for e in "${CLAUDE_WORKFLOW_PLUGINS[@]}"; do
        printf '     %d) %-18s %s\n' "$i" "${e%%|*}" "${e#*|}"; i=$((i + 1))
      done
      echo "   Language-server plugins are added automatically for the languages nvim supports."
    } > /dev/tty
    ask "Install which? all / none / numbers, e.g. 1 3 [all]" all
    case "$REPLY" in
      all|ALL|a) ;;
      none|NONE|n) CLAUDE_PLUGINS="" ;;
      *) CLAUDE_PLUGINS=""
         for n in $REPLY; do
           case "$n" in
             *[!0-9]*|"") warn "ignoring '$n'" ;;
             *) if [ "$n" -ge 1 ] && [ "$n" -le "${#CLAUDE_WORKFLOW_PLUGINS[@]}" ]; then
                  e="${CLAUDE_WORKFLOW_PLUGINS[$((n - 1))]}"; CLAUDE_PLUGINS="$CLAUDE_PLUGINS ${e%%|*}"
                else warn "ignoring '$n'"; fi ;;
           esac
         done ;;
    esac
  fi
fi
CLAUDE_PLUGINS="$(echo ${CLAUDE_PLUGINS:-})" # normalize spaces
[ "$INSTALL_CLAUDE" = 1 ] && log "Claude Code: yes, plugins: ${CLAUDE_PLUGINS:-none}" || log "Claude Code: skipped"

# ---------- System packages ----------
# Required: git, curl, unzip, tar, gzip (Mason downloads), a C compiler (treesitter parsers), tmux, ripgrep
# Optional: fd, clangd, xclip; installed when available, skipped with a warning otherwise
pm_install() { # pm_install REQUIRED... -- OPTIONAL...
  local req=() opt=() seen=0
  for a in "$@"; do
    if [ "$a" = "--" ]; then seen=1; continue; fi
    if [ $seen = 0 ]; then req+=("$a"); else opt+=("$a"); fi
  done
  case "$PM" in
    brew)    brew install "${req[@]}" ;;
    apt-get) sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${req[@]}" ;;
    dnf)     sudo dnf install -y "${req[@]}" ;;
    yum)     sudo yum install -y "${req[@]}" ;;
    pacman)  sudo pacman -S --noconfirm --needed "${req[@]}" ;;
    zypper)  sudo zypper --non-interactive install "${req[@]}" ;;
    apk)     sudo apk add "${req[@]}" ;;
  esac
  for p in "${opt[@]}"; do
    case "$PM" in
      brew)    brew install "$p" ;;
      apt-get) sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$p" ;;
      dnf)     sudo dnf install -y "$p" ;;
      yum)     sudo yum install -y "$p" ;;
      pacman)  sudo pacman -S --noconfirm --needed "$p" ;;
      zypper)  sudo zypper --non-interactive install "$p" ;;
      apk)     sudo apk add "$p" ;;
    esac >/dev/null 2>&1 || warn "optional package not available: $p"
  done
}

log "Installing system packages"
# Skip curl when present: on RHEL, curl-minimal conflicts with the curl package
CURL_PKG=curl; has curl && CURL_PKG=""
case "$PM" in
  brew)
    if ! has brew; then
      log "Installing Homebrew"
      NONINTERACTIVE=1 bash -c "$(fetch https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)"; done
    fi
    pm_install git tmux ripgrep fd neovim node -- tree-sitter-cli ;;
  apt-get)
    sudo apt-get update || true
    pm_install git $CURL_PKG wget unzip tar gzip xz-utils tmux ripgrep build-essential python3 python3-venv python3-pip \
      -- fd-find clangd xclip ;;
  dnf)
    pm_install git $CURL_PKG wget unzip tar gzip xz tmux gcc gcc-c++ make python3 python3-pip \
      -- ripgrep fd-find clang-tools-extra xclip ;;
  yum)
    pm_install git $CURL_PKG wget unzip tar gzip xz tmux gcc gcc-c++ make python3 python3-pip \
      -- ripgrep fd-find clang-tools-extra xclip ;;
  pacman)
    sudo pacman -Sy --noconfirm
    pm_install git $CURL_PKG wget unzip tar gzip xz tmux ripgrep base-devel python python-pip \
      -- fd clang xclip ;;
  zypper)
    sudo zypper --non-interactive refresh || true
    pm_install git $CURL_PKG wget unzip tar gzip xz tmux ripgrep gcc gcc-c++ make python3 python3-pip \
      -- fd clang-tools xclip ;;
  apk)
    sudo apk update
    pm_install bash git curl wget unzip tar gzip xz tmux ripgrep build-base python3 py3-pip neovim nodejs npm \
      -- fd clang-extra-tools lua-language-server tree-sitter-cli xclip ;;
esac

# Debian/Ubuntu ship fd as fdfind
if ! has fd && has fdfind; then sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sudo mkdir -p /usr/local/bin

# ---------- Neovim ----------
# glibc Linux: official release (distro versions are often too old; the config needs >= 0.11)
if [ "$USE_PM_NVIM" = 0 ]; then
  log "Installing Neovim (official release, $NVIM_ARCH)"
  fetch "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz" "$TMP/nvim.tar.gz"
  sudo rm -rf "/opt/nvim-linux-${NVIM_ARCH}"
  sudo tar -C /opt -xzf "$TMP/nvim.tar.gz"
  sudo ln -sf "/opt/nvim-linux-${NVIM_ARCH}/bin/nvim" /usr/local/bin/nvim
fi
hash -r
# Capture first, then trim: `nvim --version | head -1` can die of SIGPIPE (exit 141) under pipefail
NVIM_VER="$(nvim --version 2>/dev/null)" || die "nvim failed to run (glibc too old?). Try a newer OS release."
NVIM_VER="${NVIM_VER%%$'\n'*}"
NVIM_MINOR="$(printf '%s' "$NVIM_VER" | sed -E 's/.*v0\.([0-9]+).*/\1/')"
[ "${NVIM_MINOR:-0}" -ge 11 ] || warn "$NVIM_VER < 0.11, config needs 0.11+"

# ---------- Node.js (needed by pyright, ts_ls, bashls, prettier, ...) ----------
node_ok() { has node && [ "$(node -v | cut -d. -f1 | tr -d v)" -ge 18 ]; }
if ! node_ok && [ "$USE_PM_NODE" = 0 ]; then
  log "Installing Node.js $NODE_MAJOR ($NODE_ARCH)"
  BASE="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x"
  SUMS="$(fetch "$BASE/SHASUMS256.txt")"
  NODE_TAR="$(printf '%s\n' "$SUMS" | awk -v a="linux-${NODE_ARCH}.tar.xz" '$2 ~ a"$" {print $2; exit}')"
  [ -n "$NODE_TAR" ] || die "Cannot find Node.js tarball for linux-${NODE_ARCH}"
  fetch "$BASE/$NODE_TAR" "$TMP/$NODE_TAR"
  sudo rm -rf /opt/node && sudo mkdir -p /opt/node
  sudo tar -C /opt/node --strip-components=1 -xJf "$TMP/$NODE_TAR"
  for b in node npm npx; do sudo ln -sf "/opt/node/bin/$b" "/usr/local/bin/$b"; done
  hash -r
fi
node_ok || warn "Node.js >= 18 not found, JS-based LSPs (pyright, ts_ls...) will fail"

# ---------- tree-sitter CLI (nvim-treesitter uses it to compile parsers) ----------
if ! has tree-sitter && has npm; then
  log "Installing tree-sitter CLI"
  if [ "$PM" = brew ]; then npm install -g tree-sitter-cli >/dev/null
  else sudo npm install -g tree-sitter-cli >/dev/null; fi
  [ -x /opt/node/bin/tree-sitter ] && sudo ln -sf /opt/node/bin/tree-sitter /usr/local/bin/tree-sitter
  hash -r
fi
# The prebuilt tree-sitter binary (npm / GitHub release) needs glibc 2.39. On older systems
# (Debian 12, RHEL 9) it fails with "GLIBC_2.39 not found", so build it from source with cargo.
ts_broken() { local v; v="$(tree-sitter --version 2>&1)" || return 0; case "$v" in *GLIBC*) return 0 ;; esac; return 1; }
if has tree-sitter && ts_broken; then
  log "tree-sitter binary needs newer glibc, building from source with cargo (takes a few minutes)"
  if ! has cargo && [ ! -x "$HOME/.cargo/bin/cargo" ]; then
    fetch https://sh.rustup.rs "$TMP/rustup.sh"
    sh "$TMP/rustup.sh" -y --profile minimal --no-modify-path >/dev/null
  fi
  CARGO="$(command -v cargo || echo "$HOME/.cargo/bin/cargo")"
  "$CARGO" install --locked tree-sitter-cli
  sudo ln -sf "$HOME/.cargo/bin/tree-sitter" /usr/local/bin/tree-sitter
  hash -r
fi
if ! has tree-sitter || ts_broken; then
  warn "tree-sitter CLI missing or broken, syntax highlighting parsers will not compile"
fi

# ---------- dotfiles ----------
log "Linking dotfiles"
if [ -d "$DOTFILES_DIR/.git" ]; then
  # safe.directory: allow running as a different user than the repo owner (e.g. root in a container)
  git -c safe.directory="$DOTFILES_DIR" -C "$DOTFILES_DIR" pull --ff-only \
    || warn "git pull skipped (local changes, detached HEAD or no remote)"
else
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

link() { # back up existing config instead of overwriting it
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then mv "$dst" "$dst.bak.$(date +%s)"; fi
  ln -sfn "$src" "$dst"
}
link "$DOTFILES_DIR/nvim"      "$HOME/.config/nvim"
link "$DOTFILES_DIR/tmux.conf" "$HOME/.tmux.conf"

# Load shell/env.sh (PATH for ~/.local/bin and Mason) from the shell rc files, once
SOURCE_LINE="[ -f \"$DOTFILES_DIR/shell/env.sh\" ] && . \"$DOTFILES_DIR/shell/env.sh\" # dotfiles"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  # Always use ~/.bashrc; use ~/.zshrc when it exists, or on macOS where zsh is the default shell
  case "$rc" in
    */.zshrc) [ -f "$rc" ] || [ "$OS" = Darwin ] || continue ;;
  esac
  grep -qsF "$DOTFILES_DIR/shell/env.sh" "$rc" || printf '\n%s\n' "$SOURCE_LINE" >> "$rc"
done
# shellcheck source=shell/env.sh
. "$DOTFILES_DIR/shell/env.sh"

# ---------- tmux plugins ----------
log "Installing tmux plugins"
[ -d "$HOME/.tmux/plugins/tpm" ] || git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
"$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null || warn "tpm install failed, press prefix + I inside tmux"

# ---------- nvim plugins, LSP servers, treesitter parsers (all headless) ----------
# Bound every step so a network problem cannot hang forever (macOS has no timeout: run as is)
with_timeout() { local s="$1"; shift; if has timeout; then timeout "$s" "$@"; else "$@"; fi; }
log "Installing nvim plugins (Lazy)"
with_timeout 600 nvim --headless "+Lazy! sync" +qa || warn "Lazy sync failed or timed out, run :Lazy sync"
log "Installing LSP servers / formatters (Mason)"
with_timeout 900 nvim --headless -c "MasonToolsInstallSync" -c "qa" || warn "Mason failed or timed out (network?), check :Mason"

log "Installing treesitter parsers"
# Setting CFLAGS replaces tree-sitter's default compiler flags, which include -Wall.
# gcc 12.2 (Debian 12) spends minutes on -Wall for large generated parsers such as gitcommit;
# with CFLAGS set the same parser builds in seconds. init.lua sets the same default.
export CFLAGS="${CFLAGS:--O2}"
mkdir -p "$HOME/.cache/tree-sitter/lock"
# Parallel builds occasionally fail; the second round only retries what is still missing
for round in 1 2; do
  rm -f "$HOME/.cache/tree-sitter/lock/"*.lock # stale locks left by an interrupted round
  with_timeout 300 nvim --headless -c "lua require('nvim-treesitter').install(_G.TS_LANGS):wait(280000)" -c "qa" \
    || warn "treesitter round $round failed or timed out"
done
MISSING_TS="$(nvim --headless -c "lua local i=require('nvim-treesitter').get_installed(); local m={}; for _,l in ipairs(_G.TS_LANGS) do if not vim.list_contains(i,l) then table.insert(m,l) end end; io.stdout:write(table.concat(m,' '))" -c qa 2>/dev/null)" || true
[ -z "$MISSING_TS" ] || warn "treesitter parsers not installed: $MISSING_TS"

# ---------- Claude Code (optional, see the questions at the top) ----------
if [ "$INSTALL_CLAUDE" = 1 ]; then
  log "Installing Claude Code"
  if [ "$PM" = apk ]; then
    # musl: the native binary needs libgcc / libstdc++ and uses the system ripgrep
    sudo apk add libgcc libstdc++ ripgrep >/dev/null
    mkdir -p "$HOME/.claude"
    if [ ! -f "$HOME/.claude/settings.json" ]; then
      printf '{\n  "env": { "USE_BUILTIN_RIPGREP": "0" }\n}\n' > "$HOME/.claude/settings.json"
    elif ! grep -q USE_BUILTIN_RIPGREP "$HOME/.claude/settings.json"; then
      warn 'add "env": { "USE_BUILTIN_RIPGREP": "0" } to ~/.claude/settings.json (needed on Alpine)'
    fi
  fi
  # Native installer: updates itself in the background, so re-runs only install when missing
  if ! has claude; then
    fetch https://claude.ai/install.sh "$TMP/claude-install.sh"
    bash "$TMP/claude-install.sh"
    . "$DOTFILES_DIR/shell/env.sh"; hash -r
  fi
  if has claude; then
    log "$(claude --version 2>/dev/null || echo 'claude installed')"
    # The official marketplace is only registered by the first interactive session, so add it here
    MP=claude-plugins-official
    claude plugin marketplace add "anthropics/$MP" >/dev/null 2>&1 || true
    INSTALLED_PLUGINS="$(claude plugin list 2>/dev/null || true)"
    claude_plugin() { # claude_plugin NAME
      case "$INSTALLED_PLUGINS" in *"$1@$MP"*) return 0 ;; esac
      claude plugin install "$1@$MP" >/dev/null 2>&1 && log "  plugin: $1" || warn "plugin install failed: $1"
    }
    # Language-server plugins: one per nvim language whose server is on PATH (Mason's bin is)
    for pair in pyright-lsp:pyright-langserver clangd-lsp:clangd typescript-lsp:typescript-language-server \
                rust-analyzer-lsp:rust-analyzer lua-lsp:lua-language-server gopls-lsp:gopls; do
      if has "${pair#*:}"; then claude_plugin "${pair%%:*}"; fi
    done
    for p in ${CLAUDE_PLUGINS:-}; do claude_plugin "$p"; done
    log "Claude Code ready: run 'claude' (or prefix + A in tmux) and log in on first start"
  else
    warn "Claude Code install failed; see https://code.claude.com/docs/en/troubleshoot-install"
  fi
fi

log "Done. Open nvim and run :checkhealth to verify"
