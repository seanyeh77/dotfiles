# dotfiles

Neovim + tmux 開發環境，一個指令裝好。

| OS | 套件管理器 | 備註 |
| --- | --- | --- |
| macOS | Homebrew | 沒有 brew 會自動安裝 |
| Debian / Ubuntu | apt | |
| Fedora / RHEL / Rocky / Alma | dnf / yum | ripgrep、fd 在 RHEL 需要 EPEL，沒有會略過 |
| Arch | pacman | |
| openSUSE | zypper | |
| Alpine | apk | musl，部分 Mason 工具無法使用（best effort） |
| Windows | WSL | 在 WSL 裡跑，視同 Linux；Windows 原生不支援 |

架構支援 amd64 / arm64。glibc Linux 一律用官方 Neovim release，macOS / Alpine 用套件管理器的版本。設定需要 Neovim 0.11 以上。

## 安裝 / 更新

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
```

沒有 curl 時：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/seanyeh77/dotfiles/main/install.sh)
```

重跑同一個指令就是更新（拉最新設定、同步外掛與 LSP）。既有的 `~/.config/nvim`、`~/.tmux.conf` 會先備份成 `.bak.<timestamp>`。

## 內容

| 檔案 | 說明 |
| --- | --- |
| `install.sh` | 安裝系統套件、Neovim、Node.js、tree-sitter CLI，建立 symlink，headless 安裝外掛 |
| `nvim/init.lua` | lazy.nvim、Treesitter、Mason + LSP、blink.cmp 補全、conform 格式化、telescope |
| `tmux.conf` | prefix `C-a`、滑鼠、vim 風格切 pane、tpm 外掛 |

## 加新語言

改 `nvim/init.lua` 上方的三個清單：

- `mason_servers`：LSP（lspconfig 名稱）
- `mason_tools`：formatter
- `TS_LANGS`：Treesitter parser

## 常用按鍵

| 按鍵 | 功能 |
| --- | --- |
| `gd` / `K` | 跳到定義 / 查看文件 |
| `grn` / `gra` / `grr` | 改名 / code action / 參考 |
| `<Space>f` | 格式化 |
| `<Space>sf` / `<Space>sg` | 找檔案 / grep |
| tmux `C-a \|` / `C-a -` | 左右 / 上下分割 |

## 環境變數

| 變數 | 預設 |
| --- | --- |
| `DOTFILES_REPO` | `https://github.com/seanyeh77/dotfiles` |
| `DOTFILES_DIR` | `~/dotfiles` |
| `NODE_MAJOR` | `22` |
