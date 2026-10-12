#!/usr/bin/env bash
# 一鍵安裝 nvim + tmux 開發環境
#   OS：macOS、Debian/Ubuntu、Fedora/RHEL/Rocky、Arch、openSUSE、Alpine、WSL
#   Arch：amd64 / arm64
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
#   沒有 curl：bash <(wget -qO- https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
# 重跑即更新（git pull + 外掛/LSP 同步），可重複執行
set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/seanyeh77/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
NODE_MAJOR="${NODE_MAJOR:-22}"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

# root（例如 container）不一定有 sudo
if [ "$(id -u)" -eq 0 ]; then sudo() { "$@"; }; fi

# 下載：curl 優先，沒有就用 wget
fetch() { # fetch URL [OUTFILE]
  if has curl; then
    if [ $# -ge 2 ]; then curl -fsSL -o "$2" "$1"; else curl -fsSL "$1"; fi
  elif has wget; then
    if [ $# -ge 2 ]; then wget -qO "$2" "$1"; else wget -qO- "$1"; fi
  else die "Need curl or wget"; fi
}

# ---------- 偵測 OS / 架構 ----------
OS="$(uname -s)"
case "$(uname -m)" in
  x86_64|amd64)  ARCH=amd64; NVIM_ARCH=x86_64; NODE_ARCH=x64 ;;
  aarch64|arm64) ARCH=arm64; NVIM_ARCH=arm64;  NODE_ARCH=arm64 ;;
  *) die "Unsupported arch: $(uname -m)" ;;
esac

PM=""
case "$OS" in
  Darwin) PM=brew ;;
  Linux)
    for p in apt-get dnf yum pacman zypper apk; do has "$p" && { PM=$p; break; }; done
    [ -n "$PM" ] || die "No supported package manager (apt/dnf/yum/pacman/zypper/apk)" ;;
  MINGW*|MSYS*|CYGWIN*) die "Windows native is not supported, please use WSL: wsl --install" ;;
  *) die "Unsupported OS: $OS" ;;
esac
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1 || IS_WSL=0
log "OS: $OS ($PM)  Arch: $ARCH  WSL: $IS_WSL"

# musl（Alpine）不能跑官方 glibc 版 nvim / node，改用套件管理器的版本
USE_PM_NVIM=0; USE_PM_NODE=0
[ "$PM" = brew ] && { USE_PM_NVIM=1; USE_PM_NODE=1; }
[ "$PM" = apk ]  && { USE_PM_NVIM=1; USE_PM_NODE=1; }

# ---------- 系統套件 ----------
# 必要：git curl unzip tar gzip（Mason 下載）、C compiler（treesitter parser）、tmux、ripgrep
# 選用：fd、clangd、xclip，有就裝，沒有不中斷
pm_install() { # pm_install REQUIRED... -- OPTIONAL...
  local req=() opt=() seen=0
  for a in "$@"; do
    if [ "$a" = "--" ]; then seen=1; continue; fi
    if [ $seen = 0 ]; then req+=("$a"); else opt+=("$a"); fi
  done
  case "$PM" in
    brew)    brew install "${req[@]}" ;;
    apt-get) sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${req[@]}" ;;
    dnf)     sudo dnf install -y "${req[@]}" ;;
    yum)     sudo yum install -y "${req[@]}" ;;
    pacman)  sudo pacman -S --noconfirm --needed "${req[@]}" ;;
    zypper)  sudo zypper --non-interactive install "${req[@]}" ;;
    apk)     sudo apk add "${req[@]}" ;;
  esac
  for p in "${opt[@]}"; do
    case "$PM" in
      brew)    brew install "$p" ;;
      apt-get) sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$p" ;;
      dnf)     sudo dnf install -y "$p" ;;
      yum)     sudo yum install -y "$p" ;;
      pacman)  sudo pacman -S --noconfirm --needed "$p" ;;
      zypper)  sudo zypper --non-interactive install "$p" ;;
      apk)     sudo apk add "$p" ;;
    esac >/dev/null 2>&1 || warn "optional package not available: $p"
  done
}

log "Installing system packages"
case "$PM" in
  brew)
    if ! has brew; then
      log "Installing Homebrew"
      NONINTERACTIVE=1 bash -c "$(fetch https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)"; done
    fi
    pm_install git tmux ripgrep fd neovim node -- tree-sitter-cli ;;
  apt-get)
    sudo apt-get update || true
    pm_install git curl wget unzip tar gzip xz-utils tmux ripgrep build-essential python3 python3-venv python3-pip \
      -- fd-find clangd xclip ;;
  dnf)
    pm_install git curl wget unzip tar gzip xz tmux gcc gcc-c++ make python3 python3-pip \
      -- ripgrep fd-find clang-tools-extra xclip ;;
  yum)
    pm_install git curl wget unzip tar gzip xz tmux gcc gcc-c++ make python3 python3-pip \
      -- ripgrep fd-find clang-tools-extra xclip ;;
  pacman)
    sudo pacman -Sy --noconfirm
    pm_install git curl wget unzip tar gzip xz tmux ripgrep base-devel python python-pip \
      -- fd clang xclip ;;
  zypper)
    sudo zypper --non-interactive refresh || true
    pm_install git curl wget unzip tar gzip xz tmux ripgrep gcc gcc-c++ make python3 python3-pip \
      -- fd clang-tools xclip ;;
  apk)
    sudo apk update
    pm_install bash git curl wget unzip tar gzip xz tmux ripgrep build-base python3 py3-pip neovim nodejs npm \
      -- fd clang-extra-tools tree-sitter-cli xclip ;;
esac

# Debian/Ubuntu 的 fd 叫 fdfind
if ! has fd && has fdfind; then sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sudo mkdir -p /usr/local/bin

# ---------- Neovim ----------
# glibc Linux：官方 release（distro 版本常太舊，設定需要 >= 0.11）
if [ "$USE_PM_NVIM" = 0 ]; then
  log "Installing Neovim (official release, $NVIM_ARCH)"
  fetch "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz" "$TMP/nvim.tar.gz"
  sudo rm -rf "/opt/nvim-linux-${NVIM_ARCH}"
  sudo tar -C /opt -xzf "$TMP/nvim.tar.gz"
  sudo ln -sf "/opt/nvim-linux-${NVIM_ARCH}/bin/nvim" /usr/local/bin/nvim
fi
hash -r
nvim --version >/dev/null 2>&1 || die "nvim failed to run (glibc too old?). Try a newer OS release."
NVIM_MINOR="$(nvim --version | head -1 | sed -E 's/.*v0\.([0-9]+).*/\1/')"
[ "${NVIM_MINOR:-0}" -ge 11 ] || warn "Neovim $(nvim --version | head -1) < 0.11, config needs 0.11+"

# ---------- Node.js（pyright、ts_ls、bashls、prettier 等需要） ----------
node_ok() { has node && [ "$(node -v | cut -d. -f1 | tr -d v)" -ge 18 ]; }
if ! node_ok && [ "$USE_PM_NODE" = 0 ]; then
  log "Installing Node.js $NODE_MAJOR ($NODE_ARCH)"
  BASE="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x"
  NODE_TAR="$(fetch "$BASE/SHASUMS256.txt" | grep -o "node-v[0-9.]*-linux-${NODE_ARCH}.tar.xz" | head -1)"
  fetch "$BASE/$NODE_TAR" "$TMP/$NODE_TAR"
  sudo rm -rf /opt/node && sudo mkdir -p /opt/node
  sudo tar -C /opt/node --strip-components=1 -xJf "$TMP/$NODE_TAR"
  for b in node npm npx; do sudo ln -sf "/opt/node/bin/$b" "/usr/local/bin/$b"; done
  hash -r
fi
node_ok || warn "Node.js >= 18 not found, JS-based LSPs (pyright, ts_ls...) will fail"

# ---------- tree-sitter CLI（nvim-treesitter 編譯 parser 需要） ----------
if ! has tree-sitter && has npm; then
  log "Installing tree-sitter CLI"
  if [ "$PM" = brew ]; then npm install -g tree-sitter-cli >/dev/null
  else sudo npm install -g tree-sitter-cli >/dev/null; fi
  [ -x /opt/node/bin/tree-sitter ] && sudo ln -sf /opt/node/bin/tree-sitter /usr/local/bin/tree-sitter
  hash -r
fi
has tree-sitter || warn "tree-sitter CLI missing, syntax highlighting parsers will not compile"

# ---------- dotfiles ----------
log "Linking dotfiles"
if [ -d "$DOTFILES_DIR/.git" ]; then
  git -C "$DOTFILES_DIR" pull --ff-only || warn "git pull skipped (local changes or no remote)"
else
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

link() { # 既有設定先備份，不直接覆蓋
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then mv "$dst" "$dst.bak.$(date +%s)"; fi
  ln -sfn "$src" "$dst"
}
link "$DOTFILES_DIR/nvim"      "$HOME/.config/nvim"
link "$DOTFILES_DIR/tmux.conf" "$HOME/.tmux.conf"

# ---------- tmux 外掛 ----------
log "Installing tmux plugins"
[ -d "$HOME/.tmux/plugins/tpm" ] || git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
"$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null || warn "tpm install failed, press prefix + I inside tmux"

# ---------- nvim 外掛、LSP、treesitter parser（headless 一次裝完） ----------
# 網路有問題時避免無限等待（macOS 沒有 timeout 就直接跑）
with_timeout() { local s="$1"; shift; if has timeout; then timeout "$s" "$@"; else "$@"; fi; }
log "Installing nvim plugins (Lazy)"
with_timeout 600 nvim --headless "+Lazy! sync" +qa || warn "Lazy sync failed or timed out, run :Lazy sync"
log "Installing LSP servers / formatters (Mason)"
with_timeout 900 nvim --headless -c "MasonToolsInstallSync" -c "qa" || warn "Mason failed or timed out (network?), check :Mason"
log "Installing treesitter parsers"
with_timeout 900 nvim --headless -c "lua require('nvim-treesitter').install(_G.TS_LANGS):wait(600000)" -c "qa" \
  || warn "parsers failed or timed out, check :checkhealth nvim-treesitter"

log "Done. 開 nvim 執行 :checkhealth 確認狀態"
