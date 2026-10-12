#!/usr/bin/env bash
# 一鍵安裝 nvim + tmux 開發環境（amd64 / arm64，apt / dnf）
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
#   沒有 curl：bash <(wget -qO- https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
# 重跑即更新（git pull + 外掛/LSP 同步），可重複執行
set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/seanyeh77/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
NODE_MAJOR="${NODE_MAJOR:-22}"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

# root（例如 container）不一定有 sudo
if [ "$(id -u)" -eq 0 ]; then sudo() { "$@"; }; fi

# ---------- 架構 ----------
case "$(uname -m)" in
  x86_64|amd64)  NVIM_ARCH=x86_64; NODE_ARCH=x64;   IS_ARM=0 ;;
  aarch64|arm64) NVIM_ARCH=arm64;  NODE_ARCH=arm64; IS_ARM=1 ;;
  *) echo "Unsupported arch: $(uname -m)"; exit 1 ;;
esac
log "Arch: $(uname -m)"

# ---------- 系統套件 ----------
# git/curl/unzip/tar/gzip：Mason 下載用；gcc/make：treesitter parser 編譯
# python3-venv：Mason 的 pip 套件（clang-format）
if command -v apt-get >/dev/null; then
  PKGS="tmux git curl wget unzip tar gzip ripgrep fd-find build-essential python3 python3-venv python3-pip xclip"
  [ "$IS_ARM" = 1 ] && PKGS="$PKGS clangd"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $PKGS
elif command -v dnf >/dev/null; then
  PKGS="tmux git curl wget unzip tar gzip ripgrep fd-find gcc gcc-c++ make python3 python3-pip xclip"
  [ "$IS_ARM" = 1 ] && PKGS="$PKGS clang-tools-extra"
  sudo dnf install -y $PKGS
elif command -v pacman >/dev/null; then
  PKGS="tmux git curl wget unzip tar gzip ripgrep fd base-devel python python-pip xclip"
  [ "$IS_ARM" = 1 ] && PKGS="$PKGS clang"
  sudo pacman -Sy --noconfirm --needed $PKGS
else
  echo "Only apt / dnf / pacman supported"; exit 1
fi

# ---------- Neovim（官方 release，distro 版本太舊） ----------
log "Installing Neovim ($NVIM_ARCH)"
TMP="$(mktemp -d)"
curl -fsSL -o "$TMP/nvim.tar.gz" \
  "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz"
sudo rm -rf "/opt/nvim-linux-${NVIM_ARCH}"
sudo tar -C /opt -xzf "$TMP/nvim.tar.gz"
sudo ln -sf "/opt/nvim-linux-${NVIM_ARCH}/bin/nvim" /usr/local/bin/nvim

# ---------- Node.js（pyright、ts_ls、bashls、prettier 等 LSP 需要） ----------
if ! command -v node >/dev/null || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt 18 ]; then
  log "Installing Node.js $NODE_MAJOR ($NODE_ARCH)"
  BASE="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x"
  NODE_TAR="$(curl -fsSL "$BASE/SHASUMS256.txt" | grep -o "node-v[0-9.]*-linux-${NODE_ARCH}.tar.xz" | head -1)"
  curl -fsSL -o "$TMP/$NODE_TAR" "$BASE/$NODE_TAR"
  sudo rm -rf /opt/node
  sudo mkdir -p /opt/node
  sudo tar -C /opt/node --strip-components=1 -xJf "$TMP/$NODE_TAR"
  for b in node npm npx; do sudo ln -sf "/opt/node/bin/$b" "/usr/local/bin/$b"; done
fi

# tree-sitter CLI：nvim-treesitter (main branch) 編譯 parser 需要
log "Installing tree-sitter CLI"
sudo npm install -g tree-sitter-cli >/dev/null
sudo ln -sf /opt/node/bin/tree-sitter /usr/local/bin/tree-sitter 2>/dev/null || true

# Debian/Ubuntu 的 fd 叫 fdfind
command -v fd >/dev/null || { command -v fdfind >/dev/null && sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd; }
rm -rf "$TMP"

# ---------- dotfiles ----------
log "Linking dotfiles"
if [ -d "$DOTFILES_DIR/.git" ]; then
  git -C "$DOTFILES_DIR" pull --ff-only || log "git pull skipped (local changes or no remote)"
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
"$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null

# ---------- nvim 外掛、treesitter parser、LSP（headless 一次裝完） ----------
log "Installing nvim plugins (Lazy)"
nvim --headless "+Lazy! sync" +qa
log "Installing LSP servers / formatters (Mason)"
nvim --headless -c "MasonToolsInstallSync" -c "qa"
log "Installing treesitter parsers"
nvim --headless -c "lua require('nvim-treesitter').install(_G.TS_LANGS):wait(600000)" -c "qa"

log "Done. 開 nvim 執行 :checkhealth 確認狀態"
