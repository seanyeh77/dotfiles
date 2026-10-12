# shellcheck shell=sh
# Sourced from ~/.bashrc / ~/.zshrc by install.sh. POSIX sh so it works in bash and zsh.
#   ~/.local/bin                    Claude Code's native installer puts `claude` here
#   ~/.local/share/nvim/mason/bin   LSP servers and formatters installed by Mason, so other
#                                   tools (e.g. Claude Code's language-server plugins) reuse them
for _d in "$HOME/.local/share/nvim/mason/bin" "$HOME/.local/bin"; do
  case ":$PATH:" in
    *":$_d:"*) ;;
    *) [ -d "$_d" ] && PATH="$_d:$PATH" ;;
  esac
done
unset _d
export PATH
