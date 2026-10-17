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

# Ghostty shell integration (zsh), loaded by hand in case auto-injection did not happen
# (e.g. ZDOTDIR is changed): it wraps `ssh` so remote hosts see TERM=xterm-256color
# (Ctrl-L, colours). No-op outside Ghostty or when it is already loaded.
# shellcheck disable=SC3044  # zsh only
if [ -n "${ZSH_VERSION:-}" ] && [ -n "${GHOSTTY_RESOURCES_DIR:-}" ] \
   && [ -f "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration" ] \
   && ! typeset -f _ghostty_deferred_init >/dev/null 2>&1; then
  . "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
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
  ssh "$@"
}
