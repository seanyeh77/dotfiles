#!/usr/bin/env bash
# shellcheck disable=SC2088 # "~/..." in messages is meant literally
# One-command installer for a Neovim + tmux development environment.
#   OS:   macOS, Debian/Ubuntu, Fedora/RHEL/Rocky, Arch, openSUSE, Alpine, WSL, Termux
#   Arch: amd64 / arm64
# Usage:      curl -fsSL seanyeh77.github.io/dotfiles | bash
#   no curl:  wget -qO- seanyeh77.github.io/dotfiles | bash
# Safe to re-run: it shows what would change, then updates. Options (environment variables) are
# listed in the README.

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
  DOTFILES_RC=$?
  # Read the rest of this script from the pipe, so the download feeding it (curl ... | zsh)
  # finishes cleanly instead of failing to write once the script is larger than the pipe buffer
  [ -t 0 ] || cat >/dev/null 2>&1
  exit $DOTFILES_RC
fi

# Everything is wrapped in { ... } so bash reads the whole script before running any of it.
# With `curl ... | bash`, commands that read stdin would otherwise eat the rest of the script.
{
set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/seanyeh77/dotfiles}"
# Nothing depends on a copy of this repo after the install: its files are copied into place
# (~/.config/nvim, ~/.tmux.conf.local, ...) from a temporary clone that is deleted at the end.
# DOTFILES_DIR=PATH installs from that checkout instead (it is kept), e.g. to try local changes.
DOTFILES_DIR="${DOTFILES_DIR:-}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="$CONFIG_HOME/dotfiles"   # env.sh, git hooks, installed version, saved answers
OLD_DOTFILES="$HOME/dotfiles"       # where older versions of this installer kept the repo

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
# For version lookups: never fails, prints nothing when there is no curl / wget yet
fetch_quiet() { # fetch_quiet URL: at most 30 s
  if has curl; then curl -fsSL --connect-timeout 10 --max-time 30 "$1" 2>/dev/null || true
  elif has wget; then wget -qO- -T 30 "$1" 2>/dev/null || true; fi
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
# Termux (Android): apt-based, but its packages are the user's own (no root, no sudo), and
# Android has no glibc, so prebuilt Linux binaries do not run there
IS_TERMUX=0
if [ -n "${TERMUX_VERSION:-}" ]; then IS_TERMUX=1; else case "${PREFIX:-}" in *com.termux*) IS_TERMUX=1 ;; esac; fi
if [ "$IS_TERMUX" = 1 ]; then log "OS: Android, Termux ($PM)  Arch: $ARCH"
else log "OS: $OS ($PM)  Arch: $ARCH  WSL: $IS_WSL"; fi

# The official nvim / node / tree-sitter / uv / Python builds need glibc: use the package
# manager's on macOS, musl (Alpine) and Termux
USE_PM_NVIM=0; USE_PM_NODE=0; USE_PM_TOOLS=0
[ "$PM" = brew ] && { USE_PM_NVIM=1; USE_PM_NODE=1; USE_PM_TOOLS=1; }
[ "$PM" = apk ]  && { USE_PM_NVIM=1; USE_PM_NODE=1; USE_PM_TOOLS=1; }
[ "$IS_TERMUX" = 1 ] && { USE_PM_NVIM=1; USE_PM_NODE=1; USE_PM_TOOLS=1; }

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

# Answers are saved, so later runs do not ask again (DOTFILES_ASK=1 asks again)
ANSWERS="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/answers"
SAVED_ANSWERS=0; ASKED=0
if [ -z "${INSTALL_CLAUDE:-}" ] && [ -z "${CLAUDE_PLUGINS+set}" ] && [ "${DOTFILES_ASK:-0}" != 1 ] && [ -f "$ANSWERS" ]; then
  # shellcheck source=/dev/null
  . "$ANSWERS" # INSTALL_CLAUDE=0|1 and CLAUDE_PLUGINS="names"
  SAVED_ANSWERS=1
fi
if [ -z "${INSTALL_CLAUDE:-}" ]; then
  INSTALL_CLAUDE=0
  if [ "$HAS_TTY" = 1 ]; then
    ASKED=1
    ask "Install Claude Code? [Y/n]" y
    case "$REPLY" in [Nn]*) INSTALL_CLAUDE=0 ;; *) INSTALL_CLAUDE=1 ;; esac
  fi
fi
if [ "$INSTALL_CLAUDE" = 1 ] && [ -z "${CLAUDE_PLUGINS+set}" ]; then
  CLAUDE_PLUGINS=""
  for e in "${CLAUDE_WORKFLOW_PLUGINS[@]}"; do CLAUDE_PLUGINS="$CLAUDE_PLUGINS ${e%%|*}"; done
  if [ "$HAS_TTY" = 1 ]; then
    ASKED=1
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
case "$CLAUDE_PLUGINS" in none|NONE) CLAUDE_PLUGINS="" ;; esac
SAVED_NOTE=""; [ "$SAVED_ANSWERS" = 1 ] && SAVED_NOTE=" (saved answer; DOTFILES_ASK=1 asks again)"
if [ "$INSTALL_CLAUDE" = 1 ]; then
  n=0; for p in $CLAUDE_PLUGINS; do n=$((n + 1)); done
  log "Claude Code: yes, $n plugins and skills$SAVED_NOTE"
else
  log "Claude Code: no$SAVED_NOTE"
fi


# ---------- What to install or update ----------
# Shown as a plan with versions, installed after one confirmation:
#   - system (shared by every user): OS packages that are missing; installed ones are left alone
#   - this user (~/.local, ~/.claude, ~/.local/share/nvim): installed when missing and updated
#     to the latest release when a newer one is out
#
# Who can change the system: root, Homebrew, or a user with sudo (asked only when needed).
# NO_SUDO=1 skips sudo; USE_SUDO=1 asks for the sudo password even when this user is not in
# the wheel / sudo / admin group.
SUDO_OK=0
if [ "$(id -u)" -eq 0 ] || [ "$IS_TERMUX" = 1 ]; then
  sudo() { "$@"; }; SUDO_OK=1 # root, or Termux where packages belong to the user
elif [ "$PM" = brew ]; then
  SUDO_OK=1 # Homebrew does not use sudo
elif [ "${NO_SUDO:-0}" != 1 ] && has sudo; then
  if sudo -n true 2>/dev/null; then
    SUDO_OK=1 # sudo without a password (NOPASSWD, or a cached sudo)
  elif [ "${USE_SUDO:-0}" = 1 ] || id -nG 2>/dev/null | tr ' ' '\n' | grep -qx -e wheel -e sudo -e admin; then
    SUDO_OK=2 # ask for the password after the plan, only if there are system changes
  fi
  # Otherwise sudo is installed but this user is not an admin (a shared server or cluster):
  # do not ask for a password that cannot work. USE_SUDO=1 asks anyway.
fi

# Docker (asked; INSTALL_DOCKER=1/0 presets the answer). It is a system install, so it is only
# offered with root, sudo or Homebrew. On Linux you are also added to the docker group, so docker
# runs without sudo (that group is as powerful as root on this machine).
in_docker_group() { id -nG 2>/dev/null | tr ' ' '\n' | grep -x docker >/dev/null; }
DOCKER_TODO="" # install | group | empty
if [ "$IS_TERMUX" = 1 ]; then :            # Android: no kernel support for containers
elif ! has docker; then DOCKER_TODO=install
elif [ "$OS" = Linux ] && [ "$(id -u)" -ne 0 ] && ! in_docker_group; then DOCKER_TODO=group
fi
if [ -n "$DOCKER_TODO" ] && [ "$SUDO_OK" = 0 ]; then
  if [ "${INSTALL_DOCKER:-0}" = 1 ]; then warn "Docker needs sudo, which you do not have here: ask an admin (or use rootless Docker / Podman)"
  else log "Docker: not offered, it needs sudo"; fi
  DOCKER_TODO=""
fi
if [ -z "$DOCKER_TODO" ]; then
  INSTALL_DOCKER="${INSTALL_DOCKER:-0}"
elif [ -z "${INSTALL_DOCKER:-}" ]; then
  INSTALL_DOCKER=0
  if [ "$HAS_TTY" = 1 ]; then
    ASKED=1
    if [ "$DOCKER_TODO" = install ]; then ask "Install Docker (system-wide, with sudo)? [y/N]" n
    else ask "Docker is installed: add you to the docker group, to run docker without sudo? [y/N]" n; fi
    case "$REPLY" in [Yy]*) INSTALL_DOCKER=1 ;; esac
  fi
fi
[ "$INSTALL_DOCKER" = 1 ] || DOCKER_TODO=""
if [ -n "$DOCKER_TODO" ]; then log "Docker: yes"; fi
if [ "$ASKED" = 1 ]; then
  mkdir -p "$(dirname "$ANSWERS")"
  printf 'INSTALL_CLAUDE=%s\nCLAUDE_PLUGINS="%s"\nINSTALL_DOCKER=%s\n' "$INSTALL_CLAUDE" "$CLAUDE_PLUGINS" "$INSTALL_DOCKER" > "$ANSWERS"
fi
# Bound slow steps so a network problem cannot hang forever. macOS has no `timeout`: use gtimeout
# (coreutils) or perl's alarm, which kills the command when the time is up.
with_timeout() {
  local s="$1"; shift
  if has timeout; then timeout "$s" "$@"
  elif has gtimeout; then gtimeout "$s" "$@"
  elif has perl; then perl -e 'alarm shift; exec @ARGV or exit 127' "$s" "$@"
  else "$@"; fi
}
# git must never stop to ask for a username or password (it would wait forever, unseen)
export GIT_TERMINAL_PROMPT=0
log "Checking what is installed and the latest versions"

# OS packages as package[:command]. A package counts as installed when the package manager has
# it or, when a command is given, that command is on PATH (e.g. a git built from source).
# Required: git, curl, unzip, tar, gzip (Mason downloads), find (copying the config; minimal
# images such as openSUSE's lack it), a C compiler (treesitter parsers), tmux, ripgrep
# perl: Oh my tmux! needs it to apply its theme (git usually pulls it in, minimal Alpine does not)
# Optional: installed when available, skipped with a warning otherwise
# Python is not here: each user gets their own from uv (below).
case "$PM" in
  brew)    OS_REQ=(git tmux ripgrep:rg fd neovim:nvim node)
           OS_OPT=(tree-sitter-cli:tree-sitter lazygit) ;;
  apt-get) OS_REQ=(git curl unzip tar gzip xz-utils:xz findutils:find tmux ripgrep:rg build-essential)
           if [ "$IS_TERMUX" = 1 ]; then
             # Termux: Neovim, Node.js, tree-sitter, uv and Python come from its packages too
             OS_REQ=(git curl unzip tar gzip xz-utils:xz findutils:find tmux ripgrep:rg build-essential perl
                     neovim:nvim nodejs-lts:node tree-sitter python:python3 uv)
             OS_OPT=(fd lua-language-server lazygit wget)
           else
             OS_OPT=(fd-find:fdfind clangd xclip perl wget)
           fi ;;
  dnf|yum) OS_REQ=(git curl unzip tar gzip xz findutils:find tmux gcc gcc-c++:g++ make)
           OS_OPT=(ripgrep:rg fd-find:fd clang-tools-extra:clangd xclip perl wget) ;;
  pacman)  OS_REQ=(git curl unzip tar gzip xz findutils:find tmux ripgrep:rg base-devel)
           OS_OPT=(fd clang:clangd xclip perl wget) ;;
  zypper)  OS_REQ=(git curl unzip tar gzip xz findutils:find tmux ripgrep:rg gcc gcc-c++:g++ make)
           OS_OPT=(fd clang-tools:clangd xclip perl wget) ;;
  apk)     OS_REQ=(bash git curl unzip tar gzip xz findutils:find tmux perl ripgrep:rg build-base neovim:nvim nodejs:node npm)
           OS_OPT=(fd clang-extra-tools:clangd lua-language-server tree-sitter-cli:tree-sitter lazygit xclip wget) ;;
esac
# Claude Code on musl needs libgcc / libstdc++ (and uses the system ripgrep, already required)
[ "$PM" = apk ] && [ "$INSTALL_CLAUDE" = 1 ] && OS_REQ+=(libgcc libstdc++)
BREW_LIST=""
# `brew list` fails when no formula is installed yet (a fresh Homebrew): that just means none
if [ "$PM" = brew ] && has brew; then BREW_LIST=" $(brew list --formula -1 2>/dev/null | tr '\n' ' ' || true) "; fi
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
pkg_version() { # pkg_version PACKAGE: version the package manager would install, empty if unknown
  local v=""
  case "$PM" in
    brew)    # from one `brew info` call for all missing formulae (BREW_INFO, below)
             v="$(printf '%s\n' "$BREW_INFO" | awk -v p="==> $1: stable" 'index($0, p) == 1 {sub(/,.*/, "", $4); print $4}')" ;;
    apt-get) v="$(apt-cache policy "$1" 2>/dev/null || true)"
             v="$(printf '%s\n' "$v" | awk '/Candidate:/ {print $2}')" ;;
    # --assumeno and no stdin: a question (e.g. importing a repository key) is answered "no"
    # instead of ending up in the output; keep only lines that look like a version
    dnf)     v="$(dnf -q --assumeno repoquery --latest-limit 1 --qf '%{version}-%{release}\n' "$1" </dev/null 2>/dev/null || true)"
             v="$(printf '%s\n' "$v" | grep -E '^[0-9][^ ]*$' | tail -1 || true)" ;;
    yum)     v="$(yum -q --assumeno list available "$1" </dev/null 2>/dev/null || true)"
             v="$(printf '%s\n' "$v" | awk 'NF >= 2 && $2 ~ /^[0-9]/ {x = $2} END {print x}')" ;;
    pacman)  v="$(pacman -Si "$1" 2>/dev/null || true)"; v="$(printf '%s\n' "$v" | awk -F': *' '/^Version/ {print $2}')" ;;
    zypper)  v="$(zypper -q --non-interactive info "$1" </dev/null 2>/dev/null || true)"; v="$(printf '%s\n' "$v" | awk -F': *' '/^Version/ {print $2}')" ;;
    apk)     v="$(apk search -x "$1" 2>/dev/null || true)"; v="${v%%$'\n'*}"; v="${v#"$1"-}" ;;
  esac
  [ "$v" = "(none)" ] && v=""
  printf '%s' "${v%%$'\n'*}"
}
pkg_installed_version() { # pkg_installed_version PACKAGE
  local v=""
  case "$PM" in
    brew)    v="$(brew list --versions "$1" 2>/dev/null || true)"; v="${v##* }" ;;
    apt-get) v="$(dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true)" ;;
    dnf|yum|zypper) v="$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' --whatprovides "$1" 2>/dev/null || true)" ;;
    pacman)  v="$(pacman -Q "$1" 2>/dev/null || true)"; v="${v##* }" ;;
    apk)     v="$(apk info -e -v "$1" 2>/dev/null || true)"; v="${v#"$1"-}" ;;
  esac
  printf '%s' "${v%%$'\n'*}"
}
MISS_REQ=(); MISS_OPT=()
for s in "${OS_REQ[@]}"; do spec_installed "$s" || MISS_REQ+=("${s%%:*}"); done
for s in "${OS_OPT[@]}"; do spec_installed "$s" || MISS_OPT+=("${s%%:*}"); done
NEED_BREW=0; [ "$PM" = brew ] && ! has brew && NEED_BREW=1
NEED_OS=0; [ ${#MISS_REQ[@]} -gt 0 ] || [ ${#MISS_OPT[@]} -gt 0 ] || [ "$NEED_BREW" = 1 ] && NEED_OS=1
# As root, refresh the package index now so the plan can show the versions that will be installed
# (container images ship without one). It only refreshes metadata, nothing is upgraded.
INDEX_FRESH=0
if [ "$NEED_OS" = 1 ] && [ "$(id -u)" -eq 0 ]; then
  case "$PM" in
    apt-get) apt-get update -qq >/dev/null 2>&1 || true ;;
    pacman)  pacman -Sy --noconfirm >/dev/null 2>&1 || true ;;
    zypper)  zypper --non-interactive -q refresh >/dev/null 2>&1 || true ;;
    apk)     apk update -q >/dev/null 2>&1 || true ;;
  esac
  INDEX_FRESH=1
fi
# Older versions of this installer linked /usr/local/bin/tree-sitter to one user's ~/.cargo,
# which other users cannot run; that link is removed (a system change, so it is in the plan)
OLD_TS_LINK=0
if [ -L /usr/local/bin/tree-sitter ]; then
  case "$(readlink /usr/local/bin/tree-sitter)" in */.cargo/bin/tree-sitter) OLD_TS_LINK=1 ;; esac
fi
NEED_SYS=0; [ "$NEED_OS" = 1 ] || [ "$OLD_TS_LINK" = 1 ] && NEED_SYS=1

# ---- This user's tools: current version (empty = not installed) and latest version ----
nvim_ok() { # Neovim on PATH and >= 0.11
  local v; v="$(nvim --version 2>/dev/null)" || return 1
  # Capture first, then trim: `nvim --version | head -1` can die of SIGPIPE (exit 141) under pipefail
  v="$(printf '%s' "${v%%$'\n'*}" | sed -E 's/^NVIM v([0-9]+)\.([0-9]+).*/\1 \2/')"
  set -- $v
  [ "${1:-0}" -gt 0 ] 2>/dev/null || [ "${2:-0}" -ge 11 ] 2>/dev/null
}
node_ok() { has node && [ "$(node -v | cut -d. -f1 | tr -d v)" -ge 18 ]; }
ts_works() { local v; v="$("$1" --version 2>&1)" || return 1; case "$v" in *GLIBC*) return 1 ;; esac; return 0; }
first_line() { printf '%s' "${1%%$'\n'*}"; }
gh_latest() { # gh_latest OWNER/REPO: tag of the latest GitHub release, empty on failure
  # Only the redirect header is needed (releases/latest -> releases/tag/vX), not the page.
  # Tried twice: GitHub occasionally answers without the redirect.
  local u="" url="https://github.com/$1/releases/latest" i
  for i in 1 2; do
    if has curl; then
      u="$(curl -fsSI --connect-timeout 10 --max-time 20 -o /dev/null -w '%{redirect_url}' "$url" 2>/dev/null || true)"
      case "$u" in */tag/*) ;; *) u="$(curl -fsSL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' "$url" 2>/dev/null || true)" ;; esac
    else u="$(wget -S --spider -T 20 --max-redirect=0 "$url" 2>&1 || true)"
         u="$(printf '%s\n' "$u" | awk '/^ *Location:/ {x = $2} END {print x}')"; fi
    case "$u" in */tag/*) printf '%s' "${u##*/tag/}"; return 0 ;; esac
    [ "$i" = 1 ] && sleep 2
  done
  return 0
}
outdated() { # outdated CURRENT LATEST: true when not installed, or a newer version is known
  [ -z "$1" ] || { [ -n "$2" ] && [ "$1" != "$2" ]; }
}
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
OH_MY_TMUX="$DATA_HOME/oh-my-tmux"
git_update() { # git_update DIR: "OLD NEW COUNT" when the upstream is ahead, empty otherwise
  local d="$1" n
  GIT_TERMINAL_PROMPT=0 timeout_cmd 60 git -c safe.directory="$d" -C "$d" fetch -q 2>/dev/null || return 0
  n="$(git -c safe.directory="$d" -C "$d" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
  [ "$n" -gt 0 ] 2>/dev/null || return 0
  printf '%s %s %s' "$(git -c safe.directory="$d" -C "$d" rev-parse --short HEAD)" \
    "$(git -c safe.directory="$d" -C "$d" rev-parse --short '@{u}')" "$n"
}
timeout_cmd() { with_timeout "$@" </dev/null; }

# The network lookups run in parallel in the background; each writes its answer to a file and
# is reported as it finishes, so a slow one does not hold up the others.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
LOOKUP="$TMP/lookup"; mkdir -p "$LOOKUP"
L_PIDS=(); L_NAMES=(); L_LABELS=()
lookup() { # lookup NAME LABEL FUNCTION...
  local name="$1" label="$2"; shift 2
  ( "$@" > "$LOOKUP/$name" 2>/dev/null || true ) &
  L_PIDS+=("$!"); L_NAMES+=("$name"); L_LABELS+=("$label")
}
lookup_result() { cat "$LOOKUP/$1" 2>/dev/null || true; }
lk_node() {
  # Latest LTS: first row of index.tab whose lts column is set
  fetch_quiet https://nodejs.org/dist/index.tab | awk -F'\t' 'NR > 1 && $10 != "-" && $10 != "" && !x {x = $1} END {print x}'
}
lk_python() {
  # Newest stable CPython uv can download (skips alpha/beta/rc and free-threaded builds)
  timeout_cmd 60 "$(command -v uv)" python list 2>/dev/null \
    | sed -n 's/^cpython-\([0-9]*\.[0-9]*\.[0-9]*\)-.*/\1/p' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1
}
lk_claude() {
  # Same version numbers as the native build
  fetch_quiet https://registry.npmjs.org/@anthropic-ai/claude-code/latest | grep -o '"version":"[^"]*"' | sed -n '1s/.*:"\(.*\)"/\1/p'
}
[ "$USE_PM_NVIM" = 0 ] && lookup nvim "Neovim" gh_latest neovim/neovim
[ "$USE_PM_NODE" = 0 ] && lookup node "Node.js LTS" lk_node
if [ "$USE_PM_TOOLS" = 0 ]; then
  lookup ts "tree-sitter CLI" gh_latest tree-sitter/tree-sitter
  lookup uv "uv" gh_latest astral-sh/uv
  lookup lazygit "lazygit" gh_latest jesseduffield/lazygit
  if [ -z "${PYTHON_VERSION:-}" ] && has uv; then lookup python "Python" lk_python; fi
fi
lk_dotfiles() { # the commit this install would use
  if [ -n "$DOTFILES_DIR" ]; then git -c safe.directory="$DOTFILES_DIR" -C "$DOTFILES_DIR" rev-parse HEAD 2>/dev/null
  elif has git; then timeout_cmd 30 git ls-remote "$DOTFILES_REPO" HEAD 2>/dev/null | awk '{print $1}'; fi
}
lookup dotfiles "dotfiles" lk_dotfiles
[ -d "$OH_MY_TMUX/.git" ] && lookup omt "Oh my tmux!" git_update "$OH_MY_TMUX"
if [ "$INSTALL_CLAUDE" = 1 ]; then
  lookup claude "Claude Code" lk_claude
  has claude && lookup claude_plugins "Claude plugins" claude plugin list
fi
# Wait for all of them, printing each one as it finishes (at most ~2 minutes: every lookup is bounded)
lookup_wait() {
  local i n=${#L_PIDS[@]} start=$SECONDS shown="" pending
  [ "$n" -gt 0 ] || return 0
  [ -t 1 ] || echo "   looking up: ${L_LABELS[*]}"
  while :; do
    pending=""
    for i in "${!L_PIDS[@]}"; do
      case " $shown " in *" $i "*) continue ;; esac
      if kill -0 "${L_PIDS[$i]}" 2>/dev/null; then pending="$pending, ${L_LABELS[$i]}"; continue; fi
      shown="$shown $i"
      [ -t 1 ] || printf '   %-20s done (%ss)\n' "${L_LABELS[$i]}" "$((SECONDS - start))"
    done
    # On a terminal: one line that updates in place
    [ -z "$pending" ] && break
    [ -t 1 ] && printf '\r\033[K   %ss  waiting for: %s' "$((SECONDS - start))" "${pending#, }"
    sleep 1
  done
  [ -t 1 ] && printf '\r\033[K   checked %d items in %ss\n' "$n" "$((SECONDS - start))"
  wait 2>/dev/null || true
}
lookup_wait

# Neovim / Node.js: own copies on glibc Linux; macOS and Alpine use the package manager's builds
NVIM_CUR=""; NVIM_LATEST=""; NEED_NVIM=0
if [ "$USE_PM_NVIM" = 0 ]; then
  NVIM_CUR="$(first_line "$("$LOCAL_OPT/nvim/bin/nvim" --version 2>/dev/null || true)")"; NVIM_CUR="${NVIM_CUR#NVIM }"
  NVIM_LATEST="$(lookup_result nvim)"
  case "$NVIM_LATEST" in v[0-9]*) ;; *) NVIM_LATEST="" ;; esac
  outdated "$NVIM_CUR" "$NVIM_LATEST" && NEED_NVIM=1
fi
NODE_CUR=""; NODE_LATEST=""; NEED_NODE=0
if [ "$USE_PM_NODE" = 0 ]; then
  NODE_CUR="$("$LOCAL_OPT/node/bin/node" -v 2>/dev/null || true)"
  NODE_LATEST="$(lookup_result node)"
  outdated "$NODE_CUR" "$NODE_LATEST" && NEED_NODE=1
fi
# tree-sitter CLI (brew / apk: package manager)
TS_CUR=""; TS_LATEST=""; NEED_TS=0
if [ "$USE_PM_TOOLS" = 0 ]; then
  if ts_works "$LOCAL_BIN/tree-sitter"; then
    TS_CUR="$("$LOCAL_BIN/tree-sitter" --version 2>/dev/null || true)"; TS_CUR="$(printf '%s' "$TS_CUR" | awk '{print "v" $2}')"
  fi
  TS_LATEST="$(lookup_result ts)"
  outdated "$TS_CUR" "$TS_LATEST" && NEED_TS=1
fi
# uv and Python, both in ~/.local/bin. PYTHON_VERSION=3.13 pins a version; default is the latest.
UV_CUR=""; [ -x "$LOCAL_BIN/uv" ] && UV_CUR="$("$LOCAL_BIN/uv" --version 2>/dev/null | awk '{print $2}' || true)"
UV_LATEST="$(lookup_result uv)"
NEED_UV=0; outdated "$UV_CUR" "$UV_LATEST" && NEED_UV=1
[ "$IS_TERMUX" = 1 ] && NEED_UV=0 # from Termux's packages
# lazygit (git UI, Space g g in nvim): a static binary in ~/.local/bin on Linux; macOS, Alpine and
# Termux take it from their package manager (OS_OPT)
LG_CUR=""; LG_LATEST=""; NEED_LG=0
if [ "$USE_PM_TOOLS" = 0 ]; then
  [ -x "$LOCAL_BIN/lazygit" ] && LG_CUR="v$("$LOCAL_BIN/lazygit" --version 2>/dev/null | sed -n 's/.*, version=\([^,]*\),.*/\1/p' || true)"
  [ "$LG_CUR" = v ] && LG_CUR=""
  LG_LATEST="$(lookup_result lazygit)"
  outdated "$LG_CUR" "$LG_LATEST" && NEED_LG=1
fi
PY_CUR=""; [ -x "$LOCAL_BIN/python3" ] && PY_CUR="$("$LOCAL_BIN/python3" --version 2>/dev/null | awk '{print $2}' || true)"
PY_LATEST=""
if [ -n "${PYTHON_VERSION:-}" ]; then
  PY_LATEST="$PYTHON_VERSION"
else
  PY_LATEST="$(lookup_result python)"
fi
NEED_PY=0
if [ -z "$PY_CUR" ]; then NEED_PY=1
elif [ -n "${PYTHON_VERSION:-}" ]; then case "$PY_CUR" in "$PYTHON_VERSION"|"$PYTHON_VERSION".*) ;; *) NEED_PY=1 ;; esac
elif outdated "$PY_CUR" "$PY_LATEST"; then NEED_PY=1; fi
[ "$IS_TERMUX" = 1 ] && NEED_PY=0 # from Termux's packages (uv cannot download Python for Android)

# Oh my tmux! (git): cloned when missing, fast-forwarded when the remote has new commits
# This repo's config files: compared by commit here; the files themselves when they are copied
DF_CUR="$(cat "$STATE_DIR/version" 2>/dev/null || true)"; DF_LATEST="$(lookup_result dotfiles)"
DF_CUR="${DF_CUR:0:7}"; DF_LATEST="${DF_LATEST:0:7}"
NEED_DOTFILES=0; outdated "$DF_CUR" "$DF_LATEST" && NEED_DOTFILES=1
# The ~/dotfiles clone of older installs: removed once nothing uses it, unless it has changes of yours
RM_OLD=0
if [ "$DOTFILES_DIR" != "$OLD_DOTFILES" ] && [ -d "$OLD_DOTFILES/.git" ] && has git; then
  og() { git -c safe.directory="$OLD_DOTFILES" -C "$OLD_DOTFILES" "$@"; }
  case "$(og remote get-url origin 2>/dev/null || true)" in
    *seanyeh77/dotfiles*|"$DOTFILES_REPO"*)
      # nvim/lazy-lock.json used to be rewritten by plugin updates: not a change of yours
      if [ -z "$(og status --porcelain 2>/dev/null | grep -v ' nvim/lazy-lock.json$' || true)" ] \
         && [ -z "$(og log --oneline '@{u}..HEAD' 2>/dev/null || echo x)" ]; then RM_OLD=1
      else warn "~/dotfiles has changes of yours, so it is kept; nothing uses it any more"; fi ;;
  esac
fi
NEED_OMT=0; OMT_UPD=""
if [ -d "$OH_MY_TMUX/.git" ]; then OMT_UPD="$(lookup_result omt)"; else NEED_OMT=1; fi

# nvim plugins and Mason packages are not checked here (that needs a full nvim start and a git
# fetch of every plugin): they are always updated to the latest, and the summary lists the changes
NEED_LAZY=0; [ -d "$DATA_HOME/nvim/lazy/LazyVim" ] || NEED_LAZY=1

# Claude Code and the chosen plugins / skills that are not installed yet
NEED_CLAUDE=0; CLAUDE_CUR=""; CLAUDE_LATEST=""; MISS_PLUGINS=""
INSTALLED_PLUGINS=""
if [ "$INSTALL_CLAUDE" = 1 ]; then
  CLAUDE_LATEST="$(lookup_result claude)"
  if has claude; then
    INSTALLED_PLUGINS="$(lookup_result claude_plugins)"
    CLAUDE_CUR="$(claude --version 2>/dev/null | awk '{print $1}' || true)"
    outdated "$CLAUDE_CUR" "$CLAUDE_LATEST" && NEED_CLAUDE=1
  else
    NEED_CLAUDE=1
  fi
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

# ---------- Plan ----------
# Two parts: system changes (shared by every user, need sudo / Homebrew) and changes that stay
# in this user's home. Each line shows the version: "new 1.2" or "1.1 -> 1.2".
SYS_PLAN=(); USER_PLAN=()
sys_plan()  { SYS_PLAN+=("$1"$'\t'"$2"); }
user_plan() { USER_PLAN+=("$1"$'\t'"$2"); }
print_rows() { # print_rows "NAME<TAB>DETAIL"...: aligned in two columns
  printf '%s\n' "$@" | awk -F'\t' '{ n[NR] = $1; d[NR] = $2; if (length($1) > w) w = length($1) }
    END { for (i = 1; i <= NR; i++) printf "     %-" w "s  %s\n", n[i], d[i] }'
}
change()    { # change CURRENT LATEST [WHERE]: "new X" or "X -> Y"
  local to="${2:-latest}"
  if [ -n "$1" ]; then printf '%s -> %s' "$1" "$to"; else printf 'new %s' "$to"; fi
  [ -z "${3:-}" ] || printf ', %s' "$3"
}
case "$PM" in
  brew)    PM_CMD="brew install" ;;
  apt-get) PM_CMD="apt-get install" ;;
  pacman)  PM_CMD="pacman -S" ;;
  apk)     PM_CMD="apk add" ;;
  *)       PM_CMD="$PM install" ;;
esac
BREW_INFO=""
if [ "$PM" = brew ] && has brew && [ $((${#MISS_REQ[@]} + ${#MISS_OPT[@]})) -gt 0 ]; then
  BREW_INFO="$(brew info ${MISS_REQ[@]+"${MISS_REQ[@]}"} ${MISS_OPT[@]+"${MISS_OPT[@]}"} 2>/dev/null || true)"
fi
if [ "$NEED_OS" = 1 ]; then
  [ "$NEED_BREW" = 1 ] && sys_plan "Homebrew" "new, in /opt/homebrew (or /usr/local), asks for sudo once"
  if [ "$INDEX_FRESH" = 0 ]; then
    case "$PM" in
      apt-get) sys_plan "package index" "apt-get update (refresh only, nothing upgraded)" ;;
      pacman)  sys_plan "package index" "pacman -Sy (refresh only, nothing upgraded)" ;;
      zypper)  sys_plan "package index" "zypper refresh (refresh only, nothing upgraded)" ;;
      apk)     sys_plan "package index" "apk update (refresh only, nothing upgraded)" ;;
      brew)    [ "$NEED_BREW" = 0 ] && sys_plan "package index" "brew update (refreshes Homebrew itself, nothing upgraded)" ;;
    esac
  fi
  for p in ${MISS_REQ[@]+"${MISS_REQ[@]}"}; do v="$(pkg_version "$p")"; sys_plan "$p" "new ${v:-(version from the package index)}, $PM_CMD"; done
  for p in ${MISS_OPT[@]+"${MISS_OPT[@]}"}; do v="$(pkg_version "$p")"; sys_plan "$p" "new ${v:-(version from the package index)}, $PM_CMD, optional"; done
fi
# Docker: Docker Desktop on macOS; on Linux Docker Engine with Compose and Buildx
OS_ID=""; [ -r /etc/os-release ] && OS_ID="$(. /etc/os-release && echo "${ID:-}")"
case "$PM" in
  brew)    DOCKER_HOW="Docker Desktop, brew install --cask (open it once to finish the setup)" ;;
  apt-get) DOCKER_HOW="Docker Engine + Compose, from download.docker.com (get.docker.com)" ;;
  dnf|yum) if [ "$OS_ID" = fedora ] || [ "$PM" = yum ]; then DOCKER_HOW="Docker Engine + Compose, from download.docker.com (get.docker.com)"
           else DOCKER_HOW="Docker Engine + Compose, from download.docker.com (docker-ce repo)"; fi ;;
  pacman)  DOCKER_HOW="Docker Engine + Compose, pacman -S docker docker-compose docker-buildx" ;;
  zypper)  DOCKER_HOW="Docker Engine + Compose, zypper install docker docker-compose" ;;
  apk)     DOCKER_HOW="Docker Engine + Compose, apk add docker docker-cli-compose" ;;
esac
NEED_DOCKER=0; NEED_DOCKER_GROUP=0
if [ "$DOCKER_TODO" = install ]; then
  NEED_DOCKER=1; NEED_SYS=1; sys_plan "Docker" "new, $DOCKER_HOW"
  [ "$OS" = Linux ] && [ "$(id -u)" -ne 0 ] && NEED_DOCKER_GROUP=1
elif [ "$DOCKER_TODO" = group ]; then
  NEED_DOCKER_GROUP=1; NEED_SYS=1
fi
[ "$NEED_DOCKER_GROUP" = 1 ] && sys_plan "docker group" "add $(id -un), to run docker without sudo (takes effect at your next login)"
[ "$OLD_TS_LINK" = 1 ] && sys_plan "old link" "rm /usr/local/bin/tree-sitter (points into one user's ~/.cargo)"
[ "$NEED_NVIM" = 1 ]     && user_plan "Neovim" "$(change "$NVIM_CUR" "$NVIM_LATEST" "~/.local/opt/nvim")"
[ "$NEED_NODE" = 1 ]     && user_plan "Node.js (LTS)" "$(change "$NODE_CUR" "$NODE_LATEST" "~/.local/opt/node")"
[ "$NEED_TS" = 1 ]       && user_plan "tree-sitter CLI" "$(change "$TS_CUR" "$TS_LATEST" "~/.local/opt/tree-sitter-cli")"
[ "$NEED_UV" = 1 ]       && user_plan "uv" "$(change "$UV_CUR" "$UV_LATEST" "~/.local/bin")"
[ "$NEED_LG" = 1 ]       && user_plan "lazygit" "$(change "$LG_CUR" "$LG_LATEST" "~/.local/bin")"
[ "$NEED_PY" = 1 ]       && user_plan "Python" "$(change "$PY_CUR" "$PY_LATEST" "with uv, python3 in ~/.local/bin")"
[ "$NEED_DOTFILES" = 1 ] && user_plan "dotfiles" "$(change "$DF_CUR" "$DF_LATEST" "copied into ~/.config/nvim, ~/.tmux.conf.local, ...")"
[ "$RM_OLD" = 1 ] && user_plan "old ~/dotfiles" "removed (no longer used: the config is copied into place)"
[ "$NEED_OMT" = 1 ]      && user_plan "Oh my tmux!" "new, latest commit"
if [ -n "$OMT_UPD" ]; then set -- $OMT_UPD; user_plan "Oh my tmux!" "$1 -> $2 ($3 new commits)"; fi
[ "$NEED_LAZY" = 1 ]     && user_plan "nvim plugins" "new: LazyVim, LSP servers, formatters, parsers (latest)"
[ "$NEED_CLAUDE" = 1 ]   && user_plan "Claude Code" "$(change "$CLAUDE_CUR" "$CLAUDE_LATEST" "~/.local/bin")"
for p in $MISS_PLUGINS; do
  if [ "$(plugin_source "$p")" = skill ]; then user_plan "Claude skill $p" "new, latest"
  else user_plan "Claude plugin $p" "new, latest"; fi
done
# Claude Code settings this installer manages in ~/.claude/settings.json (only keys that are unset)
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
NEED_CLAUDE_ATTR=0; NEED_GIT_HOOK=0
GIT_HOOKS="$STATE_DIR/git/hooks"
if [ "$INSTALL_CLAUDE" = 1 ]; then
  if ! grep -qs '"attribution"' "$CLAUDE_SETTINGS" || ! grep -qs '"sessionUrl"' "$CLAUDE_SETTINGS"; then
    NEED_CLAUDE_ATTR=1
    user_plan "Claude settings" "no Co-Authored-By / Claude-Session in commits, no attribution in PRs"
  fi
  # Second layer: a global commit-msg hook strips those lines from any commit, and runs each
  # repository's own hooks too. Only when no other global hooks path is set.
  v="$(git config --global core.hooksPath 2>/dev/null || true)"
  if [ -z "$v" ] || [ "$v" = "$OLD_DOTFILES/git/hooks" ]; then
    NEED_GIT_HOOK=1
    user_plan "git commit-msg hook" "remove Claude co-author lines from every commit (git config --global core.hooksPath)"
  elif [ "$v" != "$GIT_HOOKS" ]; then
    warn "git core.hooksPath is already set to $v; not adding the hook that removes Claude co-author lines"
  fi
fi

# ---- Terminal: Nerd Font, Ghostty, iTerm2 ----
# The font matters only where the terminal runs: macOS, or a Linux desktop session. A server
# reached over SSH, WSL (the terminal is on Windows) and Termux get none. DOTFILES_FONT=1|0 forces it.
# macOS: set up the terminal this runs in (TERM_PROGRAM; LC_TERMINAL / GHOSTTY_RESOURCES_DIR still
# tell inside tmux) and the other one if installed. Ghostty is installed only when it is the one
# running or asked for. DOTFILES_TERMINAL=iterm2|ghostty|none sets up only that one (or neither);
# NO_ITERM=1 / NO_GHOSTTY=1 skip one.
#   iTerm2: this repo's profile (iterm2/dotfiles.json, a Dynamic Profile: Catppuccin Mocha,
#           JetBrainsMono Nerd Font, Option as Alt) as the default, and clipboard access for
#           programs in the terminal (tmux / nvim copying over SSH)
#   Ghostty: ghostty/config, linked with the other dotfiles below
USE_ITERM=0; USE_GHOSTTY=0
if [ "$OS" = Darwin ]; then
  case "${DOTFILES_TERMINAL:-}" in
    iterm*|iTerm*) USE_ITERM=1 ;;
    ghostty|Ghostty) USE_GHOSTTY=1 ;;
    none) ;;
    *) if [ "${TERM_PROGRAM:-}" = iTerm.app ] || [ "${LC_TERMINAL:-}" = iTerm2 ] || [ -d /Applications/iTerm.app ]; then
         USE_ITERM=1
       fi
       if [ "${TERM_PROGRAM:-}" = ghostty ] || [ -n "${GHOSTTY_RESOURCES_DIR:-}" ] || [ -d /Applications/Ghostty.app ]; then
         USE_GHOSTTY=1
       fi ;;
  esac
  [ "${NO_ITERM:-0}" = 1 ] && USE_ITERM=0
  [ "${NO_GHOSTTY:-0}" = 1 ] && USE_GHOSTTY=0
fi
NEED_GHOSTTY=0
if [ "$USE_GHOSTTY" = 1 ] && [ ! -d /Applications/Ghostty.app ]; then
  NEED_GHOSTTY=1
  user_plan "Ghostty" "new, brew install --cask (terminal that shows images in nvim)"
fi

FONT_DIR="$DATA_HOME/fonts/JetBrainsMonoNerdFont" # Linux
want_font=0
case "${DOTFILES_FONT:-}" in
  1) want_font=1 ;;
  0) ;;
  *) if [ "$OS" = Darwin ]; then
       if [ "$USE_ITERM" = 1 ] || [ "$USE_GHOSTTY" = 1 ]; then want_font=1; fi
     elif [ "$IS_WSL" = 0 ] && [ "$IS_TERMUX" = 0 ] && [ -z "${SSH_CONNECTION:-}" ] \
          && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${XDG_CURRENT_DESKTOP:-}" ]; }; then
       want_font=1
     fi ;;
esac
font_installed() {
  local f
  for f in "$HOME"/Library/Fonts/JetBrainsMonoNerdFont* /Library/Fonts/JetBrainsMonoNerdFont* "$FONT_DIR"; do
    [ -e "$f" ] && return 0
  done
  # (no grep -q: it would stop reading early and fail the pipe under pipefail)
  has fc-list && fc-list : family 2>/dev/null | grep -i 'JetBrainsMono Nerd' >/dev/null
}
NEED_FONT=0; FONT_VER=""
if [ "$want_font" = 1 ] && ! font_installed; then
  NEED_FONT=1
  if [ "$PM" = brew ]; then
    user_plan "JetBrainsMono Nerd Font" "new, brew install --cask (icons in nvim)"
  else
    FONT_VER="$(gh_latest ryanoasis/nerd-fonts)"
    user_plan "JetBrainsMono Nerd Font" "new ${FONT_VER:-latest}, ~/.local/share/fonts (icons in nvim)"
  fi
fi

ITERM_PROFILES="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
ITERM_GUID="3d9b7f2a-6c1e-4b8e-9f2d-5e7a0c1d2b3f"
NEED_ITERM=0
# (an existing profile is compared with the repo's when the files are copied, below)
if [ "$USE_ITERM" = 1 ] && [ ! -f "$ITERM_PROFILES/dotfiles.json" ]; then
  NEED_ITERM=1
  user_plan "iTerm2 profile" "Catppuccin Mocha, Nerd Font, Option as Alt; set as default, clipboard access on"
fi
# iTerm2's Minimal theme: the title bar and tabs take the terminal's background colour, as in
# Ghostty. Only when the theme was never chosen (Settings > Appearance > Theme), so a choice is kept.
NEED_ITERM_THEME=0
if [ "$USE_ITERM" = 1 ] && ! defaults read com.googlecode.iterm2 TabStyleWithAutomaticOption >/dev/null 2>&1; then
  NEED_ITERM_THEME=1
  user_plan "iTerm2 theme" "Minimal (title bar in the terminal's colour)"
fi

if [ ${#SYS_PLAN[@]} -eq 0 ] && [ ${#USER_PLAN[@]} -eq 0 ]; then
  log "Everything is installed and up to date"
else
  log "To install or update:"
  if [ ${#SYS_PLAN[@]} -gt 0 ]; then
    case "$SUDO_OK" in
      0) echo "   System, for every user (no sudo: NOT changed, ask an admin):" ;;
      1) if [ "$PM" = brew ]; then echo "   System, for every user (Homebrew):"
         elif [ "$(id -u)" -eq 0 ]; then echo "   System, for every user (as root):"
         else echo "   System, for every user (sudo):"; fi ;;
      2) echo "   System, for every user (sudo, asks for your password):" ;;
    esac
    print_rows "${SYS_PLAN[@]}"
  fi
  if [ ${#USER_PLAN[@]} -gt 0 ]; then
    echo "   Only you ($(id -un)), in ~, no sudo:"
    print_rows "${USER_PLAN[@]}"
  fi
  echo "   Installed OS packages are left as they are; everything else is kept at the latest release."
  echo "   nvim plugins and LSP servers are updated to the latest too; the summary lists what changed."
  if [ "$HAS_TTY" = 1 ] && [ "${ASSUME_YES:-0}" != 1 ]; then
    ask "Continue? [Y/n]" y
    case "$REPLY" in [Nn]*) log "Nothing changed"; exit 0 ;; esac
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
    brew)    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_UPGRADE=1 \
               HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew install "$@" ;;
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
  if [ "$INDEX_FRESH" = 0 ]; then
    case "$PM" in
      apt-get) sudo apt-get update || true ;;
      pacman)  sudo pacman -Sy --noconfirm ;;
      zypper)  sudo zypper --non-interactive refresh || true ;;
      apk)     sudo apk update ;;
      brew)    # quietly: its own output lists every new formula (hundreds of lines)
               log "Updating Homebrew (brew update)"
               brew update --quiet >/dev/null 2>&1 || warn "brew update failed, installing with the current package list" ;;
    esac
  fi
  # macOS: Homebrew stops with "You have not agreed to the Xcode license" when Xcode is
  # installed but its license was never accepted; say so before anything is installed
  if [ "$PM" = brew ] && has xcodebuild && xcode-select -p 2>/dev/null | grep -q '\.app/'; then
    xcodebuild -license check >/dev/null 2>&1 \
      || die "accept the Xcode license first: sudo xcodebuild -license accept   (then run this again)"
  fi
  if [ ${#MISS_REQ[@]} -gt 0 ]; then
    if ! pm_add "${MISS_REQ[@]}"; then
      [ "$IS_TERMUX" = 1 ] && warn "Termux could not download packages: run termux-change-repo, pick another mirror, then run this again"
      die "could not install OS packages: ${MISS_REQ[*]}"
    fi
    for p in "${MISS_REQ[@]}"; do sys_did "$p $(pkg_installed_version "$p")"; done
  fi
  for p in ${MISS_OPT[@]+"${MISS_OPT[@]}"}; do
    if pm_add "$p" >/dev/null 2>&1; then sys_did "$p $(pkg_installed_version "$p")"
    else failed "$p (optional OS package, not available)"; fi
  done
  hash -r
elif [ "$NEED_OS" = 1 ]; then
  missing="${MISS_REQ[*]:-}"
  for c in git tar; do has "$c" || die "missing required tool: $c (ask an admin to install it)"; done
  has curl || has wget || die "missing required tool: curl (ask an admin to install it)"
  [ -z "$missing" ] || warn "missing OS packages: $missing (ask an admin to install them; related features will not work)"
fi

# ---------- Docker (asked at the start) ----------
if [ "$NEED_DOCKER" = 1 ] && [ "$SUDO_OK" = 1 ]; then
  log "Installing Docker"
  docker_ok=0
  case "$PM" in
    brew)
      # the cask was renamed from docker to docker-desktop
      { HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask docker-desktop || HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask docker; } \
        > "$TMP/docker.log" 2>&1 && docker_ok=1 ;;
    apt-get|yum)
      # shellcheck disable=SC2024 # the log is written as this user, on purpose
      # Docker's own script; distributions it does not know (e.g. Linux Mint) get the distro's package
      if fetch https://get.docker.com "$TMP/get-docker.sh" && sudo sh "$TMP/get-docker.sh" > "$TMP/docker.log" 2>&1; then docker_ok=1
      elif [ "$PM" = apt-get ] && pm_add docker.io >> "$TMP/docker.log" 2>&1; then
        pm_add docker-compose-v2 >/dev/null 2>&1 || pm_add docker-compose >/dev/null 2>&1 || true; docker_ok=1
      fi ;;
    dnf)
      if [ "$OS_ID" = fedora ]; then
        # shellcheck disable=SC2024 # the log is written as this user, on purpose
        fetch https://get.docker.com "$TMP/get-docker.sh" && sudo sh "$TMP/get-docker.sh" > "$TMP/docker.log" 2>&1 && docker_ok=1
      else # RHEL, Rocky, Alma, CentOS Stream: Docker's CentOS repository
        { sudo dnf install -y dnf-plugins-core \
          && sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo \
          && sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; } \
          > "$TMP/docker.log" 2>&1 && docker_ok=1
      fi ;;
    pacman) pm_add docker docker-compose docker-buildx > "$TMP/docker.log" 2>&1 && docker_ok=1 ;;
    zypper) pm_add docker docker-compose > "$TMP/docker.log" 2>&1 && docker_ok=1 ;;
    apk)    pm_add docker docker-cli-compose > "$TMP/docker.log" 2>&1 && docker_ok=1 ;;
  esac
  hash -r
  if [ "$docker_ok" = 1 ]; then
    v="$(docker --version 2>/dev/null | sed 's/^Docker version //; s/,.*//' || true)"
    sys_did "Docker${v:+ $v}"
    # Start it now and at boot (not in containers or WSL without systemd: start dockerd yourself)
    if [ "$OS" = Linux ]; then
      if [ -d /run/systemd/system ]; then sudo systemctl enable --now docker >/dev/null 2>&1 || warn "could not start Docker (systemctl status docker)"
      elif [ "$PM" = apk ] && has rc-update; then { sudo rc-update add docker default && sudo rc-service docker start; } >/dev/null 2>&1 || true
      else DOCKER_NO_SERVICE=1; fi
    fi
  else
    tail -n 15 "$TMP/docker.log" >&2 || true
    failed "Docker ($DOCKER_HOW)"
    NEED_DOCKER_GROUP=0
  fi
fi
if [ "$NEED_DOCKER_GROUP" = 1 ] && [ "$SUDO_OK" = 1 ]; then
  me="$(id -un)"
  getent group docker >/dev/null 2>&1 || sudo groupadd docker >/dev/null 2>&1 || true
  if { has usermod && sudo usermod -aG docker "$me"; } || { has addgroup && sudo addgroup "$me" docker; }; then
    sys_did "docker group: added $me (log out and back in, or run newgrp docker)"
    DOCKER_RELOGIN=1
  else failed "docker group (sudo usermod -aG docker $me)"; fi
fi

# Debian/Ubuntu ship fd as fdfind
if ! has fd && has fdfind; then ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"; fi

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
# curl / wget may have been installed just now: look the version up again if needed
if [ "$NEED_NODE" = 1 ] && [ -z "$NODE_LATEST" ]; then
  NODE_LATEST="$(lk_node || true)"
fi
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
  log "Installing tree-sitter CLI ${TS_LATEST:-latest} in ~/.local/opt/tree-sitter-cli"
  npm install --silent --prefix "$LOCAL_OPT/tree-sitter-cli" "tree-sitter-cli@${TS_LATEST#v}" >/dev/null 2>&1 \
    || npm install --silent --prefix "$LOCAL_OPT/tree-sitter-cli" tree-sitter-cli@latest >/dev/null
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
    if [ -n "$TS_LATEST" ]; then "$CARGO" install --locked --force tree-sitter-cli --version "${TS_LATEST#v}"
    else "$CARGO" install --locked --force tree-sitter-cli; fi
    ln -sf "$HOME/.cargo/bin/tree-sitter" "$LOCAL_BIN/tree-sitter"
    hash -r
  fi
  if ts_works "$LOCAL_BIN/tree-sitter"; then
    v="v$("$LOCAL_BIN/tree-sitter" --version | awk '{print $2}')"
    if [ -n "$TS_CUR" ]; then did "tree-sitter CLI $v (was $TS_CUR)"; else did "tree-sitter CLI $v"; fi
  else failed "tree-sitter CLI"; fi
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

# ---------- lazygit (per user, Linux) ----------
# The lookup may have failed (network blip, or curl was installed only just now): try again
if [ "$NEED_LG" = 1 ] && [ -z "$LG_LATEST" ]; then LG_LATEST="$(gh_latest jesseduffield/lazygit)"; fi
if [ "$NEED_LG" = 1 ]; then
  if [ -z "$LG_LATEST" ]; then
    failed "lazygit (could not look up the latest release)"
  else
    log "Installing lazygit $LG_LATEST in ~/.local/bin"
    case "$ARCH" in amd64) a=x86_64 ;; arm64) a=arm64 ;; esac
    if fetch_once "https://github.com/jesseduffield/lazygit/releases/download/$LG_LATEST/lazygit_${LG_LATEST#v}_Linux_$a.tar.gz" "$TMP/lazygit.tgz" \
       && tar -C "$TMP" -xzf "$TMP/lazygit.tgz" lazygit && mv -f "$TMP/lazygit" "$LOCAL_BIN/lazygit"; then
      if [ -n "$LG_CUR" ]; then did "lazygit $LG_LATEST (was $LG_CUR)"; else did "lazygit $LG_LATEST"; fi
    else
      failed "lazygit"
    fi
  fi
fi

# ---------- uv and Python (per user) ----------
# uv installs into ~/.local/bin; `uv python install --default` adds python3 there too, so
# Mason's Python tools (and the user) get a recent Python with venv and pip, no sudo needed.
if [ "$NEED_UV" = 1 ] && [ -n "$UV_CUR" ]; then
  log "Updating uv to ${UV_LATEST:-latest}"
  if "$LOCAL_BIN/uv" self update -q; then did "uv $("$LOCAL_BIN/uv" --version | awk '{print $2}') (was $UV_CUR)"
  else failed "uv update"; fi
elif [ "$NEED_UV" = 1 ]; then
  log "Installing uv ${UV_LATEST:-latest} in ~/.local/bin"
  fetch https://github.com/astral-sh/uv/releases/latest/download/uv-installer.sh "$TMP/uv-installer.sh"
  if env UV_NO_MODIFY_PATH=1 UV_INSTALL_DIR="$LOCAL_BIN" sh "$TMP/uv-installer.sh" --quiet && [ -x "$LOCAL_BIN/uv" ]; then
    did "uv $("$LOCAL_BIN/uv" --version | awk '{print $2}')"
  else
    failed "uv"
  fi
fi
hash -r
if [ "$NEED_PY" = 1 ] && has uv; then
  # Without a version, uv picks the newest stable Python
  PY_ARG=(); [ -n "$PY_LATEST" ] && PY_ARG=("$PY_LATEST")
  log "Installing Python ${PY_LATEST:-latest} with uv"
  # --default (adds python / python3 next to python3.X) is marked experimental; hide that warning
  if uv python install --default ${PY_ARG[@]+"${PY_ARG[@]}"} >"$TMP/uv-python.log" 2>&1 && [ -x "$LOCAL_BIN/python3" ]; then
    hash -r; v="$("$LOCAL_BIN/python3" --version | awk '{print $2}')"
    if [ -n "$PY_CUR" ]; then did "Python $v (was $PY_CUR)"; else did "Python $v"; fi
  else
    cat "$TMP/uv-python.log" >&2; failed "Python ${PY_LATEST:-latest} (uv)"
  fi
fi

# Plugin commits before this run, to list what changed at the end. The lockfile used to live in
# the repo (nvim/lazy-lock.json), so read that one if there is no per-user lockfile yet.
LAZY_LOCK="$DATA_HOME/nvim/lazy-lock.json"
lock_commits() { [ -f "$1" ] && sed -n 's/^ *"\([^"]*\)": *{.*"commit": *"\([0-9a-f]\{7\}\).*/\1 \2/p' "$1" | LC_ALL=C sort; }
if [ -f "$LAZY_LOCK" ]; then lock_commits "$LAZY_LOCK" > "$TMP/lock.before" || true
else lock_commits "$OLD_DOTFILES/nvim/lazy-lock.json" > "$TMP/lock.before" 2>/dev/null || true; fi

# ---------- dotfiles: copy this repo's config into place ----------
log "Installing the config files"
if [ -n "$DOTFILES_DIR" ]; then
  SRC="$DOTFILES_DIR"
else
  SRC="$TMP/dotfiles"
  git clone -q --depth 1 "$DOTFILES_REPO" "$SRC" || die "could not download $DOTFILES_REPO"
fi
SRC_VER="$(git -c safe.directory="$SRC" -C "$SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
PRISTINE="$STATE_DIR/installed" # what the last install put in place, to tell your own edits apart
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$STATE_DIR"
CHANGED=0
# install_file SRC DST KEY: copy SRC to DST. A DST you edited since the last install (it differs
# from what was installed) is saved as DST.bak.<time> first.
install_file() {
  local src="$1" dst="$2" pris="$PRISTINE/$3"
  if [ -L "$dst" ]; then rm -f "${dst:?}"   # a link from an older install
  elif [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
    if [ ! -f "$pris" ] || ! cmp -s "$pris" "$dst"; then
      cp -p "$dst" "$dst.bak.$STAMP"; warn "kept your version of $dst as ${dst##*/}.bak.$STAMP"
    fi
  fi
  if ! cmp -s "$src" "$dst" 2>/dev/null; then
    mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"; CHANGED=$((CHANGED + 1))
  fi
  mkdir -p "$(dirname "$pris")"; cp "$src" "$pris"
}
# install_tree SRC_DIR DST_DIR KEY [KEEP...]: copy every file. Files an earlier install put there
# that are gone from the repo are removed; files of your own are left alone. KEEP: files that are
# only created, never overwritten (lazyvim.json, which LazyVim itself updates).
install_tree() {
  local src="$1" dst="$2" key="$3" f k keep; shift 3
  if [ -L "$dst" ]; then rm -f "${dst:?}"
  elif [ -d "$dst" ] && [ ! -d "$PRISTINE/$key" ]; then
    # a config that did not come from this installer: set it aside
    mv "$dst" "$dst.bak.$STAMP"; warn "moved your $dst to ${dst##*/}.bak.$STAMP"
  fi
  if [ -d "$PRISTINE/$key" ]; then
    while IFS= read -r f; do
      f="${f#./}"
      [ -e "$src/$f" ] && continue
      if cmp -s "$PRISTINE/$key/$f" "$dst/$f"; then rm -f "${dst:?}/${f:?}"; CHANGED=$((CHANGED + 1)); fi
      rm -f "${PRISTINE:?}/${key:?}/${f:?}"
    done < <(cd "$PRISTINE/$key" && find . -type f)
  fi
  while IFS= read -r f; do
    f="${f#./}"; keep=0
    for k in "$@"; do [ "$f" = "$k" ] && keep=1; done
    if [ "$keep" = 1 ] && [ -e "$dst/$f" ]; then continue; fi
    install_file "$src/$f" "$dst/$f" "$key/$f"
  done < <(cd "$src" && find . -type f | LC_ALL=C sort)
}
has find || die "find is missing (package findutils), it is needed to copy the config"
install_tree "$SRC/nvim" "$CONFIG_HOME/nvim" nvim lazyvim.json
# (a failure inside the < <(...) loops would not stop the script: check the result)
[ -f "$CONFIG_HOME/nvim/init.lua" ] || die "could not copy the nvim config to $CONFIG_HOME/nvim"
install_file "$SRC/tmux/tmux.conf.local" "$HOME/.tmux.conf.local" tmux.conf.local
install_file "$SRC/shell/env.sh" "$STATE_DIR/env.sh" env.sh
# git hooks: hook.sh plus one relative link per hook name (cp -R keeps them as links)
rm -rf "${STATE_DIR:?}/git.new"; cp -R "$SRC/git" "$STATE_DIR/git.new"
rm -rf "${STATE_DIR:?}/git"; mv "$STATE_DIR/git.new" "$STATE_DIR/git"
if [ "$OS" != Darwin ] || [ "$USE_GHOSTTY" = 1 ]; then
  install_file "$SRC/ghostty/config" "$CONFIG_HOME/ghostty/config" ghostty
  # Ghostty on macOS also loads a config in Application Support, after (and over) this one: move it aside
  for f in "$HOME/Library/Application Support/com.mitchellh.ghostty/config" \
           "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
    if [ -s "$f" ] && [ ! -L "$f" ]; then
      mv "$f" "$f.bak.$STAMP" && did "Ghostty: moved your old config aside (${f##*/}.bak.$STAMP), ~/.config/ghostty/config is used now"
    fi
  done
fi
if [ "$USE_ITERM" = 1 ] && ! cmp -s "$SRC/iterm2/dotfiles.json" "$ITERM_PROFILES/dotfiles.json"; then NEED_ITERM=1; fi
if [ "$DF_CUR" != "${SRC_VER:0:7}" ] || [ "$CHANGED" -gt 0 ]; then
  if [ -n "$DF_CUR" ]; then did "dotfiles $DF_CUR -> ${SRC_VER:0:7} ($CHANGED files changed)"
  else did "dotfiles ${SRC_VER:0:7} (in ~/.config/nvim, ~/.tmux.conf.local, ~/.config/dotfiles)"; fi
fi
printf '%s\n' "$SRC_VER" > "$STATE_DIR/version"

link() { # link SRC DST: a symlink; an existing file is set aside first
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then mv "$dst" "$dst.bak.$STAMP"; fi
  ln -sfn "$src" "$dst"
}

# tmux: Oh my tmux! (https://github.com/gpakosz/.tmux) plus this repo's tmux/tmux.conf.local
if [ "$NEED_OMT" = 0 ]; then
  if git -C "$OH_MY_TMUX" pull --ff-only -q; then
    if [ -n "$OMT_UPD" ]; then set -- $OMT_UPD; did "Oh my tmux! $1 -> $2"; fi
  else warn "could not update Oh my tmux!"; fi
else
  git clone -q https://github.com/gpakosz/.tmux "$OH_MY_TMUX"
  did "Oh my tmux! $(git -C "$OH_MY_TMUX" rev-parse --short HEAD)"
fi
link "$OH_MY_TMUX/.tmux.conf" "$HOME/.tmux.conf"

# Load env.sh (PATH for ~/.local/bin and Mason, sshk, ...) from the shell rc files, once.
# The line older installs added (pointing into ~/dotfiles) is replaced.
SOURCE_LINE="[ -f \"$STATE_DIR/env.sh\" ] && . \"$STATE_DIR/env.sh\" # dotfiles"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  # Always use ~/.bashrc; use ~/.zshrc when it exists, or on macOS where zsh is the default shell
  case "$rc" in
    */.zshrc) [ -f "$rc" ] || [ "$OS" = Darwin ] || continue ;;
  esac
  if grep -qs '/shell/env.sh" # dotfiles$' "$rc"; then
    # rewritten with cat >, so an rc file that is a link stays a link
    grep -v '/shell/env.sh" # dotfiles$' "$rc" > "$TMP/rc" || true
    cat "$TMP/rc" > "$rc"
  fi
  grep -qsF "$SOURCE_LINE" "$rc" || printf '\n%s\n' "$SOURCE_LINE" >> "$rc"
done
# shellcheck source=shell/env.sh
. "$STATE_DIR/env.sh"

# ---------- nvim plugins, LSP servers, treesitter parsers (all headless) ----------
# Everything is installed when missing and updated to the latest; each step is time-bounded.
# Lazy sync: install missing plugins and update all of them to the latest commit
log "Installing and updating nvim plugins (LazyVim, up to a minute)"
# Lazy's per-plugin progress goes to a log (shown only on failure); the summary lists the
# plugins whose commit changed (lockfile before vs after)
if with_timeout 900 env DOTFILES_HEADLESS_INSTALL=1 nvim --headless "+Lazy! sync" +qa </dev/null > "$TMP/lazy.log" 2>&1; then
  lock_commits "$LAZY_LOCK" > "$TMP/lock.after" || true
  n="$(wc -l < "$TMP/lock.after" | tr -d ' ')"
  m=0; [ -s "$TMP/lock.before" ] && m="$(LC_ALL=C join "$TMP/lock.before" "$TMP/lock.after" 2>/dev/null | awk '$2 != $3' | wc -l | tr -d ' ' || echo 0)"
  echo "   $n plugins, $m updated"
  if [ -s "$TMP/lock.before" ]; then
    LC_ALL=C join "$TMP/lock.before" "$TMP/lock.after" | awk '$2 != $3 {print "nvim plugin " $1 " " $2 " -> " $3}' > "$TMP/plugins.done"
    LC_ALL=C join -v 2 "$TMP/lock.before" "$TMP/lock.after" | awk '{print "nvim plugin " $1 " new " $2}' >> "$TMP/plugins.done"
    while IFS= read -r l; do did "$l"; done < "$TMP/plugins.done"
  fi
else
  tail -n 20 "$TMP/lazy.log" | tr -d '\r' >&2
  failed "nvim plugins (Lazy sync failed or timed out, run :Lazy sync)"
fi

log "Installing and updating LSP servers, formatters and treesitter parsers"
# CFLAGS: tree-sitter's default flags include -Wall, which makes gcc 12.2 (Debian 12) spend
# minutes on large generated parsers such as gitcommit. config/options.lua sets the same default.
export CFLAGS="${CFLAGS:--O2}"
# DOTFILES_HEADLESS_INSTALL stops LazyVim's background parser builds; headless.lua builds them
# itself and waits for every Mason package and parser to finish (see nvim/lua/dotfiles/headless.lua)
# `cquit 1` runs only if install() itself failed to quit (e.g. a Lua error), so nvim never hangs
# Shows only what changes (Mason installs / updates, parser builds, errors); full log in a file
if with_timeout 1500 env DOTFILES_HEADLESS_INSTALL=1 nvim --headless -c "lua require('dotfiles.headless').install()" \
     -c "cquit 1" </dev/null 2>&1 | tee "$TMP/headless.log" \
     | { grep --line-buffered -E 'mason: |treesitter round|^!!' || true; }; then
  [ "$NEED_LAZY" = 1 ] && did "nvim plugins, LSP servers, formatters and parsers (latest)"
  # "  mason: updating NAME A -> B" / "  mason: installing NAME V" lines from headless.lua
  sed -n 's/^ *mason: updating \(.*\)/Mason \1/p; s/^ *mason: installing \(.*\)/Mason \1 (new)/p' "$TMP/headless.log" \
    | tr -d '\r' > "$TMP/mason.done"
  if [ "$NEED_LAZY" = 0 ]; then while IFS= read -r l; do did "$l"; done < "$TMP/mason.done"; fi
else
  failed "some LSP servers or parsers (open nvim and check :Mason and :checkhealth)"
  # Mason's own log has the full reason for each failure
  MASON_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/nvim/mason.log"
  if [ -f "$MASON_LOG" ]; then
    warn "last Mason errors ($MASON_LOG):"
    grep -i 'error\|fail' "$MASON_LOG" | tail -n 5 | cut -c1-300 >&2 || true
  fi
fi

# ---------- Terminal: Nerd Font, Ghostty, iTerm2 ----------
if [ "$NEED_FONT" = 1 ] && [ "$PM" = brew ]; then
  log "Installing JetBrainsMono Nerd Font"
  if HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
    did "JetBrainsMono Nerd Font"
  else failed "JetBrainsMono Nerd Font (brew install --cask font-jetbrains-mono-nerd-font)"; fi
elif [ "$NEED_FONT" = 1 ]; then
  log "Installing JetBrainsMono Nerd Font ${FONT_VER:-latest} in ~/.local/share/fonts"
  if [ -n "$FONT_VER" ]; then u="download/$FONT_VER"; else u="latest/download"; fi
  u="https://github.com/ryanoasis/nerd-fonts/releases/$u/JetBrainsMono.tar.xz"
  mkdir -p "$TMP/font"
  if fetch_once "$u" "$TMP/font.tar.xz" && tar -xJf "$TMP/font.tar.xz" -C "$TMP/font" \
     && ls "$TMP"/font/JetBrainsMonoNerdFont-*.ttf >/dev/null 2>&1; then
    # The regular and Mono (single-width icons) families; not the NL / Propo variants
    mkdir -p "$FONT_DIR"
    cp "$TMP"/font/JetBrainsMonoNerdFont-*.ttf "$TMP"/font/JetBrainsMonoNerdFontMono-*.ttf "$FONT_DIR"/
    if has fc-cache; then fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true; fi
    did "JetBrainsMono Nerd Font${FONT_VER:+ $FONT_VER} (pick \"JetBrainsMono Nerd Font\" in your terminal's settings)"
  else failed "JetBrainsMono Nerd Font ($u)"; fi
fi
if [ "$NEED_GHOSTTY" = 1 ]; then
  log "Installing Ghostty"
  if HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask ghostty >/dev/null 2>&1; then did "Ghostty (config: ~/.config/ghostty/config)"
  else failed "Ghostty (brew install --cask ghostty)"; fi
fi
if [ "$NEED_ITERM" = 1 ]; then
  log "Setting up the iTerm2 profile"
  mkdir -p "$ITERM_PROFILES"
  # A copy, not a link: iTerm2 reads the folder at start and when files in it change
  cp "$SRC/iterm2/dotfiles.json" "$ITERM_PROFILES/dotfiles.json"
  # Default profile for new windows, and let programs (tmux, nvim over SSH) set the clipboard.
  # iTerm2 saves its settings when it quits, so these apply after iTerm2 restarts.
  defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$ITERM_GUID"
  defaults write com.googlecode.iterm2 AllowClipboardAccess -bool true
  did "iTerm2 profile 'Dotfiles (Catppuccin Mocha)' (default; restart iTerm2 to use it)"
fi
if [ "$NEED_ITERM_THEME" = 1 ]; then
  # 5 = Minimal (0 Light, 1 Dark, 4 Automatic, 6 Compact)
  if defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 5; then
    did "iTerm2 theme Minimal (restart iTerm2 to use it)"
  else failed "iTerm2 theme"; fi
fi

# ---------- Claude Code (optional, see the questions at the top) ----------
if [ "$INSTALL_CLAUDE" = 1 ]; then
  # Settings, merged into ~/.claude/settings.json with Node.js; keys already set are kept:
  #   attribution: Claude is not added as a co-author of commits and PRs ("" hides the text)
  #   env.USE_BUILTIN_RIPGREP=0 on musl (Alpine), where the bundled ripgrep cannot run
  if [ "$NEED_CLAUDE_ATTR" = 1 ] || [ "$PM" = apk ]; then
    mkdir -p "$HOME/.claude"
    if CLAUDE_SETTINGS="$CLAUDE_SETTINGS" MUSL="$([ "$PM" = apk ] && echo 1 || echo 0)" node -e '
      const fs = require("fs"), f = process.env.CLAUDE_SETTINGS;
      let s = {};
      if (fs.existsSync(f)) s = JSON.parse(fs.readFileSync(f, "utf8") || "{}");
      // "" hides the commit trailer / PR line; sessionUrl false drops the Claude-Session link.
      // Keys the user already set are kept.
      if (s.attribution === undefined || s.attribution === null) s.attribution = {};
      if (typeof s.attribution === "object") {
        if (s.attribution.commit === undefined) s.attribution.commit = "";
        if (s.attribution.pr === undefined) s.attribution.pr = "";
        if (s.attribution.sessionUrl === undefined) s.attribution.sessionUrl = false;
      }
      if (process.env.MUSL === "1") { s.env = s.env || {}; if (s.env.USE_BUILTIN_RIPGREP === undefined) s.env.USE_BUILTIN_RIPGREP = "0"; }
      fs.writeFileSync(f, JSON.stringify(s, null, 2) + "\n");
    '; then
      [ "$NEED_CLAUDE_ATTR" = 1 ] && did "Claude settings: no co-author or session link in commits and PRs"
    else
      failed "Claude settings (could not update ~/.claude/settings.json; is it valid JSON?)"
    fi
  fi
  if [ "$NEED_GIT_HOOK" = 1 ]; then
    if git config --global core.hooksPath "$GIT_HOOKS"; then did "git commit-msg hook (core.hooksPath $GIT_HOOKS)"
    else failed "git commit-msg hook"; fi
  fi
  # Native installer: updates itself in the background, so it is only run when claude is missing
  if [ "$NEED_CLAUDE" = 1 ] && [ -n "$CLAUDE_CUR" ]; then
    log "Updating Claude Code to ${CLAUDE_LATEST:-latest}"
    if claude update >/dev/null 2>&1; then did "Claude Code $(claude --version 2>/dev/null | awk '{print $1}') (was $CLAUDE_CUR)"
    else failed "Claude Code update (run: claude update)"; fi
  elif [ "$NEED_CLAUDE" = 1 ]; then
    log "Installing Claude Code ${CLAUDE_LATEST:-latest}"
    fetch https://claude.ai/install.sh "$TMP/claude-install.sh"
    bash "$TMP/claude-install.sh"
    . "$STATE_DIR/env.sh"; hash -r
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

# ---------- The old ~/dotfiles clone (nothing points into it any more) ----------
if [ "$RM_OLD" = 1 ]; then
  if [ "$(git config --global core.hooksPath 2>/dev/null || true)" = "$OLD_DOTFILES/git/hooks" ]; then
    git config --global core.hooksPath "$GIT_HOOKS"
  fi
  rm -rf "${HOME:?}/dotfiles" && did "removed the old ~/dotfiles (no longer used)"
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
# ---------- Next steps (printed on every run, so nothing is forgotten) ----------
log "Done. Next steps:"
echo "   - Open a new shell, then run nvim and tmux (:checkhealth and :Mason show the details)"
[ "${DOCKER_RELOGIN:-0}" = 1 ] && echo "   - Docker: log out and back in (or run: newgrp docker), then docker runs without sudo"
[ "${DOCKER_NO_SERVICE:-0}" = 1 ] && echo "   - Docker: no systemd here, so the daemon was not started (run: sudo dockerd &)"
[ "$NEED_DOCKER" = 1 ] && [ "$PM" = brew ] && echo "   - Docker: open Docker Desktop once (Applications) to finish its setup"
if [ "$INSTALL_CLAUDE" = 1 ] && has claude; then
  [ "$NEED_CLAUDE" = 1 ] && [ -z "$CLAUDE_CUR" ] && echo "   - Run claude (or tmux prefix + A) and log in"
  # MCP servers (plugin tools, claude.ai connectors) that still need a sign-in. `claude mcp list`
  # connects to each one, so it is bounded; run from ~ so no project's .mcp.json is involved.
  v="$(cd "$HOME" && timeout_cmd 60 claude mcp list 2>/dev/null || true)"
  v="$(printf '%s\n' "$v" | grep -i 'auth' | sed 's/: .*//' | tr -d '\r' || true)"
  must="$(printf '%s\n' "$v" | grep -v '^plugin:design:' | grep -v '^$' | tr '\n' ' ' || true)"
  opt="$(printf '%s\n' "$v" | sed -n 's/^plugin:design://p' | tr '\n' ' ' || true)"
  if [ -n "$must" ]; then
    echo "   - In claude, run /mcp and sign in to: $must"
    case "$must" in *claude.ai*) echo "     (claude.ai ... entries are connectors from your claude.ai account: reconnect or remove them there)" ;; esac
  fi
  if [ -n "$opt" ]; then
    echo "   - Optional, only if you use them with the design plugin: $opt"
    echo "     (or turn them off: /mcp, pick one, Disable; this is saved per project)"
  fi
fi
exit 0
}
