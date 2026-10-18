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

has()  { command -v "$1" >/dev/null 2>&1; }

# ---------- Output ----------
# On a terminal: a checklist for the choices, a plan, then one line per step with a spinner,
# while the commands' own output goes to a log file. Otherwise (CI, output into a file or a pipe,
# DOTFILES_PLAIN=1): plain "==>" lines with all the output, as before.
# fd 3 / 4 are the screen (stdout / stderr); on a terminal fd 1 / 2 go to the log.
INSTALL_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/install.log"
mkdir -p "$(dirname "$INSTALL_LOG")"; : > "$INSTALL_LOG"
exec 3>&1 4>&2
UI=0
if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ "${DOTFILES_PLAIN:-0}" != 1 ]; then UI=1; fi
HAS_TTY=0; ( exec </dev/tty ) 2>/dev/null && HAS_TTY=1
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UTF=1 ;; *) UTF=0 ;; esac
ESC=$'\033'
# Colours for anything drawn on the terminal (screen, checklist, prompts)
TB="${ESC}[1m"; TD="${ESC}[2m"; TG="${ESC}[32m"; TY="${ESC}[33m"; TR="${ESC}[31m"; TC="${ESC}[36m"; TN="${ESC}[0m"
if [ "$UI" = 1 ]; then B="$TB"; D="$TD"; G="$TG"; Y="$TY"; R="$TR"; C="$TC"; N="$TN"
else B=""; D=""; G=""; Y=""; R=""; C=""; N=""; fi
if [ "$UTF" = 1 ]; then
  S_OK="✓"; S_BAD="✗"; S_WARN="!"; S_NEW="+"; S_UP="↑"; S_TO="→"; S_PTR="›"; S_DOT="·"; S_ON="◉"; S_OFF="○"
  SPIN_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
else
  S_OK="ok"; S_BAD="xx"; S_WARN="!"; S_NEW="+"; S_UP="^"; S_TO="->"; S_PTR=">"; S_DOT="-"; S_ON="[x]"; S_OFF="[ ]"
  SPIN_FRAMES=("|" "/" "-" "\\")
fi
COLS=80
if [ "$HAS_TTY" = 1 ]; then
  c="$(stty size </dev/tty 2>/dev/null | awk '{print $2}' || true)"
  case "$c" in ''|*[!0-9]*) ;; *) [ "$c" -gt 20 ] && COLS="$c" ;; esac
fi
[ "$UI" = 1 ] && exec >>"$INSTALL_LOG" 2>&1

SPIN_PID=""; STEP_LABEL=""; STEP_T0=0; STEP_BAD=0; STEP_MSGS=()
# A background loop redraws "⠋ label  12s  <last line of the log>" until spin_stop
spin_start() {
  [ "$UI" = 1 ] || return 0
  local label="$1" t0="$SECONDS"
  (
    trap - INT TERM; exec 2>/dev/null
    i=0; nf=${#SPIN_FRAMES[@]}
    while :; do
      d="$(tail -n 1 "$INSTALL_LOG" 2>/dev/null | tr -d '\r' | sed "s/${ESC}\[[0-9;?]*[A-Za-z]//g; /^==> /d; /^!! /d" || true)"
      w=$((COLS - ${#label} - 14)); [ "$w" -gt 0 ] || w=0
      printf '\r%s[K  %s%s%s %s %s%ss  %s%s' "$ESC" "$TC" "${SPIN_FRAMES[$((i % nf))]}" "$TN" "$label" \
        "$TD" "$((SECONDS - t0))" "${d:0:$w}" "$TN" >&3
      i=$((i + 1)); sleep 0.2 2>/dev/null || sleep 1
    done
  ) &
  SPIN_PID=$!
}
spin_stop() {
  if [ -n "$SPIN_PID" ]; then
    kill "$SPIN_PID" 2>/dev/null || true; wait "$SPIN_PID" 2>/dev/null || true; SPIN_PID=""
    printf '\r%s[K' "$ESC" >&3
  fi
}
step_end() { # finish the current step: "✓ label (12s)", or "!" when something in it failed
  [ -n "$STEP_LABEL" ] || return 0
  if [ "$UI" = 1 ]; then
    spin_stop
    if [ "$STEP_BAD" = 1 ]; then m="$Y$S_WARN$N"; else m="$G$S_OK$N"; fi
    printf '  %s %s %s(%ss)%s\n' "$m" "$STEP_LABEL" "$D" "$((SECONDS - STEP_T0))" "$N" >&3
    for r in ${STEP_MSGS[@]+"${STEP_MSGS[@]}"}; do printf '    %s%s\n' "$r" "$N" >&3; done
  fi
  STEP_LABEL=""; STEP_MSGS=()
}
step() { # step LABEL: start a step (and end the previous one)
  step_end
  STEP_LABEL="$*"; STEP_T0="$SECONDS"; STEP_BAD=0
  printf '==> %s\n' "$*"   # the log, or the screen when not on a terminal
  spin_start "$*"
}
log() { # an information line
  if [ "$UI" = 1 ]; then printf '\r%s[K  %s%s%s %s\n' "$ESC" "$C" "$S_DOT" "$N" "$*" >&3; fi
  printf '==> %s\n' "$*"
}
note() { # a detail, shown under the current step
  if [ "$UI" = 1 ] && [ -n "$STEP_LABEL" ]; then STEP_MSGS+=("$D$*$N")
  elif [ "$UI" = 1 ]; then printf '\r%s[K    %s%s%s\n' "$ESC" "$D" "$*" "$N" >&3; fi
  printf '   %s\n' "$*"
}
warn() {
  if [ "$UI" = 1 ]; then printf '\r%s[K  %s%s%s %s\n' "$ESC" "$Y" "$S_WARN" "$N" "$*" >&4; fi
  printf '!! %s\n' "$*" >&2
}
die() {
  spin_stop
  if [ "$UI" = 1 ]; then
    printf '\n  %s%s%s %s\n' "$R" "$S_BAD" "$N" "$*" >&4
    printf '    %sfull log: %s%s\n' "$D" "$INSTALL_LOG" "$N" >&4
  fi
  printf 'xx %s\n' "$*" >&2
  exit 1
}
on_screen() { # on_screen CMD...: run a command that may ask something (a password) on the terminal
  local rc=0
  spin_stop
  "$@" >&3 2>&4 || rc=$?
  [ -n "$STEP_LABEL" ] && spin_start "$STEP_LABEL"
  return "$rc"
}
# ---------- Parallel jobs ----------
# job NAME LABEL FUNCTION starts FUNCTION in the background; jobs_wait shows one line per job (spinner,
# time, last line of its output) until all are done, then merges what they installed or failed.
# Inside a job, did / failed / note / warn / step write to the job's files instead of the screen.
J_NAMES=(); J_PIDS=(); J_T0=()
job() { # job NAME LABEL FUNCTION
  local name="$1" label="$2"; shift 2
  local jd="$TMP/job.$name"
  : > "$jd.res"; : > "$jd.log"; echo "$label" > "$jd.label"; echo "$label" > "$jd.name"; rm -f "$jd.rc"
  (
    trap - EXIT INT TERM
    SPIN_PID=""; STEP_LABEL=""; JD="$jd"
    did()       { printf 'did\t%s\n' "$*" >> "$JD.res"; }
    sys_did()   { printf 'sys\t%s\n' "$*" >> "$JD.res"; }
    failed()    { printf 'failed\t%s\n' "$*" >> "$JD.res"; printf '!! not installed: %s\n' "$*"; }
    note()      { printf 'note\t%s\n' "$*" >> "$JD.res"; printf '   %s\n' "$*"; }
    warn()      { printf 'warn\t%s\n' "$*" >> "$JD.res"; printf '!! %s\n' "$*"; }
    step()      { printf '%s\n' "$*" > "$JD.label"; printf '==> %s\n' "$*"; }
    die()       { printf 'failed\t%s\n' "$*" >> "$JD.res"; printf 'xx %s\n' "$*"; exit 1; }
    on_screen() { "$@"; }
    exec >> "$jd.log" 2>&1 </dev/null
    # -e would be ignored inside ( ... ) || ...: run it as a plain statement with +e outside
    set +e; ( set -e; "$@" ); rc=$?
    echo "$rc" > "$jd.rc"
  ) &
  J_NAMES+=("$name"); J_PIDS+=("$!"); J_T0+=("$SECONDS")
}
jobs_draw() { # one line per job; FINAL=1 draws the result instead of the spinner
  local i jd lab rc m d el w
  for i in "${!J_NAMES[@]}"; do
    jd="$TMP/job.${J_NAMES[$i]}"; lab="$(cat "$jd.label" 2>/dev/null || true)"
    if [ -f "$jd.rc" ]; then
      lab="$(cat "$jd.name")" # done: the job's own name, not its last step
      rc="$(cat "$jd.rc")"; el="$(cat "$jd.time" 2>/dev/null || echo "$((SECONDS - J_T0[i]))")"
      if [ "$rc" = 0 ] && ! grep -q '^failed' "$jd.res"; then m="$G$S_OK$N"; else m="$Y$S_WARN$N"; fi
      printf '\r%s[K  %s %s %s(%ss)%s\n' "$ESC" "$m" "$lab" "$D" "$el" "$N" >&3
    else
      d="$(tail -n 1 "$jd.log" 2>/dev/null | tr -d '\r' | sed "s/${ESC}\[[0-9;?]*[A-Za-z]//g; /^==> /d; /^!! /d" || true)"
      w=$((COLS - ${#lab} - 14)); [ "$w" -gt 0 ] || w=0
      printf '\r%s[K  %s%s%s %s %s%ss  %s%s\n' "$ESC" "$C" "${SPIN_FRAMES[$((J_TICK % ${#SPIN_FRAMES[@]}))]}" "$N" \
        "$lab" "$D" "$((SECONDS - J_T0[i]))" "${d:0:$w}" "$N" >&3
    fi
  done
}
jobs_wait() {
  local i jd n=${#J_NAMES[@]} left kind msg
  [ "$n" -gt 0 ] || return 0
  step_end
  J_TICK=0
  if [ "$UI" = 1 ]; then
    printf '%s[?25l' "$ESC" >&3
    jobs_draw
  else
    for i in "${!J_NAMES[@]}"; do printf '==> started: %s\n' "$(cat "$TMP/job.${J_NAMES[$i]}.name")"; done
  fi
  while :; do
    left=0
    for i in "${!J_NAMES[@]}"; do
      jd="$TMP/job.${J_NAMES[$i]}"
      if [ -f "$jd.rc" ]; then
        [ -f "$jd.time" ] || echo "$((SECONDS - J_T0[i]))" > "$jd.time"
      else left=$((left + 1)); fi
    done
    if [ "$UI" = 1 ]; then printf '%s[%dA' "$ESC" "$n" >&3; jobs_draw; fi
    [ "$left" -gt 0 ] || break
    J_TICK=$((J_TICK + 1)); sleep 0.2 2>/dev/null || sleep 1
  done
  wait "${J_PIDS[@]}" 2>/dev/null || true
  [ "$UI" = 1 ] && printf '%s[?25h' "$ESC" >&3
  # what the jobs did; their output goes to the log (and to the screen when it is not a terminal)
  for i in "${!J_NAMES[@]}"; do
    jd="$TMP/job.${J_NAMES[$i]}"
    if [ "$UI" = 1 ]; then { printf '==> %s\n' "$(cat "$jd.name")"; tr -d '\r' < "$jd.log"; } >> "$INSTALL_LOG"
    else printf '==> %s: done (%ss)\n' "$(cat "$jd.name")" "$(cat "$jd.time")"; tr -d '\r' < "$jd.log"; fi
    while IFS="$(printf '\t')" read -r kind msg; do
      case "$kind" in
        did) DONE+=("$msg") ;;
        sys) SYS_DONE+=("$msg") ;;
        failed) FAILED+=("$msg")
                [ "$UI" = 1 ] && printf '    %snot installed: %s%s\n' "$Y" "$msg" "$N" >&3 ;;
        warn) [ "$UI" = 1 ] && printf '    %s%s%s\n' "$Y" "$msg" "$N" >&3 ;;
        note) [ "$UI" = 1 ] && printf '    %s%s%s\n' "$D" "$msg" "$N" >&3 ;;
      esac
    done < "$jd.res"
    if [ "$(cat "$jd.rc")" != 0 ] && ! grep -q '^failed' "$jd.res"; then
      FAILED+=("$(cat "$jd.name") (stopped with an error, see the log)")
    fi
  done
  J_NAMES=(); J_PIDS=(); J_T0=()
  hash -r
  return 0
}

trap 'spin_stop; printf "%s[?25h" "$ESC" >&3; stty echo </dev/tty 2>/dev/null || true' EXIT
trap 'exit 130' INT TERM

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
if [ "$IS_TERMUX" = 1 ]; then OS_NAME="Android (Termux)"
elif [ "$OS" = Darwin ]; then OS_NAME="macOS $(sw_vers -productVersion 2>/dev/null || true)"
else OS_NAME="$( (. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-${NAME:-Linux}}") || echo Linux)"
     [ "$IS_WSL" = 1 ] && OS_NAME="$OS_NAME, WSL"; fi
if [ "$UI" = 1 ]; then
  printf '
  %sdotfiles%s  %sNeovim, tmux and the tools around them%s
' "$B" "$N" "$D" "$N" >&3
  printf '  %s%s %s %s %s %s %s%s

' "$D" "$OS_NAME" "$S_DOT" "$ARCH" "$S_DOT" "$(id -un)" "($PM)" "$N" >&3
fi
printf '==> OS: %s (%s)  Arch: %s  WSL: %s\n' "$OS_NAME" "$PM" "$ARCH" "$IS_WSL"

# The official nvim / node / tree-sitter / uv / Python builds need glibc: use the package
# manager's on macOS, musl (Alpine) and Termux
USE_PM_NVIM=0; USE_PM_NODE=0; USE_PM_TOOLS=0
[ "$PM" = brew ] && { USE_PM_NVIM=1; USE_PM_NODE=1; USE_PM_TOOLS=1; }
[ "$PM" = apk ]  && { USE_PM_NVIM=1; USE_PM_NODE=1; USE_PM_TOOLS=1; }
[ "$IS_TERMUX" = 1 ] && { USE_PM_NVIM=1; USE_PM_NODE=1; USE_PM_TOOLS=1; }

# ---------- Who can change the system ----------
# Root, Homebrew, or a user with sudo (the password is asked once, after the plan, and only when
# there are system changes). NO_SUDO=1 never uses sudo; USE_SUDO=1 asks for the password even
# when this user is not in the wheel / sudo / admin group.
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

# ---------- Choices (asked up front, so the rest runs unattended) ----------
# Neovim, tmux and their tools are always installed. Optional, picked in a checklist:
#   Claude Code and its plugins, Docker, the terminal setup (macOS) and the Nerd Font.
# The answers are saved in ~/.config/dotfiles/answers and reused (DOTFILES_ASK=1 asks again).
# Presets: INSTALL_CLAUDE=1|0, CLAUDE_PLUGINS="a b", INSTALL_DOCKER=1|0, SETUP_TERMINAL=1|0,
# INSTALL_FONT=1|0 (DOTFILES_FONT=1|0 too), SETUP_SSH=1|0 (tssh, trzsz, tsshd; `ssh` runs tssh).
# Without a terminal, unset ones take the defaults.
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
ALL_PLUGINS=""; for e in "${CLAUDE_WORKFLOW_PLUGINS[@]}"; do ALL_PLUGINS="$ALL_PLUGINS ${e%%|*}"; done
ALL_PLUGINS="${ALL_PLUGINS# }"

# Docker: a system install, so only offered with root, sudo or Homebrew. On Linux you are also
# added to the docker group, so docker runs without sudo (that group is as powerful as root).
in_docker_group() { id -nG 2>/dev/null | tr ' ' '\n' | grep -x docker >/dev/null; }
DOCKER_TODO="" # install | group | empty: what Docker would need here
if [ "$IS_TERMUX" = 1 ]; then :            # Android: no kernel support for containers
elif ! has docker; then DOCKER_TODO=install
elif [ "$OS" = Linux ] && [ "$(id -u)" -ne 0 ] && ! in_docker_group; then DOCKER_TODO=group
fi
DOCKER_BLOCKED=0
if [ -n "$DOCKER_TODO" ] && [ "$SUDO_OK" = 0 ]; then DOCKER_BLOCKED=1; fi

# Terminal (macOS): the one this runs in (TERM_PROGRAM; LC_TERMINAL / GHOSTTY_RESOURCES_DIR still
# tell inside tmux) and the other one if installed; Ghostty is installed only when it is the one
# running or asked for. DOTFILES_TERMINAL=iterm2|ghostty|none sets up only that one (or neither);
# NO_ITERM=1 / NO_GHOSTTY=1 skip one.
#   iTerm2: this repo's profile (iterm2/dotfiles.json: Catppuccin Mocha, JetBrainsMono Nerd Font,
#           Option as Alt) as the default, the Minimal theme, clipboard access for programs
#   Ghostty: ghostty/config
USE_ITERM=0; USE_GHOSTTY=0
if [ "$OS" = Darwin ]; then
  case "${DOTFILES_TERMINAL:-}" in
    iterm*|iTerm*) USE_ITERM=1 ;;
    ghostty|Ghostty) USE_GHOSTTY=1 ;;
    none) SETUP_TERMINAL="${SETUP_TERMINAL:-0}" ;;
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
TERM_OFFER=""
[ "$USE_ITERM" = 1 ] && TERM_OFFER="iTerm2 profile"
[ "$USE_GHOSTTY" = 1 ] && TERM_OFFER="${TERM_OFFER:+$TERM_OFFER + }Ghostty config"
# The font matters only where the terminal runs: macOS, or a Linux desktop session. A server
# reached over SSH, WSL (the terminal is on Windows) and Termux get none.
FONT_OFFER=0
if [ "$OS" = Darwin ]; then
  [ -n "$TERM_OFFER" ] && FONT_OFFER=1
elif [ "$IS_WSL" = 0 ] && [ "$IS_TERMUX" = 0 ] && [ -z "${SSH_CONNECTION:-}" ] \
     && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${XDG_CURRENT_DESKTOP:-}" ]; }; then
  FONT_OFFER=1
fi
case "${DOTFILES_FONT:-}" in 1|0) INSTALL_FONT="${INSTALL_FONT:-$DOTFILES_FONT}"; [ "$DOTFILES_FONT" = 1 ] && FONT_OFFER=1 ;; esac

# Saved answers fill in what is not preset; anything still open is asked
ANSWERS="$STATE_DIR/answers"
SAVED_ANSWERS=0
if [ "${DOTFILES_ASK:-0}" != 1 ] && [ -f "$ANSWERS" ]; then
  for k in INSTALL_CLAUDE CLAUDE_PLUGINS INSTALL_DOCKER SETUP_TERMINAL INSTALL_FONT SETUP_SSH; do
    v="$(sed -n "s/^$k=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$ANSWERS" | tail -1)"
    if [ -z "$(eval "echo \${$k+set}")" ] && grep -q "^$k=" "$ANSWERS"; then eval "$k=\"\$v\""; SAVED_ANSWERS=1; fi
  done
fi
OPEN=0 # something that applies here has no answer yet
[ -z "${INSTALL_CLAUDE:-}" ] && OPEN=1
[ -n "$DOCKER_TODO" ] && [ "$DOCKER_BLOCKED" = 0 ] && [ -z "${INSTALL_DOCKER:-}" ] && OPEN=1
[ -n "$TERM_OFFER" ] && [ -z "${SETUP_TERMINAL:-}" ] && OPEN=1
[ "$FONT_OFFER" = 1 ] && [ -z "${INSTALL_FONT:-}" ] && OPEN=1
[ -z "${SETUP_SSH:-}" ] && OPEN=1

# The checklist, drawn on the terminal: ↑↓ (or j k) move, Space toggles, a / n all / none,
# Enter continues, q quits. Rows: id | label | description | kind (main, sub, off)
M_ID=(); M_LABEL=(); M_DESC=(); M_KIND=(); M_ON=()
m_add() { M_ID+=("$1"); M_LABEL+=("$2"); M_DESC+=("$3"); M_KIND+=("$4"); M_ON+=("$5"); }
m_draw() { # m_draw CURSOR
  local i on mark lab desc w pre parent_on=1
  printf '  %sChoose what to install%s  %s(Neovim, tmux, LSP servers and git tools always)%s%s[K\n%s[K\n' \
    "$TB" "$TN" "$TD" "$TN" "$ESC" "$ESC" >/dev/tty
  for i in "${!M_ID[@]}"; do
    on="${M_ON[$i]}"; lab="${M_LABEL[$i]}"; desc="${M_DESC[$i]}"
    [ "${M_KIND[$i]}" = main ] && parent_on="$on"
    if [ "$i" = "$1" ]; then pre="$TC$S_PTR$TN"; else pre=" "; fi
    st=""
    if [ "${M_KIND[$i]}" = off ]; then mark="$TD$S_DOT$TN"; st="$TD"
    elif [ "$on" = 1 ]; then mark="$TG$S_ON$TN"; else mark="$TD$S_OFF$TN"; fi
    if [ "${M_KIND[$i]}" = sub ]; then
      [ "$parent_on" = 1 ] || { mark="$TD$S_OFF$TN"; st="$TD"; }
      lab="    $lab"
    fi
    [ "$i" = "$1" ] && st="$st$TB"
    lab="$(printf '%-33s' "$lab")"
    w=$((COLS - 40)); [ "$w" -gt 0 ] || w=0
    printf ' %s %s %s%s%s %s%s%s%s[K\n' "$pre" "$mark" "$st" "$lab" "$TN" "$TD" "${desc:0:$w}" "$TN" "$ESC" >/dev/tty
  done
  printf '%s[K\n  %s↑↓ move  Space toggle  a all  n none  Enter continue  q quit%s%s[K\n' \
    "$ESC" "$TD" "$TN" "$ESC" >/dev/tty
}
m_lines() { echo $(( ${#M_ID[@]} + 4 )); }
m_key() { # -> KEY
  local k="" k2=""
  IFS= read -rsn1 k </dev/tty || k=q
  if [ "$k" = "$ESC" ]; then IFS= read -rsn2 -t 1 k2 </dev/tty || true; k="ESC$k2"; fi
  KEY="$k"
}
m_run() {
  local cur=0 n=${#M_ID[@]} i j L
  L="$(m_lines)"
  while [ "${M_KIND[$cur]}" = off ] && [ "$cur" -lt $((n - 1)) ]; do cur=$((cur + 1)); done
  printf '%s[?25l' "$ESC" >/dev/tty; stty -echo </dev/tty 2>/dev/null || true
  m_draw "$cur"
  while :; do
    m_key
    case "$KEY" in
      "ESC[A"|"ESCOA"|k) j=$cur; while [ "$j" -gt 0 ]; do j=$((j - 1)); [ "${M_KIND[$j]}" != off ] && { cur=$j; break; }; done ;;
      "ESC[B"|"ESCOB"|j) j=$cur; while [ "$j" -lt $((n - 1)) ]; do j=$((j + 1)); [ "${M_KIND[$j]}" != off ] && { cur=$j; break; }; done ;;
      " "|x)
        if [ "${M_KIND[$cur]}" = sub ]; then
          # a plugin of a parent that is off: switch both on (it looked off already)
          j=$cur; while [ "$j" -gt 0 ]; do j=$((j - 1)); [ "${M_KIND[$j]}" = main ] && break; done
          if [ "${M_ON[$j]}" = 0 ]; then M_ON[$j]=1; M_ON[$cur]=1
          elif [ "${M_ON[$cur]}" = 1 ]; then M_ON[$cur]=0; else M_ON[$cur]=1; fi
        elif [ "${M_KIND[$cur]}" != off ]; then
          if [ "${M_ON[$cur]}" = 1 ]; then M_ON[$cur]=0; else M_ON[$cur]=1; fi
        fi ;;
      a|A) for i in "${!M_ID[@]}"; do [ "${M_KIND[$i]}" = off ] || M_ON[$i]=1; done ;;
      n|N) for i in "${!M_ID[@]}"; do [ "${M_KIND[$i]}" = off ] || M_ON[$i]=0; done ;;
      "") break ;;
      q|Q) printf '%s[?25h' "$ESC" >/dev/tty; stty echo </dev/tty 2>/dev/null || true
           printf '\n  Nothing changed.\n' >/dev/tty; exit 0 ;;
    esac
    printf '%s[%dA' "$ESC" "$L" >/dev/tty
    m_draw "$cur"
  done
  # replace the checklist with a one-line summary (printed below)
  printf '%s[%dA%s[J%s[?25h' "$ESC" "$L" "$ESC" "$ESC" >/dev/tty; stty echo </dev/tty 2>/dev/null || true
}
m_value() { # m_value ID -> 1 / 0
  local i; for i in "${!M_ID[@]}"; do [ "${M_ID[$i]}" = "$1" ] && { echo "${M_ON[$i]}"; return; }; done; echo 0
}

if [ "$HAS_TTY" = 1 ] && [ "${TERM:-dumb}" != dumb ] && { [ "$OPEN" = 1 ] || [ "${DOTFILES_ASK:-0}" = 1 ]; }; then
  # preselected: the saved / preset answers, else Claude Code with all plugins, terminal and font
  # on, Docker off
  sel="${CLAUDE_PLUGINS-$ALL_PLUGINS}"
  m_add claude "Claude Code" "AI coding agent, sees the file you have open in nvim" main "${INSTALL_CLAUDE:-1}"
  for e in "${CLAUDE_WORKFLOW_PLUGINS[@]}"; do
    nm="${e%%|*}"; on=0; case " $sel " in *" $nm "*) on=1 ;; esac
    m_add "plugin:$nm" "$nm" "${e##*|}" sub "$on"
  done
  if [ "$DOCKER_BLOCKED" = 1 ]; then m_add docker "Docker" "needs sudo, which you do not have here" off 0
  elif [ "$DOCKER_TODO" = install ] && [ "$PM" = brew ]; then m_add docker "Docker" "Docker Desktop" main "${INSTALL_DOCKER:-0}"
  elif [ "$DOCKER_TODO" = install ]; then m_add docker "Docker" "Engine + Compose, and you in the docker group (sudo)" main "${INSTALL_DOCKER:-0}"
  elif [ "$DOCKER_TODO" = group ]; then m_add docker "docker group" "run docker without sudo (Docker is installed)" main "${INSTALL_DOCKER:-0}"
  fi
  [ -n "$TERM_OFFER" ] && m_add terminal "Terminal setup" "$TERM_OFFER: Catppuccin, Nerd Font, Option as Alt" main "${SETUP_TERMINAL:-1}"
  [ "$FONT_OFFER" = 1 ] && m_add font "JetBrainsMono Nerd Font" "the icons in nvim and tmux" main "${INSTALL_FONT:-1}"
  m_add ssh "SSH tools" "ssh runs tssh: tsz / trz file transfer, host menu, tsshd" main "${SETUP_SSH:-1}"
  m_run
  INSTALL_CLAUDE="$(m_value claude)"
  CLAUDE_PLUGINS=""
  for e in "${CLAUDE_WORKFLOW_PLUGINS[@]}"; do
    nm="${e%%|*}"; [ "$(m_value "plugin:$nm")" = 1 ] && CLAUDE_PLUGINS="$CLAUDE_PLUGINS $nm"
  done
  CLAUDE_PLUGINS="${CLAUDE_PLUGINS# }"
  if [ -n "$DOCKER_TODO" ] && [ "$DOCKER_BLOCKED" = 0 ]; then INSTALL_DOCKER="$(m_value docker)"; fi
  [ -n "$TERM_OFFER" ] && SETUP_TERMINAL="$(m_value terminal)"
  [ "$FONT_OFFER" = 1 ] && INSTALL_FONT="$(m_value font)"
  SETUP_SSH="$(m_value ssh)"
  SAVED_ANSWERS=0
  mkdir -p "$STATE_DIR"
  printf 'INSTALL_CLAUDE=%s\nCLAUDE_PLUGINS="%s"\nINSTALL_DOCKER=%s\nSETUP_TERMINAL=%s\nINSTALL_FONT=%s\nSETUP_SSH=%s\n' \
    "$INSTALL_CLAUDE" "$CLAUDE_PLUGINS" "${INSTALL_DOCKER:-0}" "${SETUP_TERMINAL:-1}" "${INSTALL_FONT:-1}" \
    "${SETUP_SSH:-1}" > "$ANSWERS"
fi
# Defaults for anything still unset (no terminal: CI, cron)
INSTALL_CLAUDE="${INSTALL_CLAUDE:-0}"; INSTALL_DOCKER="${INSTALL_DOCKER:-0}"
SETUP_TERMINAL="${SETUP_TERMINAL:-1}"; INSTALL_FONT="${INSTALL_FONT:-1}"; SETUP_SSH="${SETUP_SSH:-1}"
if [ "$INSTALL_CLAUDE" = 1 ]; then CLAUDE_PLUGINS="${CLAUDE_PLUGINS-$ALL_PLUGINS}"; else CLAUDE_PLUGINS=""; fi
CLAUDE_PLUGINS="$(echo ${CLAUDE_PLUGINS:-})" # normalize spaces
case "$CLAUDE_PLUGINS" in none|NONE) CLAUDE_PLUGINS="" ;; esac
if [ "$INSTALL_DOCKER" = 1 ] && [ "$DOCKER_BLOCKED" = 1 ]; then
  warn "Docker needs sudo, which you do not have here: ask an admin (or use rootless Docker / Podman)"
fi
[ "$INSTALL_DOCKER" = 1 ] && [ "$DOCKER_BLOCKED" = 0 ] || DOCKER_TODO=""
[ "$SETUP_TERMINAL" = 1 ] || { USE_ITERM=0; USE_GHOSTTY=0; }
want_font=0; [ "$FONT_OFFER" = 1 ] && [ "$INSTALL_FONT" = 1 ] && want_font=1

# One line with the choices
n=0; for p in $CLAUDE_PLUGINS; do n=$((n + 1)); done
CH=""
if [ "$INSTALL_CLAUDE" = 1 ]; then CH="Claude Code ($n plugins)"; else CH="no Claude Code"; fi
if [ -n "$DOCKER_TODO" ]; then CH="$CH $S_DOT Docker"; fi
if [ "$USE_ITERM" = 1 ] || [ "$USE_GHOSTTY" = 1 ]; then CH="$CH $S_DOT terminal setup"; fi
[ "$want_font" = 1 ] && CH="$CH $S_DOT Nerd Font"
[ "$SETUP_SSH" = 1 ] && CH="$CH $S_DOT SSH tools"
if [ "$SAVED_ANSWERS" = 1 ]; then CH="$CH  ${D}(saved; DOTFILES_ASK=1 to change)${N}"; fi
log "Choices: $CH"

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
[ "$UI" = 1 ] || log "Checking what is installed and the latest versions"

# OS packages as package[:command]. A package counts as installed when the package manager has
# it or, when a command is given, that command is on PATH (e.g. a git built from source).
# Required: git, curl, unzip, tar, gzip (Mason downloads), find (copying the config; minimal
# images such as openSUSE's lack it), a C compiler (treesitter parsers), tmux, ripgrep
# perl: Oh my tmux! needs it to apply its theme (git usually pulls it in, minimal Alpine does not)
# Optional: installed when available, skipped with a warning otherwise
# Python is not here: each user gets their own from uv (below).
case "$PM" in
  brew)    OS_REQ=(git tmux ripgrep:rg fd neovim:nvim node)
           OS_OPT=(tree-sitter-cli:tree-sitter lazygit)
           [ "$SETUP_SSH" = 1 ] && OS_OPT+=(trzsz-go:trzsz trzsz-ssh:tssh tsshd) ;;
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
# Homebrew: refresh its index in the background now (it takes half a minute), while the plan is
# read; the OS packages step waits for it. It changes no installed formula.
BREW_UPD_PID=""
if [ "$PM" = brew ] && has brew && [ "$NEED_OS" = 1 ] && [ "$NEED_BREW" = 0 ]; then
  ( brew update --quiet >/dev/null 2>&1 ) &
  BREW_UPD_PID=$!
fi
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
# Everything here is downloaded over HTTPS. A git setting that rewrites https://github.com/ to SSH
# (url.<base>.insteadOf) would send lazy.nvim's dozens of parallel clones over SSH, and GitHub
# resets most of them ("kex_exchange_identification: Connection reset"). So git, and what runs it
# (nvim, claude), reads a copy of your global git config without those rewrites. Your own git
# config is not changed; commands that write to it use gitg.
gitg() { env -u GIT_CONFIG_GLOBAL git "$@"; }
if has git && git config --global --includes --get-regexp '^url\..*\.insteadof$' >/dev/null 2>&1; then
  : > "$TMP/gitconfig"
  git config --global --includes --list 2>/dev/null | grep -iv '^url\.' | while IFS= read -r kv; do
    git config -f "$TMP/gitconfig" --add "${kv%%=*}" "${kv#*=}" 2>/dev/null || true
  done
  export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
fi
trap 'spin_stop; printf "%s[?25h" "$ESC" >&3; rm -rf "$TMP"' EXIT
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
if [ "$PM" != brew ] && [ "$SETUP_SSH" = 1 ]; then
  lookup tz_trzsz "trzsz" gh_latest trzsz/trzsz-go
  lookup tz_tssh "tssh" gh_latest trzsz/trzsz-ssh
  [ "$IS_TERMUX" = 1 ] || lookup tz_tsshd "tsshd" gh_latest trzsz/tsshd
fi
[ -d "$OH_MY_TMUX/.git" ] && lookup omt "Oh my tmux!" git_update "$OH_MY_TMUX"
if [ "$INSTALL_CLAUDE" = 1 ]; then
  lookup claude "Claude Code" lk_claude
  has claude && lookup claude_plugins "Claude plugins" claude plugin list
fi
# Wait for all of them, printing each one as it finishes (at most ~2 minutes: every lookup is bounded)
lookup_wait() {
  local i n=${#L_PIDS[@]} start=$SECONDS shown="" pending
  [ "$n" -gt 0 ] || return 0
  [ "$UI" = 1 ] || echo "   looking up: ${L_LABELS[*]}"
  while :; do
    pending=""
    for i in "${!L_PIDS[@]}"; do
      case " $shown " in *" $i "*) continue ;; esac
      if kill -0 "${L_PIDS[$i]}" 2>/dev/null; then pending="$pending, ${L_LABELS[$i]}"; continue; fi
      shown="$shown $i"
      [ "$UI" = 1 ] || printf '   %-20s done (%ss)\n' "${L_LABELS[$i]}" "$((SECONDS - start))"
    done
    # On a terminal: one line that updates in place
    [ -z "$pending" ] && break
    if [ "$UI" = 1 ]; then
      w="$(printf '%s' "${pending#, }" | cut -c1-$((COLS - 24)))"
      printf '\r%s[K  %s%s%s checking %s%ss  %s%s' "$ESC" "$C" "${SPIN_FRAMES[$((SECONDS % ${#SPIN_FRAMES[@]}))]}" "$N" "$D" \
        "$((SECONDS - start))" "$w" "$N" >&3
    fi
    sleep 1
  done
  if [ "$UI" = 1 ]; then printf '\r%s[K  %s%s%s checked %d versions %s(%ss)%s\n' "$ESC" "$G" "$S_OK" "$N" "$n" "$D" "$((SECONDS - start))" "$N" >&3; fi
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
# trzsz family (https://trzsz.github.io): static binaries in ~/.local/bin on Linux, Alpine and
# Termux (Android builds); Homebrew on macOS (OS_OPT).
#   trzsz  trz / tsz: upload / download files over the ssh session itself, also inside tmux
#   tssh   an ssh client with trzsz built in, reads ~/.ssh/config; `ssh` runs it on your computer
#   tsshd  the server side of `tssh --udp`: sessions survive sleep and network changes (like mosh)
# name|GitHub repo|archive name|binaries
TZ_TOOLS=("trzsz|trzsz/trzsz-go|trzsz|trz tsz trzsz" "tssh|trzsz/trzsz-ssh|tssh|tssh" "tsshd|trzsz/tsshd|tsshd|tsshd")
TZ_CUR=(); TZ_LATEST=(); TZ_NEED=()
for i in "${!TZ_TOOLS[@]}"; do
  IFS='|' read -r nm _ _ bins <<< "${TZ_TOOLS[$i]}"
  TZ_CUR[$i]=""; TZ_LATEST[$i]=""; TZ_NEED[$i]=0
  [ "$PM" != brew ] && [ "$SETUP_SSH" = 1 ] || continue
  [ "$nm" = tsshd ] && [ "$IS_TERMUX" = 1 ] && continue # no Android build
  b="${bins##* }"
  if [ -x "$LOCAL_BIN/$b" ]; then
    v="$("$LOCAL_BIN/$b" --version 2>&1 || true)"
    TZ_CUR[$i]="$(printf '%s\n' "$v" | awk 'match($0, /[0-9]+\.[0-9]+\.[0-9]+/) {print "v" substr($0, RSTART, RLENGTH); exit}')"
  fi
  TZ_LATEST[$i]="$(lookup_result "tz_$nm")"
  outdated "${TZ_CUR[$i]}" "${TZ_LATEST[$i]}" && TZ_NEED[$i]=1
done
# tssh starts tsshd on the server over a plain ssh command, where ~/.local/bin is usually not on
# PATH: a Host * block at the end of ~/.ssh/config points it there (#!! lines are comments to ssh)
SSH_CFG="$HOME/.ssh/config"
NEED_SSHCFG=0
if [ "$SETUP_SSH" = 1 ] && [ "$IS_TERMUX" = 0 ] && ! grep -qs 'TsshdPath' "$SSH_CFG"; then NEED_SSHCFG=1; fi
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
# ~/.npm with files owned by root (left by an earlier `sudo npm ...`): npm, and so Mason's
# npm-based LSP servers, fail with EACCES until it belongs to you again
NPM_FIX=0
if [ "$(id -u)" -ne 0 ] && [ -d "$HOME/.npm" ] && [ -n "$(find "$HOME/.npm" ! -user "$(id -u)" -print 2>/dev/null | head -n 1 || true)" ]; then
  NPM_FIX=1; NEED_SYS=1
  sys_plan "~/.npm" "has files owned by root (from an earlier sudo npm): sudo chown them back to you"
fi
[ "$OLD_TS_LINK" = 1 ] && sys_plan "old link" "rm /usr/local/bin/tree-sitter (points into one user's ~/.cargo)"
[ "$NEED_NVIM" = 1 ]     && user_plan "Neovim" "$(change "$NVIM_CUR" "$NVIM_LATEST" "~/.local/opt/nvim")"
[ "$NEED_NODE" = 1 ]     && user_plan "Node.js (LTS)" "$(change "$NODE_CUR" "$NODE_LATEST" "~/.local/opt/node")"
[ "$NEED_TS" = 1 ]       && user_plan "tree-sitter CLI" "$(change "$TS_CUR" "$TS_LATEST" "~/.local/opt/tree-sitter-cli")"
[ "$NEED_UV" = 1 ]       && user_plan "uv" "$(change "$UV_CUR" "$UV_LATEST" "~/.local/bin")"
[ "$NEED_LG" = 1 ]       && user_plan "lazygit" "$(change "$LG_CUR" "$LG_LATEST" "~/.local/bin")"
for i in "${!TZ_TOOLS[@]}"; do
  [ "${TZ_NEED[$i]}" = 1 ] || continue
  case "${TZ_TOOLS[$i]%%|*}" in
    trzsz) w="tsz / trz: download / upload over ssh" ;;
    tssh)  w="ssh with file transfer, host menu" ;;
    tsshd) w="server side of tssh --udp: sessions survive sleep" ;;
  esac
  user_plan "${TZ_TOOLS[$i]%%|*}" "$(change "${TZ_CUR[$i]}" "${TZ_LATEST[$i]}" "~/.local/bin ($w)")"
done
[ "$NEED_SSHCFG" = 1 ] && user_plan "~/.ssh/config" "a Host * block at the end: TsshdPath ~/.local/bin/tsshd (for tssh --udp)"
[ "$NEED_PY" = 1 ]       && user_plan "Python" "$(change "$PY_CUR" "$PY_LATEST" "with uv, python3 in ~/.local/bin")"
[ "$NEED_DOTFILES" = 1 ] && user_plan "dotfiles" "$(change "$DF_CUR" "$DF_LATEST" "copied into ~/.config/nvim, ~/.tmux.conf.local, ...")"
[ "$RM_OLD" = 1 ] && user_plan "old ~/dotfiles" "removed (no longer used: the config is copied into place)"
[ "$NEED_OMT" = 1 ]      && user_plan "Oh my tmux!" "new, latest commit"
if [ -n "$OMT_UPD" ]; then set -- $OMT_UPD; user_plan "Oh my tmux!" "$1 -> $2 ($3 new commits)"; fi
[ "$NEED_LAZY" = 1 ]     && user_plan "nvim plugins" "new, LazyVim, LSP servers, formatters, parsers (latest)"
[ "$NEED_CLAUDE" = 1 ]   && user_plan "Claude Code" "$(change "$CLAUDE_CUR" "$CLAUDE_LATEST" "~/.local/bin")"
if [ -n "$MISS_PLUGINS" ]; then
  n=0; for p in $MISS_PLUGINS; do n=$((n + 1)); done
  user_plan "Claude plugins" "new $n, ${MISS_PLUGINS// /, }"
fi
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
  v="$(gitg config --global core.hooksPath 2>/dev/null || true)"
  if [ -z "$v" ] || [ "$v" = "$OLD_DOTFILES/git/hooks" ]; then
    NEED_GIT_HOOK=1
    user_plan "git commit-msg hook" "remove Claude co-author lines from every commit (git config --global core.hooksPath)"
  elif [ "$v" != "$GIT_HOOKS" ]; then
    warn "git core.hooksPath is already set to $v; not adding the hook that removes Claude co-author lines"
  fi
fi

# ---- Terminal: Nerd Font, Ghostty, iTerm2 (chosen above) ----
NEED_GHOSTTY=0
if [ "$USE_GHOSTTY" = 1 ] && [ ! -d /Applications/Ghostty.app ]; then
  NEED_GHOSTTY=1
  user_plan "Ghostty" "new, brew install --cask (terminal that shows images in nvim)"
fi

FONT_DIR="$DATA_HOME/fonts/JetBrainsMonoNerdFont" # Linux
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

# On a terminal: "+ name  version  where" (new) or "↑ name  a → b" (update), grouped
plan_rows() {
  local r name d sym ver rest wn=0 wv=0 i room
  local -a SY=() NA=() VE=() RE=()
  for r in "$@"; do
    name="${r%%$'\t'*}"; d="${r#*$'\t'}"; sym="$C$S_DOT$N"; ver=""; rest="$d"
    case "$d" in
      "new, "*) sym="$G$S_NEW$N"; rest="${d#new, }" ;;
      "new "*)  sym="$G$S_NEW$N"; d="${d#new }"; ver="${d%%, *}"; rest=""; [ "$ver" != "$d" ] && rest="${d#*, }" ;;
      *" -> "*) sym="$Y$S_UP$N"; ver="${d%%, *}"; rest=""; [ "$ver" != "$d" ] && rest="${d#*, }"
                ver="${ver/ -> / $S_TO }" ;;
    esac
    SY+=("$sym"); NA+=("$name"); VE+=("$ver"); RE+=("$rest")
    [ ${#name} -gt "$wn" ] && wn=${#name}
    [ ${#ver} -gt "$wv" ] && wv=${#ver}
  done
  for i in "${!NA[@]}"; do
    room=$((COLS - wn - wv - 10)); [ "$room" -gt 0 ] || room=0
    rest="${RE[$i]}"; [ ${#rest} -gt "$room" ] && rest="${rest:0:$((room > 1 ? room - 1 : 0))}…"
    printf '    %s %-*s  %s%-*s%s  %s%s%s\n' "${SY[$i]}" "$wn" "${NA[$i]}" "$B" "$wv" "${VE[$i]}" "$N" "$D" "$rest" "$N" >&3
  done
}
if [ ${#SYS_PLAN[@]} -eq 0 ] && [ ${#USER_PLAN[@]} -eq 0 ]; then
  if [ "$UI" = 1 ]; then printf '\n  %s%s%s Everything is installed and up to date %s(the config files are still synced)%s\n\n' "$G" "$S_OK" "$N" "$D" "$N" >&3
  else log "Everything is installed and up to date"; fi
elif [ "$UI" = 1 ]; then
  printf '\n' >&3
  if [ ${#SYS_PLAN[@]} -gt 0 ]; then
    case "$SUDO_OK" in
      0) h="${R}no sudo here: not changed, ask an admin${N}" ;;
      1) if [ "$PM" = brew ]; then h="Homebrew"; elif [ "$(id -u)" -eq 0 ]; then h="as root"; else h="sudo"; fi ;;
      2) h="sudo, asks for your password" ;;
    esac
    printf '  %sSystem%s %s%s for every user, %s%s\n' "$B" "$N" "$D" "$S_DOT" "$h" "$N" >&3
    plan_rows "${SYS_PLAN[@]}"
  fi
  if [ ${#USER_PLAN[@]} -gt 0 ]; then
    printf '  %sYou%s %s%s only %s, in ~, no sudo%s\n' "$B" "$N" "$D" "$S_DOT" "$(id -un)" "$N" >&3
    plan_rows "${USER_PLAN[@]}"
  fi
  printf '\n  %sInstalled OS packages are kept as they are; your own tools follow the latest release.%s\n' "$D" "$N" >&3
else
  # plain output (CI, a pipe): one block, the same format as always
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
fi
# One confirmation (a key press) on a terminal; ASSUME_YES=1 skips it
if [ $((${#SYS_PLAN[@]} + ${#USER_PLAN[@]})) -gt 0 ] && [ "$HAS_TTY" = 1 ] && [ "${ASSUME_YES:-0}" != 1 ]; then
  printf '\n  %sInstall?%s %s[Y/n]%s ' "$TB" "$TN" "$TD" "$TN" >/dev/tty
  k=""; IFS= read -rsn1 k </dev/tty || k=n
  case "$k" in
    [Nn]|[Qq]|"$ESC") printf 'no\n\n  Nothing changed.\n' >/dev/tty; exit 0 ;;
    *) printf 'yes\n\n' >/dev/tty ;;
  esac
fi
RUN_T0="$SECONDS"

# Everything that gets installed is recorded here and listed at the end
DONE=(); SYS_DONE=(); FAILED=()
did()     { DONE+=("$*"); }
sys_did() { SYS_DONE+=("$*"); }
failed() { # on a terminal it is shown under its step, and again in the summary
  FAILED+=("$*"); STEP_BAD=1
  if [ "$UI" = 1 ] && [ -n "$STEP_LABEL" ]; then STEP_MSGS+=("${Y}not installed: $*"); printf '!! not installed: %s\n' "$*" >&2
  else warn "not installed: $*"; fi
}

# ---------- OS packages ----------
if [ "$NEED_SYS" = 1 ] && [ "$SUDO_OK" = 2 ]; then
  if [ "$UI" = 1 ]; then printf '  %ssudo is used only for the system changes listed above%s\n' "$D" "$N" >&3; fi
  if sudo -v </dev/tty >&3 2>&4; then
    SUDO_OK=1
    # keep the sudo timestamp fresh, so a long install never stops to ask again
    ( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null || true; sleep 50; done ) &
  else SUDO_OK=0; fi
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
  if [ "$NEED_BREW" = 1 ]; then
    step "Installing Homebrew"
    fetch https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh "$TMP/brew-install.sh"
    on_screen env NONINTERACTIVE=1 bash "$TMP/brew-install.sh" # asks for the sudo password
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)"; done
    sys_did "Homebrew"
  fi
  # Refresh the package index (does not upgrade anything)
  if [ "$INDEX_FRESH" = 0 ]; then
    step "Updating the package index"
    case "$PM" in
      apt-get) sudo apt-get update || true ;;
      pacman)  sudo pacman -Sy --noconfirm ;;
      zypper)  sudo zypper --non-interactive refresh || true ;;
      apk)     sudo apk update ;;
      brew)    # started in the background before the plan (quietly: it lists every new formula)
               if [ -n "$BREW_UPD_PID" ]; then wait "$BREW_UPD_PID" 2>/dev/null || warn "brew update failed, installing with the current package list"
               else brew update --quiet >/dev/null 2>&1 || warn "brew update failed, installing with the current package list"; fi ;;
    esac
  fi
  # macOS: Homebrew stops with "You have not agreed to the Xcode license" when Xcode is
  # installed but its license was never accepted; say so before anything is installed
  if [ "$PM" = brew ] && has xcodebuild && xcode-select -p 2>/dev/null | grep -q '\.app/'; then
    xcodebuild -license check >/dev/null 2>&1 \
      || die "accept the Xcode license first: sudo xcodebuild -license accept   (then run this again)"
  fi
  step "Installing OS packages"
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
  step "Installing Docker"
  docker_ok=0
  case "$PM" in
    brew)
      # the cask was renamed from docker to docker-desktop
      # may ask for your password (it installs a helper as root)
      if on_screen env HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask docker-desktop \
         || on_screen env HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask docker; then docker_ok=1; fi ;;
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

if [ "$NPM_FIX" = 1 ]; then
  step "Giving ~/.npm back to you"
  if [ "$SUDO_OK" = 1 ] && on_screen sudo chown -R "$(id -u):$(id -g)" "$HOME/.npm"; then
    sys_did "~/.npm belongs to you again (npm and Mason can write to it)"
  else
    failed "npm cache ~/.npm is owned by root, so npm-based LSP servers fail (run: sudo chown -R $(id -un) ~/.npm)"
  fi
fi
if [ "$OLD_TS_LINK" = 1 ] && [ "$SUDO_OK" = 1 ]; then
  sudo rm -f /usr/local/bin/tree-sitter && sys_did "removed old link /usr/local/bin/tree-sitter"
fi

# Debian/Ubuntu ship fd as fdfind
if ! has fd && has fdfind; then ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"; fi

# Plugin commits before this run, to list what changed at the end. The lockfile used to live in
# the repo (nvim/lazy-lock.json), so read that one if there is no per-user lockfile yet.
LAZY_LOCK="$DATA_HOME/nvim/lazy-lock.json"
lock_commits() { [ -f "$1" ] && sed -n 's/^ *"\([^"]*\)": *{.*"commit": *"\([0-9a-f]\{7\}\).*/\1 \2/p' "$1" | LC_ALL=C sort; }
if [ -f "$LAZY_LOCK" ]; then lock_commits "$LAZY_LOCK" > "$TMP/lock.before" || true
else lock_commits "$OLD_DOTFILES/nvim/lazy-lock.json" > "$TMP/lock.before" 2>/dev/null || true; fi

# ---------- dotfiles: copy this repo's config into place ----------
step "Installing the config files"
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

# ---------- What runs in parallel (each a function, started as a job below) ----------
job_nvim() {
  # ---------- Neovim ----------
  # glibc Linux: official release in ~/.local/opt/nvim (distro versions are often too old; the
  # config needs >= 0.11). macOS and Alpine use the package manager's Neovim.
  if [ "$NEED_NVIM" = 1 ]; then
    step "Installing Neovim ${NVIM_LATEST:-latest} ($NVIM_ARCH) in ~/.local/opt/nvim"
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
}
job_node() {
  # ---------- Node.js (needed by pyright, ts_ls, bashls, prettier, ...) ----------
  # curl / wget may have been installed just now: look the version up again if needed
  if [ "$NEED_NODE" = 1 ] && [ -z "$NODE_LATEST" ]; then
    NODE_LATEST="$(lk_node || true)"
  fi
  if [ "$NEED_NODE" = 1 ] && [ -z "$NODE_LATEST" ]; then
    step "Installing Node.js"
    failed "Node.js (could not look up the latest LTS on nodejs.org)"
  elif [ "$NEED_NODE" = 1 ]; then
    step "Installing Node.js $NODE_LATEST ($NODE_ARCH) in ~/.local/opt/node"
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
}
job_ssh() {
  # ---------- trzsz, tssh, tsshd (per user, Linux / Termux) ----------
  case "$ARCH" in amd64) a=x86_64 ;; arm64) a=aarch64 ;; esac
  o=linux; [ "$IS_TERMUX" = 1 ] && o=android
  for i in "${!TZ_TOOLS[@]}"; do
    [ "${TZ_NEED[$i]}" = 1 ] || continue
    IFS='|' read -r nm repo proj bins <<< "${TZ_TOOLS[$i]}"
    ver="${TZ_LATEST[$i]}"; [ -n "$ver" ] || ver="$(gh_latest "$repo")" # the lookup may have failed
    if [ -z "$ver" ]; then
      step "Installing $nm"
      failed "$nm (could not look up the latest release)"
      continue
    fi
    step "Installing $nm $ver in ~/.local/bin"
    d="${proj}_${ver#v}_${o}_$a"
    b="${bins##* }"
    if fetch_once "https://github.com/$repo/releases/download/$ver/$d.tar.gz" "$TMP/$proj.tgz" \
       && tar -C "$TMP" -xzf "$TMP/$proj.tgz" && [ -x "$TMP/$d/$b" ]; then
      for x in $bins; do [ -f "$TMP/$d/$x" ] && mv -f "$TMP/$d/$x" "$LOCAL_BIN/$x"; done
      if [ -n "${TZ_CUR[$i]}" ]; then did "$nm $ver (was ${TZ_CUR[$i]})"; else did "$nm $ver"; fi
    else
      failed "$nm"
    fi
  done
  # Downloads (tsz) go straight to ~/Downloads, no dialog each time. Your own files are kept.
  if [ "$SETUP_SSH" = 1 ] && { [ "$OS" = Darwin ] || [ -d "$HOME/Downloads" ]; }; then
    if [ ! -e "$HOME/.trzsz.conf" ]; then # used by `trzsz ssh`
      mkdir -p "$HOME/Downloads"
      printf 'DefaultDownloadPath = %s/Downloads/\n' "$HOME" > "$HOME/.trzsz.conf"
    fi
    # ~/.tssh.conf: read whether or not XDG_CONFIG_HOME is set (often it is not, e.g. on macOS)
    if [ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/tssh/tssh.conf" ] && [ ! -e "$HOME/.tssh.conf" ]; then
      mkdir -p "$HOME/Downloads"
      printf '%s\n' "# tssh settings (https://github.com/trzsz/trzsz-ssh#custom-configuration)" \
        "# tsz saves here without asking" "DefaultDownloadPath = ~/Downloads" \
        "# read ~/.ssh/config through ssh -G, so Match blocks work too" "UseOpenSSHConfig = yes" \
        > "$HOME/.tssh.conf"
      did "tssh settings (~/.tssh.conf): tsz saves into ~/Downloads"
    fi
  fi
  if [ "$NEED_SSHCFG" = 1 ]; then
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    [ -f "$SSH_CFG" ] || { : > "$SSH_CFG"; chmod 600 "$SSH_CFG"; }
    printf '%s\n' "" "# dotfiles: where tssh finds tsshd on a server (it installs it in ~/.local/bin)." \
      "# Lines starting with #!! are read by tssh only; ssh ignores them." \
      "Host *" "  #!! TsshdPath ~/.local/bin/tsshd" >> "$SSH_CFG"
    did "~/.ssh/config: TsshdPath ~/.local/bin/tsshd (Host * at the end)"
  fi

}
job_lazygit() {
  # ---------- lazygit (per user, Linux) ----------
  # The lookup may have failed (network blip, or curl was installed only just now): try again
  if [ "$NEED_LG" = 1 ] && [ -z "$LG_LATEST" ]; then LG_LATEST="$(gh_latest jesseduffield/lazygit)"; fi
  if [ "$NEED_LG" = 1 ]; then
    if [ -z "$LG_LATEST" ]; then
      step "Installing lazygit"
      failed "lazygit (could not look up the latest release)"
    else
      step "Installing lazygit $LG_LATEST in ~/.local/bin"
      case "$ARCH" in amd64) a=x86_64 ;; arm64) a=arm64 ;; esac
      if fetch_once "https://github.com/jesseduffield/lazygit/releases/download/$LG_LATEST/lazygit_${LG_LATEST#v}_Linux_$a.tar.gz" "$TMP/lazygit.tgz" \
         && tar -C "$TMP" -xzf "$TMP/lazygit.tgz" lazygit && mv -f "$TMP/lazygit" "$LOCAL_BIN/lazygit"; then
        if [ -n "$LG_CUR" ]; then did "lazygit $LG_LATEST (was $LG_CUR)"; else did "lazygit $LG_LATEST"; fi
      else
        failed "lazygit"
      fi
    fi
  fi

}
job_uv() {
  # ---------- uv and Python (per user) ----------
  # uv installs into ~/.local/bin; `uv python install --default` adds python3 there too, so
  # Mason's Python tools (and the user) get a recent Python with venv and pip, no sudo needed.
  if [ "$NEED_UV" = 1 ] && [ -n "$UV_CUR" ]; then
    step "Updating uv to ${UV_LATEST:-latest}"
    if "$LOCAL_BIN/uv" self update -q; then did "uv $("$LOCAL_BIN/uv" --version | awk '{print $2}') (was $UV_CUR)"
    else failed "uv update"; fi
  elif [ "$NEED_UV" = 1 ]; then
    step "Installing uv ${UV_LATEST:-latest} in ~/.local/bin"
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
    step "Installing Python ${PY_LATEST:-latest} with uv"
    # --default (adds python / python3 next to python3.X) is marked experimental; hide that warning
    if uv python install --default ${PY_ARG[@]+"${PY_ARG[@]}"} >"$TMP/uv-python.log" 2>&1 && [ -x "$LOCAL_BIN/python3" ]; then
      hash -r; v="$("$LOCAL_BIN/python3" --version | awk '{print $2}')"
      if [ -n "$PY_CUR" ]; then did "Python $v (was $PY_CUR)"; else did "Python $v"; fi
    else
      cat "$TMP/uv-python.log" >&2; failed "Python ${PY_LATEST:-latest} (uv)"
    fi
  fi

}
job_terminal() {
  # ---------- Terminal: Nerd Font, Ghostty, iTerm2 ----------
  if [ "$NEED_FONT" = 1 ] && [ "$PM" = brew ]; then
    step "Installing JetBrainsMono Nerd Font"
    if HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
      did "JetBrainsMono Nerd Font"
    else failed "JetBrainsMono Nerd Font (brew install --cask font-jetbrains-mono-nerd-font)"; fi
  elif [ "$NEED_FONT" = 1 ]; then
    step "Installing JetBrainsMono Nerd Font ${FONT_VER:-latest} in ~/.local/share/fonts"
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
    step "Installing Ghostty"
    if HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask ghostty >/dev/null 2>&1; then did "Ghostty (config: ~/.config/ghostty/config)"
    else failed "Ghostty (brew install --cask ghostty)"; fi
  fi
  if [ "$NEED_ITERM" = 1 ]; then
    step "Setting up the iTerm2 profile"
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

}
job_claude() {
    # Native installer: updates itself in the background, so it is only run when claude is missing
    if [ "$NEED_CLAUDE" = 1 ] && [ -n "$CLAUDE_CUR" ]; then
      step "Updating Claude Code to ${CLAUDE_LATEST:-latest}"
      if claude update >/dev/null 2>&1; then did "Claude Code $(claude --version 2>/dev/null | awk '{print $1}') (was $CLAUDE_CUR)"
      else failed "Claude Code update (run: claude update)"; fi
    elif [ "$NEED_CLAUDE" = 1 ]; then
      step "Installing Claude Code ${CLAUDE_LATEST:-latest}"
      fetch https://claude.ai/install.sh "$TMP/claude-install.sh"
      bash "$TMP/claude-install.sh"
      . "$STATE_DIR/env.sh"; hash -r
      has claude && did "Claude Code $(claude --version 2>/dev/null | awk '{print $1}')"
    fi
}
job_mason() {
  step "Installing and updating LSP servers and formatters (Mason)"
  # DOTFILES_HEADLESS_INSTALL stops LazyVim's own background installs; headless.lua installs and
  # waits for every Mason package (see nvim/lua/dotfiles/headless.lua). `cquit 1` runs only if
  # install() itself failed to quit (e.g. a Lua error), so nvim never hangs.
  if with_timeout 1500 env DOTFILES_HEADLESS_INSTALL=1 nvim --headless -c "lua require('dotfiles.headless').install('mason')" \
       -c "cquit 1" </dev/null 2>&1 | tee "$TMP/headless.log" \
       | { grep --line-buffered -E 'mason: |^!!' || true; }; then
    [ "$NEED_LAZY" = 1 ] && did "nvim plugins, LSP servers, formatters and parsers (latest)"
    # "  mason: updating NAME A -> B" / "  mason: installing NAME V" lines from headless.lua
    sed -n 's/^ *mason: updating \(.*\)/Mason \1/p; s/^ *mason: installing \(.*\)/Mason \1 (new)/p' "$TMP/headless.log" \
      | tr -d '\r' > "$TMP/mason.done"
    if [ "$NEED_LAZY" = 0 ]; then while IFS= read -r l; do did "$l"; done < "$TMP/mason.done"; fi
  else
    failed "some LSP servers or formatters (open nvim and check :Mason)"
    # Mason's own log has the full reason for each failure
    MASON_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/nvim/mason.log"
    if [ -f "$MASON_LOG" ]; then
      note "Mason's own log: $MASON_LOG"
      grep -i 'error\|fail' "$MASON_LOG" | tail -n 5 | cut -c1-300 >&2 || true
    fi
  fi
}
job_parsers() {
  # ---------- tree-sitter CLI (nvim-treesitter uses it to compile parsers) ----------
  if [ "$NEED_TS" = 1 ] && has npm; then
    # npm package in ~/.local/opt/tree-sitter-cli; works with any Node.js, no global install
    step "Installing tree-sitter CLI ${TS_LATEST:-latest} in ~/.local/opt/tree-sitter-cli"
    npm install --silent --prefix "$LOCAL_OPT/tree-sitter-cli" "tree-sitter-cli@${TS_LATEST#v}" >/dev/null 2>&1 \
      || npm install --silent --prefix "$LOCAL_OPT/tree-sitter-cli" tree-sitter-cli@latest >/dev/null
    ln -sf "$LOCAL_OPT/tree-sitter-cli/node_modules/.bin/tree-sitter" "$LOCAL_BIN/tree-sitter"
    hash -r
    # The prebuilt binary needs glibc 2.39. On older systems (Debian 12, RHEL 9, Ubuntu 22.04)
    # it fails with "GLIBC_2.39 not found", so build it from source with cargo instead.
    if ! ts_works "$LOCAL_BIN/tree-sitter"; then
      step "tree-sitter binary needs newer glibc, building from source with cargo (takes a few minutes)"
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
  hash -r
  if ! has tree-sitter || ! ts_works tree-sitter; then
    warn "tree-sitter CLI missing or broken, syntax highlighting parsers will not compile"
  fi
  # LazyVim installs tree-sitter-cli through Mason when none is on PATH (e.g. nvim was opened before
  # this step finished). That is the same glibc 2.39 build, so remove it if it cannot run here.
  MASON_DIR="$DATA_HOME/nvim/mason"
  if [ -e "$MASON_DIR/bin/tree-sitter" ] && ! "$MASON_DIR/bin/tree-sitter" --version >/dev/null 2>&1; then
    step "Removing Mason's tree-sitter-cli (cannot run on this system)"
    rm -rf "$MASON_DIR/packages/tree-sitter-cli" "$MASON_DIR/bin/tree-sitter"
  fi
  step "Compiling treesitter parsers"
  # CFLAGS: tree-sitter's default flags include -Wall, which makes gcc 12.2 (Debian 12) spend
  # minutes on large generated parsers such as gitcommit. config/options.lua sets the same default.
  export CFLAGS="${CFLAGS:--O2}"
  if with_timeout 1500 env DOTFILES_HEADLESS_INSTALL=1 nvim --headless -c "lua require('dotfiles.headless').install('parsers')" \
       -c "cquit 1" </dev/null 2>&1 | tee "$TMP/parsers.log" \
       | { grep --line-buffered -E 'treesitter round|^!!' || true; }; then
    :
  else
    failed "some treesitter parsers (open nvim and run :checkhealth nvim-treesitter)"
  fi
}
claude_setup_plugins() { # the official marketplace and the helpers for installing plugins and skills
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
}
job_claude_plugins() {
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
    if gitg config --global core.hooksPath "$GIT_HOOKS"; then did "git commit-msg hook (core.hooksPath $GIT_HOOKS)"
    else failed "git commit-msg hook"; fi
  fi
  if has claude; then
    step "Adding Claude Code plugins"
    claude_setup_plugins
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
}

# ---------- Tools, in parallel ----------
# Each one downloads into its own place; nothing here asks anything (sudo was used above)
[ "$NEED_NVIM" = 1 ] && job nvim "Neovim" job_nvim
[ "$NEED_NODE" = 1 ] && job node "Node.js" job_node
{ [ "$NEED_UV" = 1 ] || [ "$NEED_PY" = 1 ]; } && job uv "uv and Python" job_uv
[ "$NEED_LG" = 1 ] && job lazygit "lazygit" job_lazygit
SSH_TODO=0
for i in "${!TZ_TOOLS[@]}"; do [ "${TZ_NEED[$i]}" = 1 ] && SSH_TODO=1; done
[ "$NEED_SSHCFG" = 1 ] && SSH_TODO=1
if [ "$SETUP_SSH" = 1 ] && [ ! -e "$HOME/.tssh.conf" ] && [ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/tssh/tssh.conf" ]; then SSH_TODO=1; fi
[ "$SSH_TODO" = 1 ] && job ssh "SSH tools" job_ssh
{ [ "$NEED_FONT" = 1 ] || [ "$NEED_GHOSTTY" = 1 ] || [ "$NEED_ITERM" = 1 ] || [ "$NEED_ITERM_THEME" = 1 ]; } && job terminal "Terminal setup" job_terminal
[ "$INSTALL_CLAUDE" = 1 ] && [ "$NEED_CLAUDE" = 1 ] && job claude "Claude Code" job_claude
jobs_wait
hash -r
has nvim || die "Neovim is not installed"
nvim_ok || warn "$(nvim --version 2>/dev/null | sed -n 1p) < 0.11, the config needs 0.11+"

node_ok || warn "Node.js >= 18 not found, JS-based LSPs (pyright, ts_ls...) will fail"

# shellcheck source=shell/env.sh
. "$STATE_DIR/env.sh"; hash -r

# ---------- nvim plugins, LSP servers, treesitter parsers (all headless) ----------
# Everything is installed when missing and updated to the latest; each step is time-bounded.
# Lazy sync: install missing plugins and update all of them to the latest commit
step "Installing and updating nvim plugins (LazyVim, up to a minute)"
# Lazy's per-plugin progress goes to a log (shown only on failure); the summary lists the
# plugins whose commit changed (lockfile before vs after)
if with_timeout 900 env DOTFILES_HEADLESS_INSTALL=1 nvim --headless "+Lazy! sync" +qa </dev/null > "$TMP/lazy.log" 2>&1; then
  tr -d '\r' < "$TMP/lazy.log" >> "$INSTALL_LOG" || true
  # Lazy exits 0 even when downloads failed: ask it which plugins are still not installed
  missing="$(with_timeout 60 env DOTFILES_HEADLESS_INSTALL=1 nvim --headless \
    -c 'lua for _, p in ipairs(require("lazy").plugins()) do if not p._.installed then io.stdout:write(p.name .. " ") end end' \
    -c qa </dev/null 2>/dev/null || true)"
  missing="$(echo $missing)"
  if [ -n "$missing" ]; then
    failed "nvim plugins not downloaded: $missing (run :Lazy sync; the log has git's error)"
  fi
  lock_commits "$LAZY_LOCK" > "$TMP/lock.after" || true
  n="$(wc -l < "$TMP/lock.after" | tr -d ' ')"
  m=0; [ -s "$TMP/lock.before" ] && m="$(LC_ALL=C join "$TMP/lock.before" "$TMP/lock.after" 2>/dev/null | awk '$2 != $3' | wc -l | tr -d ' ' || echo 0)"
  note "$n plugins, $m updated"
  if [ -s "$TMP/lock.before" ]; then
    LC_ALL=C join "$TMP/lock.before" "$TMP/lock.after" | awk '$2 != $3 {print "nvim plugin " $1 " " $2 " -> " $3}' > "$TMP/plugins.done"
    LC_ALL=C join -v 2 "$TMP/lock.before" "$TMP/lock.after" | awk '{print "nvim plugin " $1 " new " $2}' >> "$TMP/plugins.done"
    while IFS= read -r l; do did "$l"; done < "$TMP/plugins.done"
  fi
else
  tr -d '\r' < "$TMP/lazy.log" >> "$INSTALL_LOG" || true
  [ "$UI" = 1 ] || tail -n 20 "$TMP/lazy.log" | tr -d '\r' >&2
  failed "nvim plugins (Lazy sync failed or timed out, run :Lazy sync)"
fi

# LSP servers / parsers (Mason, treesitter) and Claude Code's plugins, in parallel
job mason "LSP servers and formatters" job_mason
job parsers "Treesitter parsers" job_parsers
[ "$INSTALL_CLAUDE" = 1 ] && job claude_plugins "Claude Code plugins" job_claude_plugins
jobs_wait
# again: Mason's bin (the language servers) only exists now on a first install
# shellcheck source=shell/env.sh
. "$STATE_DIR/env.sh"; hash -r
if [ "$INSTALL_CLAUDE" = 1 ]; then
  if has claude; then
    step "Adding Claude Code language-server plugins"
    claude_setup_plugins
    # Language-server plugins: one per nvim language whose server is on PATH (Mason's bin is)
    for pair in pyright-lsp:pyright-langserver clangd-lsp:clangd typescript-lsp:typescript-language-server \
                rust-analyzer-lsp:rust-analyzer lua-lsp:lua-language-server gopls-lsp:gopls; do
      if has "${pair#*:}"; then claude_plugin "${pair%%:*}"; fi
    done
  fi
fi

# ---------- The old ~/dotfiles clone (nothing points into it any more) ----------
if [ "$RM_OLD" = 1 ]; then
  if [ "$(gitg config --global core.hooksPath 2>/dev/null || true)" = "$OLD_DOTFILES/git/hooks" ]; then
    gitg config --global core.hooksPath "$GIT_HOOKS"
  fi
  rm -rf "${HOME:?}/dotfiles" && did "removed the old ~/dotfiles (no longer used)"
fi

# ---------- Next steps (on every run, so nothing is forgotten) ----------
NEXT=("Open a new shell, then run nvim or tmux (:checkhealth and :Mason show the details)")
[ "${DOCKER_RELOGIN:-0}" = 1 ] && NEXT+=("Docker: log out and back in (or run: newgrp docker), then docker runs without sudo")
[ "${DOCKER_NO_SERVICE:-0}" = 1 ] && NEXT+=("Docker: no systemd here, so the daemon was not started (run: sudo dockerd &)")
[ "$NEED_DOCKER" = 1 ] && [ "$PM" = brew ] && NEXT+=("Docker: open Docker Desktop once (Applications) to finish its setup")
if [ "$INSTALL_CLAUDE" = 1 ] && has claude; then
  [ "$NEED_CLAUDE" = 1 ] && [ -z "$CLAUDE_CUR" ] && NEXT+=("Run claude (or tmux prefix + A) and log in")
  # MCP servers (plugin tools, claude.ai connectors) that still need a sign-in. `claude mcp list`
  # connects to each one, so it is bounded; run from ~ so no project's .mcp.json is involved.
  step "Checking which Claude tools need a sign-in"
  v="$(cd "$HOME" && timeout_cmd 60 claude mcp list 2>/dev/null || true)"
  v="$(printf '%s\n' "$v" | grep -i 'auth' | sed 's/: .*//' | tr -d '\r' || true)"
  must="$(printf '%s\n' "$v" | grep -v '^plugin:design:' | grep -v '^$' | tr '\n' ' ' || true)"
  opt="$(printf '%s\n' "$v" | sed -n 's/^plugin:design://p' | tr '\n' ' ' || true)"
  if [ -n "$must" ]; then
    NEXT+=("In claude, run /mcp and sign in to: $must")
    case "$must" in *claude.ai*) NEXT+=("  (claude.ai ... entries are connectors from your claude.ai account: reconnect or remove them there)") ;; esac
  fi
  if [ -n "$opt" ]; then
    NEXT+=("Optional, only if you use them with the design plugin: $opt (or /mcp, pick one, Disable)")
  fi
fi
step_end

# ---------- Summary ----------
if [ "$UI" = 1 ]; then
  el=$((SECONDS - ${RUN_T0:-0})); el="$((el / 60))m$((el % 60))s"
  # nvim plugin and Mason updates are counted here; the full list is in the log
  sum_rows() { # sum_rows ROW...
    local r np=0 nm=0
    for r in "$@"; do
      case "$r" in
        "nvim plugin "*) np=$((np + 1)) ;;
        "Mason "*) nm=$((nm + 1)) ;;
        *) case "$r" in
             *" (was "*) printf '    %s%s%s %s\n' "$Y" "$S_UP" "$N" "${r/ (was / ${D}(was }$N" >&3 ;;
             *" -> "*) printf '    %s%s%s %s\n' "$Y" "$S_UP" "$N" "${r/ -> / $S_TO }" >&3 ;;
             *) printf '    %s%s%s %s\n' "$G" "$S_NEW" "$N" "$r" >&3 ;;
           esac ;;
      esac
    done
    [ "$np" -gt 0 ] && printf '    %s%s%s nvim plugins: %d changed %s(list in the log)%s\n' "$Y" "$S_UP" "$N" "$np" "$D" "$N" >&3
    [ "$nm" -gt 0 ] && printf '    %s%s%s LSP servers and tools (Mason): %d changed %s(list in the log)%s\n' "$Y" "$S_UP" "$N" "$nm" "$D" "$N" >&3
    return 0
  }
  if [ ${#FAILED[@]} -gt 0 ]; then
    printf '\n  %s%s Done with problems%s %s(%s)%s\n' "$B$Y" "$S_WARN" "$N" "$D" "$el" "$N" >&3
  else
    printf '\n  %s%s Done%s %s(%s)%s\n' "$B$G" "$S_OK" "$N" "$D" "$el" "$N" >&3
  fi
  if [ ${#SYS_DONE[@]} -gt 0 ]; then printf '\n  %sSystem%s\n' "$B" "$N" >&3; sum_rows "${SYS_DONE[@]}"; fi
  if [ ${#DONE[@]} -gt 0 ]; then printf '\n  %sYou%s\n' "$B" "$N" >&3; sum_rows "${DONE[@]}"; fi
  if [ ${#SYS_DONE[@]} -eq 0 ] && [ ${#DONE[@]} -eq 0 ]; then printf '  %sNothing new was installed.%s\n' "$D" "$N" >&3; fi
  if [ ${#FAILED[@]} -gt 0 ]; then
    printf '\n  %sNot installed%s\n' "$B$R" "$N" >&3
    for r in "${FAILED[@]}"; do printf '    %s%s%s %s\n' "$R" "$S_BAD" "$N" "$r" >&3; done
  fi
  printf '\n  %sNext%s\n' "$B" "$N" >&3
  i=1; for r in "${NEXT[@]}"; do
    case "$r" in "  "*) printf '       %s%s%s\n' "$D" "${r#  }" "$N" >&3 ;; *) printf '    %d. %s\n' "$i" "$r" >&3; i=$((i + 1)) ;; esac
  done
  printf '\n  %sFull log: %s%s\n\n' "$D" "$INSTALL_LOG" "$N" >&3
fi
# plain output, and the complete list for the log
if [ ${#SYS_DONE[@]} -gt 0 ] || [ ${#DONE[@]} -gt 0 ]; then
  echo "==> Installed:"
  if [ ${#SYS_DONE[@]} -gt 0 ]; then echo "   System, for every user:"; printf '     %s\n' "${SYS_DONE[@]}"; fi
  if [ ${#DONE[@]} -gt 0 ]; then echo "   Only you, in ~:"; printf '     %s\n' "${DONE[@]}"; fi
else
  echo "==> Nothing new was installed"
fi
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "!! Not installed:" >&2
  printf '   %s\n' "${FAILED[@]}" >&2
fi
echo "==> Done. Next steps:"
for r in "${NEXT[@]}"; do case "$r" in "  "*) echo "     ${r#  }" ;; *) echo "   - $r" ;; esac; done
exit 0
}
