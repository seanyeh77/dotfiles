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
  command -v "${pair#*:}" >/dev/null || { echo "SKIP ${pair%%:*} (${pair#*:} not on PATH)"; continue; }
  case "$list" in *"${pair%%:*}@claude-plugins-official"*) r=0 ;; *) r=1 ;; esac
  check "plugin ${pair%%:*}" $r
done
for p in "$@"; do
  case "$list" in *"$p@claude-plugins-official"*) r=0 ;; *) r=1 ;; esac
  check "plugin $p" $r
done
echo "========== claude: $failed failed =========="
exit "$failed"
