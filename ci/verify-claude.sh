#!/usr/bin/env bash
# CI: check that install.sh installed Claude Code and its plugins.
# Usage: bash ci/verify-claude.sh [extra plugin names expected]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. shell/env.sh
failed=0
check() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; failed=$((failed + 1)); fi; }

command -v claude >/dev/null; check "claude on PATH ($(command -v claude || echo none))" $?
claude --version; check "claude --version" $?
list="$(claude plugin list 2>&1)"; echo "$list"

# Language-server plugins are installed when their server is on PATH (Mason's bin is)
for pair in pyright-lsp:pyright-langserver clangd-lsp:clangd typescript-lsp:typescript-language-server \
            rust-analyzer-lsp:rust-analyzer lua-lsp:lua-language-server gopls-lsp:gopls; do
  if ! command -v "${pair#*:}" >/dev/null; then
    # gopls only exists when Go is installed; every other server comes from Mason or the OS
    if [ "${pair%%:*}" = gopls-lsp ]; then echo "SKIP gopls-lsp (no go)"; else check "${pair#*:} on PATH" 1; fi
    continue
  fi
  case "$list" in *"${pair%%:*}@claude-plugins-official"*) r=0 ;; *) r=1 ;; esac
  check "plugin ${pair%%:*}" $r
done
for p in "$@"; do
  case "$list" in *"$p@claude-plugins-official"*) r=0 ;; *) r=1 ;; esac
  check "plugin $p" $r
done
echo "========== claude: $failed failed =========="
# Summary as an annotation, readable from the run page without downloading logs
[ -n "${GITHUB_ACTIONS:-}" ] && echo "::notice title=claude plugins::$(claude --version 2>/dev/null) | $(printf '%s\n' "$list" | grep -o '[a-z-]*@claude-plugins-official' | sort -u | tr '\n' ' ')"
exit "$failed"
