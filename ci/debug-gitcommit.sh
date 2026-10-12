#!/usr/bin/env bash
# 調查：Debian 12 上 `tree-sitter build` 編 gitcommit 為什麼會卡住
# 每個實驗都有 timeout，結果以 GitHub annotation 輸出（::notice / ::error）
set -uo pipefail

W="$(mktemp -d)"
REV=55a265cf763ec15d6e2d96bb206e3f5e30d82bae # nvim-treesitter 鎖定的 gitcommit 版本
encode() { local s="$1"; s="${s//'%'/'%25'}"; s="${s//$'\r'/'%0D'}"; s="${s//$'\n'/'%0A'}"; printf '%s' "$s"; }
note() { echo "::notice title=$1::$(encode "$2")"; }

note "env" "$(. /etc/os-release; echo "$PRETTY_NAME") | glibc $(ldd --version | head -1 | awk '{print $NF}') | $(gcc --version | head -1) | nproc $(nproc) | HOME=$HOME uid=$(id -u)
tree-sitter: $(command -v tree-sitter) -> $(readlink -f "$(command -v tree-sitter)")
version: $(tree-sitter --version 2>&1)
cache dir: ${XDG_CACHE_HOME:-$HOME/.cache}/tree-sitter"

# 跟 nvim-treesitter 一樣，下載 codeload tarball
fetch_grammar() { # repo rev dir
  mkdir -p "$3" && curl -fsSL "https://codeload.github.com/$1/tar.gz/$2" | tar -xz -C "$3" --strip-components=1
}
fetch_grammar gbprod/tree-sitter-gitcommit "$REV" "$W/gitcommit"
fetch_grammar tree-sitter-grammars/tree-sitter-lua main "$W/lua"
note "gitcommit source" "$(cd "$W/gitcommit" && ls -la src | head -20; echo; cat tree-sitter.json 2>/dev/null | head -40)"

# 實驗：在背景跑，20 秒後抓診斷，最多等 limit 秒
run_exp() { # title limit dir cmd...
  local title="$1" limit="$2" dir="$3"; shift 3
  local start; start=$(date +%s)
  ( cd "$dir" && exec "$@" ) > "$W/out" 2>&1 &
  local pid=$! snap=""
  while kill -0 "$pid" 2>/dev/null; do
    local el=$(( $(date +%s) - start ))
    if [ "$el" -ge 20 ] && [ -z "$snap" ]; then
      snap="processes:
$(ps -eo pid,ppid,stat,etime,wchan:24,args --forest | grep -v ' ps -eo' | tail -25)

lock dir:
$(ls -la "${XDG_CACHE_HOME:-$HOME/.cache}/tree-sitter/lock" 2>&1)"
    fi
    if [ "$el" -ge "$limit" ]; then
      pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null
      echo "::error title=$title::$(encode "TIMEOUT after ${limit} s
$snap
--- output ---
$(tail -20 "$W/out")")"
      return
    fi
    sleep 1
  done
  wait "$pid"; local rc=$?
  note "$title" "exit=$rc in $(( $(date +%s) - start )) s
$(tail -15 "$W/out")
$snap"
}

# 第 1 輪結果：A（tree-sitter build）卡在 cc1，B（cc -O2 直接編）5 s 完成
# 第 2 輪：二分 tree-sitter 加的 flag，找出是哪個讓 gcc 12.2 卡住
G="$W/gitcommit"
BASE=(cc -shared -fPIC -O2 -Isrc src/parser.c -o t.so)
run_exp "1 base"                          60 "$G" "${BASE[@]}"
run_exp "2 base + -Wall"                  60 "$G" "${BASE[@]}" -Wall
run_exp "3 base + -std=c11"               60 "$G" "${BASE[@]}" -std=c11
run_exp "4 base + -ffunction/data-sections" 60 "$G" "${BASE[@]}" -ffunction-sections -fdata-sections
run_exp "5 base + -Werror=implicit-fn-decl" 60 "$G" "${BASE[@]}" -Werror=implicit-function-declaration
run_exp "6 base + -Wall -Wno-maybe-uninitialized" 60 "$G" "${BASE[@]}" -Wall -Wno-maybe-uninitialized
run_exp "7 base + -Wall -Wno-array-bounds" 60 "$G" "${BASE[@]}" -Wall -Wno-array-bounds
# 修法候選：用 CFLAGS 讓 tree-sitter build 本身避開
run_exp "8 tree-sitter build CFLAGS=-Wno-maybe-uninitialized" 90 "$G" env CFLAGS=-Wno-maybe-uninitialized tree-sitter build -o p8.so
run_exp "9 tree-sitter build CFLAGS=-O1"  90 "$G" env CFLAGS=-O1 tree-sitter build -o p9.so
exit 0
