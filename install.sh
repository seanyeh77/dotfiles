#!/usr/bin/env bash
# One-command installer for a Neovim + tmux development environment.
#   OS:   macOS, Debian/Ubuntu, Fedora/RHEL/Rocky, Arch, openSUSE, Alpine, WSL
#   Arch: amd64 / arm64
# Usage:      curl -fsSL seanyeh77.github.io/dotfiles | bash
#   no curl:  wget -qO- seanyeh77.github.io/dotfiles | bash
# Safe to re-run: it updates the repo and syncs plugins / LSP servers.

# This is a bash script. When started by another shell (`curl ... | zsh`, `| sh`), hand over
# to bash: from a file run it again with bash, from a pipe download it again into bash.
# On macOS, sh is bash in POSIX mode, which sets BASH_VERSION but changes behaviour, so it
# hands over too. Written in plain POSIX sh so zsh and dash can run these lines first.
case ":${SHELLOPTS:-}:" in *:posix:*) DOTFILES_POSIX=1 ;; *) DOTFILES_POSIX=0 ;; esac
if [ -z "${BASH_VERSION:-}" ] || [ "$DOTFILES_POSIX" = 1 ]; then
  DOTFILES_URL="${DOTFILES_URL:-https://seanyeh77.github.io/dotfiles}"
  if ! command -v bash >/dev/null 2>&1; then
    echo "xx this installer needs bash; install bash and run it again" >&2; exit 1
  fi
  case "${0:-}" in
    *install.sh) [ -f "$0" ] && exec bash "$0" "$@" ;;
  esac
  echo "==> re-running with bash" >&2
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$DOTFILES_URL" | bash -s -- "$@"
  else
    wget -qO- "$DOTFILES_URL" | bash -s -- "$@"
  fi
  exit $?
fi

# Everything is wrapped in { ... } so bash reads the whole script before running any of it.
# With `curl ... | bash`, commands that read stdin would otherwise eat the rest of the script.
{
set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/seanyeh77/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

# Each user gets their own Neovim, Node.js and tree-sitter in ~/.local, so users on the same
# machine never share or overwrite each other's tools. Only shared OS packages (tmux, git,
# compilers, ripgrep) need sudo, and that step is skipped when sudo is not available.
LOCAL_BIN="$HOME/.local/bin"
LOCAL_OPT="$HOME/.local/opt"
mkdir -p "$LOCAL_BIN" "$LOCAL_OPT"
case ":$PATH:" in *":$LOCAL_BIN:"*) ;; *) PATH="$LOCAL_BIN:$PATH" ;; esac
export PATH

# Download with curl, falling back to wget; retry a few times so a network blip does not
# abort the whole install
fetch_once() { # fetch_once URL [OUTFILE]
  if has curl; then
    if [ $# -ge 2 ]; then curl -fsSL --connect-timeout 20 -o "$2" "$1"; else curl -fsSL --connect-timeout 20 "$1"; fi
  elif has wget; then
    if [ $# -ge 2 ]; then wget -qO "$2" "$1"; else wget -qO- "$1"; fi
  else die "Need curl or wget"; fi
}
fetch() { # fetch URL [OUTFILE]
  local i
  for i in 1 2 3 4; do
    if [ $# -ge 2 ]; then
      fetch_once "$@" && return 0
    else
      # Buffer stdout so a failed attempt does not leave partial output behind
      local out
      out="$(fetch_once "$@")" && { printf '%s\n' "$out"; return 0; }
    fi
    [ "$i" -lt 4 ] && { warn "download failed, retrying in $((i * 5)) s: $1"; sleep $((i * 5)); }
  done
  die "download failed after 4 attempts: $1"
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
# name|source|description; source is a marketplace (official, knowledge-work) or "skill"
CLAUDE_WORKFLOW_PLUGINS=(
  "commit-commands|official|commit, push and open pull requests"
  "code-review|official|review your changes before committing"
  "feature-dev|official|guided feature development workflow"
  "security-guidance|official|warn about security issues while Claude edits"
  "code-simplifier|official|simplify code Claude just changed, same behaviour"
  "claude-md-management|official|keep the project's CLAUDE.md notes up to date"
  "superpowers|official|brainstorm, TDD and debugging workflows (third-party)"
  "context7|official|up-to-date library docs for Claude (third-party)"
  "frontend-design|official|distinctive, production-grade web UI design"
  "playwright|official|let Claude open a browser and see the page (third-party)"
  "design|knowledge-work|design critique, accessibility and UX writing"
  "vercel-react-best-practices|skill|React / Next.js performance rules (Vercel)"
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
      echo "   Claude Code plugins and skills:"
      i=1; for e in "${CLAUDE_WORKFLOW_PLUGINS[@]}"; do
        printf '    %2d) %-28s %s\n' "$i" "${e%%|*}" "${e##*|}"; i=$((i + 1))
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


# ---------- What is missing ----------
# Only things that are not installed yet get installed: existing packages and tools are never
# upgraded or replaced. The plan is shown first and installed after one confirmation.
#
# OS packages as package[:command]. A package counts as installed when the package manager has
# it or, when a command is given, that command is on PATH (e.g. a git built from source).
# Required: git, curl, unzip, tar, gzip (Mason downloads), a C compiler (treesitter parsers), tmux, ripgrep
# perl: Oh my tmux! needs it to apply its theme (git usually pulls it in, minimal Alpine does not)
# Optional: installed when available, skipped with a warning otherwise
# Python is not here: each user gets their own from uv (below).
case "$PM" in
  brew)    OS_REQ=(git tmux ripgrep:rg fd neovim:nvim node)
           OS_OPT=(tree-sitter-cli:tree-sitter) ;;
  apt-get) OS_REQ=(git curl unzip tar gzip xz-utils:xz tmux ripgrep:rg build-essential)
           OS_OPT=(fd-find:fdfind clangd xclip perl wget) ;;
  dnf|yum) OS_REQ=(git curl unzip tar gzip xz tmux gcc gcc-c++:g++ make)
           OS_OPT=(ripgrep:rg fd-find:fd clang-tools-extra:clangd xclip perl wget) ;;
  pacman)  OS_REQ=(git curl unzip tar gzip xz tmux ripgrep:rg base-devel)
           OS_OPT=(fd clang:clangd xclip perl wget) ;;
  zypper)  OS_REQ=(git curl unzip tar gzip xz tmux ripgrep:rg gcc gcc-c++:g++ make)
           OS_OPT=(fd clang-tools:clangd xclip perl wget) ;;
  apk)     OS_REQ=(bash git curl unzip tar gzip xz tmux perl ripgrep:rg build-base neovim:nvim nodejs:node npm)
           OS_OPT=(fd clang-extra-tools:clangd lua-language-server tree-sitter-cli:tree-sitter xclip wget) ;;
esac
# Claude Code on musl needs libgcc / libstdc++ (and uses the system ripgrep, already required)
[ "$PM" = apk ] && [ "$INSTALL_CLAUDE" = 1 ] && OS_REQ+=(libgcc libstdc++)
BREW_LIST=""
[ "$PM" = brew ] && has brew && BREW_LIST=" $(brew list --formula -1 2>/dev/null | tr '\n' ' ') "
pkg_installed() { # pkg_installed PACKAGE
  local s
  case "$PM" in
    brew)    case "$BREW_LIST" in *" $1 "*) return 0 ;; esac; return 1 ;;
    apt-get) s="$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" || return 1
             case "$s" in *" installed") return 0 ;; esac; return 1 ;;
    dnf|yum|zypper) rpm -q --whatprovides "$1" >/dev/null 2>&1 ;;
    pacman)  pacman -Q "$1" >/dev/null 2>&1 || pacman -Qg "$1" >/dev/null 2>&1 ;;
    apk)     apk info -e "$1" >/dev/null 2>&1 ;;
  esac
}
spec_installed() { # spec_installed PACKAGE[:COMMAND]
  local pkg="${1%%:*}" cmd=""
  case "$1" in *:*) cmd="${1#*:}" ;; *) has "$1" && return 0 ;; esac
  { [ -n "$cmd" ] && has "$cmd"; } || pkg_installed "$pkg"
}
MISS_REQ=(); MISS_OPT=()
for s in "${OS_REQ[@]}"; do spec_installed "$s" || MISS_REQ+=("${s%%:*}"); done
for s in "${OS_OPT[@]}"; do spec_installed "$s" || MISS_OPT+=("${s%%:*}"); done
NEED_BREW=0; [ "$PM" = brew ] && ! has brew && NEED_BREW=1
NEED_OS=0; [ ${#MISS_REQ[@]} -gt 0 ] || [ ${#MISS_OPT[@]} -gt 0 ] || [ "$NEED_BREW" = 1 ] && NEED_OS=1
# Older versions of this installer linked /usr/local/bin/tree-sitter to one user's ~/.cargo,
# which other users cannot run; that link is removed (a system change, so it is in the plan)
OLD_TS_LINK=0
if [ -L /usr/local/bin/tree-sitter ]; then
  case "$(readlink /usr/local/bin/tree-sitter)" in */.cargo/bin/tree-sitter) OLD_TS_LINK=1 ;; esac
fi
NEED_SYS=0; [ "$NEED_OS" = 1 ] || [ "$OLD_TS_LINK" = 1 ] && NEED_SYS=1

# Per-user tools in ~/.local
nvim_ok() { # Neovim on PATH and >= 0.11
  local v; v="$(nvim --version 2>/dev/null)" || return 1
  # Capture first, then trim: `nvim --version | head -1` can die of SIGPIPE (exit 141) under pipefail
  v="$(printf '%s' "${v%%$'\n'*}" | sed -E 's/^NVIM v([0-9]+)\.([0-9]+).*/\1 \2/')"
  set -- $v
  [ "${1:-0}" -gt 0 ] 2>/dev/null || [ "${2:-0}" -ge 11 ] 2>/dev/null
}
node_ok() { has node && [ "$(node -v | cut -d. -f1 | tr -d v)" -ge 18 ]; }
ts_works() { local v; v="$("$1" --version 2>&1)" || return 1; case "$v" in *GLIBC*) return 1 ;; esac; return 0; }
# This user's own Neovim and Node.js (glibc Linux) are kept at the latest release: installed when
# missing, updated when a newer one is out. macOS and Alpine use the package manager's builds,
# which are installed when missing and otherwise left alone.
latest_url() { # final URL after redirects, empty on failure
  if has curl; then curl -fsSLI --connect-timeout 20 -o /dev/null -w '%{url_effective}' "$1" 2>/dev/null || true
  else wget -S --spider --max-redirect=0 "$1" 2>&1 | awk '/^ *Location:/ {print $2}' | tail -1 || true; fi
}
NVIM_CUR=""; NVIM_LATEST=""; NEED_NVIM=0
if [ "$USE_PM_NVIM" = 0 ]; then
  v="$("$LOCAL_OPT/nvim/bin/nvim" --version 2>/dev/null || true)"; v="${v%%$'\n'*}"; NVIM_CUR="${v#NVIM }"
  v="$(latest_url https://github.com/neovim/neovim/releases/latest)"; NVIM_LATEST="${v##*/tag/}"
  case "$NVIM_LATEST" in v[0-9]*) ;; *) NVIM_LATEST="" ;; esac
  if [ -z "$NVIM_CUR" ] || { [ -n "$NVIM_LATEST" ] && [ "$NVIM_LATEST" != "$NVIM_CUR" ]; }; then NEED_NVIM=1; fi
fi
NODE_CUR=""; NODE_LATEST=""; NEED_NODE=0
if [ "$USE_PM_NODE" = 0 ]; then
  NODE_CUR="$("$LOCAL_OPT/node/bin/node" -v 2>/dev/null || true)"
  # Latest LTS: first row of index.tab whose lts column is set (capture first: awk exits early)
  v="$(fetch_once https://nodejs.org/dist/index.tab 2>/dev/null || true)"
  NODE_LATEST="$(printf '%s\n' "$v" | awk -F'\t' 'NR > 1 && $10 != "-" && $10 != "" {print $1; exit}')"
  if [ -z "$NODE_CUR" ] || { [ -n "$NODE_LATEST" ] && [ "$NODE_LATEST" != "$NODE_CUR" ]; }; then NEED_NODE=1; fi
fi
NEED_TS=0
if [ "$PM" != brew ] && [ "$PM" != apk ] && ! ts_works "$LOCAL_BIN/tree-sitter"; then NEED_TS=1; fi
NEED_UV=0; has uv || NEED_UV=1
NEED_PY=0; [ -x "$LOCAL_BIN/python3" ] || NEED_PY=1
PYTHON_VERSION="${PYTHON_VERSION:-3.13}"

# Configuration
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
OH_MY_TMUX="$DATA_HOME/oh-my-tmux"
NEED_DOTFILES=0; [ -d "$DOTFILES_DIR/.git" ] || NEED_DOTFILES=1
NEED_OMT=0; [ -d "$OH_MY_TMUX/.git" ] || NEED_OMT=1
NEED_LAZY=0; [ -d "$DATA_HOME/nvim/lazy/LazyVim" ] || NEED_LAZY=1

# Claude Code and the chosen plugins / skills that are not installed yet
NEED_CLAUDE=0; MISS_PLUGINS=""
INSTALLED_PLUGINS=""
if [ "$INSTALL_CLAUDE" = 1 ]; then
  if has claude; then INSTALLED_PLUGINS="$(claude plugin list 2>/dev/null || true)"; else NEED_CLAUDE=1; fi
  plugin_source() { # plugin_source NAME -> official | knowledge-work | skill
    local e; for e in "${CLAUDE_WORKFLOW_PLUGINS[@]}"; do
      if [ "${e%%|*}" = "$1" ]; then e="${e#*|}"; echo "${e%%|*}"; return; fi
    done; echo official
  }
  plugin_installed() { # plugin_installed NAME
    case "$(plugin_source "$1")" in
      skill) [ -e "$HOME/.claude/skills/$1" ] ;;
      knowledge-work) case "$INSTALLED_PLUGINS" in *"$1@knowledge-work-plugins"*) return 0 ;; esac; return 1 ;;
      *) case "$INSTALLED_PLUGINS" in *"$1@claude-plugins-official"*) return 0 ;; esac; return 1 ;;
    esac
  }
  for p in ${CLAUDE_PLUGINS:-}; do plugin_installed "$p" || MISS_PLUGINS="$MISS_PLUGINS $p"; done
  MISS_PLUGINS="$(echo $MISS_PLUGINS)"
fi

# Who can install OS packages: root, Homebrew, or a user with sudo (asked only when needed).
# NO_SUDO=1 skips sudo.
SUDO_OK=0
if [ "$(id -u)" -eq 0 ]; then
  sudo() { "$@"; }; SUDO_OK=1
elif [ "$PM" = brew ]; then
  SUDO_OK=1 # Homebrew does not use sudo
elif [ "${NO_SUDO:-0}" != 1 ] && has sudo; then
  SUDO_OK=2 # ask for the password after the plan, only if OS packages are missing
fi

# ---------- Plan ----------
# Two parts: system changes (shared by every user, need sudo / Homebrew) and changes that stay
# in this user's home. Only items that are not installed yet are listed.
SYS_PLAN=(); USER_PLAN=()
sys_plan()  { SYS_PLAN+=("$(printf '     %-22s %s' "$1" "$2")"); }
user_plan() { USER_PLAN+=("$(printf '     %-22s %s' "$1" "$2")"); }
case "$PM" in
  brew)    PM_CMD="brew install" ;;
  apt-get) PM_CMD="apt-get install" ;;
  pacman)  PM_CMD="pacman -S" ;;
  apk)     PM_CMD="apk add" ;;
  *)       PM_CMD="$PM install" ;;
esac
if [ "$NEED_OS" = 1 ]; then
  [ "$NEED_BREW" = 1 ] && sys_plan "Homebrew" "installs into /opt/homebrew (or /usr/local), asks for sudo once"
  case "$PM" in
    apt-get) sys_plan "package index" "apt-get update (refresh only, nothing upgraded)" ;;
    pacman)  sys_plan "package index" "pacman -Sy (refresh only, nothing upgraded)" ;;
    zypper)  sys_plan "package index" "zypper refresh (refresh only, nothing upgraded)" ;;
    apk)     sys_plan "package index" "apk update (refresh only, nothing upgraded)" ;;
  esac
  [ ${#MISS_REQ[@]} -gt 0 ] && sys_plan "OS packages" "$PM_CMD ${MISS_REQ[*]}"
  [ ${#MISS_OPT[@]} -gt 0 ] && sys_plan "optional OS packages" "$PM_CMD ${MISS_OPT[*]} (skipped if not available)"
fi
[ "$OLD_TS_LINK" = 1 ] && sys_plan "old link" "rm /usr/local/bin/tree-sitter (points into one user's ~/.cargo)"
if [ "$NEED_NVIM" = 1 ]; then
  if [ -n "$NVIM_CUR" ]; then user_plan "Neovim ${NVIM_LATEST:-latest}" "update from $NVIM_CUR, in ~/.local/opt/nvim"
  else user_plan "Neovim ${NVIM_LATEST:-latest}" "in ~/.local/opt/nvim"; fi
fi
if [ "$NEED_NODE" = 1 ]; then
  if [ -n "$NODE_CUR" ]; then user_plan "Node.js ${NODE_LATEST:-LTS}" "latest LTS, update from $NODE_CUR, in ~/.local/opt/node"
  else user_plan "Node.js ${NODE_LATEST:-LTS}" "latest LTS, in ~/.local/opt/node"; fi
fi
[ "$NEED_TS" = 1 ]       && user_plan "tree-sitter CLI" "in ~/.local/opt/tree-sitter-cli (built with cargo on old glibc)"
[ "$NEED_UV" = 1 ]       && user_plan "uv" "in ~/.local/bin"
[ "$NEED_PY" = 1 ]       && user_plan "Python $PYTHON_VERSION" "with uv, python3 in ~/.local/bin"
[ "$NEED_DOTFILES" = 1 ] && user_plan "dotfiles" "clone to $DOTFILES_DIR"
[ "$NEED_OMT" = 1 ]      && user_plan "Oh my tmux!" "clone to $OH_MY_TMUX"
[ "$NEED_LAZY" = 1 ]     && user_plan "nvim plugins" "LazyVim, LSP servers, formatters, parsers in ~/.local/share/nvim"
[ "$NEED_CLAUDE" = 1 ]   && user_plan "Claude Code" "native installer, in ~/.local/bin"
[ -n "$MISS_PLUGINS" ]   && user_plan "Claude plugins" "$MISS_PLUGINS (in ~/.claude)"

if [ ${#SYS_PLAN[@]} -eq 0 ] && [ ${#USER_PLAN[@]} -eq 0 ]; then
  log "Everything is already installed; updating the config and adding any missing nvim plugins"
else
  log "Not installed yet:"
  if [ ${#SYS_PLAN[@]} -gt 0 ]; then
    case "$SUDO_OK" in
      0) echo "   System, for every user (no sudo: NOT changed, ask an admin):" ;;
      1) if [ "$PM" = brew ]; then echo "   System, for every user (Homebrew):"
         else echo "   System, for every user (as root):"; fi ;;
      2) echo "   System, for every user (sudo, asks for your password):" ;;
    esac
    printf '%s
' "${SYS_PLAN[@]}"
  fi
  if [ ${#USER_PLAN[@]} -gt 0 ]; then
    echo "   Only you ($(id -un)), in ~, no sudo:"
    printf '%s
' "${USER_PLAN[@]}"
  fi
  echo "   Anything else already installed is left as it is."
  if [ "$HAS_TTY" = 1 ] && [ "${ASSUME_YES:-0}" != 1 ]; then
    ask "Install these? [Y/n]" y
    case "$REPLY" in [Nn]*) log "Nothing installed"; exit 0 ;; esac
  fi
fi

# Everything that gets installed is recorded here and listed at the end
DONE=(); SYS_DONE=(); FAILED=()
did()     { DONE+=("$*"); }
sys_did() { SYS_DONE+=("$*"); }
failed() { FAILED+=("$*"); warn "not installed: $*"; }

# ---------- OS packages ----------
if [ "$NEED_SYS" = 1 ] && [ "$SUDO_OK" = 2 ]; then
  log "sudo is used only for the system changes listed above"
  if sudo -v; then SUDO_OK=1; else SUDO_OK=0; fi
fi
pm_add() { # pm_add PACKAGE...
  case "$PM" in
    brew)    HOMEBREW_NO_INSTALL_UPGRADE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew install "$@" ;;
    apt-get) sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-upgrade "$@" ;;
    dnf)     sudo dnf install -y "$@" ;;
    yum)     sudo yum install -y "$@" ;;
    pacman)  sudo pacman -S --noconfirm --needed "$@" ;;
    zypper)  sudo zypper --non-interactive install "$@" ;;
    apk)     sudo apk add "$@" ;;
  esac
}
if [ "$NEED_OS" = 1 ] && [ "$SUDO_OK" = 1 ]; then
  log "Installing OS packages"
  if [ "$NEED_BREW" = 1 ]; then
    log "Installing Homebrew"
    NONINTERACTIVE=1 bash -c "$(fetch https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)"; done
    sys_did "Homebrew"
  fi
  # Refresh the package index (does not upgrade anything)
  case "$PM" in
    apt-get) sudo apt-get update || true ;;
    pacman)  sudo pacman -Sy --noconfirm ;;
    zypper)  sudo zypper --non-interactive refresh || true ;;
    apk)     sudo apk update ;;
  esac
  if [ ${#MISS_REQ[@]} -gt 0 ]; then
    pm_add "${MISS_REQ[@]}" || die "could not install OS packages: ${MISS_REQ[*]}"
    sys_did "OS packages: ${MISS_REQ[*]}"
  fi
  for p in ${MISS_OPT[@]+"${MISS_OPT[@]}"}; do
    if pm_add "$p" >/dev/null 2>&1; then sys_did "OS package: $p"; else failed "$p (optional OS package, not available)"; fi
  done
  hash -r
elif [ "$NEED_OS" = 1 ]; then
  missing="${MISS_REQ[*]:-}"
  for c in git tar; do has "$c" || die "missing required tool: $c (ask an admin to install it)"; done
  has curl || has wget || die "missing required tool: curl (ask an admin to install it)"
  [ -z "$missing" ] || warn "missing OS packages: $missing (ask an admin to install them; related features will not work)"
fi

# Debian/Ubuntu ship fd as fdfind
if ! has fd && has fdfind; then ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------- Neovim ----------
# glibc Linux: official release in ~/.local/opt/nvim (distro versions are often too old; the
# config needs >= 0.11). macOS and Alpine use the package manager's Neovim.
if [ "$NEED_NVIM" = 1 ]; then
  log "Installing Neovim ${NVIM_LATEST:-latest} ($NVIM_ARCH) in ~/.local/opt/nvim"
  if [ -n "$NVIM_LATEST" ]; then u="download/$NVIM_LATEST"; else u="latest/download"; fi
  fetch "https://github.com/neovim/neovim/releases/$u/nvim-linux-${NVIM_ARCH}.tar.gz" "$TMP/nvim.tar.gz"
  rm -rf "$LOCAL_OPT/nvim" && mkdir -p "$LOCAL_OPT/nvim"
  tar -C "$LOCAL_OPT/nvim" --strip-components=1 -xzf "$TMP/nvim.tar.gz"
  ln -sf "$LOCAL_OPT/nvim/bin/nvim" "$LOCAL_BIN/nvim"
  hash -r
  nvim --version >/dev/null 2>&1 || die "nvim failed to run (glibc too old?). Try a newer OS release."
  v="$(nvim --version)"; v="${v%%$'\n'*}"
  if [ -n "$NVIM_CUR" ]; then did "Neovim ${v#NVIM } (was $NVIM_CUR)"; else did "Neovim ${v#NVIM }"; fi
fi
hash -r
has nvim || die "Neovim is not installed"
nvim_ok || warn "$(nvim --version 2>/dev/null | sed -n 1p) < 0.11, the config needs 0.11+"

# ---------- Node.js (needed by pyright, ts_ls, bashls, prettier, ...) ----------
if [ "$NEED_NODE" = 1 ] && [ -z "$NODE_LATEST" ]; then
  failed "Node.js (could not look up the latest LTS on nodejs.org)"
elif [ "$NEED_NODE" = 1 ]; then
  log "Installing Node.js $NODE_LATEST ($NODE_ARCH) in ~/.local/opt/node"
  NODE_TAR="node-$NODE_LATEST-linux-$NODE_ARCH.tar.xz"
  fetch "https://nodejs.org/dist/$NODE_LATEST/$NODE_TAR" "$TMP/$NODE_TAR"
  rm -rf "$LOCAL_OPT/node" && mkdir -p "$LOCAL_OPT/node"
  tar -C "$LOCAL_OPT/node" --strip-components=1 -xJf "$TMP/$NODE_TAR"
  for b in node npm npx; do ln -sf "$LOCAL_OPT/node/bin/$b" "$LOCAL_BIN/$b"; done
  hash -r
  if ! node_ok; then failed "Node.js"
  elif [ -n "$NODE_CUR" ]; then did "Node.js $(node -v) (was $NODE_CUR)"
  else did "Node.js $(node -v)"; fi
fi
node_ok || warn "Node.js >= 18 not found, JS-based LSPs (pyright, ts_ls...) will fail"

# ---------- tree-sitter CLI (nvim-treesitter uses it to compile parsers) ----------
if [ "$NEED_TS" = 1 ] && has npm; then
  # npm package in ~/.local/opt/tree-sitter-cli; works with any Node.js, no global install
  log "Installing tree-sitter CLI in ~/.local/opt/tree-sitter-cli"
  npm install --silent --prefix "$LOCAL_OPT/tree-sitter-cli" tree-sitter-cli >/dev/null
  ln -sf "$LOCAL_OPT/tree-sitter-cli/node_modules/.bin/tree-sitter" "$LOCAL_BIN/tree-sitter"
  hash -r
  # The prebuilt binary needs glibc 2.39. On older systems (Debian 12, RHEL 9, Ubuntu 22.04)
  # it fails with "GLIBC_2.39 not found", so build it from source with cargo instead.
  if ! ts_works "$LOCAL_BIN/tree-sitter"; then
    log "tree-sitter binary needs newer glibc, building from source with cargo (takes a few minutes)"
    if ! has cargo && [ ! -x "$HOME/.cargo/bin/cargo" ]; then
      fetch https://sh.rustup.rs "$TMP/rustup.sh"
      sh "$TMP/rustup.sh" -y --profile minimal --no-modify-path >/dev/null
      did "Rust (rustup, in ~/.cargo)"
    fi
    CARGO="$(command -v cargo || echo "$HOME/.cargo/bin/cargo")"
    "$CARGO" install --locked tree-sitter-cli
    ln -sf "$HOME/.cargo/bin/tree-sitter" "$LOCAL_BIN/tree-sitter"
    hash -r
  fi
  ts_works "$LOCAL_BIN/tree-sitter" && did "tree-sitter CLI $(tree-sitter --version | awk '{print $2}')" || failed "tree-sitter CLI"
fi
if [ "$OLD_TS_LINK" = 1 ] && [ "$SUDO_OK" = 1 ]; then
  sudo rm -f /usr/local/bin/tree-sitter && sys_did "removed old link /usr/local/bin/tree-sitter"
fi
if ! has tree-sitter || ! ts_works tree-sitter; then
  warn "tree-sitter CLI missing or broken, syntax highlighting parsers will not compile"
fi
# LazyVim installs tree-sitter-cli through Mason when none is on PATH (e.g. nvim was opened before
# this step finished). That is the same glibc 2.39 build, so remove it if it cannot run here.
MASON_DIR="$DATA_HOME/nvim/mason"
if [ -e "$MASON_DIR/bin/tree-sitter" ] && ! "$MASON_DIR/bin/tree-sitter" --version >/dev/null 2>&1; then
  log "Removing Mason's tree-sitter-cli (cannot run on this system)"
  rm -rf "$MASON_DIR/packages/tree-sitter-cli" "$MASON_DIR/bin/tree-sitter"
fi

# ---------- uv and Python (per user) ----------
# uv installs into ~/.local/bin; `uv python install --default` adds python3 there too, so
# Mason's Python tools (and the user) get a recent Python with venv and pip, no sudo needed.
if [ "$NEED_UV" = 1 ]; then
  log "Installing uv in ~/.local/bin"
  fetch https://github.com/astral-sh/uv/releases/latest/download/uv-installer.sh "$TMP/uv-installer.sh"
  if env UV_NO_MODIFY_PATH=1 UV_INSTALL_DIR="$LOCAL_BIN" sh "$TMP/uv-installer.sh" --quiet && has uv; then
    did "$(uv --version)"
  else
    failed "uv"
  fi
  hash -r
fi
if [ "$NEED_PY" = 1 ] && has uv; then
  log "Installing Python $PYTHON_VERSION with uv"
  # --default (adds python / python3 next to python3.X) is marked experimental; hide that warning
  if uv python install --default "$PYTHON_VERSION" >"$TMP/uv-python.log" 2>&1 && [ -x "$LOCAL_BIN/python3" ]; then
    hash -r; did "$(python3 --version) (uv)"
  else
    cat "$TMP/uv-python.log" >&2; failed "Python $PYTHON_VERSION (uv)"
  fi
fi

# ---------- dotfiles ----------
log "Linking dotfiles"
if [ "$NEED_DOTFILES" = 0 ]; then
  # safe.directory: allow running as a different user than the repo owner (e.g. root in a container)
  git -c safe.directory="$DOTFILES_DIR" -C "$DOTFILES_DIR" pull -q --ff-only \
    || warn "git pull skipped (local changes, detached HEAD or no remote)"
else
  git clone -q "$DOTFILES_REPO" "$DOTFILES_DIR"
  did "dotfiles ($DOTFILES_DIR)"
fi

link() { # back up existing config instead of overwriting it
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then mv "$dst" "$dst.bak.$(date +%s)"; fi
  ln -sfn "$src" "$dst"
}
link "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"

# tmux: Oh my tmux! (https://github.com/gpakosz/.tmux) plus this repo's tmux/tmux.conf.local
if [ "$NEED_OMT" = 0 ]; then
  git -C "$OH_MY_TMUX" pull --ff-only -q || warn "could not update Oh my tmux!"
else
  git clone -q --depth 1 https://github.com/gpakosz/.tmux "$OH_MY_TMUX"
  did "Oh my tmux!"
fi
link "$OH_MY_TMUX/.tmux.conf" "$HOME/.tmux.conf"
link "$DOTFILES_DIR/tmux/tmux.conf.local" "$HOME/.tmux.conf.local"

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

# ---------- nvim plugins, LSP servers, treesitter parsers (all headless) ----------
# Only missing ones are installed: `Lazy! install` does not update plugins (use :Lazy update),
# and Mason / treesitter skip what is already there.
# Bound every step so a network problem cannot hang forever (macOS has no timeout: run as is)
with_timeout() { local s="$1"; shift; if has timeout; then timeout "$s" "$@"; else "$@"; fi; }
log "Installing missing nvim plugins (LazyVim)"
with_timeout 900 env DOTFILES_HEADLESS_INSTALL=1 nvim --headless "+Lazy! install" +qa || warn "Lazy install failed or timed out, run :Lazy install"

log "Installing missing LSP servers, formatters and treesitter parsers"
# CFLAGS: tree-sitter's default flags include -Wall, which makes gcc 12.2 (Debian 12) spend
# minutes on large generated parsers such as gitcommit. config/options.lua sets the same default.
export CFLAGS="${CFLAGS:--O2}"
# DOTFILES_HEADLESS_INSTALL stops LazyVim's background parser builds; headless.lua builds them
# itself and waits for every Mason package and parser to finish (see nvim/lua/dotfiles/headless.lua)
if with_timeout 1500 env DOTFILES_HEADLESS_INSTALL=1 nvim --headless -c "lua require('dotfiles.headless').install()"; then
  [ "$NEED_LAZY" = 1 ] && did "nvim plugins, LSP servers, formatters and parsers"
else
  failed "some LSP servers or parsers (open nvim and check :Mason and :checkhealth)"
fi

# ---------- Claude Code (optional, see the questions at the top) ----------
if [ "$INSTALL_CLAUDE" = 1 ]; then
  if [ "$PM" = apk ]; then
    # musl: libgcc / libstdc++ come with the OS packages above; use the system ripgrep
    mkdir -p "$HOME/.claude"
    if [ ! -f "$HOME/.claude/settings.json" ]; then
      printf '{\n  "env": { "USE_BUILTIN_RIPGREP": "0" }\n}\n' > "$HOME/.claude/settings.json"
    elif ! grep -q USE_BUILTIN_RIPGREP "$HOME/.claude/settings.json"; then
      warn 'add "env": { "USE_BUILTIN_RIPGREP": "0" } to ~/.claude/settings.json (needed on Alpine)'
    fi
  fi
  # Native installer: updates itself in the background, so it is only run when claude is missing
  if [ "$NEED_CLAUDE" = 1 ]; then
    log "Installing Claude Code"
    fetch https://claude.ai/install.sh "$TMP/claude-install.sh"
    bash "$TMP/claude-install.sh"
    . "$DOTFILES_DIR/shell/env.sh"; hash -r
    has claude && did "Claude Code $(claude --version 2>/dev/null | awk '{print $1}')"
  fi
  if has claude; then
    # The official marketplace is only registered by the first interactive session, so add it here
    MP=claude-plugins-official
    claude plugin marketplace add "anthropics/$MP" >/dev/null 2>&1 || true
    INSTALLED_PLUGINS="$(claude plugin list 2>/dev/null || true)"
    claude_plugin() { # claude_plugin NAME [MARKETPLACE]
      local mp="${2:-$MP}"
      case "$INSTALLED_PLUGINS" in *"$1@$mp"*) return 0 ;; esac
      if claude plugin install "$1@$mp" >/dev/null 2>&1; then did "Claude plugin $1"; else failed "Claude plugin $1@$mp"; fi
    }
    # A skill that is not packaged as a plugin: clone its repo and link the skill folder into
    # ~/.claude/skills, where Claude Code picks up user skills
    claude_skill() { # claude_skill NAME REPO PATH_IN_REPO
      local dir="$DATA_HOME/claude-skills/${2//\//_}"
      [ -e "$HOME/.claude/skills/$1" ] && return 0
      [ -d "$dir/.git" ] || git clone -q --depth 1 "https://github.com/$2" "$dir" || { failed "Claude skill $1"; return; }
      mkdir -p "$HOME/.claude/skills"
      ln -sfn "$dir/$3" "$HOME/.claude/skills/$1" && did "Claude skill $1"
    }
    # Language-server plugins: one per nvim language whose server is on PATH (Mason's bin is)
    for pair in pyright-lsp:pyright-langserver clangd-lsp:clangd typescript-lsp:typescript-language-server \
                rust-analyzer-lsp:rust-analyzer lua-lsp:lua-language-server gopls-lsp:gopls; do
      if has "${pair#*:}"; then claude_plugin "${pair%%:*}"; fi
    done
    for p in ${CLAUDE_PLUGINS:-}; do
      case "$(plugin_source "$p")" in
        official) claude_plugin "$p" ;;
        knowledge-work)
          claude plugin marketplace add anthropics/knowledge-work-plugins >/dev/null 2>&1 || true
          claude_plugin "$p" knowledge-work-plugins ;;
        skill)
          case "$p" in
            vercel-react-best-practices) claude_skill "$p" vercel-labs/agent-skills skills/react-best-practices ;;
            *) warn "unknown skill: $p" ;;
          esac ;;
      esac
    done
  else
    failed "Claude Code (see https://code.claude.com/docs/en/troubleshoot-install)"
  fi
fi

# ---------- Summary ----------
if [ ${#SYS_DONE[@]} -gt 0 ] || [ ${#DONE[@]} -gt 0 ]; then
  log "Installed:"
  if [ ${#SYS_DONE[@]} -gt 0 ]; then
    echo "   System, for every user:"; printf '     %s\n' "${SYS_DONE[@]}"
  fi
  if [ ${#DONE[@]} -gt 0 ]; then
    echo "   Only you, in ~:"; printf '     %s\n' "${DONE[@]}"
  fi
else
  log "Nothing new was installed"
fi
if [ ${#FAILED[@]} -gt 0 ]; then
  warn "Not installed:"
  printf '   %s\n' "${FAILED[@]}" >&2
fi
[ "$INSTALL_CLAUDE" = 1 ] && has claude && log "Claude Code: run 'claude' (or prefix + A in tmux) and log in on first start"
log "Done. Open a new shell, then run nvim (and tmux). :checkhealth and :Mason show the details"
exit 0
}
