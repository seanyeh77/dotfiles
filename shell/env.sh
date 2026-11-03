# shellcheck shell=sh
# Sourced from ~/.bashrc / ~/.zshrc by install.sh. POSIX sh so it works in bash and zsh.
#   ~/.local/bin                    Claude Code's native installer puts `claude` here
#   ~/.local/share/nvim/mason/bin   LSP servers and formatters installed by Mason, so other
#                                   tools (e.g. Claude Code's language-server plugins) reuse them
# ~/.local/bin goes first; Mason's bin goes last, so tools from the OS and install.sh win
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) [ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH" ;;
esac
_d="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/mason/bin"
case ":$PATH:" in
  *":$_d:"*) ;;
  *) [ -d "$_d" ] && PATH="$PATH:$_d" ;;
esac
unset _d
export PATH

# A shell started in a folder that has been deleted (typically a new tmux pane split from a pane
# whose folder was removed) cannot tell where it is: prompts show ".", git and other tools fail.
# Go back into the folder if it was recreated, otherwise start in ~. Only interactive shells.
case "$-" in *i*)
  case "$(command pwd -P 2>/dev/null)" in
    /*) ;;
    *) case "${PWD:-}" in
         /*) cd -- "$PWD" 2>/dev/null || true ;;
       esac
       case "$(command pwd -P 2>/dev/null)" in
         /*) ;;
         *) printf 'dotfiles: this folder no longer exists, starting in ~\n' >&2
            cd ~ 2>/dev/null || cd / ;;
       esac ;;
  esac ;;
esac

# Ghostty shell integration (zsh), loaded by hand in case auto-injection did not happen
# (e.g. ZDOTDIR is changed): it wraps `ssh` so remote hosts see TERM=xterm-256color
# (Ctrl-L, colours). No-op outside Ghostty or when it is already loaded.
# shellcheck disable=SC3044  # zsh only
if [ -n "${ZSH_VERSION:-}" ] && [ -n "${GHOSTTY_RESOURCES_DIR:-}" ] \
   && [ -f "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration" ] \
   && ! typeset -f _ghostty_deferred_init >/dev/null 2>&1; then
  . "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
fi

# ssh on your own computer (not inside an ssh session) runs tssh: an ssh client that reads
# ~/.ssh/config like ssh, with file transfer built in (on the server: `tsz FILE` saves FILE in
# ~/Downloads here, `trz` uploads, also inside tmux), a host menu (`ssh` alone) and, for hosts
# with `#!! UdpMode yes`, sessions that survive sleep and network changes. Ghostty's terminal type
# is replaced by xterm-256color, which every server knows. `command ssh` is the plain one, and so
# is ssh without a terminal (scripts, pipes).
dotfiles_ssh() {
  _t="${TERM:-}"; [ "$_t" = xterm-ghostty ] && _t=xterm-256color
  if [ -t 0 ] && [ -t 1 ] && command -v tssh >/dev/null 2>&1; then TERM="$_t" tssh "$@"
  elif [ -t 0 ] && [ -t 1 ] && command -v trzsz >/dev/null 2>&1; then TERM="$_t" trzsz ssh "$@"
  else TERM="$_t" command ssh "$@"; fi
}
# Not when "SSH tools" is unticked in the installer's checklist (SETUP_SSH=0 in its saved answers)
if [ -z "${SSH_CONNECTION:-}" ] && { command -v tssh >/dev/null 2>&1 || command -v trzsz >/dev/null 2>&1; } \
   && ! grep -qs '^SETUP_SSH=0' "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/answers"; then
  alias ssh=dotfiles_ssh
fi

# sshk HOST: ssh, but first copy your ed25519 key there if the host does not accept it yet (asks
# for the password once), so later logins need no password. Creates ~/.ssh/id_ed25519 if missing
# (an RSA key is not used, even if you have one).
sshk() {
  _k="$HOME/.ssh/id_ed25519"
  [ -f "$_k.pub" ] || ssh-keygen -q -t ed25519 -N "" -f "$_k" || return
  if ! command ssh -o BatchMode=yes -o ConnectTimeout=5 -o IdentitiesOnly=yes -i "$_k" "$@" true >/dev/null 2>&1; then
    ssh-copy-id -i "$_k.pub" "$@" || return
  fi
  dotfiles_ssh "$@"
}

# fzf shell integration (interactive bash / zsh): Ctrl-R searches the command history, Ctrl-T
# inserts files, Alt-C (Option-C on macOS) changes into a folder; `**<Tab>` completes paths, e.g.
# `nvim **<Tab>`. Needs fzf 0.48 or newer (install.sh puts one in ~/.local/bin). Skipped when your
# own setup already loaded it, or with DOTFILES_FZF=0. fd, when present, lists the files (it skips
# .gitignore'd ones and is faster); the colours are Catppuccin Mocha. Your own FZF_* settings win.
case "$-" in *i*)
  if [ "${DOTFILES_FZF:-1}" != 0 ] && command -v fzf >/dev/null 2>&1; then
    _fd=""; if command -v fd >/dev/null 2>&1; then _fd=fd; elif command -v fdfind >/dev/null 2>&1; then _fd=fdfind; fi
    if [ -n "$_fd" ]; then
      : "${FZF_DEFAULT_COMMAND:=$_fd --type f --hidden --follow --exclude .git}"
      : "${FZF_CTRL_T_COMMAND:=$_fd --hidden --follow --exclude .git}"
      : "${FZF_ALT_C_COMMAND:=$_fd --type d --hidden --follow --exclude .git}"
      export FZF_DEFAULT_COMMAND FZF_CTRL_T_COMMAND FZF_ALT_C_COMMAND
    fi
    unset _fd
    : "${FZF_DEFAULT_OPTS:=--height 40% --layout reverse --border \
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8,selected-bg:#45475a,border:#6c7086}"
    export FZF_DEFAULT_OPTS
    # shellcheck disable=SC3044,SC1090  # bash / zsh only
    if [ -n "${ZSH_VERSION:-}" ]; then
      typeset -f fzf-history-widget >/dev/null 2>&1 || { _s="$(fzf --zsh 2>/dev/null)" && eval "$_s"; }
    elif [ -n "${BASH_VERSION:-}" ]; then
      declare -F __fzf_history__ >/dev/null 2>&1 || { _s="$(fzf --bash 2>/dev/null)" && eval "$_s"; }
    fi
    unset _s
  fi ;;
esac
