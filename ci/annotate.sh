#!/usr/bin/env bash
# 把 install / verify log 的重點轉成 GitHub annotation
# 這樣不用下載完整 log，在 Actions 摘要頁（或 API）就看得到失敗原因
# 用法：bash ci/annotate.sh <log 目錄>
dir="${1:-.}"

# workflow command 的訊息要把 % \r \n 編碼
encode() { local s="$1"; s="${s//'%'/'%25'}"; s="${s//$'\r'/'%0D'}"; s="${s//$'\n'/'%0A'}"; printf '%s' "$s"; }
strip_ansi() { sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g'; }

for name in install verify; do
  f="$dir/$name.log"
  [ -s "$f" ] || continue
  # 1. verify 的 FAIL 項目
  fails="$(strip_ansi < "$f" | grep -a '^FAIL' || true)"
  [ -n "$fails" ] && echo "::error title=$name failed checks::$(encode "$fails")"
  # 2. 警告 / 錯誤行（install.sh 的 !! 與 xx）
  warns="$(strip_ansi < "$f" | grep -aE '^(!!|xx) |E[0-9]+:|[Ee]rror' | grep -av 'nvim-treesitter/install' | tail -20 || true)"
  [ -n "$warns" ] && echo "::warning title=$name warnings::$(encode "$warns")"
  # 3. 最後 40 行
  echo "::error title=$name tail::$(encode "$(strip_ansi < "$f" | tail -40)")"
done
exit 0
