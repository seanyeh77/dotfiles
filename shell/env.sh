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
