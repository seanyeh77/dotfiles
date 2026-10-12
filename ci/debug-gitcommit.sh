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
$(ls -la "${XDG_CACHE_HOME:-$HOME/.cache}/tree-sitter/lock" 2>&1)

strace 5 s:
$(timeout 5 strace -f -tt -p "$pid" 2>&1 | tail -25)"
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

run_exp "A tree-sitter build gitcommit" 120 "$W/gitcommit" tree-sitter build -o parser.so
run_exp "B cc parser.c directly"        180 "$W/gitcommit" cc -shared -fPIC -O2 -Isrc src/parser.c -o direct.so
run_exp "C tree-sitter build lua"       120 "$W/lua"       tree-sitter build -o parser.so
exit 0
