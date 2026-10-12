#!/usr/bin/env bash
# Turn the key lines of the install / verify logs into GitHub annotations, so failures
# are visible on the run summary page (and through the API) without downloading logs.
# Usage: bash ci/annotate.sh <log dir>
dir="${1:-.}"

# Workflow command messages must encode % \r \n
encode() { local s="$1"; s="${s//'%'/'%25'}"; s="${s//$'\r'/'%0D'}"; s="${s//$'\n'/'%0A'}"; printf '%s' "$s"; }
strip_ansi() { sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g'; }

for name in install verify; do
  f="$dir/$name.log"
  [ -s "$f" ] || continue
  # 1. Failed verify checks
  fails="$(strip_ansi < "$f" | grep -a '^FAIL' || true)"
  [ -n "$fails" ] && echo "::error title=$name failed checks::$(encode "$fails")"
  # 2. Warnings and errors (install.sh prints them with !! and xx)
  warns="$(strip_ansi < "$f" | grep -aE '^(!!|xx) |E[0-9]+:|[Ee]rror' | grep -av 'nvim-treesitter/install' | tail -20 || true)"
  [ -n "$warns" ] && echo "::warning title=$name warnings::$(encode "$warns")"
  # 3. Parsers that started compiling but never finished (look here when a build hangs)
  started="$(strip_ansi < "$f" | grep -ao 'install/[a-z_]*\]: Compiling' | sed -E 's#install/([a-z_]*).*#\1#' | sort -u)"
  done_="$(strip_ansi < "$f" | grep -ao 'install/[a-z_]*\]: Language installed' | sed -E 's#install/([a-z_]*).*#\1#' | sort -u)"
  stuck="$(comm -23 <(printf '%s\n' "$started") <(printf '%s\n' "$done_") | tr '\n' ' ')"
  [ -n "${stuck// }" ] && echo "::error title=$name parsers never finished::$stuck"
  # 4. Last 40 lines
  echo "::error title=$name tail::$(encode "$(strip_ansi < "$f" | tail -40)")"
done
exit 0
