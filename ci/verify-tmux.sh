#!/usr/bin/env bash
# CI: start a tmux server from the installed config (Oh my tmux! + tmux/tmux.conf.local) and
# check the settings this repo relies on. Exits non-zero if any check fails.
set -uo pipefail
failed=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; failed=$((failed + 1)); fi; }
T=(tmux -L dotfiles-verify)
TERM=xterm-256color "${T[@]}" new-session -d -x 200 -y 50 || { echo "FAIL tmux could not start"; exit 1; }
sleep 2
check "prefix"      "$("${T[@]}" show -gv prefix)"      "C-a"
check "prefix2"     "$("${T[@]}" show -gv prefix2)"     "None"
check "mouse"       "$("${T[@]}" show -gv mouse)"       "on"
check "mode-keys"   "$("${T[@]}" show -gv mode-keys)"   "vi"
case "$("${T[@]}" show -gv status-style)" in *"bg=#181825"*) s=catppuccin ;; *) s="$("${T[@]}" show -gv status-style)" ;; esac
check "status bar colours" "$s" "catppuccin"
keys="$("${T[@]}" list-keys -T prefix)"
for k in A '|' - _ h j k l; do
  case "$keys" in *"-T prefix $k "*|*"-T prefix \\$k "*) r=bound ;; *) r=unbound ;; esac
  check "prefix + $k" "$r" "bound"
done
"${T[@]}" kill-server
echo "========== tmux: $failed failed =========="
exit "$failed"
