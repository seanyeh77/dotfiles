#!/bin/sh
# Global git hooks for this dotfiles setup (git config --global core.hooksPath points here).
# commit-msg removes the lines Claude Code adds to credit itself, so Claude never shows up as a
# co-author, whatever its settings. Every hook then runs the repository's own hook of the same
# name, so per-project hooks (pre-commit, linters, ...) keep working.
name="$(basename "$0")"
if [ "$name" = commit-msg ] && [ -f "${1:-}" ]; then
  tmp="$1.dotfiles.$$"
  grep -v -i -E '^(Co-Authored-By:[[:space:]]*Claude|Claude-Session:)' "$1" > "$tmp"
  cat "$tmp" > "$1"
  rm -f "$tmp"
fi
dir="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 0
if [ -x "$dir/hooks/$name" ]; then exec "$dir/hooks/$name" "$@"; fi
exit 0
